"""Phase-peak cursor for continuous alignment (confocal transducer focus).

The transducer and the sample-arm lens are aligned by moving translation and
angle by hand until the phase response at the selected depth is maximal. Each
alignment block holds M phase samples in time; this module finds the peak
(largest |phase| relative to the reference, inside a user ROI) or reads the
phase at a manual cursor, and keeps a short history and the maximum held.
Times are in ms from the start of the block.
"""
from __future__ import annotations

import json
import time
from collections import deque
from dataclasses import asdict, dataclass, fields, replace
from math import isfinite
from pathlib import Path
from typing import Any

import numpy as np

from .paths import CONFIG_DIR

DEFAULT_PATH = CONFIG_DIR / "phase_peak.json"
MODES = ("off", "manual", "auto")
MODE_LABELS = {"off": "Desactivado", "manual": "Manual (cursor)", "auto": "Automático (ROI)"}


@dataclass(frozen=True, slots=True)
class PhasePeakSettings:
    """What the phase-plot settings window controls (saved between sessions)."""

    mode: str = "off"
    roi_ms: tuple[float, float] | None = None  # auto-peak search range; None = whole block
    view_ms: tuple[float, float] | None = None  # plotted time range; None = whole block
    manual_ms: float | None = None  # manual cursor time
    history_enabled: bool = True
    history_s: float = 20.0
    max_hold: bool = True

    def validate(self) -> None:
        if self.mode not in MODES:
            raise ValueError(f"Modo de pico desconocido: {self.mode!r}.")
        for label, window in (("ROI", self.roi_ms), ("Ventana", self.view_ms)):
            if window is not None:
                start, end = window
                if not (isfinite(start) and isfinite(end) and 0 <= start < end):
                    raise ValueError(f"{label}: el inicio debe ser ≥ 0 ms y menor que el fin.")
        if self.manual_ms is not None and not (isfinite(self.manual_ms) and self.manual_ms >= 0):
            raise ValueError("El cursor manual debe estar en un tiempo ≥ 0 ms.")
        if not (isfinite(self.history_s) and 1.0 <= self.history_s <= 600.0):
            raise ValueError("El historial debe durar entre 1 y 600 s.")

    @classmethod
    def load(cls, path: Path = DEFAULT_PATH) -> "PhasePeakSettings":
        """Saved settings, or the defaults when there are none or they are invalid."""
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            known = {field.name for field in fields(cls)}
            values = {key: value for key, value in data.items() if key in known}
            for key in ("roi_ms", "view_ms"):
                if values.get(key) is not None:
                    values[key] = (float(values[key][0]), float(values[key][1]))
            settings = replace(cls(), **values)
            settings.validate()
            return settings
        except (OSError, ValueError, TypeError, KeyError, IndexError):
            return cls()

    def save(self, path: Path = DEFAULT_PATH) -> None:
        self.validate()
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps({"version": 1, **asdict(self)}, indent=2), encoding="utf-8")
        temporary.replace(path)


@dataclass(frozen=True, slots=True)
class PeakReading:
    index: int  # sample index in the plotted arrays
    time_ms: float
    value_rad: float  # signed phase at the peak / cursor


def find_peak(time_ms: np.ndarray, phase: np.ndarray, roi_ms: tuple[float, float] | None) -> PeakReading | None:
    """Largest |phase| inside the ROI (whole block when None); None without samples."""
    time_ms = np.asarray(time_ms, dtype=np.float64)
    phase = np.asarray(phase, dtype=np.float64)
    inside = np.isfinite(phase)
    if roi_ms is not None:
        inside &= (time_ms >= roi_ms[0]) & (time_ms <= roi_ms[1])
    candidates = np.flatnonzero(inside)
    if candidates.size == 0:
        return None
    index = int(candidates[np.argmax(np.abs(phase[candidates]))])
    return PeakReading(index, float(time_ms[index]), float(phase[index]))


def value_at(time_ms: np.ndarray, phase: np.ndarray, target_ms: float) -> PeakReading | None:
    """Phase at the sample nearest to ``target_ms`` (manual cursor)."""
    time_ms = np.asarray(time_ms, dtype=np.float64)
    if time_ms.size == 0:
        return None
    index = int(np.argmin(np.abs(time_ms - target_ms)))
    value = float(np.asarray(phase, dtype=np.float64)[index])
    if not isfinite(value):
        return None
    return PeakReading(index, float(time_ms[index]), value)


class PeakHistory:
    """Peak magnitude of each new block over the last seconds, plus the maximum held."""

    def __init__(self, seconds: float = 20.0) -> None:
        self.seconds = seconds
        self.samples: deque[tuple[float, float]] = deque()
        self.best: tuple[float, float] | None = None  # (|value| rad, time ms in block)

    def add(self, reading: PeakReading, now: float | None = None) -> None:
        now = time.monotonic() if now is None else now
        magnitude = abs(reading.value_rad)
        self.samples.append((now, magnitude))
        while self.samples and now - self.samples[0][0] > self.seconds:
            self.samples.popleft()
        if self.best is None or magnitude > self.best[0]:
            self.best = (magnitude, reading.time_ms)

    def reset(self) -> None:
        self.samples.clear()
        self.best = None

    def as_arrays(self, now: float | None = None) -> tuple[np.ndarray, np.ndarray]:
        """(seconds before now, |peak| rad), oldest first."""
        now = time.monotonic() if now is None else now
        if not self.samples:
            return np.empty(0), np.empty(0)
        data = np.asarray(self.samples, dtype=np.float64)
        return data[:, 0] - now, data[:, 1]


def settings_from_text(current: PhasePeakSettings, values: dict[str, Any]) -> PhasePeakSettings:
    """Settings from the dialog fields (text); blank ROI/window fields mean the whole block."""

    def number(text: str, label: str) -> float:
        try:
            return float(str(text).strip().replace(",", "."))
        except ValueError as exc:
            raise ValueError(f"{label}: '{text}' no es un número.") from exc

    def window(start: str, end: str, label: str) -> tuple[float, float] | None:
        if not str(start).strip() and not str(end).strip():
            return None
        return (number(start, f"{label} inicio"), number(end, f"{label} fin"))

    settings = replace(
        current,
        mode=values["mode"],
        roi_ms=window(values["roi_start"], values["roi_end"], "ROI"),
        view_ms=window(values["view_start"], values["view_end"], "Ventana"),
        history_enabled=bool(values["history_enabled"]),
        history_s=number(values["history_s"], "Historial"),
        max_hold=bool(values["max_hold"]),
    )
    settings.validate()
    return settings
