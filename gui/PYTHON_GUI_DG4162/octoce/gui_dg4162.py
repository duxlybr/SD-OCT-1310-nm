"""USB GUI variant that also drives the RIGOL DG4162 and runs Excel series."""
from __future__ import annotations

import json
import tkinter as tk
from dataclasses import replace
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import Any

from .config import ConfigurationError, ScanParameters
from .dg4162 import (
    CH2_WAVEFORMS,
    WARNING_CH1_VPP,
    DG4162Controller,
    Excitation,
    GeneratorSettings,
    GeneratorState,
    waveform_label,
    waveform_scpi,
)
from .engine import EngineEvent, EngineState
from .gui import MODE_LABELS, ORIENTATION_LABELS, PATTERN_LABELS, _duration
from .gui_usb import OCTOCEUSBApp
from .naming import MODE_PREFIX, clean_stem, default_stem, unique_path
from .paths import ACQUISITIONS_DIR
from .sequence import SequenceJob, build_jobs, read_rows, write_template
from .usb_camera import USBCameraStream

_MODE_LABEL = {mode: label for label, mode in MODE_LABELS.items()}
_PATTERN_LABEL = {pattern: label for label, pattern in PATTERN_LABELS.items()}
_ORIENTATION_LABEL = {orientation: label for label, orientation in ORIENTATION_LABELS.items()}
_FINAL_STATES = {EngineState.COMPLETED.value, EngineState.STOPPED.value, EngineState.ERROR.value}
MAX_RETRIES = 3
RETRY_DELAY_MS = 1500


def _parse_float(text: str, label: str) -> float:
    try:
        return float(str(text).strip().replace(",", "."))
    except ValueError as exc:
        raise ValueError(f"{label}: '{text}' no es un número.") from exc


class _SequenceWindow:
    """Non-modal window: load an Excel series, review it and run it."""

    COLUMNS = (
        ("n", "#", 40), ("fila", "Fila", 45), ("rep", "Rep", 50), ("modo", "Modo", 50),
        ("a", "A", 50), ("b", "B", 45), ("m", "M", 55), ("ss", "SS", 45),
        ("mvpp", "mVpp", 60), ("hz", "Hz CH2", 70), ("onda", "Onda", 70),
        ("ms", "Ret. ms", 60), ("espera", "Espera s", 65), ("archivo", "Archivo", 330),
    )

    def __init__(self, app: "OCTOCEDG4162App") -> None:
        self.app = app
        self.window = tk.Toplevel(app.root)
        self.window.title("Secuencia de adquisiciones · Excel")
        self.window.transient(app.root)
        self.window.geometry("1180x620")
        self.window.minsize(900, 480)
        self.window.protocol("WM_DELETE_WINDOW", self.window.withdraw)
        self.window.configure(bg="#eef2f7")
        body = ttk.Frame(self.window, padding=12)
        body.pack(fill="both", expand=True)
        body.columnconfigure(1, weight=1)
        body.rowconfigure(3, weight=1)

        ttk.Label(body, text="Archivo Excel", style="Sequence.TLabel").grid(row=0, column=0, sticky="w")
        self.path_var = tk.StringVar(value="")
        ttk.Entry(body, textvariable=self.path_var).grid(row=0, column=1, sticky="ew", padx=6)
        file_buttons = ttk.Frame(body)
        file_buttons.grid(row=0, column=2, sticky="e")
        ttk.Button(file_buttons, text="…", width=4, command=self._browse).pack(side="left")
        ttk.Button(file_buttons, text="Crear plantilla…", command=self._create_template).pack(side="left", padx=(6, 0))
        ttk.Button(file_buttons, text="Cargar y validar", command=self.load).pack(side="left", padx=(6, 0))

        ttk.Label(
            body,
            text="Las celdas vacías de parámetros toman el valor actual de la GUI. "
                 "Se valida todo antes de empezar; los nombres mostrados son los previstos.",
            style="Sequence.TLabel",
        ).grid(row=1, column=0, columnspan=3, sticky="w", pady=(6, 4))
        self.summary_var = tk.StringVar(value="Cargue un Excel para ver la secuencia.")
        ttk.Label(body, textvariable=self.summary_var, style="SequenceBold.TLabel").grid(
            row=2, column=0, columnspan=3, sticky="w", pady=(0, 4))

        table = ttk.Frame(body)
        table.grid(row=3, column=0, columnspan=3, sticky="nsew")
        table.columnconfigure(0, weight=1)
        table.rowconfigure(0, weight=1)
        self.tree = ttk.Treeview(table, columns=[c[0] for c in self.COLUMNS], show="headings", height=12)
        for key, title, width in self.COLUMNS:
            self.tree.heading(key, text=title)
            self.tree.column(key, width=width, anchor="w" if key == "archivo" else "center",
                             stretch=key == "archivo")
        self.tree.tag_configure("done", foreground="#2477d4")
        self.tree.tag_configure("current", background="#e3f6ec")
        self.tree.tag_configure("failed", foreground="#d34f4f")
        self.tree.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(table, orient="vertical", command=self.tree.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.tree.configure(yscrollcommand=scroll.set)

        self.errors = tk.Text(body, height=5, wrap="word", fg="#a52d2d", relief="flat", bg="#fbf3f3")
        self.errors.grid(row=4, column=0, columnspan=3, sticky="ew", pady=(8, 0))
        self.errors.configure(state="disabled")

        bottom = ttk.Frame(body)
        bottom.grid(row=5, column=0, columnspan=3, sticky="ew", pady=(10, 0))
        bottom.columnconfigure(0, weight=1)
        self.progress_var = tk.DoubleVar(value=0.0)
        ttk.Progressbar(bottom, variable=self.progress_var, maximum=100.0).grid(row=0, column=0, sticky="ew")
        self.status_var = tk.StringVar(value="Sin secuencia en curso.")
        ttk.Label(bottom, textvariable=self.status_var, style="Sequence.TLabel").grid(row=1, column=0, sticky="w", pady=(4, 0))
        self.start_button = ttk.Button(bottom, text="Iniciar secuencia", style="Primary.TButton",
                                       command=app._start_sequence, state="disabled")
        self.start_button.grid(row=0, column=1, rowspan=2, padx=(12, 0))
        self.stop_button = ttk.Button(bottom, text="Detener secuencia", style="Danger.TButton",
                                      command=app._stop_sequence, state="disabled")
        self.stop_button.grid(row=0, column=2, rowspan=2, padx=(8, 0))

    def show(self) -> None:
        self.window.deiconify()
        self.window.lift()
        self.window.focus_set()

    def _browse(self) -> None:
        selected = filedialog.askopenfilename(
            parent=self.window, title="Secuencia de adquisiciones",
            filetypes=(("Excel", "*.xlsx"), ("Todos", "*.*")),
            initialdir=self.app.folder_var.get() or str(ACQUISITIONS_DIR),
        )
        if selected:
            self.path_var.set(selected)
            self.load()

    def _create_template(self) -> None:
        selected = filedialog.asksaveasfilename(
            parent=self.window, title="Crear plantilla de secuencia",
            defaultextension=".xlsx", filetypes=(("Excel", "*.xlsx"),),
            initialfile="plantilla_secuencia_DG4162.xlsx",
            initialdir=self.app.folder_var.get() or str(ACQUISITIONS_DIR),
        )
        if not selected:
            return
        try:
            path = write_template(selected)
        except Exception as exc:
            messagebox.showerror("Plantilla", str(exc), parent=self.window)
            return
        self.path_var.set(str(path))
        self.app._append_log(f"Plantilla de secuencia creada: {path}")
        messagebox.showinfo(
            "Plantilla", f"Plantilla creada:\n{path}\n\nEdítela en Excel, guárdela y pulse 'Cargar y validar'.",
            parent=self.window,
        )

    def load(self) -> None:
        if self.app._sequence_active:
            return
        self.app._sequence_jobs = []
        self.tree.delete(*self.tree.get_children())
        self.start_button.configure(state="disabled")
        self.progress_var.set(0.0)
        try:
            rows = read_rows(self.path_var.get().strip())
            jobs, errors = build_jobs(
                rows, self.app._sequence_defaults(), validate_scan=self.app._validate_job_scan,
            )
        except Exception as exc:
            jobs, errors = [], [f"No se pudo leer el Excel: {exc}"]
        self._set_errors(errors)
        if errors:
            self.summary_var.set(f"Secuencia NO válida · {len(errors)} problema(s). Corrija el Excel y recargue.")
            return
        planned: set[Path] = set()
        total_s = 0.0
        for index, job in enumerate(jobs):
            path = self.app._job_output_path(job, planned)
            planned.add(path)
            total_s += self.app._job_duration_s(job) + (job.wait_s if index < len(jobs) - 1 else 0.0)
            g = job.generator
            self.tree.insert("", "end", iid=str(index), values=(
                index + 1, job.row, f"{job.repetition}/{job.repetitions}", MODE_PREFIX[job.mode],
                job.alines, job.bscans, job.m_repetitions, job.sync_points,
                f"{g.ch1_vpp * 1000:g}", f"{g.ch2_frequency_hz:g}", waveform_label(g.ch2_waveform),
                f"{g.ch2_delay_ms:g}", f"{job.wait_s:g}", str(path),
            ))
        self.app._sequence_jobs = jobs
        confirm_rows = sorted({job.row for job in jobs if job.generator.ch1_vpp > WARNING_CH1_VPP})
        note = f" · CH1 > 1 Vpp en filas {', '.join(map(str, confirm_rows))}" if confirm_rows else ""
        self.summary_var.set(
            f"Secuencia válida: {len(jobs)} adquisiciones de {len({j.row for j in jobs})} filas · "
            f"duración mínima estimada {_duration(total_s)}{note}"
        )
        self.start_button.configure(state="normal")

    def _set_errors(self, errors: list[str]) -> None:
        self.errors.configure(state="normal")
        self.errors.delete("1.0", "end")
        self.errors.insert("end", "\n".join(errors) if errors else "Sin errores.")
        self.errors.configure(state="disabled")

    def mark(self, index: int, tag: str) -> None:
        iid = str(index)
        if self.tree.exists(iid):
            self.tree.item(iid, tags=(tag,))
            if tag == "current":
                self.tree.see(iid)

    def set_running(self, running: bool) -> None:
        self.start_button.configure(state="disabled" if running or not self.app._sequence_jobs else "normal")
        self.stop_button.configure(state="normal" if running else "disabled")


class OCTOCEDG4162App(OCTOCEUSBApp):
    """USB GUI + DG4162 control + separate folder/name + Excel series."""

    def __init__(
        self,
        root: tk.Tk,
        *,
        usb_stream: USBCameraStream | None = None,
        show_setup_on_start: bool = False,
        generator: DG4162Controller | None = None,
        auto_connect: bool = True,
    ) -> None:
        self.generator = generator or DG4162Controller()
        self._generator_run = False
        self._pending_settings: GeneratorSettings | None = None
        self._applied_state: GeneratorState | None = None
        self._output1_on = False
        self._last_output: Path | None = None
        self._sequence_jobs: list[SequenceJob] = []
        self._sequence_active = False
        self._sequence_starting = False
        self._sequence_index = 0
        self._sequence_after: str | None = None
        self._sequence_window: _SequenceWindow | None = None
        self._current_job: SequenceJob | None = None
        self._connect_after: str | None = None
        self._run_kind: str | None = None  # "acquisition" | "alignment" while the engine runs
        self._retry_count = 0
        self._retrying = False
        self._retry_after: str | None = None
        self._square_after: str | None = None
        super().__init__(root, usb_stream=usb_stream, show_setup_on_start=show_setup_on_start)
        self.root.title("OCT / OCE Acquisition · USB · DG4162")
        for variable in (
            self.folder_var, self.name_var, self.mode_var, self.alines_var, self.bscans_var,
            self.repetitions_var, self.sync_var, self.ch1_mvpp_var, self.ch2_freq_var,
            self.gen_enabled_var,
        ):
            variable.trace_add("write", lambda *_args: self._update_target())
        for variable in (self.ch1_mvpp_var, self.excitation_var):
            variable.trace_add("write", lambda *_args: self._update_voltage_warning())
        self._update_target()
        self._update_voltage_warning()
        if auto_connect:
            self._connect_after = self.root.after(600, lambda: self._connect_generator(interactive=False))
        self._square_after = self.root.after(700, self._square_usb_view)

    # -- layout ---------------------------------------------------------------
    def _build_style(self) -> None:
        super()._build_style()
        style = ttk.Style(self.root)
        style.configure("Warning.TLabel", background="#ffffff", foreground="#b54708",
                        font=("Segoe UI", 9, "bold"))
        style.configure("Target.TLabel", background="#ffffff", foreground="#1d6b46", font=("Segoe UI", 8))
        style.configure("Sequence.TLabel", background="#eef2f7", font=("Segoe UI", 9))
        style.configure("Small.TButton", font=("Segoe UI", 8), padding=(4, 1))
        style.configure("SequenceBold.TLabel", background="#eef2f7", font=("Segoe UI", 9, "bold"))

    def _build_variables(self) -> None:
        super()._build_variables()
        self.folder_var = tk.StringVar(value=str(ACQUISITIONS_DIR))
        self.name_var = tk.StringVar(value="")
        self.target_var = tk.StringVar(value="")
        self.gen_enabled_var = tk.BooleanVar(value=True)
        self.excitation_var = tk.StringVar(value=Excitation.NON_CONTACT.value)
        self.ch1_mvpp_var = tk.StringVar(value="500")
        self.ch2_freq_var = tk.StringVar(value="2000")
        self.ch2_wave_var = tk.StringVar(value="Pulso")
        self.ch2_delay_var = tk.StringVar(value="2")
        self.gen_warning_var = tk.StringVar(value="")
        self.gen_status_var = tk.StringVar(value="DG4162 sin conectar.")

    def _build_output_controls(self, parent: ttk.Frame, row: int) -> int:
        ttk.Label(parent, text="Carpeta", style="Card.TLabel").grid(row=row, column=0, columnspan=2, sticky="w")
        folder = ttk.Frame(parent, style="Card.TFrame")
        folder.grid(row=row + 1, column=0, columnspan=2, sticky="ew", pady=(2, 4))
        folder.columnconfigure(0, weight=1)
        ttk.Entry(folder, textvariable=self.folder_var).grid(row=0, column=0, sticky="ew")
        ttk.Button(folder, text="…", width=4, command=self._browse_folder).grid(row=0, column=1, padx=(6, 0))
        ttk.Label(parent, text="Nombre del archivo (vacío = nombre por defecto)", style="Card.TLabel").grid(
            row=row + 2, column=0, columnspan=2, sticky="w")
        name = ttk.Frame(parent, style="Card.TFrame")
        name.grid(row=row + 3, column=0, columnspan=2, sticky="ew", pady=(2, 2))
        name.columnconfigure(0, weight=1)
        ttk.Entry(name, textvariable=self.name_var).grid(row=0, column=0, sticky="ew")
        ttk.Button(name, text="Sugerido", style="Small.TButton", width=8,
                   command=self._use_suggested_name).grid(row=0, column=1, padx=(4, 0))
        ttk.Label(parent, textvariable=self.target_var, style="Target.TLabel", wraplength=330,
                  justify="left").grid(row=row + 4, column=0, columnspan=2, sticky="w", pady=(0, 4))
        return row + 5

    def _build_extra_controls(self, parent: ttk.Frame, row: int) -> int:
        ttk.Separator(parent).grid(row=row, column=0, columnspan=2, sticky="ew", pady=10)
        ttk.Label(parent, text="Generador DG4162", style="CardTitle.TLabel").grid(
            row=row + 1, column=0, columnspan=2, sticky="w", pady=(0, 4))
        ttk.Checkbutton(
            parent, text="Controlar DG4162 en cada adquisición (OUTPUT1 on/off)",
            variable=self.gen_enabled_var,
        ).grid(row=row + 2, column=0, columnspan=2, sticky="w")
        row += 3

        def field(label: str, variable: tk.StringVar, suffix: str = "", values: list[str] | None = None) -> None:
            nonlocal row
            ttk.Label(parent, text=label, style="Card.TLabel").grid(row=row, column=0, sticky="w", pady=3)
            holder = ttk.Frame(parent, style="Card.TFrame")
            holder.grid(row=row, column=1, sticky="ew", padx=(12, 0), pady=3)
            holder.columnconfigure(0, weight=1)
            if values is None:
                widget: ttk.Widget = ttk.Entry(holder, textvariable=variable, width=12)
            else:
                widget = ttk.Combobox(holder, textvariable=variable, values=values, state="readonly", width=16)
            widget.grid(row=0, column=0, sticky="ew")
            if suffix:
                ttk.Label(holder, text=suffix, style="Muted.TLabel").grid(row=0, column=1, padx=(6, 0))
            row += 1

        field("Excitación", self.excitation_var,
              values=[Excitation.NON_CONTACT.value, Excitation.CONTACT.value])
        field("CH1 amplitud", self.ch1_mvpp_var, "mVpp")
        field("CH2 frecuencia", self.ch2_freq_var, "Hz")
        field("CH2 forma de onda", self.ch2_wave_var, values=list(CH2_WAVEFORMS))
        field("CH2 retardo burst", self.ch2_delay_var, "ms")
        ttk.Label(parent, textvariable=self.gen_warning_var, style="Warning.TLabel", wraplength=330,
                  justify="left").grid(row=row, column=0, columnspan=2, sticky="w")
        row += 1
        buttons = ttk.Frame(parent, style="Card.TFrame")
        buttons.grid(row=row, column=0, columnspan=2, sticky="ew", pady=(4, 2))
        buttons.columnconfigure((0, 1, 2), weight=1)
        self.gen_connect_button = ttk.Button(buttons, text="Conectar / leer",
                                             command=lambda: self._connect_generator(interactive=True))
        self.gen_connect_button.grid(row=0, column=0, sticky="ew", padx=(0, 3))
        self.gen_load_button = ttk.Button(buttons, text="Copiar del equipo", command=self._load_from_generator)
        self.gen_load_button.grid(row=0, column=1, sticky="ew", padx=3)
        self.gen_apply_button = ttk.Button(buttons, text="Aplicar ahora", command=self._apply_generator_now)
        self.gen_apply_button.grid(row=0, column=2, sticky="ew", padx=(3, 0))
        ttk.Label(parent, textvariable=self.gen_status_var, style="Muted.TLabel", wraplength=330,
                  justify="left").grid(row=row + 1, column=0, columnspan=2, sticky="w", pady=(2, 6))
        self.sequence_button = ttk.Button(parent, text="Secuencia desde Excel…", command=self._open_sequence)
        self.sequence_button.grid(row=row + 2, column=0, columnspan=2, sticky="ew", pady=(4, 0))
        return row + 3

    def _square_usb_view(self) -> None:
        """Start with the USB camera pane as wide as it is tall (square view)."""
        self._square_after = None
        if self._closing:
            return
        pane_width = self.lower_pane.winfo_width()
        canvas_height = self.usb_canvas.winfo_height()
        if pane_width < 200 or canvas_height < 50:
            self._square_after = self.root.after(200, self._square_usb_view)
            return
        card_width = canvas_height + 2 * 8 + 2  # diagnostic card padding + canvas border
        self.lower_pane.sashpos(0, max(200, pane_width - card_width))

    def _toggle_fullscreen(self, _event: object | None = None) -> None:
        super()._toggle_fullscreen(_event)
        if self._square_after is not None:
            self.root.after_cancel(self._square_after)
        self._square_after = self.root.after(300, self._square_usb_view)

    # -- file name ------------------------------------------------------------
    def _browse_folder(self) -> None:
        selected = filedialog.askdirectory(
            title="Carpeta de adquisiciones", initialdir=self.folder_var.get() or str(ACQUISITIONS_DIR),
            mustexist=False,
        )
        if selected:
            self.folder_var.set(selected)

    def _folder(self) -> Path:
        text = self.folder_var.get().strip()
        return Path(text) if text else ACQUISITIONS_DIR

    def _default_stem(self) -> str:
        generator = self.gen_enabled_var.get()
        return default_stem(
            MODE_LABELS[self.mode_var.get()],
            int(self.alines_var.get()),
            int(self.bscans_var.get()),
            int(self.repetitions_var.get()),
            int(self.sync_var.get()),
            ch1_vpp=_parse_float(self.ch1_mvpp_var.get(), "CH1") / 1000.0 if generator else None,
            ch2_frequency_hz=_parse_float(self.ch2_freq_var.get(), "CH2") if generator else None,
        )

    def _use_suggested_name(self) -> None:
        try:
            self.name_var.set(self._default_stem())
        except (ValueError, KeyError) as exc:
            messagebox.showerror("Nombre sugerido", f"Parámetros incompletos: {exc}")

    def _update_target(self) -> None:
        try:
            typed = clean_stem(self.name_var.get())
            stem = typed or self._default_stem()
            path = unique_path(self._folder(), stem)
            origin = "nombre escrito" if typed else "nombre por defecto"
            suffix = " (ya existía: se añade sufijo)" if path.stem != stem else ""
            self.target_var.set(f"Se guardará como: {path.name}  · {origin}{suffix}")
            self.output_var.set(str(path))
        except (ValueError, KeyError) as exc:
            self.target_var.set(f"Nombre no disponible: {exc}")

    def _resolve_output_path(self) -> Path:
        job = self._current_job if self._sequence_active else None
        if job is not None:
            path = self._job_output_path(job, set())
        else:
            stem = clean_stem(self.name_var.get()) or self._default_stem()
            path = unique_path(self._folder(), stem)
        self.output_var.set(str(path))
        self._last_output = path
        return path

    # -- generator panel ------------------------------------------------------
    def _generator_settings(self) -> GeneratorSettings:
        return GeneratorSettings(
            ch1_vpp=_parse_float(self.ch1_mvpp_var.get(), "CH1 amplitud") / 1000.0,
            ch2_frequency_hz=_parse_float(self.ch2_freq_var.get(), "CH2 frecuencia"),
            ch2_waveform=waveform_scpi(self.ch2_wave_var.get()),
            ch2_delay_ms=_parse_float(self.ch2_delay_var.get(), "CH2 retardo"),
            excitation=Excitation.parse(self.excitation_var.get()),
        )

    def _update_voltage_warning(self) -> None:
        try:
            excitation = Excitation.parse(self.excitation_var.get())
            vpp = _parse_float(self.ch1_mvpp_var.get(), "CH1") / 1000.0
        except ValueError:
            self.gen_warning_var.set("CH1: valor no válido.")
            return
        if vpp > excitation.limit_vpp:
            self.gen_warning_var.set(
                f"⛔ CH1 supera {excitation.limit_vpp:g} Vpp ({excitation.value.lower()}): "
                "la adquisición quedará bloqueada."
            )
        elif vpp > WARNING_CH1_VPP:
            self.gen_warning_var.set("⚠ CH1 > 1 Vpp: se pedirá confirmación antes de adquirir.")
        else:
            self.gen_warning_var.set("")

    def _confirm_high_voltage(self, settings: GeneratorSettings, *, detail: str = "") -> bool:
        return messagebox.askyesno(
            "CH1 por encima de 1 Vpp",
            f"CH1 = {settings.ch1_vpp * 1000:g} mVpp supera 1 Vpp "
            f"(excitación {settings.excitation.value.lower()}, límite {settings.excitation.limit_vpp:g} Vpp)."
            f"{detail}\n\nConfirme que el amplificador y el transductor admiten esta amplitud. ¿Continuar?",
            icon="warning",
        )

    def _generator_busy(self) -> bool:
        if self.engine.is_active or self._sequence_active:
            messagebox.showinfo("DG4162", "Espere a que termine la adquisición o la secuencia.")
            return True
        return False

    def _connect_generator(self, *, interactive: bool) -> bool:
        self._connect_after = None
        if self._closing:
            return False
        try:
            identity = self.generator.connect()
            state = self.generator.read_state()
        except Exception as exc:
            self.gen_status_var.set(f"DG4162 sin conexión: {exc}")
            self._append_log(f"DG4162 sin conexión: {exc}")
            if interactive:
                messagebox.showerror("DG4162", str(exc))
            return False
        self.gen_status_var.set(state.summary())
        self._append_log(f"DG4162 conectado: {identity}")
        self._append_log("DG4162 estado actual (solo lectura): " + state.summary().replace("\n", " | "))
        return True

    def _load_from_generator(self) -> None:
        if self._generator_busy() or not self._connect_generator(interactive=True):
            return
        try:
            state = self.generator.read_state()
        except Exception as exc:
            messagebox.showerror("DG4162", str(exc))
            return
        self.ch1_mvpp_var.set(f"{state.ch1_vpp * 1000:g}")
        self.ch2_freq_var.set(f"{state.ch2_frequency_hz:g}")
        self.ch2_wave_var.set(waveform_label(state.ch2_function))
        self.ch2_delay_var.set(f"{state.ch2_delay_ms:g}")
        self._append_log("Campos del generador copiados desde el DG4162.")

    def _apply_generator_now(self) -> None:
        if self._generator_busy():
            return
        try:
            settings = self._generator_settings()
            if settings.validate() and not self._confirm_high_voltage(settings):
                return
            if not self._connect_generator(interactive=True):
                return
            state = self.generator.apply(settings)
            if not state.output2:
                self.generator.set_output(2, True)
                state = self.generator.read_state()
        except Exception as exc:
            self._append_log(f"DG4162: no se pudo aplicar: {exc}")
            messagebox.showerror("DG4162", str(exc))
            return
        self.gen_status_var.set(state.summary())
        self._append_log("DG4162 programado (OUTPUT1 OFF, OUTPUT2 ON): " + state.summary().replace("\n", " | "))

    # -- acquisition hooks ----------------------------------------------------
    def _prepare_generator(self, *, confirm: bool) -> bool:
        """Validate the panel values before arming; False aborts the start."""
        self._pending_settings = None
        self._applied_state = None
        if not self.gen_enabled_var.get():
            return True
        try:
            settings = self._generator_settings()
            needs_confirmation = settings.validate()
        except ValueError as exc:
            messagebox.showerror("No se puede iniciar", f"Generador DG4162: {exc}")
            return False
        if needs_confirmation and confirm and not self._confirm_high_voltage(settings):
            return False
        self._pending_settings = settings
        return True

    def _start(self, *, confirm: bool = True) -> bool:
        if self._sequence_active and not self._sequence_starting:
            messagebox.showinfo("Secuencia en curso", "Detenga la secuencia antes de iniciar otra adquisición.")
            return False
        if not self._retrying:
            self._cancel_retry()
            self._retry_count = 0
        self._last_output = None
        if not self._prepare_generator(confirm=confirm):
            return False
        self._generator_run = True
        self._run_kind = "acquisition"
        try:
            started = super()._start(confirm=confirm)
        finally:
            self._generator_run = False
        if started:
            self._write_generator_sidecar()
        else:
            self._run_kind = None
        return started

    def _start_alignment(self) -> None:
        if self._sequence_active:
            messagebox.showinfo("Secuencia en curso", "Detenga la secuencia antes de alinear.")
            return
        if self.engine.is_active:
            super()._start_alignment()  # shows the "stop first" error
            return
        self._cancel_retry()
        if not self._prepare_generator(confirm=True):
            return
        self._generator_run = True
        self._run_kind = "alignment"
        try:
            super()._start_alignment()
        finally:
            self._generator_run = False
        if not self._alignment_active:
            self._run_kind = None

    def _before_oct_start(self, output: Path | None) -> None:
        settings = self._pending_settings if self._generator_run else None
        if settings is None:
            super()._before_oct_start(output)
            return
        self.generator.connect()
        state = self.generator.apply(settings)
        super()._before_oct_start(output)  # USB photo/video before the excitation starts
        self._output1_on = True  # from here on, any failure must turn OUTPUT1 off
        self.generator.start_excitation()  # on during arming: ready before the first trigger
        self._applied_state = replace(state, output1=True, output2=True)
        self.gen_status_var.set(self._applied_state.summary())
        purpose = "alineación" if self._run_kind == "alignment" else "adquisición"
        self._append_log(
            f"DG4162: CH1 {settings.ch1_vpp * 1000:g} mVpp · CH2 {waveform_label(settings.ch2_waveform)} "
            f"{settings.ch2_frequency_hz:g} Hz · retardo {settings.ch2_delay_ms:g} ms · "
            f"OUTPUT1 ON para {purpose}."
        )

        def verify_excitation() -> None:  # acquisition thread, hardware armed
            if self.generator.start_excitation():
                self.event_queue.put(EngineEvent(
                    "dg4162", {"message": "OUTPUT1 estaba apagado al terminar el armado: encendido."}))

        self.engine.before_acquire = verify_excitation

    def _write_generator_sidecar(self) -> None:
        output = self._last_output
        if output is None or self._pending_settings is None:
            return
        job = self._current_job if self._sequence_active else None
        record: dict[str, Any] = {
            "acquisition_file": output.name,
            "created_local": datetime.now().isoformat(timespec="seconds"),
            "generator_settings": self._pending_settings.as_dict(),
            "generator_state": self._applied_state.as_dict() if self._applied_state else None,
            "sequence": None if job is None else {
                "excel_row": job.row, "repetition": job.repetition, "repetitions": job.repetitions,
                "index": self._sequence_index + 1, "total": len(self._sequence_jobs),
            },
        }
        path = output.with_name(output.stem + "_dg4162.json")
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("x", encoding="utf-8") as handle:
                json.dump(record, handle, indent=2, ensure_ascii=False)
        except OSError as exc:
            self._append_log(f"No se pudo guardar {path.name}: {exc}")

    def _generator_off(self, reason: str) -> None:
        if not self._output1_on:
            return
        try:
            self.generator.stop_excitation()
            self._output1_on = False
            self._append_log(f"DG4162: OUTPUT1 OFF ({reason}).")
        except Exception as exc:
            self._append_log(f"DG4162: ERROR al apagar OUTPUT1: {exc}")
            messagebox.showwarning(
                "DG4162", f"No se pudo apagar OUTPUT1: {exc}\n\nApáguelo manualmente en el panel del generador.",
            )

    def _on_oct_start_failed(self) -> None:
        self.engine.before_acquire = None
        self._generator_off("inicio fallido")
        super()._on_oct_start_failed()

    def _handle_event(self, event: EngineEvent) -> None:
        if event.kind == "dg4162":
            self._append_log(f"DG4162: {event.payload.get('message', '')}")
            if self._applied_state is not None:
                self.gen_status_var.set(self._applied_state.summary())
            return
        super()._handle_event(event)
        if event.kind != "state" or event.payload.get("state") not in _FINAL_STATES:
            return
        state = event.payload["state"]
        self._generator_off({"completed": "adquisición completa", "stopped": "detenida",
                             "error": "error"}.get(state, state))
        kind, self._run_kind = self._run_kind, None
        if state == EngineState.ERROR.value and kind == "acquisition" and not self._closing:
            if self._retry_failed_acquisition():
                self._update_target()
                return
        self._update_target()
        if self._sequence_active and not self._sequence_starting:
            self._sequence_step_finished(state)

    def _delete_failed_files(self, output: Path | None) -> list[str]:
        if output is None:
            return []
        removed: list[str] = []
        candidates = (
            output,
            output.with_name(output.stem + "_dg4162.json"),
            output.with_name(output.stem + "_usb.png"),
            output.with_name(output.stem + "_usb.mp4"),
        )
        for path in candidates:
            try:
                if path.exists():
                    path.unlink()
                    removed.append(path.name)
            except OSError as exc:
                self._append_log(f"No se pudo eliminar {path.name}: {exc}")
        return removed

    def _retry_failed_acquisition(self) -> bool:
        """Delete the failed file and schedule a new attempt (max MAX_RETRIES)."""
        removed = self._delete_failed_files(self._last_output)
        removed_text = ", ".join(removed) if removed else "ningún archivo"
        if self._retry_count >= MAX_RETRIES:
            self._append_log(
                f"Adquisición fallida tras {MAX_RETRIES} reintentos; eliminado: {removed_text}."
            )
            if not self._sequence_active:
                messagebox.showerror(
                    "Adquisición fallida",
                    f"La adquisición falló {MAX_RETRIES + 1} veces seguidas y se descartó. "
                    "Revise la consola antes de volver a intentarlo.",
                )
            return False
        self._retry_count += 1
        self._append_log(
            f"Error al adquirir: eliminado {removed_text}; se repite la adquisición "
            f"(reintento {self._retry_count}/{MAX_RETRIES})."
        )
        self._retry_after = self.root.after(RETRY_DELAY_MS, self._run_retry)
        self.stop_button.configure(state="normal")  # lets the user cancel the retry
        if self._sequence_window is not None and self._sequence_active:
            self._sequence_window.status_var.set(
                f"Error en la adquisición {self._sequence_index + 1}: reintento "
                f"{self._retry_count}/{MAX_RETRIES}…"
            )
        return True

    def _run_retry(self) -> None:
        self._retry_after = None
        if self._closing:
            return
        self._retrying = True
        try:
            if self._sequence_active:
                self._run_sequence_job()
            else:
                self._start(confirm=False)
        finally:
            self._retrying = False

    def _cancel_retry(self) -> bool:
        if self._retry_after is None:
            return False
        try:
            self.root.after_cancel(self._retry_after)
        except tk.TclError:
            pass
        self._retry_after = None
        return True

    def _stop(self) -> None:
        if not self.engine.is_active and self._cancel_retry():
            self.stop_button.configure(state="disabled")
            self._append_log("Reintento cancelado por el usuario.")
            if self._sequence_active:
                self._finish_sequence("Secuencia detenida por el usuario durante un reintento.")
            return
        super()._stop()

    # -- sequence ---------------------------------------------------------------
    def _open_sequence(self) -> None:
        if self._sequence_window is None or not self._sequence_window.window.winfo_exists():
            self._sequence_window = _SequenceWindow(self)
        self._sequence_window.show()

    def _sequence_defaults(self) -> dict[str, Any]:
        return {
            "modo": MODE_PREFIX[MODE_LABELS[self.mode_var.get()]],
            "patron": self.pattern_var.get(),
            "orientacion": self.orientation_var.get(),
            "a_lines": self.alines_var.get(),
            "b_scans": self.bscans_var.get(),
            "m_reps": self.repetitions_var.get(),
            "sync_samples": self.sync_var.get(),
            "longitud_x_mm": self.x_length_var.get(),
            "longitud_y_mm": self.y_length_var.get(),
            "bframes_delay_us": self.bframes_delay_var.get(),
            "excitacion": self.excitation_var.get(),
            "ch1_mVpp": self.ch1_mvpp_var.get(),
            "ch2_frecuencia_Hz": self.ch2_freq_var.get(),
            "ch2_forma_onda": self.ch2_wave_var.get(),
            "ch2_retardo_ms": self.ch2_delay_var.get(),
        }

    def _job_scan(self, job: SequenceJob) -> tuple[ScanParameters, Any]:
        scan = ScanParameters(
            alines=job.alines, bscans=job.bscans, m_repetitions=job.m_repetitions,
            sync_points=job.sync_points, bframes_delay_us=job.bframes_delay_us,
            x_length_mm=job.x_length_mm, y_length_mm=job.y_length_mm,
            mode=job.mode, pattern=job.pattern, orientation=job.orientation,
        )
        scan.validate()
        hardware = replace(
            self.hardware,
            k_start_nm=float(self.k_start_var.get().replace(",", ".")),
            k_end_nm=float(self.k_end_var.get().replace(",", ".")),
            dispersion_d2_rad=float(self.d2_var.get().replace(",", ".")),
            dispersion_d3_rad=float(self.d3_var.get().replace(",", ".")),
        )
        hardware.validate(scan)
        return scan, hardware

    def _validate_job_scan(self, job: SequenceJob) -> None:
        try:
            self._job_scan(job)
        except ConfigurationError as exc:
            raise ValueError(str(exc)) from exc

    def _job_duration_s(self, job: SequenceJob) -> float:
        scan, hardware = self._job_scan(job)
        return (
            scan.expected_alines
            + scan.total_segments * scan.sync_points
            + scan.oce_trigger_segments * hardware.oce_post_hold_points(scan)
        ) / hardware.effective_line_rate_hz

    def _job_output_path(self, job: SequenceJob, taken: set[Path]) -> Path:
        folder = Path(job.folder) if job.folder else self._folder()
        generator = self.gen_enabled_var.get()
        stem = job.name or default_stem(
            job.mode, job.alines, job.bscans, job.m_repetitions, job.sync_points,
            ch1_vpp=job.generator.ch1_vpp if generator else None,
            ch2_frequency_hz=job.generator.ch2_frequency_hz if generator else None,
        )
        return unique_path(folder, stem, taken=taken)

    def _apply_job_to_gui(self, job: SequenceJob) -> None:
        self.mode_var.set(_MODE_LABEL[job.mode])
        self.pattern_var.set(_PATTERN_LABEL[job.pattern])
        self.orientation_var.set(_ORIENTATION_LABEL[job.orientation])
        self.alines_var.set(str(job.alines))
        self.bscans_var.set(str(job.bscans))
        self.repetitions_var.set(str(job.m_repetitions))
        self.sync_var.set(str(job.sync_points))
        self.x_length_var.set(f"{job.x_length_mm:g}")
        self.y_length_var.set(f"{job.y_length_mm:g}")
        self.bframes_delay_var.set(f"{job.bframes_delay_us:g}")
        g = job.generator
        self.excitation_var.set(g.excitation.value)
        self.ch1_mvpp_var.set(f"{g.ch1_vpp * 1000:g}")
        self.ch2_freq_var.set(f"{g.ch2_frequency_hz:g}")
        self.ch2_wave_var.set(waveform_label(g.ch2_waveform))
        self.ch2_delay_var.set(f"{g.ch2_delay_ms:g}")

    def _start_sequence(self) -> None:
        window = self._sequence_window
        jobs = self._sequence_jobs
        if window is None or not jobs or self._sequence_active:
            return
        if self.engine.is_active:
            messagebox.showerror("Secuencia", "Hay una adquisición en curso.", parent=window.window)
            return
        if not self.save_var.get():
            messagebox.showerror("Secuencia", "Active 'Guardar datos crudos (.bin)' para ejecutar una secuencia.",
                                 parent=window.window)
            return
        high = sorted({job.row for job in jobs if job.generator.ch1_vpp > WARNING_CH1_VPP})
        if self.gen_enabled_var.get():
            if high and not messagebox.askyesno(
                "CH1 por encima de 1 Vpp",
                f"Las filas {', '.join(map(str, high))} usan CH1 > 1 Vpp (excitación con contacto, "
                "límite 5 Vpp). ¿Confirma que el amplificador y el transductor lo admiten?",
                icon="warning", parent=window.window,
            ):
                return
            if not self._connect_generator(interactive=True):
                return
        elif not messagebox.askyesno(
            "Secuencia sin generador",
            "El control del DG4162 está desactivado: no se programará CH1/CH2 ni se conmutará OUTPUT1. "
            "¿Ejecutar la secuencia igualmente?", parent=window.window,
        ):
            return
        if self.backend_var.get() == "Hardware NI" and not messagebox.askyesno(
            "Armar hardware NI",
            f"Se ejecutarán {len(jobs)} adquisiciones seguidas con hardware NI (AO0/AO1, PFI12/PFI13).\n"
            "No se volverá a pedir confirmación entre adquisiciones. Use 'Detener secuencia' para abortar.\n\n"
            "¿Iniciar la secuencia?", icon="warning", parent=window.window,
        ):
            return
        self._sequence_active = True
        self._sequence_index = 0
        for index in range(len(jobs)):
            window.mark(index, "")
        window.set_running(True)
        self.sequence_button.configure(text="Secuencia en curso…")
        self._append_log(f"Secuencia iniciada: {len(jobs)} adquisiciones.")
        self._run_sequence_job()

    def _run_sequence_job(self) -> None:
        self._sequence_after = None
        window = self._sequence_window
        jobs = self._sequence_jobs
        index = self._sequence_index
        job = jobs[index]
        self._current_job = job
        self._apply_job_to_gui(job)
        if window is not None:
            window.mark(index, "current")
            window.progress_var.set(100.0 * index / len(jobs))
            window.status_var.set(
                f"Adquisición {index + 1}/{len(jobs)} · fila {job.row} · repetición {job.repetition}/{job.repetitions}"
            )
        self._sequence_starting = True
        try:
            started = self._start(confirm=False)
        finally:
            self._sequence_starting = False
        if not started:
            if window is not None:
                window.mark(index, "failed")
            self._finish_sequence(f"Secuencia abortada: no se pudo iniciar la adquisición {index + 1}.")

    def _sequence_step_finished(self, state: str) -> None:
        window = self._sequence_window
        index = self._sequence_index
        jobs = self._sequence_jobs
        if state != EngineState.COMPLETED.value:
            if window is not None:
                window.mark(index, "failed")
            label = "detenida" if state == EngineState.STOPPED.value else "con error"
            self._finish_sequence(f"Secuencia abortada: adquisición {index + 1}/{len(jobs)} {label}.")
            return
        if window is not None:
            window.mark(index, "done")
        self._sequence_index += 1
        if self._sequence_index >= len(jobs):
            self._finish_sequence(f"Secuencia completa: {len(jobs)} adquisiciones.")
            return
        self._sequence_wait(jobs[index].wait_s)

    def _sequence_wait(self, remaining_s: float) -> None:
        self._sequence_after = None
        if not self._sequence_active:
            return
        if remaining_s <= 0:
            self._run_sequence_job()
            return
        window = self._sequence_window
        if window is not None:
            window.progress_var.set(100.0 * self._sequence_index / len(self._sequence_jobs))
            window.status_var.set(
                f"Esperando {remaining_s:.0f} s antes de la adquisición "
                f"{self._sequence_index + 1}/{len(self._sequence_jobs)}…"
            )
        step = min(1.0, remaining_s)
        self._sequence_after = self.root.after(
            int(step * 1000), lambda: self._sequence_wait(remaining_s - step)
        )

    def _stop_sequence(self) -> None:
        if not self._sequence_active:
            return
        if self.engine.is_active:
            self._append_log("Deteniendo la secuencia: se detiene la adquisición actual.")
            super()._stop()  # the STOPPED event finishes the sequence
        else:
            self._finish_sequence(
                f"Secuencia detenida por el usuario antes de la adquisición {self._sequence_index + 1}."
            )

    def _finish_sequence(self, message: str) -> None:
        self._cancel_retry()
        if self._sequence_after is not None:
            try:
                self.root.after_cancel(self._sequence_after)
            except tk.TclError:
                pass
            self._sequence_after = None
        self._sequence_active = False
        self._current_job = None
        self._append_log(message)
        self._update_target()
        if hasattr(self, "sequence_button"):
            self.sequence_button.configure(text="Secuencia desde Excel…")
        window = self._sequence_window
        if window is not None and window.window.winfo_exists():
            if message.startswith("Secuencia completa"):
                window.progress_var.set(100.0)
            window.status_var.set(message)
            window.set_running(False)

    # -- shutdown ---------------------------------------------------------------
    def _on_close(self) -> None:
        if self._sequence_active and not self.engine.is_active:
            if not messagebox.askyesno("Cerrar aplicación", "Hay una secuencia en curso. ¿Detenerla y cerrar?",
                                       icon="warning"):
                return
            self._finish_sequence("Secuencia cancelada al cerrar la aplicación.")
        super()._on_close()

    def _before_root_destroy(self) -> None:
        if self._sequence_active:
            self._finish_sequence("Secuencia cancelada al cerrar la aplicación.")
        self._cancel_retry()
        for name in ("_connect_after", "_square_after"):
            callback = getattr(self, name)
            if callback is not None:
                try:
                    self.root.after_cancel(callback)
                except tk.TclError:
                    pass
                setattr(self, name, None)
        connected = self.generator.connected
        warnings = self.generator.close(restore=True)
        self._output1_on = False
        if warnings:
            for warning in warnings:
                self._append_log(f"DG4162: {warning}")
            messagebox.showwarning(
                "DG4162", "\n".join(warnings) + "\n\nApague OUTPUT1 y OUTPUT2 manualmente.",
            )
        elif connected:
            self._append_log("DG4162: OUTPUT1/OUTPUT2 OFF y configuración inicial restaurada.")
        super()._before_root_destroy()


def main() -> None:
    root = tk.Tk()
    OCTOCEDG4162App(root)
    root.mainloop()
