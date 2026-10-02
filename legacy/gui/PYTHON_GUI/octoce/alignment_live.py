"""Live spectrometer alignment dashboard.

Acquires exactly like the main GUI's "Alineación continua" button (stationary
MB at the centre, 1000 A-lines per block, no file) and compares each frame's
spectrum with a reference alignment (default: Penetration_3/15um.tdms, exported
by ``Exportar_Referencia_Alineacion.m``).  The acquisition engine and NI
backend are reused unchanged; analysis runs in its own thread so the critical
acquisition path is never touched by plotting.
"""
from __future__ import annotations

import math
import queue
import threading
import time
import tkinter as tk
from collections import deque
from dataclasses import dataclass, replace
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import Any, Callable, Sequence

import numpy as np

if __package__ in (None, ""):
    # Run as a plain file (e.g. VS Code "Run Python File"): import as octoce.*
    import sys

    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    import octoce  # noqa: F401  (parent package must be imported for relative imports)

    __package__ = "octoce"

from .alignment_metrics import (
    BLUE_BAND_PX,
    RED_BAND_PX,
    AlignmentProcessor,
    AlignmentReference,
    AlignmentResult,
    compare,
    gauss_model,
    spectral_sharpness,
)
from .alignment_pipeline import STEPS, AlignmentPipeline, PipelineTargets, StepView
from .backends.ni_hardware import NIHardwareBackend
from .backends.simulated import SimulatedBackend
from .config import AcquisitionMode, HardwareConfig, ScanParameters, ScanPattern, stationary_alignment_timing
from .engine import AcquisitionEngine, EngineEvent
from .paths import CONFIG_DIR, DATA_ROOT

DEFAULT_REFERENCE = CONFIG_DIR / "alineacion_referencia.json"
DEFAULT_TARGETS = CONFIG_DIR / "alineacion_objetivos.json"
SESSIONS_DIR = DATA_ROOT / "alignment_sessions"
MAX_ANALYSIS_LINES = 300     # A-lines analysed per frame (keeps the dashboard at ~10 Hz)
CAPTURE_FRAMES = 12          # frames averaged by a pipeline capture
BLOCKED_ARM_STEPS = ("oscuro", "referencia", "forma", "muestra")

# Palette consistent with octoce.gui
NAVY = "#10233f"
NAVY_TEXT = "#b8c8df"
BG = "#eef2f7"
CARD = "#ffffff"
INK = "#14243c"
MUTED = "#6a788b"
GRID = "#e6ebf2"
AXIS = "#a8b5c6"
REF_COLOR = "#2477d4"
CUR_COLOR = "#e8590c"
GOOD = "#1da56d"
WARN = "#e0a100"
BAD = "#d64545"
NEUTRAL = "#5b6b82"
LOSS_FILL = "#fbd5c4"
GAIN_FILL = "#d6e6fa"
STATUS_COLORS = {"good": GOOD, "warn": WARN, "bad": BAD, "neutral": NEUTRAL}
PSF_MIN_SNR_DB = 15.0   # below this the "PSF" is most likely noise


# ---------------------------------------------------------------------------
# Plot widget
# ---------------------------------------------------------------------------
def _nice_ticks(lo: float, hi: float, target: int = 6) -> list[float]:
    if not (math.isfinite(lo) and math.isfinite(hi)) or hi <= lo:
        return []
    raw = (hi - lo) / max(target, 1)
    magnitude = 10 ** math.floor(math.log10(raw))
    step = next(m * magnitude for m in (1, 2, 2.5, 5, 10) if m * magnitude >= raw)
    first = math.ceil(lo / step) * step
    ticks = []
    value = first
    while value <= hi + step * 1e-9:
        ticks.append(round(value, 10))
        value += step
    return ticks


def _fmt_tick(value: float) -> str:
    if abs(value) >= 1000 or value == int(value):
        return f"{value:.0f}"
    if abs(value) >= 10:
        return f"{value:.1f}"
    return f"{value:.2f}".rstrip("0").rstrip(".")


@dataclass
class Series:
    x: np.ndarray
    y: np.ndarray
    color: str
    width: float = 2.0
    dash: tuple[int, ...] | None = None
    label: str | None = None


@dataclass
class Band:
    x: np.ndarray
    low: np.ndarray
    high: np.ndarray
    color: str


@dataclass
class Marker:
    x: float
    y: float
    color: str
    size: int = 6
    outline: str = "#ffffff"


@dataclass
class Rule:
    value: float
    color: str
    vertical: bool = True
    dash: tuple[int, ...] | None = (4, 3)
    label: str | None = None
    width: float = 1.0
    label_bottom: bool = False


class PlotCanvas(tk.Canvas):
    """Small, dependency-free line plot for live dashboards."""

    def __init__(self, parent: tk.Misc, *, title: str = "", xlabel: str = "", ylabel: str = "",
                 height: int = 220, legend: bool = True, legend_anchor: str = "ne",
                 margins: tuple[int, int, int, int] = (64, 18, 34, 42),
                 on_select: Callable[[float | None, float | None], None] | None = None):
        super().__init__(parent, bg=CARD, highlightthickness=0, height=height,
                         cursor="crosshair" if on_select else "")
        self.title, self.xlabel, self.ylabel = title, xlabel, ylabel
        self.legend = legend
        self.legend_anchor = legend_anchor
        self.margins = margins
        self.xlim: tuple[float, float] = (0.0, 1.0)
        self.ylim: tuple[float, float] = (0.0, 1.0)
        self.series: list[Series] = []
        self.bands: list[Band] = []
        self.markers: list[Marker] = []
        self.rules: list[Rule] = []
        self.texts: list[tuple[float, float, str, str, str]] = []
        self.message: str | None = "Esperando datos…"
        self.on_select = on_select
        self._frame: tuple[int, int, int, int] = (0, 1, 0, 1)   # left, width, top, height
        self._drag: tuple[float, float] | None = None
        self.bind("<Configure>", lambda _e: self.redraw())
        if on_select is not None:
            self.bind("<ButtonPress-1>", self._drag_start)
            self.bind("<B1-Motion>", self._drag_move)
            self.bind("<ButtonRelease-1>", self._drag_end)
            self.bind("<Double-Button-1>", lambda _e: self.on_select(None, None))

    def _data_x(self, px: float) -> float:
        left, pw, _top, _ph = self._frame
        frac = min(max((px - left) / max(pw, 1), 0.0), 1.0)
        return self.xlim[0] + frac * (self.xlim[1] - self.xlim[0])

    def _drag_start(self, event: tk.Event[Any]) -> None:
        if self.message is None:
            self._drag = (event.x, event.x)

    def _drag_move(self, event: tk.Event[Any]) -> None:
        if self._drag is not None:
            self._drag = (self._drag[0], event.x)
            self._draw_drag()

    def _drag_end(self, event: tk.Event[Any]) -> None:
        drag, self._drag = self._drag, None
        self.delete("drag")
        if drag is None or abs(event.x - drag[0]) < 6 or self.on_select is None:
            return
        a, b = sorted((self._data_x(drag[0]), self._data_x(event.x)))
        self.on_select(a, b)

    def _draw_drag(self) -> None:
        self.delete("drag")
        if self._drag is None:
            return
        left, pw, top, ph = self._frame
        x0, x1 = sorted(min(max(v, left), left + pw) for v in self._drag)
        self.create_rectangle(x0, top, x1, top + ph, outline=GOOD, width=2, dash=(4, 2), tags="drag")
        self.create_text((x0 + x1) / 2, top + 4, anchor="n", tags="drag", fill=GOOD,
                         font=("Segoe UI", 9, "bold"),
                         text=f"{self._data_x(x0):.0f}–{self._data_x(x1):.0f}")

    def set_data(self, *, xlim: tuple[float, float], ylim: tuple[float, float],
                 series: Sequence[Series] = (), bands: Sequence[Band] = (),
                 markers: Sequence[Marker] = (), rules: Sequence[Rule] = (),
                 texts: Sequence[tuple[float, float, str, str, str]] = (), title: str | None = None) -> None:
        self.xlim, self.ylim = xlim, ylim
        self.series, self.bands = list(series), list(bands)
        self.markers, self.rules, self.texts = list(markers), list(rules), list(texts)
        if title is not None:
            self.title = title
        self.message = None
        self.redraw()

    def show_message(self, message: str) -> None:
        self.message = message
        self.series, self.bands, self.markers, self.rules, self.texts = [], [], [], [], []
        self.redraw()

    def redraw(self) -> None:
        self.delete("all")
        width, height = max(self.winfo_width(), 120), max(self.winfo_height(), 80)
        left, right, top, bottom = self.margins
        pw, ph = max(1, width - left - right), max(1, height - top - bottom)
        self._frame = (left, pw, top, ph)
        self.create_text(left, 10, anchor="nw", text=self.title, fill=INK, font=("Segoe UI", 11, "bold"))
        if self.message is not None:
            self.create_rectangle(left, top, left + pw, top + ph, outline=GRID)
            self.create_text(left + pw / 2, top + ph / 2, text=self.message, fill=MUTED, font=("Segoe UI", 11))
            return
        x0, x1 = self.xlim
        y0, y1 = self.ylim
        if not (x1 > x0 and y1 > y0):
            return

        def sx(x: np.ndarray | float) -> np.ndarray | float:
            return left + (np.asarray(x, dtype=float) - x0) / (x1 - x0) * pw

        def sy(y: np.ndarray | float) -> np.ndarray | float:
            return top + (y1 - np.clip(np.asarray(y, dtype=float), y0 - (y1 - y0), y1 + (y1 - y0))) / (y1 - y0) * ph

        for tick in _nice_ticks(y0, y1, max(3, ph // 45)):
            y = float(sy(tick))
            self.create_line(left, y, left + pw, y, fill=GRID)
            self.create_text(left - 8, y, anchor="e", text=_fmt_tick(tick), fill=MUTED, font=("Segoe UI", 9))
        for tick in _nice_ticks(x0, x1, max(3, pw // 90)):
            x = float(sx(tick))
            self.create_line(x, top, x, top + ph, fill=GRID)
            self.create_text(x, top + ph + 6, anchor="n", text=_fmt_tick(tick), fill=MUTED, font=("Segoe UI", 9))
        self.create_text(left + pw / 2, height - 4, anchor="s", text=self.xlabel, fill=MUTED, font=("Segoe UI", 9))
        if self.ylabel:
            self.create_text(12, top + ph / 2, angle=90, text=self.ylabel, fill=MUTED, font=("Segoe UI", 9))

        def decimate(*arrays: np.ndarray) -> tuple[np.ndarray, ...]:
            n = arrays[0].size
            step = max(1, int(math.ceil(n / max(pw, 1))))
            return tuple(a[::step] for a in arrays)

        for band in self.bands:
            x, lo, hi = decimate(band.x, band.low, band.high)
            if x.size < 2:
                continue
            xs = sx(x)
            pts = np.concatenate([np.column_stack((xs, sy(hi))), np.column_stack((xs[::-1], sy(lo[::-1])))])
            self.create_polygon(*pts.ravel().tolist(), fill=band.color, outline="")
        for rule in self.rules:
            if rule.vertical:
                x = float(sx(rule.value))
                if left <= x <= left + pw:
                    self.create_line(x, top, x, top + ph, fill=rule.color, dash=rule.dash, width=rule.width)
                    if rule.label:
                        ly, anchor = (top + ph - 4, "sw") if rule.label_bottom else (top + 4, "nw")
                        self.create_text(x + 4, ly, anchor=anchor, text=rule.label, fill=rule.color,
                                         font=("Segoe UI", 8))
            else:
                y = float(sy(rule.value))
                if top <= y <= top + ph:
                    self.create_line(left, y, left + pw, y, fill=rule.color, dash=rule.dash, width=rule.width)
                    if rule.label:
                        ly, anchor = (y + 3, "ne") if y < top + 16 else (y - 3, "se")
                        self.create_text(left + pw - 4, ly, anchor=anchor, text=rule.label, fill=rule.color,
                                         font=("Segoe UI", 8, "bold"))
        for series in self.series:
            x, y = decimate(series.x, series.y)
            finite = np.isfinite(y)
            if np.count_nonzero(finite) < 2:
                if np.count_nonzero(finite) == 1:
                    px, py = float(sx(x[finite][0])), float(sy(y[finite][0]))
                    self.create_oval(px - 3, py - 3, px + 3, py + 3, fill=series.color, outline="")
                continue
            pts = np.column_stack((sx(x[finite]), sy(y[finite]))).ravel().tolist()
            self.create_line(*pts, fill=series.color, width=series.width, dash=series.dash, smooth=False)
        for marker in self.markers:
            if not (math.isfinite(marker.x) and math.isfinite(marker.y)):
                continue
            px, py, r = float(sx(marker.x)), float(sy(marker.y)), marker.size
            self.create_oval(px - r, py - r, px + r, py + r, fill=marker.color, outline=marker.outline, width=2)
        for x, y, text, color, anchor in self.texts:
            self.create_text(float(sx(x)), float(sy(y)), text=text, fill=color, anchor=anchor,
                             font=("Segoe UI", 9, "bold"))
        self.create_rectangle(left, top, left + pw, top + ph, outline=AXIS)
        if self.legend:
            labelled = [s for s in self.series if s.label]
            for i, s in enumerate(labelled):
                ly = top + 12 + i * 18
                if self.legend_anchor == "nw":
                    lx = left + 12
                    self.create_line(lx, ly, lx + 24, ly, fill=s.color, width=3, dash=s.dash)
                    self.create_text(lx + 32, ly, anchor="w", text=s.label, fill=INK, font=("Segoe UI", 9))
                else:
                    lx = left + pw - 10
                    self.create_text(lx, ly, anchor="e", text=s.label, fill=INK, font=("Segoe UI", 9))
                    self.create_line(lx - 8 - 7 * len(s.label) - 26, ly, lx - 8 - 7 * len(s.label) - 4, ly,
                                     fill=s.color, width=3, dash=s.dash)
        self._draw_drag()


# ---------------------------------------------------------------------------
# KPI tile
# ---------------------------------------------------------------------------
class KpiTile(tk.Frame):
    """Large indicator: value, target, change and a gauge with tolerance band."""

    def __init__(self, parent: tk.Misc, title: str, unit: str = "", hint: str = ""):
        super().__init__(parent, bg=CARD, highlightthickness=1, highlightbackground="#d5dde8")
        self.strip = tk.Frame(self, bg=NEUTRAL, width=6)
        self.strip.pack(side="left", fill="y")
        body = tk.Frame(self, bg=CARD, padx=14, pady=10)
        body.pack(side="left", fill="both", expand=True)
        tk.Label(body, text=title.upper(), bg=CARD, fg=MUTED, font=("Segoe UI", 9, "bold"),
                 anchor="w").pack(fill="x")
        row = tk.Frame(body, bg=CARD)
        row.pack(fill="x", pady=(2, 0))
        self.value = tk.Label(row, text="—", bg=CARD, fg=INK, font=("Segoe UI", 28, "bold"), anchor="w")
        self.value.pack(side="left")
        self.unit = tk.Label(row, text=unit, bg=CARD, fg=MUTED, font=("Segoe UI", 12), anchor="sw")
        self.unit.pack(side="left", padx=(6, 0), pady=(12, 0))
        self.delta = tk.Label(body, text="", bg=CARD, fg=MUTED, font=("Segoe UI", 11, "bold"), anchor="w")
        self.delta.pack(fill="x")
        self.gauge = tk.Canvas(body, bg=CARD, height=16, highlightthickness=0)
        self.gauge.pack(fill="x", pady=(6, 2))
        self.target = tk.Label(body, text=hint, bg=CARD, fg=MUTED, font=("Segoe UI", 9), anchor="w",
                               justify="left")
        self.target.pack(fill="x")
        body.bind("<Configure>", lambda e: self.target.configure(wraplength=max(e.width - 10, 80)))
        self._gauge_state: tuple[float, float, float, float, float, str] | None = None
        self.gauge.bind("<Configure>", lambda _e: self._draw_gauge())

    def show(self, *, value: str, status: str, target: str, delta: str = "", delta_color: str = MUTED,
               gauge: tuple[float, float, float, float, float] | None = None) -> None:
        color = STATUS_COLORS[status]
        self.strip.configure(bg=color)
        self.value.configure(text=value, fg=color if status != "neutral" else INK)
        self.target.configure(text=target)
        self.delta.configure(text=delta, fg=delta_color)
        self._gauge_state = (*gauge, color) if gauge is not None else None
        self._draw_gauge()

    def _draw_gauge(self) -> None:
        g = self.gauge
        g.delete("all")
        if self._gauge_state is None:
            return
        lo, hi, value, tol_lo, tol_hi, color = self._gauge_state
        w = max(g.winfo_width(), 40)
        if not (hi > lo):
            return

        def px(v: float) -> float:
            return 4 + (min(max(v, lo), hi) - lo) / (hi - lo) * (w - 8)

        g.create_rectangle(4, 6, w - 4, 11, fill="#e3e9f0", outline="")
        g.create_rectangle(px(tol_lo), 4, px(tol_hi), 13, fill="#c8ecd9", outline="")
        if math.isfinite(value):
            x = px(value)
            g.create_oval(x - 7, 1, x + 7, 15, fill=color, outline="#ffffff", width=2)


# ---------------------------------------------------------------------------
# Analysis thread
# ---------------------------------------------------------------------------
class _Analyzer:
    """Single-slot consumer: always analyses the newest frame, drops stale ones."""

    def __init__(self, on_result: Callable[[AlignmentResult], None]):
        self.on_result = on_result
        self._slot: queue.Queue[np.ndarray] = queue.Queue(maxsize=1)
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self.processor: AlignmentProcessor | None = None
        self.reference: AlignmentReference | None = None
        self.average = 3
        self.flip = False
        self.search_um: tuple[float, float] | None = None
        self.dark: np.ndarray | None = None
        self.rho: np.ndarray | None = None
        self._last_raw: np.ndarray | None = None
        self._history: deque[np.ndarray] = deque(maxlen=self.average)
        self.errors = 0
        self.last_error = ""
        self.thread = threading.Thread(target=self._run, name="alignment-analysis", daemon=True)
        self.thread.start()

    def configure(self, *, processor: AlignmentProcessor | None = None,
                  reference: AlignmentReference | None = None, average: int | None = None,
                  flip: bool | None = None, search_um: object = ..., dark: object = ...,
                  rho: object = ...) -> None:
        """``search_um``: (desde, hasta) µm for a manual PSF window, None = automatic.
        ``dark``/``rho``: dark spectrum and Is/Ir ratio captured by the pipeline."""
        resubmit = None
        with self._lock:
            if dark is not ...:
                self.dark = dark  # type: ignore[assignment]
            if rho is not ...:
                self.rho = rho  # type: ignore[assignment]
            if search_um is not ...:
                self.search_um = search_um  # type: ignore[assignment]
                resubmit = self._last_raw
            if processor is not None:
                self.processor = processor
            if reference is not None:
                self.reference = reference
            if average is not None and average != self.average:
                self.average = max(1, int(average))
                self._history = deque(self._history, maxlen=self.average)
            if flip is not None and flip != self.flip:
                self.flip = flip
                self._history.clear()
        if resubmit is not None:   # immediate feedback, even without new frames
            self.submit(resubmit)

    def reset(self) -> None:
        with self._lock:
            self._history.clear()

    def submit(self, spectra: np.ndarray) -> None:
        try:
            self._slot.put_nowait(spectra)
        except queue.Full:
            try:
                self._slot.get_nowait()
            except queue.Empty:
                pass
            try:
                self._slot.put_nowait(spectra)
            except queue.Full:
                pass

    def close(self) -> None:
        self._stop.set()

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                raw = self._slot.get(timeout=0.2)
            except queue.Empty:
                continue
            with self._lock:
                processor, reference, flip = self.processor, self.reference, self.flip
                search_um, dark, rho = self.search_um, self.dark, self.rho
                self._last_raw = raw
            if processor is None:
                continue
            try:
                data = np.ascontiguousarray(raw[:, ::-1]) if flip else np.asarray(raw)
                if data.shape[0] > MAX_ANALYSIS_LINES:
                    data = data[:: int(math.ceil(data.shape[0] / MAX_ANALYSIS_LINES))]
                with self._lock:
                    self._history.append(data.mean(axis=0, dtype=np.float64))
                    averaged = np.mean(np.vstack(self._history), axis=0)
                    n_avg = len(self._history)
                spectrum = processor.spectrum_metrics(
                    averaged, max_counts=float(data.max()),
                    saturated_fraction=float(np.mean(data >= processor.sensor_max)),
                )
                psf = processor.psf_metrics(data, search_um)
                f0 = psf.peak_px / processor.params.n_fft if psf is not None else None
                spectrum.sharpness = spectral_sharpness(averaged, spectrum.envelope, f0)
                result = AlignmentResult(spectrum=spectrum, psf=psf, n_alines=int(data.shape[0]),
                                         timestamp=time.monotonic(),
                                         frame_mean=data.mean(axis=0, dtype=np.float64))
                if psf is not None:
                    result.fringe = processor.fringe_metrics(data, psf, dark, rho)
                if reference is not None:
                    compare(result, reference)
                if psf is not None and psf.shallow_warning:
                    result.warnings.append("Espejo muy cerca del retardo cero: mueva el espejo a ≥ 70 µm.")
                if data.max() >= processor.sensor_max:
                    result.warnings.append("Saturación del sensor: reduzca la potencia o el tiempo de exposición.")
                result.warnings.append(f"__avg__{n_avg}")
                self.on_result(result)
            except Exception as exc:  # keep the dashboard alive on a bad frame
                self.errors += 1
                self.last_error = str(exc)


# ---------------------------------------------------------------------------
# Main application
# ---------------------------------------------------------------------------
class AlignmentLiveApp:
    TREND_SECONDS = 300.0

    def __init__(self, root: tk.Tk, *, reference_path: Path | None = None):
        self.root = root
        self.root.title("Alineación del espectrómetro · en vivo")
        self.root.configure(bg=BG)
        self.root.minsize(1280, 760)
        try:
            self.root.state("zoomed")
        except tk.TclError:
            self.root.geometry("1600x950")
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        self.events: queue.Queue[EngineEvent] = queue.Queue()
        self.results: queue.Queue[AlignmentResult] = queue.Queue(maxsize=4)
        self.engine = AcquisitionEngine(self.events.put)
        self.hardware = HardwareConfig()
        self.analyzer = _Analyzer(self._push_result)
        self.reference: AlignmentReference | None = None
        self.processor: AlignmentProcessor | None = None
        self.latest: AlignmentResult | None = None
        self.frozen = False
        self.trend: deque[tuple[float, float, float, float, float]] = deque()
        self.best: tuple[float, float, AlignmentResult] | None = None  # (fwhm, t, result)
        self.frames = 0
        self.frame_times: deque[float] = deque(maxlen=30)
        self.acquired_alines = 0
        self.t0 = time.monotonic()
        self._closing = False
        self._source_text = ""
        self.psf_window_um: tuple[float, float] | None = None
        self._errors_seen = 0
        self.pipeline = AlignmentPipeline(
            PipelineTargets.load(DEFAULT_TARGETS),
            sensor_max=float((1 << self.hardware.sensor_bit_depth) - 1))
        self._capture_buffer: list[AlignmentResult] | None = None
        self.pipeline_visible = True
        self._pipeline_view: StepView | None = None

        self._build_style()
        self._build_layout()
        self._load_reference(reference_path or DEFAULT_REFERENCE, quiet=True)
        self._refresh_pipeline_static()
        self.root.after(40, self._poll)

    # -- layout ---------------------------------------------------------------
    def _build_style(self) -> None:
        style = ttk.Style(self.root)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TFrame", background=BG)
        style.configure("Bar.TFrame", background=CARD)
        style.configure("Bar.TLabel", background=CARD, foreground=INK, font=("Segoe UI", 10))
        style.configure("Bar.TCheckbutton", background=CARD, font=("Segoe UI", 10))
        style.configure("Primary.TButton", font=("Segoe UI", 11, "bold"), padding=(18, 8),
                        foreground="#ffffff", background=GOOD)
        style.map("Primary.TButton", background=[("disabled", "#9fd8bf"), ("active", "#178a5b")])
        style.configure("Danger.TButton", font=("Segoe UI", 11, "bold"), padding=(18, 8),
                        foreground="#ffffff", background=BAD)
        style.map("Danger.TButton", background=[("disabled", "#eab1b1"), ("active", "#b83737")])
        style.configure("TButton", font=("Segoe UI", 10), padding=(12, 7))
        style.configure("TCombobox", padding=5)

    def _build_layout(self) -> None:
        header = tk.Frame(self.root, bg=NAVY, padx=24, pady=14)
        header.pack(fill="x")
        title = tk.Frame(header, bg=NAVY)
        title.pack(side="left")
        tk.Label(title, text="Alineación del espectrómetro", bg=NAVY, fg="#ffffff",
                 font=("Segoe UI", 22, "bold")).pack(anchor="w")
        self.reference_var = tk.StringVar(value="Referencia: —")
        tk.Label(title, textvariable=self.reference_var, bg=NAVY, fg=NAVY_TEXT,
                 font=("Segoe UI", 10)).pack(anchor="w")
        status = tk.Frame(header, bg=NAVY)
        status.pack(side="right")
        self.status_dot = tk.Canvas(status, width=18, height=18, bg=NAVY, highlightthickness=0)
        self.status_dot.grid(row=0, column=0, rowspan=2, padx=(0, 10))
        self.status_var = tk.StringVar(value="Detenido")
        tk.Label(status, textvariable=self.status_var, bg=NAVY, fg="#ffffff",
                 font=("Segoe UI", 14, "bold"), anchor="w").grid(row=0, column=1, sticky="w")
        self.rate_var = tk.StringVar(value="Sin adquisición")
        tk.Label(status, textvariable=self.rate_var, bg=NAVY, fg=NAVY_TEXT,
                 font=("Segoe UI", 10), anchor="w").grid(row=1, column=1, sticky="w")
        self._set_status("Detenido", NEUTRAL)

        bar = ttk.Frame(self.root, style="Bar.TFrame", padding=(24, 10))
        bar.pack(fill="x")
        ttk.Label(bar, text="Fuente", style="Bar.TLabel").pack(side="left")
        self.backend_var = tk.StringVar(value="Hardware NI")
        ttk.Combobox(bar, textvariable=self.backend_var, values=("Hardware NI", "Simulación"),
                     state="readonly", width=14).pack(side="left", padx=(8, 14))
        self.start_button = ttk.Button(bar, text="▶  Iniciar", style="Primary.TButton", command=self._start)
        self.start_button.pack(side="left")
        self.stop_button = ttk.Button(bar, text="■  Detener", style="Danger.TButton", command=self._stop,
                                      state="disabled")
        self.stop_button.pack(side="left", padx=(8, 22))
        ttk.Button(bar, text="Cargar referencia…", command=self._choose_reference).pack(side="left")
        ttk.Button(bar, text="Fijar actual como referencia", command=self._save_reference).pack(
            side="left", padx=(8, 0))
        ttk.Button(bar, text="Reiniciar tendencia", command=self._reset_trend).pack(side="left", padx=(8, 0))
        self.freeze_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(bar, text="Congelar pantalla", variable=self.freeze_var, style="Bar.TCheckbutton",
                        command=lambda: setattr(self, "frozen", self.freeze_var.get())).pack(
            side="left", padx=(18, 0))
        self.flip_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(bar, text="Invertir eje espectral", variable=self.flip_var, style="Bar.TCheckbutton",
                        command=lambda: self.analyzer.configure(flip=self.flip_var.get())).pack(
            side="left", padx=(14, 0))
        ttk.Label(bar, text="Promedio", style="Bar.TLabel").pack(side="left", padx=(18, 6))
        self.average_var = tk.IntVar(value=3)
        spin = ttk.Spinbox(bar, from_=1, to=20, width=4, textvariable=self.average_var,
                           command=self._average_changed)
        spin.pack(side="left")
        spin.bind("<Return>", lambda _e: self._average_changed())
        ttk.Label(bar, text="cuadros", style="Bar.TLabel").pack(side="left", padx=(6, 0))
        self.pipeline_button = ttk.Button(bar, text="◂ Ocultar pipeline", command=self._toggle_pipeline)
        self.pipeline_button.pack(side="right")

        guide = tk.Frame(self.root, bg=NAVY, padx=24, pady=10)
        guide.pack(fill="x", side="bottom")   # packed before the body: never squeezed out
        center = ttk.Frame(self.root)
        center.pack(fill="both", expand=True)
        self.sidebar = tk.Frame(center, bg=CARD, width=440, highlightthickness=1, highlightbackground="#d5dde8")
        self.sidebar.pack(side="left", fill="y", padx=(18, 0), pady=(12, 6))
        self.sidebar.pack_propagate(False)
        self._build_pipeline_panel(self.sidebar)
        body = ttk.Frame(center, padding=(14, 12, 18, 6))
        body.pack(side="left", fill="both", expand=True)
        body.columnconfigure(0, weight=1)
        body.rowconfigure(1, weight=4)
        body.rowconfigure(2, weight=5)

        kpis = ttk.Frame(body)
        kpis.grid(row=0, column=0, sticky="ew")
        self.tiles: dict[str, KpiTile] = {}
        specs = (
            ("ratio", "Equilibrio azul / rojo", "", "px600 / px1300"),
            ("focus", "Enfoque del espectrómetro", "", "Contraste de franjas"),
            ("fwhm_esp", "Resolución del espectro", "µm", "FWHM limitado por el espectro"),
            ("width", "Ancho espectral al 50 %", "px", "Bordes sobre la cámara"),
            ("psf", "FWHM del espejo", "µm", "Como Penetration_Analysis"),
            ("counts", "Cuentas máximas", "", "Sensor de 12 bits"),
        )
        for i, (key, title, unit, hint) in enumerate(specs):
            tile = KpiTile(kpis, title, unit, hint)
            tile.grid(row=0, column=i, sticky="nsew", padx=(0 if i == 0 else 10, 0))
            kpis.columnconfigure(i, weight=1, uniform="kpi")
            self.tiles[key] = tile

        main = tk.Frame(body, bg=CARD, highlightthickness=1, highlightbackground="#d5dde8")
        main.grid(row=1, column=0, sticky="nsew", pady=(12, 0))
        self.envelope_plot = PlotCanvas(
            main, title="Forma del espectro sobre la cámara", xlabel="Píxel de la cámara",
            ylabel="Envolvente normalizada", height=250, legend_anchor="nw")
        self.envelope_plot.pack(fill="both", expand=True, padx=6, pady=6)

        lower = ttk.Frame(body)
        lower.grid(row=2, column=0, sticky="nsew", pady=(12, 0))
        for i, weight in enumerate((4, 5, 4)):
            lower.columnconfigure(i, weight=weight, uniform="lower")
        lower.rowconfigure(0, weight=1)
        cards = []
        for i in range(3):
            card = tk.Frame(lower, bg=CARD, highlightthickness=1, highlightbackground="#d5dde8")
            card.grid(row=0, column=i, sticky="nsew", padx=(0 if i == 0 else 10, 0))
            cards.append(card)
        self.lower_tabs = ttk.Notebook(cards[0])
        self.lower_tabs.pack(fill="both", expand=True, padx=4, pady=4)
        tab_counts, tab_contrast = tk.Frame(self.lower_tabs, bg=CARD), tk.Frame(self.lower_tabs, bg=CARD)
        self.lower_tabs.add(tab_counts, text="  Cuentas  ")
        self.lower_tabs.add(tab_contrast, text="  Contraste local (enfoque)  ")
        self.counts_plot = PlotCanvas(tab_counts, title="Espectro medio (cuentas)", xlabel="Píxel de la cámara",
                                      ylabel="Cuentas", height=210, legend_anchor="nw")
        self.counts_plot.pack(fill="both", expand=True, padx=2, pady=2)
        self.contrast_plot = PlotCanvas(tab_contrast, title="Contraste de franjas a lo largo de la cámara",
                                        xlabel="Píxel de la cámara", ylabel="Contraste", height=210,
                                        legend=False)
        self.contrast_plot.pack(fill="both", expand=True, padx=2, pady=2)
        psf_card = cards[1]
        controls = tk.Frame(psf_card, bg=CARD)
        controls.pack(fill="x", padx=10, pady=(8, 0))
        tk.Label(controls, text="Ventana PSF", bg=CARD, fg=INK, font=("Segoe UI", 10, "bold")).pack(side="left")
        self.psf_mode_var = tk.StringVar(value="auto")
        for text, value in (("Automática", "auto"), ("Manual", "manual")):
            tk.Radiobutton(controls, text=text, value=value, variable=self.psf_mode_var, bg=CARD,
                           activebackground=CARD, font=("Segoe UI", 10),
                           command=self._psf_mode_changed).pack(side="left", padx=(8, 0))
        self.psf_from_var, self.psf_to_var = tk.StringVar(), tk.StringVar()
        for label, var in (("desde", self.psf_from_var), ("hasta", self.psf_to_var)):
            tk.Label(controls, text=label, bg=CARD, fg=MUTED, font=("Segoe UI", 10)).pack(side="left", padx=(12, 4))
            entry = ttk.Entry(controls, textvariable=var, width=7)
            entry.pack(side="left")
            entry.bind("<Return>", lambda _e: self._apply_psf_entries())
        tk.Label(controls, text="µm", bg=CARD, fg=MUTED, font=("Segoe UI", 10)).pack(side="left", padx=(4, 0))
        ttk.Button(controls, text="Aplicar", command=self._apply_psf_entries).pack(side="left", padx=(10, 0))
        self.ascan_plot = PlotCanvas(
            psf_card, title="A-scan · arrastre para fijar la ventana de la PSF", xlabel="Profundidad [µm]",
            ylabel="dB", height=120, legend=False, margins=(52, 14, 30, 38),
            on_select=self._psf_window_selected)
        self.ascan_plot.pack(fill="both", expand=True, padx=6, pady=(4, 0))
        self.psf_plot = PlotCanvas(psf_card, title="PSF del espejo", xlabel="Profundidad [µm]",
                                   ylabel="|FFT| norm.", height=130, margins=(52, 14, 30, 38))
        self.psf_plot.pack(fill="both", expand=True, padx=6, pady=(0, 6))
        trend_frame = tk.Frame(cards[2], bg=CARD)
        trend_frame.pack(fill="both", expand=True, padx=6, pady=6)
        self.trend_ratio = PlotCanvas(trend_frame, title="Tendencia · equilibrio azul/rojo", xlabel="",
                                      ylabel="", height=110, legend=False, margins=(54, 14, 30, 22))
        self.trend_ratio.pack(fill="both", expand=True)
        self.trend_fwhm = PlotCanvas(trend_frame, title="Tendencia · FWHM limitado por el espectro [µm]",
                                     xlabel="Segundos", ylabel="", height=120, legend=False,
                                     margins=(54, 14, 30, 36))
        self.trend_fwhm.pack(fill="both", expand=True)

        self.guide_icon = tk.Label(guide, text="●", bg=NAVY, fg=NEUTRAL, font=("Segoe UI", 18))
        self.guide_icon.pack(side="left")
        self.guide_var = tk.StringVar(value="Pulse Iniciar para comenzar. Cierre la GUI principal si "
                                             "está usando la cámara: NI-IMAQ es exclusivo.")
        tk.Label(guide, textvariable=self.guide_var, bg=NAVY, fg="#ffffff", font=("Segoe UI", 13, "bold"),
                 anchor="w", justify="left").pack(side="left", padx=(10, 0), fill="x", expand=True)
        self.best_var = tk.StringVar(value="")
        tk.Label(guide, textvariable=self.best_var, bg=NAVY, fg=NAVY_TEXT, font=("Segoe UI", 10),
                 anchor="e", justify="right").pack(side="right")

    # -- pipeline panel -----------------------------------------------------------
    def _build_pipeline_panel(self, parent: tk.Frame) -> None:
        head = tk.Frame(parent, bg=NAVY, padx=16, pady=10)
        head.pack(fill="x")
        tk.Label(head, text="Pipeline de alineación", bg=NAVY, fg="#ffffff",
                 font=("Segoe UI", 15, "bold")).pack(anchor="w")
        self.pipe_progress_var = tk.StringVar()
        tk.Label(head, textvariable=self.pipe_progress_var, bg=NAVY, fg=NAVY_TEXT,
                 font=("Segoe UI", 9)).pack(anchor="w")
        steps = tk.Frame(parent, bg=CARD, padx=14, pady=8)
        steps.pack(fill="x")
        self.step_rows: list[tuple[tk.Frame, tk.Canvas, tk.Label]] = []
        for i, step in enumerate(STEPS):
            row = tk.Frame(steps, bg=CARD, cursor="hand2")
            row.pack(fill="x", pady=1)
            dot = tk.Canvas(row, width=26, height=26, bg=CARD, highlightthickness=0, cursor="hand2")
            dot.pack(side="left")
            label = tk.Label(row, text=step.title, bg=CARD, fg=INK, font=("Segoe UI", 10), anchor="w",
                             cursor="hand2")
            label.pack(side="left", padx=(8, 0), fill="x", expand=True)
            for widget in (row, dot, label):
                widget.bind("<Button-1>", lambda _e, k=i: self._pipeline_goto(k))
            self.step_rows.append((row, dot, label))
        tk.Frame(parent, bg="#e3e9f0", height=1).pack(fill="x", padx=14)
        detail = tk.Frame(parent, bg=CARD, padx=16, pady=8)
        detail.pack(fill="both", expand=True)
        self.pipe_title_var = tk.StringVar()
        tk.Label(detail, textvariable=self.pipe_title_var, bg=CARD, fg=INK, font=("Segoe UI", 13, "bold"),
                 anchor="w", justify="left", wraplength=400).pack(fill="x")
        self.pipe_instr_var = tk.StringVar()
        tk.Label(detail, textvariable=self.pipe_instr_var, bg=CARD, fg="#36465e", font=("Segoe UI", 10),
                 anchor="w", justify="left", wraplength=400).pack(fill="x", pady=(4, 8))
        crit = tk.Frame(detail, bg=CARD)
        crit.pack(fill="x")
        crit.columnconfigure(1, weight=1)
        self.crit_rows: list[tuple[tk.Canvas, tk.Label, tk.Label, tk.Label]] = []
        for i in range(6):
            dot = tk.Canvas(crit, width=14, height=14, bg=CARD, highlightthickness=0)
            label = tk.Label(crit, bg=CARD, fg=INK, font=("Segoe UI", 10), anchor="w")
            value = tk.Label(crit, bg=CARD, fg=INK, font=("Segoe UI", 10, "bold"), anchor="e")
            target = tk.Label(crit, bg=CARD, fg=MUTED, font=("Segoe UI", 8), anchor="w", justify="left",
                              wraplength=380)
            dot.grid(row=2 * i, column=0, padx=(0, 6), pady=(4, 0))
            label.grid(row=2 * i, column=1, sticky="w", pady=(4, 0))
            value.grid(row=2 * i, column=2, sticky="e", pady=(4, 0))
            target.grid(row=2 * i + 1, column=1, columnspan=2, sticky="w")
            self.crit_rows.append((dot, label, value, target))
        self.pipe_hint_var = tk.StringVar()
        tk.Label(detail, textvariable=self.pipe_hint_var, bg=CARD, fg="#b06a00", font=("Segoe UI", 10, "bold"),
                 anchor="w", justify="left", wraplength=400).pack(fill="x", pady=(8, 0))
        self.pipe_capture_var = tk.StringVar()
        tk.Label(detail, textvariable=self.pipe_capture_var, bg=CARD, fg=GOOD, font=("Segoe UI", 10, "bold"),
                 anchor="w", justify="left", wraplength=400).pack(fill="x", pady=(4, 0))
        buttons = tk.Frame(detail, bg=CARD)
        buttons.pack(fill="x", pady=(10, 0))
        self.pipe_prev = ttk.Button(buttons, text="◂", width=3, command=self._pipeline_prev)
        self.pipe_prev.pack(side="left")
        self.pipe_capture = ttk.Button(buttons, text="Capturar", style="Primary.TButton",
                                       command=self._pipeline_capture)
        self.pipe_capture.pack(side="left", padx=(8, 0))
        self.pipe_next = ttk.Button(buttons, text="Siguiente ▸", command=self._pipeline_next)
        self.pipe_next.pack(side="left", padx=(8, 0))
        self.pipe_skip = ttk.Button(buttons, text="Omitir", command=self._pipeline_skip)
        self.pipe_skip.pack(side="left", padx=(8, 0))
        footer = tk.Frame(parent, bg=CARD, padx=16, pady=8)
        footer.pack(fill="x", side="bottom")
        ttk.Button(footer, text="Guardar informe", command=self._save_pipeline_report).pack(side="left")
        ttk.Button(footer, text="Reiniciar pipeline", command=self._reset_pipeline).pack(side="left", padx=(8, 0))
        self.pipe_log_var = tk.StringVar()
        tk.Label(parent, textvariable=self.pipe_log_var, bg=CARD, fg=MUTED, font=("Segoe UI", 8), anchor="sw",
                 justify="left", wraplength=400, padx=16).pack(fill="x", side="bottom")

    def _toggle_pipeline(self) -> None:
        self.pipeline_visible = not self.pipeline_visible
        if self.pipeline_visible:
            self.sidebar.pack(side="left", fill="y", padx=(18, 0), pady=(12, 6), before=self.sidebar.master
                              .winfo_children()[-1])
            self.pipeline_button.configure(text="◂ Ocultar pipeline")
        else:
            self.sidebar.pack_forget()
            self.pipeline_button.configure(text="Pipeline de alineación ▸")

    def _refresh_pipeline_static(self) -> None:
        pipe = self.pipeline
        step = pipe.step
        colors = {"active": REF_COLOR, "done": GOOD, "skipped": "#9aa7b8", "pending": "#c9d3df"}
        for i, (row, dot, label) in enumerate(self.step_rows):
            status = pipe.status_of(STEPS[i].key)
            dot.delete("all")
            dot.create_oval(2, 2, 24, 24, fill=colors[status], outline="")
            dot.create_text(13, 13, text="✓" if status == "done" else str(i + 1), fill="#ffffff",
                            font=("Segoe UI", 9, "bold"))
            label.configure(font=("Segoe UI", 10, "bold" if status == "active" else "normal"),
                            fg=INK if status in ("active", "done") else MUTED)
            row.configure(bg="#eef4fc" if status == "active" else CARD)
            label.configure(bg="#eef4fc" if status == "active" else CARD)
            dot.configure(bg="#eef4fc" if status == "active" else CARD)
        self.pipe_progress_var.set(f"Paso {pipe.index + 1} de {len(STEPS)}  ·  "
                                   f"{len(pipe.completed)} completados")
        self.pipe_title_var.set(f"{pipe.index + 1}. {step.title}")
        self.pipe_instr_var.set(step.instructions)
        if step.capture_label:
            self.pipe_capture.configure(text=step.capture_label)
            self.pipe_capture.pack(side="left", padx=(8, 0), after=self.pipe_prev)
        else:
            self.pipe_capture.pack_forget()
        if step.optional:
            self.pipe_skip.pack(side="left", padx=(8, 0))
        else:
            self.pipe_skip.pack_forget()
        self.pipe_next.configure(text="Finalizar ✓" if pipe.index == len(STEPS) - 1 else "Siguiente ▸")
        self.pipe_capture_var.set("")
        self.pipe_log_var.set("\n".join(pipe.log[-4:]))
        if step.key in ("interferencia", "enfoque"):
            self.lower_tabs.select(1)
        elif step.key in ("oscuro", "referencia", "muestra"):
            self.lower_tabs.select(0)

    def _render_pipeline(self, view: StepView) -> None:
        self._pipeline_view = view
        for i, (dot, label, value, target) in enumerate(self.crit_rows):
            if i < len(view.criteria):
                c = view.criteria[i]
                dot.delete("all")
                dot.create_oval(2, 2, 12, 12, fill=STATUS_COLORS[c.status], outline="")
                label.configure(text=c.label)
                value.configure(text=c.value, fg=STATUS_COLORS[c.status] if c.status != "neutral" else INK)
                target.configure(text=c.target)
                for w in (dot, label, value, target):
                    w.grid()
            else:
                for w in (dot, label, value, target):
                    w.grid_remove()
        self.pipe_hint_var.set(view.hint)
        capturing = self._capture_buffer is not None
        self.pipe_capture.configure(state="normal" if view.can_capture and not capturing else "disabled")
        self.pipe_next.configure(style="Primary.TButton" if view.ready else "TButton")

    def _pipeline_goto(self, index: int) -> None:
        self._capture_buffer = None
        self.pipeline.goto(index)
        self._refresh_pipeline_static()

    def _pipeline_prev(self) -> None:
        self._pipeline_goto(self.pipeline.index - 1)

    def _pipeline_next(self) -> None:
        if self.pipeline.index == len(STEPS) - 1:
            self.pipeline.completed.add(self.pipeline.step.key)
            self._save_pipeline_report()
            self._refresh_pipeline_static()
            return
        self.pipeline.next()
        self._refresh_pipeline_static()

    def _pipeline_skip(self) -> None:
        self.pipeline.skip()
        self._refresh_pipeline_static()

    def _pipeline_capture(self) -> None:
        if not self.engine.is_active:
            messagebox.showinfo("Pipeline", "Inicie la adquisición antes de capturar.")
            return
        self._capture_buffer = []
        self.pipe_capture.configure(state="disabled")
        self.pipe_capture_var.set(f"Capturando 0/{CAPTURE_FRAMES} cuadros… no mueva nada.")

    def _feed_capture(self, result: AlignmentResult) -> None:
        if self._capture_buffer is None:
            return
        self._capture_buffer.append(result)
        n = len(self._capture_buffer)
        if n < CAPTURE_FRAMES:
            self.pipe_capture_var.set(f"Capturando {n}/{CAPTURE_FRAMES} cuadros… no mueva nada.")
            return
        frames, self._capture_buffer = self._capture_buffer, None
        step_key = self.pipeline.step.key
        try:
            message = self.pipeline.capture(frames)
        except Exception as exc:
            messagebox.showerror("Captura", str(exc))
            self.pipe_capture_var.set("")
            return
        self.analyzer.configure(dark=self.pipeline.dark, rho=self.pipeline.rho)
        if step_key == "verificacion":
            path = self.pipeline.save_report(SESSIONS_DIR)
            message += f" Informe: {path.name}"
        else:
            self.pipeline.goto(self.pipeline.index + 1)
        self._refresh_pipeline_static()
        self.pipe_capture_var.set("✔ " + message)

    def _save_pipeline_report(self) -> None:
        path = self.pipeline.save_report(SESSIONS_DIR)
        self.pipe_capture_var.set(f"✔ Informe guardado: {path}")

    def _reset_pipeline(self) -> None:
        if not messagebox.askyesno("Pipeline", "¿Borrar las capturas y empezar el pipeline desde el paso 1?"):
            return
        self.pipeline = AlignmentPipeline(self.pipeline.targets, sensor_max=self.pipeline.sensor_max)
        self.analyzer.configure(dark=None, rho=None)
        self._capture_buffer = None
        self._refresh_pipeline_static()

    # -- reference --------------------------------------------------------------
    def _load_reference(self, path: Path, *, quiet: bool = False) -> None:
        try:
            reference = AlignmentReference.load(path)
        except Exception as exc:
            self.reference_var.set(f"Referencia: no disponible ({path.name})")
            if not quiet:
                messagebox.showerror("Referencia", f"No se pudo cargar {path}:\n{exc}")
            return
        self.reference = reference
        sensor_max = float((1 << self.hardware.sensor_bit_depth) - 1)
        self.processor = AlignmentProcessor(reference.params, sensor_max=sensor_max)
        self.analyzer.configure(processor=self.processor, reference=reference)
        p = reference.params
        exact = "spline" if self.processor.spline_exact else "lineal (instale SciPy)"
        self.reference_var.set(
            f"Referencia: {reference.name}  ·  creada {reference.created}  ·  λ {p.lambda_start_nm:.2f}–"
            f"{p.lambda_end_nm:.2f} nm  ·  {p.um_per_px:.4f} µm/px  ·  interp. {exact}"
        )
        self._reset_trend()
        if self.latest is not None:
            compare(self.latest, reference)
            self._render(self.latest)

    def _choose_reference(self) -> None:
        selected = filedialog.askopenfilename(
            title="Cargar referencia de alineación", initialdir=CONFIG_DIR,
            filetypes=(("Referencia de alineación", "*.json"), ("Todos", "*.*")))
        if selected:
            self._load_reference(Path(selected))

    def _save_reference(self) -> None:
        if self.latest is None or self.reference is None:
            messagebox.showinfo("Fijar referencia", "Todavía no hay un cuadro adquirido.")
            return
        default = f"alineacion_referencia_{datetime.now():%Y%m%d_%H%M%S}.json"
        selected = filedialog.asksaveasfilename(
            title="Guardar el espectro actual como referencia", initialdir=CONFIG_DIR, initialfile=default,
            defaultextension=".json", filetypes=(("Referencia de alineación", "*.json"),))
        if not selected:
            return
        ref = AlignmentReference.from_result(self.latest, self.reference.params, Path(selected).stem)
        path = ref.save(selected)
        self._load_reference(path)

    # -- acquisition -------------------------------------------------------------
    def _set_status(self, text: str, color: str) -> None:
        self.status_var.set(text)
        self.status_dot.delete("all")
        self.status_dot.create_oval(2, 2, 16, 16, fill=color, outline="")

    def _start(self) -> None:
        if self.engine.is_active:
            return
        if self.processor is None:
            messagebox.showerror("Sin referencia", "Cargue primero una referencia de alineación (.json).")
            return
        try:
            # Same plan as octoce.gui.OCTOCEApp._start_alignment
            scan = ScanParameters(alines=1, bscans=1, m_repetitions=1000, sync_points=0,
                                  x_length_mm=0.0, y_length_mm=0.0, mode=AcquisitionMode.MB,
                                  pattern=ScanPattern.LINEAR)
            hardware = self.hardware
            real = self.backend_var.get() == "Hardware NI"
            if real:
                hardware, block_rate_hz = stationary_alignment_timing(hardware, 1000)
            else:
                block_rate_hz = hardware.effective_line_rate_hz / 1000
            scan.validate()
            hardware.validate(scan)
            if real:
                if not hardware.oce_enabled:
                    raise RuntimeError("La alineación continua necesita la salida OCE (PFI13) habilitada.")
                if not messagebox.askyesno(
                    "Alineación continua",
                    "AO0/AO1 se mantendrán en 0 V (centro). Se adquirirán grupos MB de 1000 A-lines "
                    "indefinidamente, sin guardar ni puntos sync. PFI12 y PFI13 se temporizarán por "
                    f"hardware cada {1000 / block_rate_hz:.2f} ms; PFI13 tendrá 10 % de ciclo útil "
                    "(dispara la excitación OCE si está conectada). La cámara usará "
                    f"{hardware.effective_line_rate_hz / 1000:.3f} klps.\n\n"
                    "Cierre la GUI principal si la tiene abierta: NI-IMAQ es exclusivo. ¿Iniciar?",
                    icon="warning",
                ):
                    return
                backend = NIHardwareBackend(continuous_alignment=True, alignment_block_rate_hz=block_rate_hz)
            else:
                backend = SimulatedBackend()
            self.engine.set_preview_remove_dc(False)
            self.engine.set_preview_depth_range(1, 64)   # only the raw spectra are used here
            self.analyzer.reset()
            self.acquired_alines = 0
            self.frame_times.clear()
            self._source_text = (f"{'Hardware NI' if real else 'Simulación'} · "
                                 f"{hardware.effective_line_rate_hz / 1000:.3f} klps · "
                                 f"bloques de 1000 A-lines a {block_rate_hz:.1f} Hz")
            self.engine.start(scan, hardware, output_path=None, backend=backend, continuous=True)
            self.start_button.configure(state="disabled")
            self.stop_button.configure(state="normal")
            self._set_status("Armando…", WARN)
        except Exception as exc:
            messagebox.showerror("No se puede iniciar", str(exc))

    def _stop(self) -> None:
        self.engine.stop()
        self.stop_button.configure(state="disabled")

    def _push_result(self, result: AlignmentResult) -> None:
        try:
            self.results.put_nowait(result)
        except queue.Full:
            try:
                self.results.get_nowait()
            except queue.Empty:
                pass
            self.results.put_nowait(result)

    def _poll(self) -> None:
        if self._closing:
            return
        try:
            while True:
                event = self.events.get_nowait()
                self._handle_event(event)
        except queue.Empty:
            pass
        latest = None
        try:
            while True:
                latest = self.results.get_nowait()
        except queue.Empty:
            pass
        if self.analyzer.errors > self._errors_seen:
            self._errors_seen = self.analyzer.errors
            self.guide_var.set(f"⚠  Análisis: {self.analyzer.last_error}")
            self.guide_icon.configure(fg=WARN)
        if latest is not None:
            self._feed_capture(latest)
            self.latest = latest
            self.frames += 1
            self.frame_times.append(time.monotonic())
            self._update_trend(latest)
            if not self.frozen:
                self._render(latest)
        self.root.after(40, self._poll)

    def _handle_event(self, event: EngineEvent) -> None:
        kind, payload = event.kind, event.payload
        if kind == "preview":
            spectra = payload.get("source_spectra")
            if spectra is not None:
                self.analyzer.submit(np.asarray(spectra))
        elif kind == "progress":
            self.acquired_alines = int(payload.get("acquired_alines", 0))
            fps = 0.0
            if len(self.frame_times) >= 2:
                fps = (len(self.frame_times) - 1) / max(self.frame_times[-1] - self.frame_times[0], 1e-6)
            lost = payload.get("lost_buffers", 0)
            self.rate_var.set(f"{self._source_text}  ·  análisis {fps:.1f} Hz  ·  "
                              f"{self.acquired_alines:,} A-lines  ·  buffers perdidos {lost}")
        elif kind == "state":
            state = payload.get("state")
            if state == "arming":
                self._set_status("Armando…", WARN)
            elif state == "running":
                self._set_status("Adquiriendo", GOOD)
            elif state in ("stopped", "completed"):
                self._set_status("Detenido", NEUTRAL)
                self._idle_buttons()
            elif state == "error":
                self._set_status("Error", BAD)
                self._idle_buttons()
                reason = payload.get("reason") or "Error desconocido."
                self.guide_var.set(f"Adquisición detenida: {reason}")
                self.guide_icon.configure(fg=BAD)
            elif state == "stopping":
                self._set_status("Deteniendo…", WARN)
        elif kind in ("error", "consumer_error"):
            self.guide_var.set(f"Error: {payload.get('message', '')}")
            self.guide_icon.configure(fg=BAD)

    def _idle_buttons(self) -> None:
        self.start_button.configure(state="normal")
        self.stop_button.configure(state="disabled")

    # -- manual PSF window -------------------------------------------------------
    def _psf_window_selected(self, lo: float | None, hi: float | None) -> None:
        """Drag on the A-scan sets a manual window; double click returns to automatic."""
        if lo is None or hi is None:
            self.psf_mode_var.set("auto")
            self._apply_psf_window(None)
            return
        self.psf_from_var.set(f"{lo:.0f}")
        self.psf_to_var.set(f"{hi:.0f}")
        self._apply_psf_entries()

    def _psf_mode_changed(self) -> None:
        if self.psf_mode_var.get() == "auto":
            self._apply_psf_window(None)
            return
        if not (self.psf_from_var.get().strip() and self.psf_to_var.get().strip()):
            if self.latest is not None and self.latest.psf is not None:
                depth = self.latest.psf.depth_um
                self.psf_from_var.set(f"{max(0.0, depth - 150):.0f}")
                self.psf_to_var.set(f"{depth + 150:.0f}")
            else:
                self.guide_var.set("Escriba 'desde' y 'hasta' en µm o arrastre sobre el A-scan para elegir "
                                   "la ventana de la PSF.")
                return
        self._apply_psf_entries()

    def _apply_psf_entries(self) -> None:
        try:
            lo = float(self.psf_from_var.get().replace(",", "."))
            hi = float(self.psf_to_var.get().replace(",", "."))
        except ValueError:
            messagebox.showerror("Ventana PSF", "Escriba los límites 'desde' y 'hasta' en µm.")
            return
        lo, hi = sorted((lo, hi))
        um = self.processor.params.um_per_px if self.processor else 1.48
        if hi - lo < 6 * um:
            messagebox.showerror("Ventana PSF", f"La ventana debe medir al menos {6 * um:.0f} µm.")
            return
        self.psf_from_var.set(f"{lo:.0f}")
        self.psf_to_var.set(f"{hi:.0f}")
        self.psf_mode_var.set("manual")
        self._apply_psf_window((lo, hi))

    def _apply_psf_window(self, window: tuple[float, float] | None) -> None:
        self.psf_window_um = window
        self._errors_seen = self.analyzer.errors
        self.analyzer.configure(search_um=window)

    def _average_changed(self) -> None:
        try:
            self.analyzer.configure(average=int(self.average_var.get()))
        except (tk.TclError, ValueError):
            pass

    # -- trend -------------------------------------------------------------------
    def _reset_trend(self) -> None:
        self.trend.clear()
        self.best = None
        self.best_var.set("")
        self.t0 = time.monotonic()

    def _update_trend(self, r: AlignmentResult) -> None:
        now = time.monotonic() - self.t0
        psf_fwhm = r.psf.fwhm_fit_um if r.psf is not None else float("nan")
        rms = r.rms_diff_pct if r.rms_diff_pct is not None else float("nan")
        self.trend.append((now, r.spectrum.ratio, rms,
                           r.spectrum.fwhm_spectrum_um, psf_fwhm))
        while self.trend and now - self.trend[0][0] > self.TREND_SECONDS:
            self.trend.popleft()
        fwhm = r.spectrum.fwhm_spectrum_um
        sensor = self.processor.sensor_max if self.processor else 4095.0
        real_spectrum = r.spectrum.max_counts >= 0.2 * sensor
        if real_spectrum and math.isfinite(fwhm) and (self.best is None or fwhm < self.best[0]):
            self.best = (fwhm, now, r)

    # -- rendering ---------------------------------------------------------------
    @staticmethod
    def _grade(error: float, good: float, warn: float) -> str:
        if not math.isfinite(error):
            return "neutral"
        return "good" if error <= good else "warn" if error <= warn else "bad"

    def _render(self, r: AlignmentResult) -> None:
        ref = self.reference
        if ref is None:
            return
        s, rs = r.spectrum, ref.metrics
        warnings = [w for w in r.warnings if not w.startswith("__avg__")]
        n_avg = next((int(w[7:]) for w in r.warnings if w.startswith("__avg__")), 1)

        # KPI tiles
        d_ratio = s.ratio - rs.ratio
        self.tiles["ratio"].show(
            value=f"{s.ratio:.3f}", status=self._grade(abs(d_ratio), 0.03, 0.08),
            target=f"Objetivo {rs.ratio:.3f} ± 0.03  ·  px{ref.params.ratio_px[0]} / px{ref.params.ratio_px[1]}",
            delta=self._delta_text(d_ratio, "{:+.3f}"), delta_color=self._delta_color(abs(d_ratio), 0.03, 0.08),
            gauge=(min(0.2, rs.ratio - 0.3), max(1.0, rs.ratio + 0.3), s.ratio, rs.ratio - 0.03, rs.ratio + 0.03))
        rms = r.rms_diff_pct if r.rms_diff_pct is not None else float("nan")
        self._show_focus_tile(r)
        d_fwhm = s.fwhm_spectrum_um - rs.fwhm_spectrum_um
        rel = d_fwhm / rs.fwhm_spectrum_um if rs.fwhm_spectrum_um > 0 else float("nan")
        self.tiles["fwhm_esp"].show(
            value=f"{s.fwhm_spectrum_um:.2f}", status=self._grade(rel, 0.02, 0.08),
            target=f"Referencia {rs.fwhm_spectrum_um:.2f} µm  ·  menor es mejor",
            delta=self._delta_text(d_fwhm, "{:+.2f} µm"), delta_color=self._delta_color(rel, 0.02, 0.08),
            gauge=(rs.fwhm_spectrum_um * 0.85, rs.fwhm_spectrum_um * 1.35, s.fwhm_spectrum_um,
                   rs.fwhm_spectrum_um * 0.85, rs.fwhm_spectrum_um * 1.02))
        edge_err = max(abs(s.edges50_px[0] - rs.edges50_px[0]), abs(s.edges50_px[1] - rs.edges50_px[1]))
        self.tiles["width"].show(
            value=f"{s.width50_px}", status=self._grade(edge_err, 30, 80),
            target=f"Actual {s.edges50_px[0]}–{s.edges50_px[1]} px  ·  ref. {rs.edges50_px[0]}–{rs.edges50_px[1]} px",
            delta=self._delta_text(s.width50_px - rs.width50_px, "{:+.0f} px"),
            delta_color=self._delta_color(edge_err, 30, 80),
            gauge=(rs.width50_px * 0.6, rs.width50_px * 1.15, s.width50_px, rs.width50_px - 60, rs.width50_px + 60))
        if r.psf is not None:
            psf = r.psf
            ref_psf = f" · ref. {ref.psf.fwhm_fit_um:.2f} a {ref.psf.depth_um:.0f} µm" if ref.psf else ""
            if psf.manual_window:
                ref_psf = " · ventana manual"
            noisy = self._psf_is_noise(r)
            self.tiles["psf"].show(
                value=f"{psf.fwhm_fit_um:.2f}", status="bad" if noisy else "neutral",
                delta=f"SNR {psf.snr_db:.0f} dB", delta_color=BAD if noisy else MUTED,
                target=f"Espejo a {psf.depth_um:.0f} µm · directo {psf.fwhm_direct_um:.2f}{ref_psf}")
        sensor = self.processor.sensor_max if self.processor else 4095.0
        frac = s.max_counts / sensor
        self.tiles["counts"].show(
            value=f"{s.max_counts:.0f}",
            status="bad" if frac >= 0.999 else "warn" if frac >= 0.95 else "good" if frac >= 0.35 else "warn",
            target=f"{100 * frac:.0f} % del rango  ·  saturación en {sensor:.0f}",
            gauge=(0.0, sensor, s.max_counts, 0.35 * sensor, 0.95 * sensor))

        # Envelope plot
        px = np.arange(s.envelope_norm.size, dtype=float)
        cur, rn = s.envelope_norm, rs.envelope_norm
        rules = [Rule(p, "#7b8798", label=f"px {p}", label_bottom=True) for p in ref.params.ratio_px]
        rules += [Rule(BLUE_BAND_PX[0], "#b9c7da", dash=(2, 4)), Rule(RED_BAND_PX[1], "#b9c7da", dash=(2, 4)),
                  Rule(0.5, "#9aa7b8", vertical=False, label="50 %")]
        a, b = ref.params.ratio_px
        blue = r.blue_change_pct if r.blue_change_pct is not None else float("nan")
        red = r.red_change_pct if r.red_change_pct is not None else float("nan")
        texts = [
            (sum(BLUE_BAND_PX) / 2, 1.13, f"Lado azul  {blue:+.0f} %", self._band_color(blue), "center"),
            (sum(RED_BAND_PX) / 2, 1.13, f"Lado rojo  {red:+.0f} %", self._band_color(red), "center"),
        ]
        self.envelope_plot.set_data(
            xlim=(0, px[-1]), ylim=(0, 1.2),
            bands=[Band(px, np.minimum(cur, rn), rn, LOSS_FILL), Band(px, rn, np.maximum(cur, rn), GAIN_FILL)],
            series=[Series(px, rn, REF_COLOR, 3, label=f"Referencia · {ref.name}"),
                    Series(px, cur, CUR_COLOR, 3, label=f"Actual (promedio de {n_avg})")],
            markers=[Marker(a, rn[a], REF_COLOR), Marker(b, rn[b], REF_COLOR),
                     Marker(a, cur[a], CUR_COLOR, 7), Marker(b, cur[b], CUR_COLOR, 7)],
            rules=rules, texts=texts,
            title=f"Forma del espectro sobre la cámara  ·  RMS {rms:.1f} %  ·  naranja: pérdida respecto a "
                  "la referencia, azul: ganancia")

        # Counts plot
        top = max(sensor * 1.05, float(s.mean_spectrum.max()) * 1.1)
        count_series = [Series(px, s.mean_spectrum, "#f2b38f", 1, label="Espectro medio"),
                        Series(px, s.envelope, CUR_COLOR, 2.5, label="Envolvente actual")]
        count_rules = [Rule(sensor, BAD, vertical=False, label="Saturación", width=1.5)]
        pipe = self.pipeline
        dark_level = float(np.median(pipe.dark)) if pipe.dark is not None else 0.0
        if pipe.ir is not None:
            count_series.append(Series(px, pipe.ir + dark_level, REF_COLOR, 2, (5, 3), label="Ir capturado"))
        else:
            count_series.append(Series(px, rs.envelope, REF_COLOR, 2, (5, 3), label="Envolvente ref."))
        if pipe.is_ is not None:
            count_series.append(Series(px, pipe.is_ + dark_level, "#8e44ad", 2, (5, 3), label="Is capturado"))
        t = pipe.targets
        if self.pipeline_visible and pipe.step.key == "referencia":
            count_rules += [Rule(t.reference_min_pct / 100 * sensor, GOOD, vertical=False, label="banda Ir"),
                            Rule(t.reference_max_pct / 100 * sensor, GOOD, vertical=False)]
        elif self.pipeline_visible and pipe.step.key == "muestra" and pipe.sample_limit_counts() is not None:
            count_rules.append(Rule(pipe.sample_limit_counts() + dark_level, GOOD, vertical=False,
                                    label="límite Is", width=2))
        elif self.pipeline_visible and pipe.step.key == "interferencia":
            count_rules.append(Rule(t.interference_max_pct / 100 * sensor, WARN, vertical=False,
                                    label=f"{t.interference_max_pct:.0f} %"))
        self.counts_plot.set_data(xlim=(0, px[-1]), ylim=(0, top), series=count_series, rules=count_rules)

        # A-scan with the PSF search window
        window_rules: list[Rule] = []
        if r.psf is not None and r.psf.ascan.size:
            psf = r.psf
            um = ref.params.um_per_px
            z = np.arange(psf.ascan.size, dtype=float) * um
            peak_amp = 10.0 ** (psf.peak_db / 10.0)
            db = 20.0 * np.log10(np.maximum(psf.ascan, 1e-12) / peak_amp)
            lo_um, hi_um = psf.search_px[0] * um, psf.search_px[1] * um
            window_bands: list[Band] = []
            if psf.manual_window:
                window_bands = [Band(np.array([lo_um, hi_um]), np.array([-70.0, -70.0]),
                                     np.array([10.0, 10.0]), "#d3f0e2")]
                window_rules = [Rule(lo_um, GOOD, dash=(4, 2), width=1.5),
                                Rule(hi_um, GOOD, dash=(4, 2), width=1.5)]
                title = f"A-scan · ventana manual {lo_um:.0f}–{hi_um:.0f} µm  (doble clic: automática)"
            else:
                title = "A-scan · arrastre para fijar la ventana de la PSF"
            self.ascan_plot.set_data(
                xlim=(0.0, ref.params.px_max_search * um), ylim=(-60.0, 6.0),
                bands=window_bands, rules=window_rules,
                series=[Series(z, db, "#3d5a80", 1.2)],
                markers=[Marker(psf.depth_um, 0.0, CUR_COLOR, 5)], title=title)

        # PSF plot
        if r.psf is not None and r.psf.window_px.size:
            psf = r.psf
            um = ref.params.um_per_px
            xw = psf.window_px * um
            xf = np.linspace(psf.window_px[0], psf.window_px[-1], 600)
            scale = float(max(psf.window_amp.max(), 1e-12))
            fit = gauss_model(psf.fit_params, xf) / scale
            hm = (psf.fit_params[0] / 2 + psf.fit_params[3]) / scale
            half = abs(psf.fit_params[2]) / 2
            self.psf_plot.set_data(
                xlim=(xw[0], xw[-1]), ylim=(0, 1.15),
                series=[Series(xw, psf.window_amp / scale, "#7b8798", 1.5, label="Datos"),
                        Series(xf * um, fit, BAD, 2.5, label="Ajuste gauss"),
                        Series(np.array([psf.fit_params[1] - half, psf.fit_params[1] + half]) * um,
                               np.array([hm, hm]), GOOD, 3, label=f"FWHM {psf.fwhm_fit_um:.2f} µm")],
                rules=window_rules,
                title=f"PSF del espejo a {psf.depth_um:.0f} µm")

        # Trend plots
        if self.trend:
            data = np.asarray(self.trend, dtype=float)
            t = data[:, 0]
            t_lo, t_hi = max(0.0, t[-1] - self.TREND_SECONDS), max(t[-1], 10.0)
            ratio_vals = np.append(data[:, 1], rs.ratio)
            self.trend_ratio.set_data(
                xlim=(t_lo, t_hi), ylim=self._padded(ratio_vals, 0.02),
                series=[Series(t, data[:, 1], CUR_COLOR, 2)],
                rules=[Rule(rs.ratio, REF_COLOR, vertical=False, label=f"objetivo {rs.ratio:.3f}", width=1.5)])
            fwhm_vals = np.append(data[:, 3], rs.fwhm_spectrum_um)
            markers = []
            if self.best is not None:
                markers.append(Marker(self.best[1], self.best[0], GOOD, 6))
            self.trend_fwhm.set_data(
                xlim=(t_lo, t_hi), ylim=self._padded(fwhm_vals, 0.1),
                series=[Series(t, data[:, 3], CUR_COLOR, 2)], markers=markers,
                rules=[Rule(rs.fwhm_spectrum_um, REF_COLOR, vertical=False,
                            label=f"referencia {rs.fwhm_spectrum_um:.2f} µm", width=1.5)])

        if self.best is not None:
            age = time.monotonic() - self.t0 - self.best[1]
            br = self.best[2].spectrum
            self.best_var.set(f"Mejor de la sesión: {br.fwhm_spectrum_um:.2f} µm · equilibrio "
                              f"{br.ratio:.3f}\nhace {age:.0f} s")

        self._render_contrast(r)
        if self.pipeline_visible:
            self._render_pipeline(self.pipeline.evaluate(r, ref))
        self._update_guidance(r, warnings)

    @staticmethod
    def _psf_is_noise(r: AlignmentResult) -> bool:
        """Low SNR, or no measurable fringes (e.g. an arm covered: the DC tail fakes a peak)."""
        if r.psf is None:
            return True
        no_fringes = r.fringe is not None and r.fringe.valid and r.fringe.contrast < 0.03
        return r.psf.snr_db < PSF_MIN_SNR_DB or no_fringes

    def _sharpness_drop(self, r: AlignmentResult) -> float | None:
        """Spectral sharpness relative to the pipeline's final state (None if unknown)."""
        base = self.pipeline.sharpness_baseline
        if base is None or not math.isfinite(r.spectrum.sharpness) or base <= 0:
            return None
        return r.spectrum.sharpness / base

    def _show_focus_tile(self, r: AlignmentResult) -> None:
        t = self.pipeline.targets
        f = r.fringe
        tile = self.tiles["focus"]
        sharp = self._sharpness_drop(r)
        if f is not None and f.valid and f.focus_sensitive:
            value = f.contrast
            vis_txt = f" · V {f.visibility:.2f}" if math.isfinite(f.visibility) else ""
            lo, hi = t.blue_red
            w_lo, w_hi = t.blue_red_warn
            status = "good" if lo <= f.blue_red <= hi else "warn" if w_lo <= f.blue_red <= w_hi else "bad"
            best = self.pipeline.best_focus
            best_txt = f" · máx. {best['contrast']:.3f}" if best and abs(best["depth_um"] - f.depth_um) <= 60 else ""
            tile.show(value=f"{value:.3f}", status=status,
                      delta=f"azul/rojo {f.blue_red:.2f}", delta_color=STATUS_COLORS[status],
                      target=f"Contraste a {f.depth_um / 1000:.2f} mm{vis_txt}{best_txt}"
                             f" · azul/rojo P3 {lo:.2f}–{hi:.2f}",
                      gauge=(0.0, 1.0, value, 0.0, 1.0))
        elif sharp is not None:
            status = "good" if sharp >= 0.95 else "warn" if sharp >= t.sharpness_drop_warn else "bad"
            tile.show(value=f"{100 * sharp:.0f}", status=status, delta="nitidez",
                      delta_color=STATUS_COLORS[status],
                      target="% de la nitidez espectral del estado final del pipeline",
                      gauge=(0.5, 1.2, sharp, t.sharpness_drop_warn, 1.2))
        else:
            depth = r.psf.depth_um if r.psf is not None else float("nan")
            tile.show(value="—", status="neutral",
                      target=f"Espejo a {depth:.0f} µm: aquí no se ve el enfoque. Mida a ~2 mm (paso 6).")

    def _render_contrast(self, r: AlignmentResult) -> None:
        f = r.fringe
        if f is None or not f.valid:
            self.contrast_plot.show_message("Sin franjas medibles (espejo muy cerca del retardo cero o brazo tapado)")
            return
        profile = f.profile
        if math.isfinite(f.visibility) and self.pipeline.rho is not None:
            rho_k = np.interp(f.pixel, np.arange(self.pipeline.rho.size), self.pipeline.rho)
            profile = profile * (1 + rho_k) / (2 * np.sqrt(np.clip(rho_k, 1e-6, None)))
            label = "Visibilidad local"
        else:
            label = "Contraste local"
        finite = np.isfinite(profile)
        if np.count_nonzero(finite) >= 40:   # 31-sample moving average over the valid band
            kernel = np.ones(31) / 31
            filled = np.where(finite, profile, 0.0)
            weight = np.convolve(finite.astype(float), kernel, mode="same")
            profile = np.where(finite, np.convolve(filled, kernel, mode="same") / np.maximum(weight, 1e-9), np.nan)
        if np.count_nonzero(finite) < 10:
            self.contrast_plot.show_message("Sin franjas medibles")
            return
        top = max(1.0, float(np.nanmax(profile)) * 1.1) if label.startswith("Vis") else \
            float(np.nanmax(profile)) * 1.25
        order = np.argsort(f.pixel)
        sensitive = "" if f.focus_sensitive else "  ·  espejo demasiado cerca: insensible al enfoque"
        self.contrast_plot.set_data(
            xlim=(0, len(f.pixel) - 1), ylim=(0, top),
            series=[Series(f.pixel[order], profile[order], "#2f9e6e", 2.5, label=label)],
            rules=[Rule(BLUE_BAND_PX[1], "#b9c7da", dash=(2, 4)), Rule(RED_BAND_PX[0], "#b9c7da", dash=(2, 4))],
            texts=[(sum(BLUE_BAND_PX) / 2, top * 0.93, "lado azul", REF_COLOR, "center"),
                   (sum(RED_BAND_PX) / 2, top * 0.93, "lado rojo", BAD, "center")],
            title=f"{label} a {f.depth_um / 1000:.2f} mm  ·  azul/rojo {f.blue_red:.2f}{sensitive}")

    def _update_guidance(self, r: AlignmentResult, warnings: list[str]) -> None:
        step = self.pipeline.step.key if self.pipeline_visible else None
        view = self._pipeline_view if self.pipeline_visible else None
        sharp = self._sharpness_drop(r)
        if sharp is not None and sharp < self.pipeline.targets.sharpness_drop_warn and \
                step not in BLOCKED_ARM_STEPS:
            warnings = [f"La nitidez espectral bajó al {100 * sharp:.0f} % del estado final: el espectrómetro "
                        "se está desenfocando y se perderá penetración. Vuelva al paso 6 (enfoque a ~2 mm)."] \
                + warnings
        if step in BLOCKED_ARM_STEPS:   # a covered arm gives no PSF: do not flag noise
            if view is not None and view.hint:
                warnings = [f"Paso {self.pipeline.index + 1}: {view.hint}"] + [
                    w for w in warnings if "Saturación" in w]
        elif r.psf is not None and self._psf_is_noise(r):
            where = "la ventana elegida" if r.psf.manual_window else "el A-scan"
            warnings = [f"No hay un pico claro en {where} (SNR {r.psf.snr_db:.0f} dB): el FWHM del espejo "
                        "corresponde a ruido. Arrastre sobre el A-scan para elegir la ventana del espejo."] + warnings
        if not warnings and view is not None and step != "forma":
            n = self.pipeline.index + 1
            if view.hint:
                warnings = [f"Paso {n}: {view.hint}"]
            else:
                action = self.pipeline.step.capture_label or "Siguiente"
                if view.ready:
                    self.guide_var.set(f"✔  Paso {n} en objetivo: pulse «{action}».")
                    self.guide_icon.configure(fg=GOOD)
                else:
                    self.guide_var.set(f"Paso {n} · {self.pipeline.step.title}: lleve los indicadores del "
                                       "panel izquierdo a verde.")
                    self.guide_icon.configure(fg=WARN)
                return
        if warnings:
            self.guide_var.set("⚠  " + "  ".join(warnings))
            bad = "Saturación" in warnings[0] or "desenfocando" in warnings[0]
            self.guide_icon.configure(fg=BAD if bad else WARN)
            return
        blue = r.blue_change_pct if r.blue_change_pct is not None else 0.0
        red = r.red_change_pct if r.red_change_pct is not None else 0.0
        rms = r.rms_diff_pct if r.rms_diff_pct is not None else 0.0
        ref = self.reference
        assert ref is not None
        shift = ((r.spectrum.edges50_px[0] - ref.metrics.edges50_px[0])
                 + (r.spectrum.edges50_px[1] - ref.metrics.edges50_px[1])) / 2
        if rms <= 3.0:
            self.guide_var.set("✔  Forma del espectro equivalente a la referencia. Fije esta posición.")
            self.guide_icon.configure(fg=GOOD)
        elif abs(shift) > 40 and abs(blue - red) < 10:
            side = "rojo (píxeles altos)" if shift > 0 else "azul (píxeles bajos)"
            self.guide_var.set(f"El espectro está desplazado {abs(shift):.0f} px hacia el lado {side}: "
                               "posible cambio del ángulo de la rejilla o de la posición lateral de la cámara.")
            self.guide_icon.configure(fg=WARN)
        elif blue < -5 and red > -5:
            self.guide_var.set(f"Pierde el lado azul (px {BLUE_BAND_PX[0]}–{BLUE_BAND_PX[1]}: {blue:+.0f} %). "
                               "Posibles causas: rotación/altura de la cámara o viñeteo en la lente de enfoque.")
            self.guide_icon.configure(fg=BAD if blue < -15 else WARN)
        elif red < -5 and blue > -5:
            self.guide_var.set(f"Pierde el lado rojo (px {RED_BAND_PX[0]}–{RED_BAND_PX[1]}: {red:+.0f} %). "
                               "Posibles causas: rotación/altura de la cámara o viñeteo en la lente de enfoque.")
            self.guide_icon.configure(fg=BAD if red < -15 else WARN)
        elif blue < -5 and red < -5:
            self.guide_var.set(f"Ambos extremos más débiles (azul {blue:+.0f} %, rojo {red:+.0f} %): el espectro "
                               "es más estrecho. Revise enfoque/inclinación de la cámara y la colimación.")
            self.guide_icon.configure(fg=WARN)
        else:
            self.guide_var.set(f"Forma distinta de la referencia (RMS {rms:.1f} %, azul {blue:+.0f} %, "
                               f"rojo {red:+.0f} %). Ajuste observando la curva naranja.")
            self.guide_icon.configure(fg=WARN)

    @staticmethod
    def _padded(values: np.ndarray, minimum_span: float) -> tuple[float, float]:
        finite = values[np.isfinite(values)]
        if finite.size == 0:
            return (0.0, 1.0)
        lo, hi = float(finite.min()), float(finite.max())
        span = max(hi - lo, minimum_span)
        mid = (hi + lo) / 2
        return (mid - span * 0.9, mid + span * 0.9)

    @staticmethod
    def _delta_text(delta: float, fmt: str) -> str:
        if not math.isfinite(delta):
            return ""
        return fmt.format(delta)

    @staticmethod
    def _delta_color(error: float, good: float, warn: float) -> str:
        if not math.isfinite(error):
            return MUTED
        return GOOD if error <= good else WARN if error <= warn else BAD

    @staticmethod
    def _band_color(change: float) -> str:
        if not math.isfinite(change):
            return MUTED
        return GOOD if change >= -5 else WARN if change >= -15 else BAD

    # -- shutdown ----------------------------------------------------------------
    def _on_close(self) -> None:
        if self.engine.is_active:
            if not messagebox.askyesno("Salir", "La adquisición está activa. ¿Detenerla y salir?"):
                return
            self.engine.stop()
            self.engine.join(timeout=10.0)
        self._closing = True
        self.analyzer.close()
        NIHardwareBackend.release_warm_camera()
        self.root.destroy()


def main(argv: Sequence[str] | None = None) -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Monitor en vivo para alinear el espectrómetro.")
    parser.add_argument("--referencia", type=Path, default=None,
                        help="JSON de referencia (por defecto config/alineacion_referencia.json)")
    args = parser.parse_args(argv)
    root = tk.Tk()
    AlignmentLiveApp(root, reference_path=args.referencia)
    root.mainloop()


if __name__ == "__main__":
    main()
