"""Interfaz gráfica del simulador OCE (Tkinter + matplotlib).

Panel izquierdo: parámetros por pestañas (medio, excitación, adquisición OCT,
simulación, procesamiento, validación, salida). Panel derecho: geometría,
teoría, supuestos, videos B-mode/en-face, mapas de velocidad, dispersión,
validación y registro. La simulación corre en un hilo de trabajo.
"""
from __future__ import annotations

import json
import os
import queue
import threading
import traceback
from pathlib import Path
from tkinter import colorchooser, filedialog, messagebox
import tkinter as tk
from tkinter import ttk
from typing import Any, Callable

import numpy as np
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg, NavigationToolbar2Tk
from matplotlib.figure import Figure

from . import figures, references
from .acquisition import ORIENTATIONS, PATTERNS, MODES as ACQ_MODES, build_plan
from .backend import get_backend
from .config import SimulationConfig, explicit_assumptions
from .excitation import CH2_WAVEFORMS, MODES as EXC_MODES, REGIMES, SHAPES, SOURCE_LAYOUTS, describe_load
from .fdtd import SimulationCancelled
from .geometry import BOTTOMS, INCLUSION_SHAPES, LATERALS, SURFACES, Inclusion, Layer
from .materials import Material
from .presets import PRESETS
from .video import WAVE_CMAP, robust_limit

APP_TITLE = "Simulador OCE - SD-OCT 1310 nm (GIBIO-PUCP)"
SPEED_METHODS = ("gradiente_fase", "tiempo_vuelo", "lfe", "kf", "reverberante")

# --------------------------------------------------------------------------------------
# Especificación de formularios: (campo, etiqueta, unidad, tipo/opciones)
# tipo: "float", "int", "str", "bool", "floats" (lista separada por comas), o tupla de opciones
# --------------------------------------------------------------------------------------
MATERIAL_FIELDS = [
    ("name", "Nombre", "", "str"),
    ("E_kPa", "Módulo de Young E", "kPa", "float"),
    ("nu", "Coef. de Poisson nu (simulación)", "", "float"),
    ("rho", "Densidad rho", "kg/m³", "float"),
    ("eta_Pa_s", "Viscosidad de corte eta (Kelvin-Voigt)", "Pa·s", "float"),
    ("n", "Índice de refracción de grupo n", "", "float"),
    ("backscatter_db", "Retrodispersión OCT (por celda)", "dB", "float"),
    ("mu_oct_per_mm", "Atenuación OCT mu", "1/mm", "float"),
    ("alpha_db_cm_mhz", "Atenuación ultrasónica alpha0", "dB/cm/MHz", "float"),
    ("c_acoustic", "Velocidad del sonido real (ARF)", "m/s", "float"),
    ("is_fluid", "Es fluido (mu = 0)", "", "bool"),
    ("c_fluid_sim", "c del fluido en simulación (0 = auto)", "m/s", "float"),
]
GEOMETRY_FIELDS = [
    ("size_x_mm", "Dimensión X", "mm", "float"),
    ("size_y_mm", "Dimensión Y", "mm", "float"),
    ("size_z_mm", "Dimensión Z (profundidad)", "mm", "float"),
    ("surface", "Superficie", "", SURFACES),
    ("dome_radius_mm", "Radio del domo", "mm", "float"),
    ("bottom", "Condición de fondo", "", BOTTOMS),
    ("lateral", "Condición lateral", "", LATERALS),
]
EXCITATION_FIELDS = [
    ("mode", "Modo de excitación", "", EXC_MODES),
    ("regime", "Régimen", "", REGIMES),
    ("pressure_MPa", "Presión (acústica pico / contacto)", "MPa", "float"),
    ("carrier_hz", "Portadora CH1", "Hz", "float"),
    ("shape", "Geometría del área de excitación", "", SHAPES),
    ("center_x_mm", "Centro x", "mm", "float"),
    ("center_y_mm", "Centro y", "mm", "float"),
    ("size_a_mm", "Tamaño a (FWHM / ancho / radio anillo)", "mm", "float"),
    ("size_b_mm", "Tamaño b (2.º eje / largo / ancho anillo)", "mm", "float"),
    ("angle_deg", "Ángulo del eje a", "°", "float"),
    ("focal_depth_mm", "Profundidad focal (contacto)", "mm", "float"),
    ("dof_mm", "Profundidad de foco FWHM (contacto)", "mm", "float"),
    ("ch2_waveform", "CH2: forma de onda", "", CH2_WAVEFORMS),
    ("ch2_freq_hz", "CH2: frecuencia", "Hz", "float"),
    ("ch2_duty", "CH2: ciclo útil (Pulso)", "", "float"),
    ("ch2_cycles", "CH2: ciclos por burst", "", "int"),
    ("ch2_delay_ms", "CH2: retardo tras PFI13", "ms", "float"),
    ("rise_time_us", "Tiempo de subida del transductor", "µs", "float"),
    ("harmonic_hz", "Armónico: frecuencia", "Hz", "float"),
    ("n_sources", "Armónico: número de fuentes", "", "int"),
    ("source_layout", "Armónico: disposición", "", SOURCE_LAYOUTS),
    ("ring_radius_mm", "Armónico: radio del anillo / zona", "mm", "float"),
    ("tip_radius_mm", "Anillo: radio de cada punta", "mm", "float"),
    ("random_phase", "Armónico: fases aleatorias", "", "bool"),
    ("seed", "Semilla aleatoria", "", "int"),
    ("ramp_periods", "Rampa de encendido", "periodos", "float"),
]
ACQ_FIELDS = [
    ("mode", "Modo (MB = OCE, BM = OCT)", "", ACQ_MODES),
    ("pattern", "Patrón", "", PATTERNS),
    ("orientation", "Orientación (lineal)", "", ORIENTATIONS),
    ("alines", "A-lines por B-scan", "", "int"),
    ("bscans", "B-scans", "", "int"),
    ("m_reps", "Repeticiones M", "", "int"),
    ("sync_points", "Puntos sync", "", "int"),
    ("x_length_mm", "Longitud X", "mm", "float"),
    ("y_length_mm", "Longitud Y", "mm", "float"),
    ("center_x_mm", "Centro X", "mm", "float"),
    ("center_y_mm", "Centro Y", "mm", "float"),
    ("raster_bidirectional", "Raster bidireccional (BM)", "", "bool"),
    ("bframes_delay_us", "BFramesDelay", "µs", "float"),
    ("line_rate_hz", "Frecuencia de línea", "Hz", "float"),
]
OCT_FIELDS = [
    ("lambda0_nm", "Longitud de onda central", "nm", "float"),
    ("axial_res_um", "Resolución axial (FWHM, aire)", "µm", "float"),
    ("lateral_res_um", "Resolución lateral (FWHM)", "µm", "float"),
    ("depth_px_um", "Muestreo axial (aire)", "µm/px", "float"),
    ("sensitivity_db", "Sensibilidad", "dB", "float"),
    ("rolloff_db_per_mm", "Roll-off", "dB/mm", "float"),
    ("phase_stability_mrad", "Estabilidad de fase", "mrad", "float"),
    ("zero_delay_gap_mm", "Distancia retardo cero - ápice", "mm", "float"),
    ("depth_window_mm", "Profundidad simulada bajo el ápice", "mm", "float"),
    ("specular", "Reflexión especular de Fresnel", "", "bool"),
    ("trigger_jitter_us", "Jitter de disparo", "µs", "float"),
    ("seed", "Semilla del speckle/ruido", "", "int"),
]
FDTD_FIELDS = [
    ("backend", "Backend", "", ("auto", "gpu", "cpu")),
    ("cell_mm", "Tamaño de celda (0 = auto)", "mm", "float"),
    ("ppw", "Puntos por longitud de onda", "", "float"),
    ("f_max_hz", "Frecuencia máxima (0 = auto)", "Hz", "float"),
    ("courant", "Fracción del límite de estabilidad", "", "float"),
    ("pml_cells", "Celdas C-PML", "", "int"),
    ("pml_R", "Reflexión teórica C-PML", "", "float"),
    ("duration_ms", "Duración transitoria (0 = auto)", "ms", "float"),
    ("record_margin_mm", "Margen del registro", "mm", "float"),
    ("record_depth_mm", "Profundidad registrada", "mm", "float"),
    ("record_stride", "Paso del registro (0 = auto)", "celdas", "int"),
    ("harmonic_min_periods", "Armónico: periodos mínimos", "", "int"),
    ("harmonic_max_periods", "Armónico: periodos máximos", "", "int"),
    ("harmonic_tol", "Armónico: tolerancia de convergencia", "", "float"),
    ("harmonics", "Armónicos extraídos (ARF: 2)", "", "int"),
    ("max_cells", "Máximo de celdas", "", "int"),
]
PROC_FIELDS = [
    ("loupas_window", "Ventana axial de Loupas", "px", "int"),
    ("n_processing", "Índice para fase->desplazamiento (0 = capa sup.)", "", "float"),
    ("surface_correction", "Corrección de superficie [Song2013]", "", "bool"),
    ("surface_threshold_db", "Umbral de superficie", "dB", "float"),
    ("surface_samples", "Muestras de superficie promediadas", "", "int"),
    ("filter_low_hz", "Filtro temporal: f baja", "Hz", "float"),
    ("filter_high_hz", "Filtro temporal: f alta", "Hz", "float"),
    ("remove_temporal_mean", "Remover media temporal", "", "bool"),
    ("speed_filter", "Filtro espacial de velocidades", "", "bool"),
    ("speed_min_m_s", "Velocidad mínima del filtro", "m/s", "float"),
    ("speed_max_m_s", "Velocidad máxima del filtro", "m/s", "float"),
    ("enface_method", "Interpolación en-face", "", ("lineal", "cubica", "vecino")),
    ("enface_pixel_mm", "Píxel en-face", "mm", "float"),
    ("enface_depths_mm", "Profundidades en-face extra", "mm", "floats"),
    ("bmode_bscans", "B-scans con video (vacío = auto)", "", "ints"),
    ("intensity_mask_db", "Máscara de intensidad B-mode", "dB", "float"),
]
SPEED_FIELDS = [
    ("frequencies_hz", "Frecuencia de análisis (vacío = auto)", "Hz", "floats"),
    ("window_mm", "Ventana lateral", "mm", "float"),
    ("window_z_mm", "Ventana en profundidad (B-mode)", "mm", "float"),
    ("ci_threshold_pct", "Umbral de IC del ajuste de fase", "%", "float"),
    ("tof_r2_min", "R² mínimo del TOF", "", "float"),
    ("lfe_bandwidth_oct", "Ancho de banda LFE", "octavas", "float"),
    ("reverb_model", "Modelo reverberante", "", ("auto", "3D", "2D")),
    ("reverb_phase_only", "Reverberante: solo fase [Ormachea2018]", "", "bool"),
    ("reverb_estimator", "Reverberante: estimador", "", ("ajuste", "curvatura")),
    ("c_min", "Velocidad mínima válida", "m/s", "float"),
    ("c_max", "Velocidad máxima válida", "m/s", "float"),
    ("exclude_radius_mm", "Radio excluido en la fuente (0 = auto)", "mm", "float"),
]
VALIDATION_FIELDS = [
    ("model", "Modelo teórico", "", ("auto", "rayleigh", "lamb_libre", "lamb_fluido", "corte", "ninguno")),
    ("layer", "Capa de referencia (índice)", "", "int"),
    ("band_hz", "Banda k-f (vacío = filtro)", "Hz", "floats"),
    ("tolerance_pct", "Tolerancia k-f", "%", "float"),
    ("oct_chain_min_r", "r mínimo cadena OCT", "", "float"),
]
OUTPUT_FIELDS = [
    ("root", "Carpeta raíz de resultados", "", "str"),
    ("fps", "Cuadros por segundo del video", "", "float"),
    ("max_video_frames", "Cuadros máximos del video", "", "int"),
    ("save_npz", "Guardar datos (.npz)", "", "bool"),
]


class Form(ttk.Frame):
    """Formulario genérico ligado a un dataclass."""

    def __init__(self, master: tk.Misc, specs: list[tuple[str, str, str, Any]], on_change: Callable[[], None] | None = None):
        super().__init__(master)
        self.specs = specs
        self.vars: dict[str, tk.Variable] = {}
        self.on_change = on_change
        for r, (name, label, unit, kind) in enumerate(specs):
            ttk.Label(self, text=label).grid(row=r, column=0, sticky="w", padx=(2, 6), pady=1)
            if kind == "bool":
                var: tk.Variable = tk.BooleanVar()
                w = ttk.Checkbutton(self, variable=var)
            elif isinstance(kind, tuple):
                var = tk.StringVar()
                w = ttk.Combobox(self, textvariable=var, values=kind, state="readonly", width=18)
            else:
                var = tk.StringVar()
                w = ttk.Entry(self, textvariable=var, width=20)
            w.grid(row=r, column=1, sticky="ew", pady=1)
            ttk.Label(self, text=unit, foreground="#555").grid(row=r, column=2, sticky="w", padx=4)
            self.vars[name] = var
            if on_change is not None:
                var.trace_add("write", lambda *_: on_change())
        self.columnconfigure(1, weight=1)

    def load(self, obj: Any) -> None:
        for name, _l, _u, kind in self.specs:
            v = getattr(obj, name)
            if kind == "bool":
                self.vars[name].set(bool(v))
            elif kind in ("floats", "ints"):
                self.vars[name].set(", ".join(f"{x:g}" for x in v if not (kind == "floats" and x == 0 and name == "band_hz")))
            else:
                self.vars[name].set(repr(v) if isinstance(v, float) else str(v))   # ida y vuelta exacta

    def store(self, obj: Any) -> None:
        for name, label, _u, kind in self.specs:
            raw = self.vars[name].get()
            try:
                if kind == "bool":
                    val: Any = bool(raw)
                elif kind == "int":
                    val = int(float(str(raw).replace(",", ".")))
                elif kind == "float":
                    val = float(str(raw).replace(",", "."))
                elif kind == "floats":
                    parts = [p for p in str(raw).replace(";", ",").split(",") if p.strip()]
                    val = tuple(float(p) for p in parts)
                    if name == "band_hz":
                        val = val if len(val) == 2 else (0.0, 0.0)
                elif kind == "ints":
                    parts = [p for p in str(raw).replace(";", ",").split(",") if p.strip()]
                    val = tuple(int(float(p)) for p in parts)
                else:
                    val = str(raw)
            except ValueError as exc:
                raise ValueError(f"Valor inválido en '{label}': {raw!r}") from exc
            setattr(obj, name, val)


class ScrollFrame(ttk.Frame):
    """Marco con barra de desplazamiento vertical."""

    def __init__(self, master: tk.Misc):
        super().__init__(master)
        self.canvas = tk.Canvas(self, highlightthickness=0)
        sb = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        self.inner = ttk.Frame(self.canvas)
        self.inner.bind("<Configure>", lambda e: self.canvas.configure(scrollregion=self.canvas.bbox("all")))
        self._win = self.canvas.create_window((0, 0), window=self.inner, anchor="nw")
        self.canvas.bind("<Configure>", lambda e: self.canvas.itemconfigure(self._win, width=e.width))
        self.canvas.configure(yscrollcommand=sb.set)
        self.canvas.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        self.inner.bind("<Enter>", lambda e: self.canvas.bind_all("<MouseWheel>", self._wheel))
        self.inner.bind("<Leave>", lambda e: self.canvas.unbind_all("<MouseWheel>"))

    def _wheel(self, event: tk.Event) -> None:
        self.canvas.yview_scroll(int(-event.delta / 120), "units")


class MaterialDialog(tk.Toplevel):
    """Edición de una capa (material + espesor) o de una inclusión (material + forma)."""

    def __init__(self, master: tk.Misc, title: str, material: Material, extra_specs: list, extra_obj: Any):
        super().__init__(master)
        self.title(title)
        self.transient(master)
        self.result = False
        self.material = material
        self.extra_obj = extra_obj
        frm = ttk.Frame(self, padding=8)
        frm.pack(fill="both", expand=True)
        self.extra = Form(frm, extra_specs) if extra_specs else None
        if self.extra:
            self.extra.pack(fill="x")
            self.extra.load(extra_obj)
            ttk.Separator(frm).pack(fill="x", pady=6)
        self.form = Form(frm, MATERIAL_FIELDS)
        self.form.pack(fill="x")
        self.form.load(material)
        self.color = material.color
        cf = ttk.Frame(frm)
        cf.pack(fill="x", pady=4)
        ttk.Label(cf, text="Color en las vistas").pack(side="left")
        self.swatch = tk.Label(cf, width=4, background=self.color)
        self.swatch.pack(side="left", padx=6)
        ttk.Button(cf, text="Elegir...", command=self._pick).pack(side="left")
        bf = ttk.Frame(frm)
        bf.pack(fill="x", pady=(8, 0))
        ttk.Button(bf, text="Aceptar", command=self._ok).pack(side="right", padx=4)
        ttk.Button(bf, text="Cancelar", command=self.destroy).pack(side="right")
        self.grab_set()
        self.wait_window()

    def _pick(self) -> None:
        c = colorchooser.askcolor(self.color, parent=self)[1]
        if c:
            self.color = c
            self.swatch.configure(background=c)

    def _ok(self) -> None:
        try:
            self.form.store(self.material)
            if self.extra:
                self.extra.store(self.extra_obj)
        except ValueError as exc:
            messagebox.showerror("Valor inválido", str(exc), parent=self)
            return
        self.material.color = self.color
        errs = self.material.validate()
        if errs:
            messagebox.showerror("Material inválido", "\n".join(errs), parent=self)
            return
        self.result = True
        self.destroy()


class _InclusionShape:
    """Adaptador editable de la geometría de una inclusión."""

    def __init__(self, inc: Inclusion):
        self.shape = inc.shape
        self.cx, self.cy, self.cz = inc.center_mm
        self.a, self.b, self.c = inc.size_mm
        self.axis = inc.axis
        self.relative_to_surface = inc.relative_to_surface

    def apply(self, inc: Inclusion) -> None:
        inc.shape = self.shape
        inc.center_mm = (self.cx, self.cy, self.cz)
        inc.size_mm = (self.a, self.b, self.c)
        inc.axis = self.axis
        inc.relative_to_surface = self.relative_to_surface


INCLUSION_SHAPE_FIELDS = [
    ("shape", "Forma", "", INCLUSION_SHAPES),
    ("cx", "Centro x", "mm", "float"),
    ("cy", "Centro y", "mm", "float"),
    ("cz", "Centro z (profundidad)", "mm", "float"),
    ("a", "a: radio / semieje x / semilado", "mm", "float"),
    ("b", "b: semieje y / semilado (elipsoide, caja)", "mm", "float"),
    ("c", "c: semieje z / semilargo del cilindro", "mm", "float"),
    ("axis", "Eje del cilindro", "", ("x", "y", "z")),
    ("relative_to_surface", "z medido desde la superficie local", "", "bool"),
]


class _LayerThickness:
    def __init__(self, layer: Layer):
        self.thickness_mm = layer.thickness_mm


# --------------------------------------------------------------------------------------
class SimulatorApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_TITLE)
        try:
            self.state("zoomed")
        except tk.TclError:
            self.geometry("1500x900")
        self.cfg: SimulationConfig = PRESETS["Prueba rápida"]()
        self.result: Any = None
        self.worker: threading.Thread | None = None
        self.cancel = threading.Event()
        self.queue: queue.Queue = queue.Queue()
        self._preview_job: str | None = None
        self.backend_text = get_backend("auto").describe()
        self._build()
        self._load_config(self.cfg)
        self.after(150, self._poll)

    # ------------------------------------------------------------------ construcción
    def _build(self) -> None:
        top = ttk.Frame(self, padding=(6, 4))
        top.pack(fill="x")
        ttk.Label(top, text="Ejemplo:").pack(side="left")
        self.preset_var = tk.StringVar(value="Prueba rápida")
        ttk.Combobox(top, textvariable=self.preset_var, values=list(PRESETS), width=52,
                     state="readonly").pack(side="left", padx=4)
        ttk.Button(top, text="Cargar ejemplo", command=self._load_preset).pack(side="left")
        ttk.Separator(top, orient="vertical").pack(side="left", fill="y", padx=6)
        ttk.Button(top, text="Abrir JSON...", command=self._open_json).pack(side="left")
        ttk.Button(top, text="Guardar JSON...", command=self._save_json).pack(side="left", padx=2)
        ttk.Separator(top, orient="vertical").pack(side="left", fill="y", padx=6)
        ttk.Button(top, text="Estimar recursos", command=self._estimate).pack(side="left")
        self.run_btn = ttk.Button(top, text="▶ Simular", command=self._run)
        self.run_btn.pack(side="left", padx=4)
        self.stop_btn = ttk.Button(top, text="■ Detener", command=self._stop, state="disabled")
        self.stop_btn.pack(side="left")
        self.cache_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(top, text="Reutilizar campo FDTD (caché)", variable=self.cache_var).pack(side="left", padx=8)
        ttk.Button(top, text="Abrir carpeta de resultados", command=self._open_results).pack(side="left")
        ttk.Label(top, text=self.backend_text, foreground="#2b6").pack(side="right")

        paned = ttk.PanedWindow(self, orient="horizontal")
        paned.pack(fill="both", expand=True)
        left = ttk.Frame(paned, width=520)
        right = ttk.Frame(paned)
        paned.add(left, weight=0)
        paned.add(right, weight=1)

        # nombre y descripción
        nf = ttk.Frame(left, padding=4)
        nf.pack(fill="x")
        ttk.Label(nf, text="Nombre (carpeta de resultados):").pack(anchor="w")
        self.name_var = tk.StringVar()
        ttk.Entry(nf, textvariable=self.name_var).pack(fill="x")
        self.desc_text = tk.Text(nf, height=4, wrap="word", font=("Segoe UI", 8))
        self.desc_text.pack(fill="x", pady=(2, 0))

        nb = ttk.Notebook(left)
        nb.pack(fill="both", expand=True)
        self.forms: dict[str, Form] = {}

        def tab(title: str) -> ttk.Frame:
            sf = ScrollFrame(nb)
            nb.add(sf, text=title)
            return sf.inner

        # Medio
        t = tab("Medio")
        self.forms["geometry"] = Form(t, GEOMETRY_FIELDS, self._schedule_preview)
        self.forms["geometry"].pack(fill="x", padx=4, pady=4)
        ttk.Label(t, text="Capas (de arriba hacia abajo; espesor 0 = hasta el fondo)",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=4, pady=(8, 0))
        self.layer_tree = self._tree(t, ("material", "esp_mm", "E_kPa", "eta", "n"),
                                     ("Material", "Espesor (mm)", "E (kPa)", "eta (Pa·s)", "n"))
        self._tree_buttons(t, self._add_layer, self._edit_layer, self._del_layer, self._move_layer)
        ttk.Label(t, text="Inclusiones (propiedades biomecánicas independientes)",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=4, pady=(8, 0))
        self.inc_tree = self._tree(t, ("forma", "centro", "tam", "E_kPa", "n"),
                                   ("Forma", "Centro (mm)", "Tamaño (mm)", "E (kPa)", "n"))
        self._tree_buttons(t, self._add_inclusion, self._edit_inclusion, self._del_inclusion, None)

        # Excitación
        t = tab("Excitación")
        self.forms["excitation"] = Form(t, EXCITATION_FIELDS, self._schedule_preview)
        self.forms["excitation"].pack(fill="x", padx=4, pady=4)
        self.load_label = ttk.Label(t, text="", wraplength=480, foreground="#333")
        self.load_label.pack(fill="x", padx=4, pady=4)

        # Adquisición OCT
        t = tab("Adquisición OCT")
        ttk.Label(t, text="Plan de barrido (semántica de la GUI de adquisición octoce)",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=4)
        self.forms["acquisition"] = Form(t, ACQ_FIELDS, self._schedule_preview)
        self.forms["acquisition"].pack(fill="x", padx=4, pady=4)
        self.timing_label = ttk.Label(t, text="", wraplength=480, foreground="#333")
        self.timing_label.pack(fill="x", padx=4)
        ttk.Label(t, text="Sistema SD-OCT 1310 nm (valores medidos, characterization/LATEST.md)",
                  font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=4, pady=(8, 0))
        self.forms["oct"] = Form(t, OCT_FIELDS)
        self.forms["oct"].pack(fill="x", padx=4, pady=4)

        # Simulación
        t = tab("Simulación")
        self.forms["fdtd"] = Form(t, FDTD_FIELDS)
        self.forms["fdtd"].pack(fill="x", padx=4, pady=4)
        self.estimate_label = ttk.Label(t, text="Pulse 'Estimar recursos' para ver malla, memoria y tiempo.",
                                        wraplength=480, foreground="#333", justify="left")
        self.estimate_label.pack(fill="x", padx=4, pady=6)

        # Procesamiento
        t = tab("Procesamiento")
        self.forms["processing"] = Form(t, PROC_FIELDS)
        self.forms["processing"].pack(fill="x", padx=4, pady=4)
        ttk.Label(t, text="Mapas de velocidad", font=("Segoe UI", 9, "bold")).pack(anchor="w", padx=4, pady=(8, 0))
        mf = ttk.Frame(t)
        mf.pack(fill="x", padx=4)
        self.method_vars = {m: tk.BooleanVar() for m in SPEED_METHODS}
        labels = {"gradiente_fase": "Gradiente de fase", "tiempo_vuelo": "Tiempo de vuelo",
                  "lfe": "Número de onda local (LFE)", "kf": "Dispersión k-f",
                  "reverberante": "Autocorrelación reverberante"}
        for i, m in enumerate(SPEED_METHODS):
            ttk.Checkbutton(mf, text=labels[m], variable=self.method_vars[m]).grid(row=i // 2, column=i % 2, sticky="w")
        self.forms["speed"] = Form(t, SPEED_FIELDS)
        self.forms["speed"].pack(fill="x", padx=4, pady=4)

        # Validación
        t = tab("Validación")
        self.forms["validation"] = Form(t, VALIDATION_FIELDS)
        self.forms["validation"].pack(fill="x", padx=4, pady=4)
        ttk.Label(t, text="Comprobaciones de regiones (JSON editable):").pack(anchor="w", padx=4)
        self.checks_text = tk.Text(t, height=14, wrap="none", font=("Consolas", 8))
        self.checks_text.pack(fill="both", expand=True, padx=4, pady=4)

        # Salida
        t = tab("Salida")
        self.forms["output"] = Form(t, OUTPUT_FIELDS)
        self.forms["output"].pack(fill="x", padx=4, pady=4)

        # Panel derecho: resultados
        self.rnb = ttk.Notebook(right)
        self.rnb.pack(fill="both", expand=True)
        self.figs: dict[str, tuple[Figure, FigureCanvasTkAgg]] = {}
        for key, title in (("geometria", "Geometría"), ("teoria", "Teoría"), ("bmode", "Video B-mode"),
                           ("enface", "Video en-face"), ("velocidad", "Mapas de velocidad"),
                           ("kf", "Dispersión k-f"), ("validacion", "Validación")):
            frame = ttk.Frame(self.rnb)
            self.rnb.add(frame, text=title)
            if key in ("bmode", "enface"):
                ctrl = ttk.Frame(frame)
                ctrl.pack(fill="x")
                setattr(self, f"{key}_slider", tk.Scale(ctrl, from_=0, to=1, orient="horizontal", showvalue=False,
                                                        command=lambda v, k=key: self._show_frame(k, int(float(v)))))
                getattr(self, f"{key}_slider").pack(side="left", fill="x", expand=True, padx=4)
                ttk.Button(ctrl, text="▶/❚❚", width=6, command=lambda k=key: self._toggle_play(k)).pack(side="left")
                if key == "enface":
                    self.enface_plane = tk.StringVar(value="superficie")
                    self.enface_combo = ttk.Combobox(ctrl, textvariable=self.enface_plane, width=16, state="readonly",
                                                     values=["superficie"])
                    self.enface_combo.pack(side="left", padx=4)
                    self.enface_combo.bind("<<ComboboxSelected>>", lambda e: self._setup_player("enface"))
            if key == "velocidad":
                ctrl = ttk.Frame(frame)
                ctrl.pack(fill="x")
                ttk.Label(ctrl, text="Plano:").pack(side="left")
                self.speed_plane = tk.StringVar(value="enface")
                self.speed_combo = ttk.Combobox(ctrl, textvariable=self.speed_plane, width=16, state="readonly",
                                                values=["enface", "bmode"])
                self.speed_combo.pack(side="left", padx=4)
                self.speed_combo.bind("<<ComboboxSelected>>", lambda e: self._draw_result_tab("velocidad"))
                self.modulus_var = tk.BooleanVar(value=False)
                ttk.Checkbutton(ctrl, text="Mostrar E estimado (kPa)", variable=self.modulus_var,
                                command=lambda: self._draw_result_tab("velocidad")).pack(side="left", padx=8)
            fig = Figure(figsize=(8, 6), dpi=100)
            canvas = FigureCanvasTkAgg(fig, master=frame)
            NavigationToolbar2Tk(canvas, frame, pack_toolbar=True)
            canvas.get_tk_widget().pack(fill="both", expand=True)
            self.figs[key] = (fig, canvas)
        tf = ttk.Frame(self.rnb)
        self.rnb.add(tf, text="Supuestos y referencias")
        self.assump_text = tk.Text(tf, wrap="word", font=("Segoe UI", 9))
        self.assump_text.pack(fill="both", expand=True)
        lf = ttk.Frame(self.rnb)
        self.rnb.add(lf, text="Registro")
        self.log_text = tk.Text(lf, wrap="word", font=("Consolas", 9))
        self.log_text.pack(fill="both", expand=True)

        bottom = ttk.Frame(self, padding=(6, 2))
        bottom.pack(fill="x")
        self.progress = ttk.Progressbar(bottom, maximum=1000, length=320)
        self.progress.pack(side="left")
        self.status = ttk.Label(bottom, text="Listo.")
        self.status.pack(side="left", padx=8)
        self.players: dict[str, dict[str, Any]] = {}

    def _tree(self, master: tk.Misc, cols: tuple[str, ...], heads: tuple[str, ...]) -> ttk.Treeview:
        tree = ttk.Treeview(master, columns=cols, show="headings", height=4)
        for c, h in zip(cols, heads):
            tree.heading(c, text=h)
            tree.column(c, width=90, anchor="center")
        tree.column(cols[0], width=170, anchor="w")
        tree.pack(fill="x", padx=4)
        return tree

    def _tree_buttons(self, master: tk.Misc, add: Callable, edit: Callable, delete: Callable,
                      move: Callable | None) -> None:
        f = ttk.Frame(master)
        f.pack(fill="x", padx=4, pady=2)
        ttk.Button(f, text="Añadir", command=add).pack(side="left")
        ttk.Button(f, text="Editar", command=edit).pack(side="left", padx=2)
        ttk.Button(f, text="Eliminar", command=delete).pack(side="left")
        if move:
            ttk.Button(f, text="↑", width=3, command=lambda: move(-1)).pack(side="left", padx=(8, 0))
            ttk.Button(f, text="↓", width=3, command=lambda: move(+1)).pack(side="left")

    # ------------------------------------------------------------------ config <-> GUI
    def _load_config(self, cfg: SimulationConfig) -> None:
        self.cfg = cfg
        self._loading = True
        self.name_var.set(cfg.name)
        self.desc_text.delete("1.0", "end")
        self.desc_text.insert("1.0", cfg.description)
        self.forms["geometry"].load(cfg.geometry)
        self.forms["excitation"].load(cfg.excitation)
        self.forms["acquisition"].load(cfg.acquisition)
        self.forms["oct"].load(cfg.oct)
        self.forms["fdtd"].load(cfg.fdtd)
        self.forms["processing"].load(cfg.processing)
        self.forms["speed"].load(cfg.speed)
        self.forms["validation"].load(cfg.validation)
        self.forms["output"].load(cfg.output)
        for m, v in self.method_vars.items():
            v.set(m in cfg.speed.methods)
        self.checks_text.delete("1.0", "end")
        self.checks_text.insert("1.0", json.dumps(cfg.validation.checks, indent=1, ensure_ascii=False))
        self._refresh_trees()
        self._loading = False
        self._schedule_preview()
        self._show_assumptions()

    def _collect(self) -> SimulationConfig:
        cfg = self.cfg
        cfg.name = self.name_var.get().strip() or "simulacion"
        cfg.description = self.desc_text.get("1.0", "end").strip()
        self.forms["geometry"].store(cfg.geometry)
        self.forms["excitation"].store(cfg.excitation)
        self.forms["acquisition"].store(cfg.acquisition)
        self.forms["oct"].store(cfg.oct)
        self.forms["fdtd"].store(cfg.fdtd)
        self.forms["processing"].store(cfg.processing)
        self.forms["speed"].store(cfg.speed)
        cfg.speed.methods = tuple(m for m, v in self.method_vars.items() if v.get())
        self.forms["validation"].store(cfg.validation)
        self.forms["output"].store(cfg.output)
        try:
            cfg.validation.checks = json.loads(self.checks_text.get("1.0", "end") or "[]")
        except json.JSONDecodeError as exc:
            raise ValueError(f"JSON de comprobaciones inválido: {exc}") from exc
        return cfg

    def _refresh_trees(self) -> None:
        self.layer_tree.delete(*self.layer_tree.get_children())
        for i, layer in enumerate(self.cfg.geometry.layers):
            m = layer.material
            self.layer_tree.insert("", "end", iid=str(i), values=(
                m.name, f"{layer.thickness_mm:g}" if layer.thickness_mm > 0 else "hasta el fondo",
                "fluido" if m.is_fluid else f"{m.E_kPa:g}", f"{m.eta_Pa_s:g}", f"{m.n:g}"))
        self.inc_tree.delete(*self.inc_tree.get_children())
        for i, inc in enumerate(self.cfg.geometry.inclusions):
            m = inc.material
            self.inc_tree.insert("", "end", iid=str(i), values=(
                inc.shape, ", ".join(f"{v:g}" for v in inc.center_mm), ", ".join(f"{v:g}" for v in inc.size_mm),
                f"{m.E_kPa:g}", f"{m.n:g}"))

    # ------------------------------------------------------------------ capas / inclusiones
    def _selected(self, tree: ttk.Treeview) -> int | None:
        sel = tree.selection()
        return int(sel[0]) if sel else None

    def _add_layer(self) -> None:
        layer = Layer(Material(name=f"Capa {len(self.cfg.geometry.layers) + 1}"), 0.5)
        th = _LayerThickness(layer)
        d = MaterialDialog(self, "Nueva capa", layer.material, [("thickness_mm", "Espesor (0 = hasta el fondo)", "mm", "float")], th)
        if d.result:
            layer.thickness_mm = th.thickness_mm
            self.cfg.geometry.layers.append(layer)
            self._refresh_trees()
            self._schedule_preview()

    def _edit_layer(self) -> None:
        i = self._selected(self.layer_tree)
        if i is None:
            return
        layer = self.cfg.geometry.layers[i]
        th = _LayerThickness(layer)
        d = MaterialDialog(self, "Editar capa", layer.material, [("thickness_mm", "Espesor (0 = hasta el fondo)", "mm", "float")], th)
        if d.result:
            layer.thickness_mm = th.thickness_mm
            self._refresh_trees()
            self._schedule_preview()

    def _del_layer(self) -> None:
        i = self._selected(self.layer_tree)
        if i is not None and len(self.cfg.geometry.layers) > 1:
            del self.cfg.geometry.layers[i]
            self._refresh_trees()
            self._schedule_preview()

    def _move_layer(self, d: int) -> None:
        i = self._selected(self.layer_tree)
        L = self.cfg.geometry.layers
        if i is None or not 0 <= i + d < len(L):
            return
        L[i], L[i + d] = L[i + d], L[i]
        self._refresh_trees()
        self.layer_tree.selection_set(str(i + d))
        self._schedule_preview()

    def _add_inclusion(self) -> None:
        inc = Inclusion(Material(name=f"Inclusión {len(self.cfg.geometry.inclusions) + 1}", E_kPa=30.0,
                                 color="#08519c"))
        shp = _InclusionShape(inc)
        d = MaterialDialog(self, "Nueva inclusión", inc.material, INCLUSION_SHAPE_FIELDS, shp)
        if d.result:
            shp.apply(inc)
            self.cfg.geometry.inclusions.append(inc)
            self._refresh_trees()
            self._schedule_preview()

    def _edit_inclusion(self) -> None:
        i = self._selected(self.inc_tree)
        if i is None:
            return
        inc = self.cfg.geometry.inclusions[i]
        shp = _InclusionShape(inc)
        d = MaterialDialog(self, "Editar inclusión", inc.material, INCLUSION_SHAPE_FIELDS, shp)
        if d.result:
            shp.apply(inc)
            self._refresh_trees()
            self._schedule_preview()

    def _del_inclusion(self) -> None:
        i = self._selected(self.inc_tree)
        if i is not None:
            del self.cfg.geometry.inclusions[i]
            self._refresh_trees()
            self._schedule_preview()

    # ------------------------------------------------------------------ vista previa
    def _schedule_preview(self) -> None:
        if getattr(self, "_loading", False):
            return
        if self._preview_job:
            self.after_cancel(self._preview_job)
        self._preview_job = self.after(500, self._preview)

    def _preview(self) -> None:
        self._preview_job = None
        try:
            cfg = self._collect()
        except ValueError as exc:
            self.status.configure(text=str(exc))
            return
        errs = cfg.geometry.validate() + cfg.excitation.validate() + cfg.acquisition.validate()
        try:
            fig, canvas = self.figs["geometria"]
            figures.draw_geometry(fig, cfg)
            canvas.draw_idle()
            fig, canvas = self.figs["teoria"]
            figures.draw_theory(fig, cfg)
            canvas.draw_idle()
        except Exception as exc:  # noqa: BLE001 - vista previa tolerante
            errs.append(f"Vista previa: {exc}")
        if cfg.geometry.layers:
            self.load_label.configure(text=describe_load(cfg.excitation, cfg.geometry.layers[0].material))
        try:
            plan = build_plan(cfg.acquisition)
            i = plan.info
            self.timing_label.configure(text=(
                f"Línea efectiva {i['frecuencia_linea_efectiva_hz'] / 1e3:.3f} kHz ({i['periodo_linea_us']:.1f} µs); "
                f"segmento {i['periodo_segmento_ms']:.3f} ms ({i['ticks_segmento']} ticks, hold {i['hold_oce']}); "
                f"{i['segmentos']} segmentos, {i['a_lines_totales']:,} A-lines, adquisición de "
                f"{i['duracion_adquisicion_s']:.2f} s. Ventana MB por posición: "
                f"{cfg.acquisition.m_reps * cfg.acquisition.line_period_s * 1e3:.2f} ms."))
        except Exception as exc:  # noqa: BLE001
            self.timing_label.configure(text=f"Plan inválido: {exc}")
        self.status.configure(text="; ".join(errs) if errs else "Configuración válida.")
        self._show_assumptions()

    def _show_assumptions(self) -> None:
        try:
            cfg = self.cfg
            txt = ["SUPUESTOS EXPLÍCITOS DE ESTA CONFIGURACIÓN", ""]
            txt += [f"• {a}" for a in explicit_assumptions(cfg)]
            if cfg.sources:
                txt += ["", "FUENTES DE LOS PARÁMETROS DEL EJEMPLO", ""]
                txt += [f"[{k}] {references.REFERENCES.get(k, k)}" for k in cfg.sources]
            txt += ["", "BIBLIOGRAFÍA COMPLETA (cada ecuación del código cita una de estas claves)", ""]
            txt += [f"[{k}] {v}" for k, v in sorted(references.REFERENCES.items())]
            self.assump_text.delete("1.0", "end")
            self.assump_text.insert("1.0", "\n".join(txt))
        except Exception:  # noqa: BLE001
            pass

    # ------------------------------------------------------------------ acciones
    def _load_preset(self) -> None:
        self._load_config(PRESETS[self.preset_var.get()]())
        self._log(f"Ejemplo cargado: {self.preset_var.get()}")

    def _open_json(self) -> None:
        path = filedialog.askopenfilename(filetypes=[("Configuración JSON", "*.json")])
        if path:
            try:
                self._load_config(SimulationConfig.load_json(path))
                self._log(f"Configuración cargada: {path}")
            except Exception as exc:  # noqa: BLE001
                messagebox.showerror("Error", f"No se pudo leer {path}:\n{exc}")

    def _save_json(self) -> None:
        try:
            cfg = self._collect()
        except ValueError as exc:
            messagebox.showerror("Valor inválido", str(exc))
            return
        path = filedialog.asksaveasfilename(defaultextension=".json", initialfile=f"{cfg.name}.json",
                                            filetypes=[("Configuración JSON", "*.json")])
        if path:
            cfg.save_json(path)
            self._log(f"Configuración guardada: {path}")

    def _open_results(self) -> None:
        from .pipeline import default_outdir  # noqa: PLC0415
        path = self.result.outdir if self.result is not None else default_outdir(self.cfg)
        path = Path(path)
        path.mkdir(parents=True, exist_ok=True)
        os.startfile(path) if hasattr(os, "startfile") else None  # type: ignore[attr-defined]

    def _estimate(self) -> None:
        try:
            cfg = self._collect()
        except ValueError as exc:
            messagebox.showerror("Valor inválido", str(exc))
            return
        errs = cfg.validate()
        if errs:
            messagebox.showerror("Configuración inválida", "\n".join(errs))
            return
        self.estimate_label.configure(text="Estimando (construyendo la malla)...")

        def work() -> None:
            try:
                from .acquisition import scan_extent_mm  # noqa: PLC0415
                from .fdtd import FDTDSolver  # noqa: PLC0415
                from .pipeline import _transient_duration  # noqa: PLC0415
                box = list(scan_extent_mm(cfg.acquisition))
                s = FDTDSolver(cfg.geometry, cfg.excitation, cfg.fdtd, tuple(box))
                d = s.describe()
                if cfg.excitation.regime == "transitorio":
                    T = _transient_duration(cfg)
                    steps = T / (cfg.acquisition.line_period_s / max(1, int(np.ceil(cfg.acquisition.line_period_s / s.dt_max))))
                else:
                    steps = cfg.fdtd.harmonic_min_periods * 1.5 / cfg.excitation.harmonic_hz / s.dt_max
                secs = s.grid.cells * steps / (1.0e9 if s.backend.is_gpu else 2.0e7)
                txt = (f"{d['backend']}\nCelda {d['celda_mm'] * 1e3:.1f} µm ({', '.join(f'{k}={v:.3g}' for k, v in d['restricciones_celda'].items())})\n"
                       f"Malla {d['malla']} = {d['celdas_M']:.2f} M celdas; dt máx {d['dt_max_us']:.3f} µs; "
                       f"~{steps:,.0f} pasos\nMemoria FDTD ~{d['memoria_GB']:.2f} GB; tiempo FDTD estimado ~{secs:.0f} s\n"
                       f"{d['fuentes']}\nRegistro {d['registro']}; c_fluido_sim = {d['c_fluido_sim']:.1f} m/s"
                       + ("\nADVERTENCIAS: " + " | ".join(s.warnings) if s.warnings else ""))
            except Exception as exc:  # noqa: BLE001
                txt = f"No se pudo estimar: {exc}"
            self.queue.put(("estimate", txt))

        threading.Thread(target=work, daemon=True).start()

    def _run(self) -> None:
        if self.worker is not None and self.worker.is_alive():
            return
        try:
            cfg = self._collect()
        except ValueError as exc:
            messagebox.showerror("Valor inválido", str(exc))
            return
        errs = cfg.validate()
        if errs:
            messagebox.showerror("Configuración inválida", "\n".join(errs))
            return
        self.cancel.clear()
        self.run_btn.configure(state="disabled")
        self.stop_btn.configure(state="normal")
        self._log(f"=== Simulación '{cfg.name}' ===")
        use_cache = self.cache_var.get()

        def work() -> None:
            from .pipeline import run_simulation  # noqa: PLC0415
            try:
                res = run_simulation(SimulationConfig.from_dict(cfg.to_dict()),
                                     lambda f, m: self.queue.put(("progress", (f, m))),
                                     self.cancel, use_cache=use_cache)
                self.queue.put(("done", res))
            except SimulationCancelled as exc:
                self.queue.put(("error", str(exc)))
            except Exception:  # noqa: BLE001
                self.queue.put(("error", traceback.format_exc()))

        self.worker = threading.Thread(target=work, daemon=True)
        self.worker.start()

    def _stop(self) -> None:
        self.cancel.set()
        self.status.configure(text="Deteniendo...")

    def _poll(self) -> None:
        try:
            while True:
                kind, payload = self.queue.get_nowait()
                if kind == "progress":
                    f, m = payload
                    self.progress["value"] = int(f * 1000)
                    self.status.configure(text=m)
                    if "Listo" in m or f in (0.85, 0.9, 0.94, 0.96) or "Campo FDTD" in m:
                        self._log(m)
                elif kind == "estimate":
                    self.estimate_label.configure(text=payload)
                    self._log(payload)
                elif kind == "done":
                    self._finished(payload)
                elif kind == "error":
                    self.run_btn.configure(state="normal")
                    self.stop_btn.configure(state="disabled")
                    self.status.configure(text="Error o cancelación (ver Registro).")
                    self._log(payload)
                    if "cancelada" not in payload:
                        messagebox.showerror("Error en la simulación", payload[-1500:])
        except queue.Empty:
            pass
        self.after(120, self._poll)

    def _log(self, msg: str) -> None:
        self.log_text.insert("end", msg + "\n")
        self.log_text.see("end")

    # ------------------------------------------------------------------ resultados
    def _finished(self, res: Any) -> None:
        self.result = res
        self.run_btn.configure(state="normal")
        self.stop_btn.configure(state="disabled")
        v = res.validation
        self._log(f"Resultados: {res.outdir}")
        self._log(f"Validación ({v.get('modelo')}): {'APROBADA' if v.get('aprobado') else 'CON FALLAS'}")
        for c in v.get("checks", []):
            self._log(f"  [{'OK' if c.get('ok') else 'X '}] {c['nombre']}: {c.get('valor', float('nan')):.3f} vs "
                      f"{c.get('esperado', float('nan')):.3f} ({c.get('error_pct', float('nan')):+.1f} %, tol "
                      f"{c.get('tol_pct', float('nan')):.0f} %)")
        for w in res.warnings:
            self._log(f"  ADVERTENCIA: {w}")
        planes = sorted({m.plane for m in res.speed_maps})
        self.speed_combo.configure(values=planes or ["enface"])
        if planes:
            self.speed_plane.set(planes[0])
        self.enface_combo.configure(values=["superficie"] + [f"{d:g} mm" for d in res.enface_depths])
        self.enface_plane.set("superficie")
        for key in ("bmode", "enface"):
            self._setup_player(key)
        for key in ("velocidad", "kf", "validacion"):
            self._draw_result_tab(key)
        self.status.configure(text=f"Listo: {res.outdir}")
        self.rnb.select(2 if res.bmode else 3)

    def _draw_result_tab(self, key: str) -> None:
        res = self.result
        if res is None:
            return
        fig, canvas = self.figs[key]
        if key == "velocidad":
            figures.draw_speed_maps(fig, res, self.speed_plane.get())
            if self.modulus_var.get():
                self._overlay_modulus(fig, res)
        elif key == "kf":
            figures.draw_kf(fig, res)
        elif key == "validacion":
            fig.clear()
            sub1 = fig.add_subfigure(fig.add_gridspec(2, 1)[0]) if hasattr(fig, "add_subfigure") else fig
            figures.draw_validation(sub1, res)
            if res.truth_check is not None and hasattr(fig, "add_subfigure"):
                sub2 = fig.add_subfigure(fig.add_gridspec(2, 1)[1])
                figures.draw_truth(sub2, res)
        canvas.draw_idle()

    def _overlay_modulus(self, fig: Figure, res: Any) -> None:
        from .speed import youngs_modulus_kpa  # noqa: PLC0415
        maps = [m for m in res.speed_maps if m.plane == self.speed_plane.get()]
        rho = res.cfg.geometry.layers[0].material.rho
        rayleigh = self.speed_plane.get() == "enface" or any(m.method == "kf" for m in maps)
        for ax, m in zip(fig.axes, maps):
            for im in ax.images:
                E = youngs_modulus_kpa(m.c, rho, rayleigh=rayleigh)
                im.set_data(E)
                im.set_clim(*np.nanpercentile(E, [2, 98]) if np.isfinite(E).any() else (0, 1))
            ax.set_title(ax.get_title().replace("m/s", "") + " -> E (kPa)", fontsize=8)
        fig.suptitle("E estimado = 3 rho c_s^2 [Singh2022, Ecs. (4)-(5)]"
                     + (", c_s = c_R/0.955 [Singh2022, Ec. (12)]" if rayleigh else ""), fontsize=9)

    def _setup_player(self, key: str) -> None:
        res = self.result
        fig, canvas = self.figs[key]
        fig.clear()
        ax = fig.add_subplot(1, 1, 1)
        if key == "bmode":
            if not res or not res.bmode:
                ax.text(0.5, 0.5, "Sin B-mode", ha="center")
                canvas.draw_idle()
                return
            bm = res.bmode[0]
            I = bm["structural_db"]
            lo, hi = np.percentile(I, [5, 99.5])
            ax.imshow(I, cmap="gray", vmin=lo, vmax=hi, aspect="auto",
                      extent=[bm["x_mm"][0], bm["x_mm"][-1], bm["struct_z_mm"][-1], bm["struct_z_mm"][0]])
            data = bm["velocity"]
            ext = [bm["x_mm"][0], bm["x_mm"][-1], bm["z_mm"][-1], bm["z_mm"][0]]
            times = bm["times_ms"]
            ax.set_ylim(bm["z_mm"][-1], bm["struct_z_mm"][0])
            ax.set_xlabel("x (mm)")
            ax.set_ylabel("z = OPL/n (mm)")
            title = f"B-mode OCE (B{bm['b'] + 1}), v_z sobre estructura"
        else:
            sel = self.enface_plane.get() if hasattr(self, "enface_plane") else "superficie"
            e = None
            if res is not None:
                e = res.enface if sel == "superficie" else next(
                    (v for d, v in res.enface_depths.items() if f"{d:g} mm" == sel), None)
            if e is None:
                ax.text(0.5, 0.5, "Sin en-face (el patrón no cubre un área)", ha="center")
                canvas.draw_idle()
                return
            data = e["frames"]
            ext = [e["x_mm"][0], e["x_mm"][-1], e["y_mm"][-1], e["y_mm"][0]]
            times = e["times_ms"]
            ax.set_xlabel("x (mm)")
            ax.set_ylabel("y (mm)")
            title = f"En-face ({sel})"
        lim = robust_limit(data) * 1e3
        im = ax.imshow(data[..., 0] * 1e3, cmap=WAVE_CMAP, vmin=-lim, vmax=lim, extent=ext,
                       aspect="auto" if key == "bmode" else "equal", alpha=0.9)
        fig.colorbar(im, ax=ax, fraction=0.04).set_label("v_z (mm/s), + hacia +z")
        ttl = ax.set_title(title)
        n = data.shape[-1]
        slider = getattr(self, f"{key}_slider")
        slider.configure(to=max(1, n - 1))
        self.players[key] = {"im": im, "data": data, "times": times, "title": title, "ttl": ttl, "n": n,
                             "i": 0, "playing": False}
        slider.set(0)
        self._show_frame(key, 0)

    def _show_frame(self, key: str, i: int) -> None:
        pl = self.players.get(key)
        if not pl:
            return
        i = int(np.clip(i, 0, pl["n"] - 1))
        pl["i"] = i
        pl["im"].set_data(pl["data"][..., i] * 1e3)
        pl["ttl"].set_text(f"{pl['title']}  t = {pl['times'][i]:.2f} ms")
        if not pl.get("drawing"):
            self.figs[key][1].draw_idle()

    def _toggle_play(self, key: str) -> None:
        pl = self.players.get(key)
        if pl:
            pl["playing"] = not pl["playing"]
            if pl["playing"]:
                self._play_tick(key)

    def _play_tick(self, key: str) -> None:
        """Avanza un cuadro, lo dibuja una vez y programa el siguiente con una pausa
        mayor que el tiempo de render (la GUI sigue respondiendo)."""
        import time  # noqa: PLC0415
        pl = self.players.get(key)
        if not pl or not pl.get("playing"):
            return
        t0 = time.perf_counter()
        pl["i"] = (pl["i"] + 1) % pl["n"]
        pl["drawing"] = True
        getattr(self, f"{key}_slider").set(pl["i"])
        self._show_frame(key, pl["i"])
        self.figs[key][1].draw()
        pl["drawing"] = False
        render_ms = (time.perf_counter() - t0) * 1e3
        self.after(int(max(50.0, 1.5 * render_ms)), lambda: self._play_tick(key))


def main() -> None:
    app = SimulatorApp()
    app.mainloop()


if __name__ == "__main__":
    main()
