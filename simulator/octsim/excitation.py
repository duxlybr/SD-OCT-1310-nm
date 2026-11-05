"""Excitación mecánica: fuerza de radiación acústica (ARF) y anillo de contactos.

Modelos (todos empujan en +z, hacia dentro de la muestra):

1. ``arf_contacto`` - ultrasonido focalizado acoplado al tejido. Fuerza de
   volumen [Palmeri2017, Ec. (1)]:
        F(x, y, z, t) = 2 alpha I(x, y, z, t) / c
   con alpha = atenuación de amplitud (Np/m) a la portadora (se asume absorción
   = atenuación, como en [Palmeri2017]) y c la velocidad del sonido del tejido.
   Intensidad de onda plana a partir de la presión pico en el foco p0
   [Kinsler2000]:
        I0 = p0^2 / (2 rho c)
   Distribución: I = I0 S(x, y) G(z) A(z) m(t)^2, donde S es la forma lateral
   del foco (pico 1), G(z) una gaussiana de profundidad de foco (FWHM = DOF) y
   A(z) = exp(-2 int_{z_f}^{z} alpha dz') la atenuación de intensidad
   normalizada en el foco (supuestos explícitos del simulador).

2. ``arf_sin_contacto`` - micro-tapping acústico acoplado por aire. Presión de
   radiación en la interfaz aire/tejido [Ambrozinski2016, Métodos]:
        P = (1 + R) I / c_aire,   R ~ 1  =>  P ~ 2 I / c_aire
   donde R = ((Z2 - Z1)/(Z2 + Z1))^2 es el coeficiente de reflexión en
   intensidad [Kinsler2000] e I0 = p0^2 / (2 rho_aire c_aire) [Kinsler2000].
   Se aplica como fuerza de volumen equivalente P/h en la primera celda sólida.

3. ``anillo_contactos`` - N puntas que tocan la superficie y vibran en
   armónico, como el anillo impreso en 3D de [Zvietcovich2019, Métodos:
   "eight vertical equidistant and circular-distributed rods", 2 kHz, misma
   fase]. La presión en MPa es la amplitud del esfuerzo normal de contacto.

Modulación temporal: el CH1 (portadora 954.9 kHz) está modulado en AM 100 %
por el CH2 [repo:dg4162]. Si m(t) en [0, 1] es la envolvente normalizada del
CH2, la presión acústica es p0 m(t) y la ARF, proporcional a la intensidad
(~p^2) [Palmeri2017, Ec. (1)], sigue m(t)^2. Se suaviza con un tiempo de
subida finito (ancho de banda del transductor; supuesto explícito).

Régimen armónico (reverberante con focos ARF): m_i(t) = (1 + sin(w t + phi_i))/2,
de modo que la fuerza contiene DC, f y 2f; el campo estacionario se calcula
para los armónicos f y 2f (la componente DC estática no se propaga y no afecta
la fase diferencial).
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, fields
from math import log, pi, sqrt
from typing import Any

import numpy as np

from .materials import AIR, Material

MODES = ("arf_contacto", "arf_sin_contacto", "anillo_contactos")
REGIMES = ("transitorio", "armonico")
SHAPES = ("circulo", "elipse", "rectangulo", "linea", "anillo", "punto")
# Formas de onda del CH2 disponibles en el DG4162 [repo:dg4162]
CH2_WAVEFORMS = (
    "Pulso", "Gaussiana", "Pulso gaussiano", "Cuadrada", "Senoidal", "Semiseno",
    "Haversine", "Hanning", "Blackman", "Triangular", "Trapecio", "Rampa",
    "Rampa negativa", "Exp. creciente", "Exp. decreciente", "Sinc", "Lorentz",
)
SOURCE_LAYOUTS = ("anillo", "aleatoria")

FWHM_TO_SIGMA = 1.0 / (2.0 * sqrt(2.0 * log(2.0)))


@dataclass
class ExcitationConfig:
    mode: str = "arf_contacto"
    regime: str = "transitorio"
    pressure_MPa: float = 1.0          # presión acústica pico (ARF) o esfuerzo de contacto
    carrier_hz: float = 954.9e3        # CH1 [repo:dg4162]
    # forma lateral del área de excitación
    shape: str = "circulo"
    center_x_mm: float = 0.0
    center_y_mm: float = 0.0
    size_a_mm: float = 0.4             # FWHM / ancho / radio del anillo según la forma
    size_b_mm: float = 0.4             # segundo eje (elipse, rectángulo, longitud de línea)
    angle_deg: float = 0.0             # orientación del eje a respecto de x
    # foco en profundidad (solo ARF con contacto)
    focal_depth_mm: float = 0.5
    dof_mm: float = 3.0                # FWHM axial del foco
    # temporización CH2 (régimen transitorio)
    ch2_waveform: str = "Pulso"
    ch2_freq_hz: float = 1000.0
    ch2_duty: float = 0.5
    ch2_cycles: int = 1
    ch2_delay_ms: float = 2.0          # retardo del burst tras PFI13 [repo:dg4162]
    rise_time_us: float = 50.0         # subida finita del transductor (supuesto)
    # régimen armónico / reverberante
    harmonic_hz: float = 2000.0
    n_sources: int = 8
    source_layout: str = "anillo"
    ring_radius_mm: float = 3.0
    tip_radius_mm: float = 0.25
    random_phase: bool = False
    seed: int = 1
    ramp_periods: float = 2.0          # rampa de encendido suave (periodos)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "ExcitationConfig":
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in d.items() if k in known})

    def validate(self) -> list[str]:
        e: list[str] = []
        if self.mode not in MODES:
            e.append(f"Modo de excitación desconocido: {self.mode}")
        if self.regime not in REGIMES:
            e.append(f"Régimen desconocido: {self.regime}")
        if self.mode == "anillo_contactos" and self.regime != "armonico":
            e.append("El anillo de contactos se simula en régimen armónico (reverberante).")
        if self.shape not in SHAPES:
            e.append(f"Forma de excitación desconocida: {self.shape}")
        if self.ch2_waveform not in CH2_WAVEFORMS:
            e.append(f"Forma de onda CH2 desconocida: {self.ch2_waveform}")
        if self.pressure_MPa <= 0:
            e.append("La presión debe ser > 0 MPa.")
        if self.mode == "arf_sin_contacto" and self.pressure_MPa > 0.05:
            e.append("ARF sin contacto: presiones en aire > 0.05 MPa no son físicas "
                     "(AµT usa ~7 kPa [Ambrozinski2016]).")
        if self.regime == "transitorio" and (self.ch2_freq_hz <= 0 or self.ch2_cycles < 1):
            e.append("La frecuencia y los ciclos del CH2 deben ser positivos.")
        if self.regime == "armonico" and (self.harmonic_hz <= 0 or self.n_sources < 1):
            e.append("El régimen armónico requiere frecuencia > 0 y al menos una fuente.")
        if not 0 < self.ch2_duty <= 1:
            e.append("El ciclo útil del CH2 debe estar en (0, 1].")
        return e


# --------------------------------------------------------------------------------------
# Envolvente temporal del CH2
# --------------------------------------------------------------------------------------
def ch2_unit_cycle(name: str, phase: np.ndarray, duty: float) -> np.ndarray:
    """Forma normalizada m en [0, 1] de un ciclo del CH2, phase en [0, 1).

    Son aproximaciones de las formas estándar del generador (supuesto): la
    salida baja del CH2 corresponde a portadora nula (AM 100 %).
    """
    p = np.asarray(phase, dtype=float)
    if name == "Pulso":
        return (p < duty).astype(float)
    if name == "Cuadrada":
        return (p < 0.5).astype(float)
    if name == "Gaussiana" or name == "Pulso gaussiano":
        return np.exp(-0.5 * ((p - 0.5) / 0.12) ** 2)
    if name == "Senoidal":
        return 0.5 * (1 - np.cos(2 * pi * p))
    if name == "Semiseno":
        return np.sin(pi * p)
    if name == "Haversine" or name == "Hanning":
        return 0.5 * (1 - np.cos(2 * pi * p))
    if name == "Blackman":
        return 0.42 - 0.5 * np.cos(2 * pi * p) + 0.08 * np.cos(4 * pi * p)
    if name == "Triangular":
        return 1 - np.abs(2 * p - 1)
    if name == "Trapecio":
        return np.clip(np.minimum(4 * p, 4 * (1 - p)), 0, 1)
    if name == "Rampa":
        return p
    if name == "Rampa negativa":
        return 1 - p
    if name == "Exp. creciente":
        return np.expm1(4 * p) / np.expm1(4)
    if name == "Exp. decreciente":
        return np.exp(-4 * p)
    if name == "Sinc":
        x = 8 * (p - 0.5)
        return np.clip(np.sinc(x), 0, 1)
    if name == "Lorentz":
        return 1 / (1 + ((p - 0.5) / 0.1) ** 2)
    raise ValueError(f"Forma de onda CH2 desconocida: {name}")


def _smooth(signal: np.ndarray, dt: float, rise_s: float) -> np.ndarray:
    """Convolución con una ventana de Hann de duración rise_s (área unitaria)."""
    n = int(round(rise_s / dt))
    if n < 3:
        return signal
    win = np.hanning(n)
    win /= win.sum()
    return np.convolve(signal, win, mode="full")[: signal.size]


def transient_force_envelope(cfg: ExcitationConfig, t: np.ndarray) -> np.ndarray:
    """m(t)^2 para el régimen transitorio; t = 0 es el inicio del burst del CH2.

    El burst dura ``ch2_cycles`` periodos de 1/ch2_freq_hz.
    """
    T = 1.0 / cfg.ch2_freq_hz
    t = np.asarray(t, dtype=float)
    active = (t >= 0) & (t < cfg.ch2_cycles * T)
    m = np.zeros_like(t)
    m[active] = ch2_unit_cycle(cfg.ch2_waveform, (t[active] / T) % 1.0, cfg.ch2_duty)
    dt = float(t[1] - t[0]) if t.size > 1 else 1e-6
    m = _smooth(m, dt, cfg.rise_time_us * 1e-6)
    if cfg.mode == "anillo_contactos":
        return m          # contacto mecánico: esfuerzo proporcional a la señal
    return m * m          # ARF ~ intensidad ~ p^2 [Palmeri2017, Ec. (1)]


def burst_duration_s(cfg: ExcitationConfig) -> float:
    return cfg.ch2_cycles / cfg.ch2_freq_hz + cfg.rise_time_us * 1e-6


def harmonic_group_signals(cfg: ExcitationConfig, t: np.ndarray, phases: np.ndarray) -> np.ndarray:
    """Señales por grupo de fuentes en régimen armónico, forma [G, nt].

    ARF:  ((1 + sin(w t + phi_g)) / 2)^2  (AM con ARF ~ p^2)
    anillo de contactos: sin(w t + phi_g) (actuador piezoeléctrico bipolar)
    Ambas se multiplican por una rampa de encendido de ``ramp_periods``.
    """
    w = 2 * pi * cfg.harmonic_hz
    t = np.asarray(t, dtype=float)
    ramp_T = cfg.ramp_periods / cfg.harmonic_hz
    ramp = np.ones_like(t) if ramp_T <= 0 else 0.5 * (1 - np.cos(pi * np.clip(t / ramp_T, 0, 1)))
    out = np.empty((phases.size, t.size))
    for g, phi in enumerate(phases):
        s = np.sin(w * t + phi)
        out[g] = ramp * (s if cfg.mode == "anillo_contactos" else (0.5 * (1 + s)) ** 2)
    return out


def source_phases(cfg: ExcitationConfig) -> np.ndarray:
    if cfg.regime != "armonico":
        return np.zeros(1)
    n = max(1, cfg.n_sources)
    if cfg.random_phase:
        rng = np.random.default_rng(cfg.seed)
        return rng.uniform(0, 2 * pi, n)
    return np.zeros(n)


def source_centers_mm(cfg: ExcitationConfig) -> np.ndarray:
    """Centros (x, y) en mm de cada fuente/grupo."""
    if cfg.regime != "armonico":
        return np.array([[cfg.center_x_mm, cfg.center_y_mm]])
    n = max(1, cfg.n_sources)
    if cfg.source_layout == "anillo":
        ang = 2 * pi * np.arange(n) / n
        return np.column_stack((cfg.center_x_mm + cfg.ring_radius_mm * np.cos(ang),
                                cfg.center_y_mm + cfg.ring_radius_mm * np.sin(ang)))
    rng = np.random.default_rng(cfg.seed + 1000)
    r = cfg.ring_radius_mm * np.sqrt(rng.uniform(0, 1, n))
    a = rng.uniform(0, 2 * pi, n)
    return np.column_stack((cfg.center_x_mm + r * np.cos(a), cfg.center_y_mm + r * np.sin(a)))


# --------------------------------------------------------------------------------------
# Forma lateral S(x, y)
# --------------------------------------------------------------------------------------
def lateral_shape(cfg: ExcitationConfig, x_mm: np.ndarray, y_mm: np.ndarray,
                  cx: float, cy: float, h_mm: float) -> np.ndarray:
    """Perfil lateral de intensidad normalizado (pico 1).

    circulo/elipse: gaussianas con FWHM a (y b) - aproximación de un foco
    gaussiano (supuesto); rectangulo/linea: super-gaussiana de orden 6 (bordes
    suaves para evitar escalones en la malla); anillo: gaussiana radial de radio
    medio a y FWHM b; punto: gaussiana con FWHM = 2 celdas.
    """
    th = np.deg2rad(cfg.angle_deg)
    dx, dy = x_mm - cx, y_mm - cy
    u = dx * np.cos(th) + dy * np.sin(th)
    v = -dx * np.sin(th) + dy * np.cos(th)
    a, b = max(cfg.size_a_mm, 1e-6), max(cfg.size_b_mm, 1e-6)
    shape = cfg.shape
    if cfg.mode == "anillo_contactos":
        # cada punta: disco gaussiano de FWHM = 2 * radio de la punta (supuesto)
        fw = 2 * max(cfg.tip_radius_mm, h_mm)
        return np.exp(-4 * log(2) * (dx * dx + dy * dy) / fw**2)
    if shape == "circulo":
        return np.exp(-4 * log(2) * (dx * dx + dy * dy) / a**2)
    if shape == "elipse":
        return np.exp(-4 * log(2) * ((u / a) ** 2 + (v / b) ** 2))
    if shape == "rectangulo":
        return np.exp(-((2 * u / a) ** 6)) * np.exp(-((2 * v / b) ** 6))
    if shape == "linea":
        # a = ancho (FWHM gaussiano), b = longitud (super-gaussiana)
        return np.exp(-4 * log(2) * (u / a) ** 2) * np.exp(-((2 * v / b) ** 6))
    if shape == "anillo":
        r = np.sqrt(dx * dx + dy * dy)
        return np.exp(-4 * log(2) * ((r - a) / b) ** 2)
    if shape == "punto":
        fw = 2 * h_mm
        return np.exp(-4 * log(2) * (dx * dx + dy * dy) / fw**2)
    raise ValueError(f"Forma desconocida: {shape}")


def characteristic_width_mm(cfg: ExcitationConfig, h_mm: float) -> float:
    """FWHM más pequeño de la distribución (para la regla de >= 10 muestras/FWHM
    de [Palmeri2017, sec. "Mesh resolution"])."""
    if cfg.mode == "anillo_contactos":
        return 2 * max(cfg.tip_radius_mm, h_mm)
    if cfg.shape in ("circulo",):
        return cfg.size_a_mm
    if cfg.shape in ("elipse", "rectangulo"):
        return min(cfg.size_a_mm, cfg.size_b_mm)
    if cfg.shape == "linea":
        return cfg.size_a_mm
    if cfg.shape == "anillo":
        return cfg.size_b_mm
    return 2 * h_mm


# --------------------------------------------------------------------------------------
# Magnitudes físicas
# --------------------------------------------------------------------------------------
def acoustic_intensity(p0_pa: float, rho: float, c: float) -> float:
    """Intensidad de onda plana I = p0^2 / (2 rho c) [Kinsler2000]."""
    return p0_pa * p0_pa / (2.0 * rho * c)


def intensity_reflection(z1: float, z2: float) -> float:
    """Coeficiente de reflexión en intensidad R = ((Z2 - Z1)/(Z2 + Z1))^2 [Kinsler2000]."""
    return ((z2 - z1) / (z2 + z1)) ** 2


def radiation_pressure_air(p0_pa: float, tissue: Material) -> float:
    """Presión de radiación por reflexión en aire/tejido [Ambrozinski2016]:
    P = (1 + R) I / c_aire, con I = p0^2/(2 rho_aire c_aire) [Kinsler2000]."""
    I = acoustic_intensity(p0_pa, AIR.rho, AIR.c)
    R = intensity_reflection(AIR.rho * AIR.c, tissue.rho * tissue.c_acoustic)
    return (1.0 + R) * I / AIR.c


def contact_body_force_peak(p0_pa: float, tissue: Material, carrier_hz: float) -> float:
    """Fuerza de volumen pico F = 2 alpha I / c [Palmeri2017, Ec. (1)], N/m^3."""
    I = acoustic_intensity(p0_pa, tissue.rho, tissue.c_acoustic)
    return 2.0 * tissue.alpha_np_per_m(carrier_hz) * I / tissue.c_acoustic


def describe_load(cfg: ExcitationConfig, top: Material) -> str:
    p0 = cfg.pressure_MPa * 1e6
    if cfg.mode == "arf_contacto":
        I = acoustic_intensity(p0, top.rho, top.c_acoustic)
        F = contact_body_force_peak(p0, top, cfg.carrier_hz)
        return (f"ARF con contacto: p0 = {cfg.pressure_MPa:g} MPa -> I0 = {I / 1e4:.3g} W/cm², "
                f"alpha = {top.alpha_np_per_m(cfg.carrier_hz):.3g} Np/m -> F0 = {F:.4g} N/m³ "
                f"[Palmeri2017 Ec.(1); Kinsler2000]")
    if cfg.mode == "arf_sin_contacto":
        P = radiation_pressure_air(p0, top)
        return (f"ARF sin contacto: p0 (aire) = {cfg.pressure_MPa * 1e3:g} kPa -> "
                f"P_rad = {P:.4g} Pa [Ambrozinski2016; Kinsler2000]")
    return (f"Anillo de {cfg.n_sources} contactos: esfuerzo de contacto {cfg.pressure_MPa * 1e3:g} kPa "
            f"a {cfg.harmonic_hz:g} Hz [Zvietcovich2019]")
