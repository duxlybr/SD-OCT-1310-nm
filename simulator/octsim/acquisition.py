"""Plan de adquisición OCT: posiciones y tiempos de cada A-line, como en el equipo real.

Replica la semántica del planificador de la GUI de adquisición [repo:octoce]:

* Modos: ``MB`` (B -> A -> M: M repeticiones en cada posición, un disparo OCE
  por posición) y ``BM`` (B -> M -> A: barridos completos repetidos M veces, un
  disparo OCE por barrido; en crosshair solo en el barrido X).
* Patrones: raster, crosshair (X+Y = un B-scan lógico), meridianos
  (theta = pi b / B, elipse X/Y) y lineal (horizontal/vertical, ida y vuelta).
* Cada segmento: ``sync_points`` muestras de transición (sin adquisición),
  luego las muestras activas. La primera A-line activa ocurre en
  t = sync / f_linea + desfase_cámara; PFI13 (disparo OCE) en
  t_primera + BFramesDelay [repo:octoce, config.optimized_scan_period_ticks].
* Período uniforme de segmento (ruta optimizada por lotes de octoce):
      ticks = max(sync + activas + hold,  activas + ceil(0.05 activas),
                  ceil(retardo_OCE * f / (1 - 0.1)))
  [repo:octoce, config.optimized_scan_period_ticks]. El hold OCE se calcula
  con ``oce_post_hold_points``.
* La frecuencia de línea efectiva se cuantiza a pasos de 0.1 us del período
  CC1 de la cámara [repo:octoce, HardwareConfig.cc1_period_us].
* La excitación del DG4162 comienza ``ch2_delay_ms`` después de PFI13
  [repo:dg4162].

Supuestos explícitos: los galvanómetros siguen la orden sin error dinámico; la
trayectoria de sincronismo no adquiere datos; el disparo y la excitación no
tienen jitter (opcional en la señal OCT).
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field, fields
from math import ceil, floor
from typing import Any

import numpy as np

MODES = ("MB", "BM")
PATTERNS = ("raster", "crosshair", "meridianos", "lineal")
ORIENTATIONS = ("horizontal", "vertical")
OCE_TRIGGER_DUTY = 0.10          # [repo:octoce] OCE_TRIGGER_DUTY_CYCLE


@dataclass
class AcquisitionConfig:
    mode: str = "MB"
    pattern: str = "raster"
    orientation: str = "horizontal"
    alines: int = 64
    bscans: int = 64
    m_reps: int = 200
    sync_points: int = 50
    x_length_mm: float = 4.0
    y_length_mm: float = 4.0
    center_x_mm: float = 0.0
    center_y_mm: float = 0.0
    raster_bidirectional: bool = False
    bframes_delay_us: float = 0.0
    line_rate_hz: float = 50_000.0
    camera_phase_offset_us: float = 0.0
    oce_pulse_width_us: float = 10.0

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "AcquisitionConfig":
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in d.items() if k in known})

    # ---------------------------------------------------------- temporización octoce
    @property
    def cc1_period_us(self) -> float:
        """Período de línea cuantizado a 0.1 us, acotado a [6.8, 106] us [repo:octoce]."""
        q = floor(1e6 / self.line_rate_hz * 10.0 + 0.5) / 10.0
        return min(106.0, max(6.8, q))

    @property
    def line_period_s(self) -> float:
        return self.cc1_period_us * 1e-6

    @property
    def sweeps(self) -> int:
        return 2 if self.pattern == "crosshair" else 1

    @property
    def active_count(self) -> int:
        return self.m_reps if self.mode == "MB" else self.alines

    def hold_points(self) -> int:
        """Muestras de hold para no truncar el pulso OCE [repo:octoce, oce_post_hold_points]."""
        Tus = self.cc1_period_us
        nominal_end = (self.sync_points + self.active_count) * Tus
        oce_end = (self.sync_points * Tus + self.camera_phase_offset_us + self.bframes_delay_us
                   + self.oce_pulse_width_us)
        return int(ceil(max(0.0, oce_end - nominal_end) / Tus))

    def segment_ticks(self) -> int:
        """Período uniforme del segmento en ticks [repo:octoce, optimized_scan_period_ticks]."""
        rate = 1e6 / self.cc1_period_us
        active = self.active_count
        camera_delay_s = self.sync_points / rate + self.camera_phase_offset_us * 1e-6
        oce_delay_s = camera_delay_s + self.bframes_delay_us * 1e-6
        ceil_tick = lambda v: ceil(v - 1e-9)  # noqa: E731
        nominal = self.sync_points + active + self.hold_points()
        rearm = max(1, ceil_tick(active * 0.05))
        ticks = max(nominal, active + rearm, ceil_tick((camera_delay_s + active / rate) * rate))
        ticks = max(ticks, ceil_tick(oce_delay_s * rate / (1.0 - OCE_TRIGGER_DUTY)))
        return int(ticks)

    @property
    def segment_period_s(self) -> float:
        return self.segment_ticks() * self.line_period_s

    @property
    def n_segments(self) -> int:
        if self.mode == "MB":
            return self.bscans * self.sweeps * self.alines
        return self.bscans * self.m_reps * self.sweeps

    @property
    def total_alines(self) -> int:
        return self.alines * self.bscans * self.m_reps * self.sweeps

    @property
    def duration_s(self) -> float:
        return self.n_segments * self.segment_period_s

    def validate(self) -> list[str]:
        e: list[str] = []
        if self.mode not in MODES:
            e.append(f"Modo desconocido: {self.mode}")
        if self.pattern not in PATTERNS:
            e.append(f"Patrón desconocido: {self.pattern}")
        if self.alines < 1 or self.bscans < 1 or self.m_reps < 1:
            e.append("A-lines, B-scans y M deben ser >= 1.")
        if self.sync_points < 0:
            e.append("Los puntos sync no pueden ser negativos.")
        if self.line_rate_hz <= 0 or self.line_rate_hz > 147_000:
            e.append("La frecuencia de línea debe estar en (0, 147] kHz (cámara GL2048R).")
        if self.x_length_mm < 0 or self.y_length_mm < 0:
            e.append("Las longitudes de barrido no pueden ser negativas.")
        if self.camera_phase_offset_us + self.bframes_delay_us < -self.sync_points * self.cc1_period_us:
            e.append("El retardo OCE adelanta PFI13 antes del inicio del segmento [repo:octoce].")
        if self.mode == "MB" and self.m_reps < 4:
            e.append("MB necesita al menos 4 repeticiones M para estimar la fase.")
        if self.total_alines > 60_000_000:
            e.append("La adquisición supera 60 millones de A-lines simuladas; reduzca el plan.")
        return e


# --------------------------------------------------------------------------------------
# Posiciones
# --------------------------------------------------------------------------------------
def sweep_positions(cfg: AcquisitionConfig, b: int) -> list[np.ndarray]:
    """Posiciones físicas (A, 2) en mm de cada barrido del B-scan b, en orden de la
    línea sin invertir [repo:octoce, ScanPlanner._line/_sweeps]."""
    u = np.linspace(-1.0, 1.0, cfg.alines) if cfg.alines > 1 else np.zeros(1)
    cx, cy = cfg.center_x_mm, cfg.center_y_mm
    if cfg.pattern == "crosshair":
        return [np.column_stack((cx + u * cfg.x_length_mm / 2, np.full_like(u, cy))),
                np.column_stack((np.full_like(u, cx), cy + u * cfg.y_length_mm / 2))]
    if cfg.pattern == "raster":
        yo = np.linspace(-cfg.y_length_mm / 2, cfg.y_length_mm / 2, cfg.bscans) if cfg.bscans > 1 else [0.0]
        line = np.column_stack((cx + u * cfg.x_length_mm / 2, np.full_like(u, cy + yo[b])))
    elif cfg.pattern == "lineal":
        if cfg.orientation == "horizontal":
            line = np.column_stack((cx + u * cfg.x_length_mm / 2, np.full_like(u, cy)))
        else:
            line = np.column_stack((np.full_like(u, cx), cy + u * cfg.y_length_mm / 2))
    else:  # meridianos
        th = np.pi * b / cfg.bscans
        line = np.column_stack((cx + u * cfg.x_length_mm / 2 * np.cos(th),
                                cy + u * cfg.y_length_mm / 2 * np.sin(th)))
    return [line]


def bscan_axis_mm(cfg: AcquisitionConfig, b: int, s: int) -> np.ndarray:
    """Coordenada lateral física a lo largo del barrido (mm).

    Líneas horizontales: x; verticales: y; meridianos: distancia con signo al centro
    del patrón a lo largo de la dirección del meridiano.
    """
    pos = sweep_positions(cfg, b)[s]
    if np.ptp(pos[:, 1]) < 1e-12:
        return pos[:, 0].copy()
    if np.ptp(pos[:, 0]) < 1e-12:
        return pos[:, 1].copy()
    direction = pos[-1] - pos[0]
    direction = direction / np.linalg.norm(direction)
    return (pos - np.array([cfg.center_x_mm, cfg.center_y_mm])) @ direction


# --------------------------------------------------------------------------------------
# Plan temporal
# --------------------------------------------------------------------------------------
@dataclass
class AcquisitionPlan:
    cfg: AcquisitionConfig
    positions: np.ndarray            # [B, S, A, 2] mm, orden físico
    t_first: np.ndarray              # MB: [B, S, A] tiempo de la 1.a A-line activa (s)
                                     # BM: [B, M, S] tiempo de la 1.a A-line del barrido
    traversal_reversed: np.ndarray   # MB: [B, S] ; BM: [B, M, S] si el barrido recorre al revés
    trigger_times: np.ndarray        # tiempos absolutos de PFI13 (s), ordenados
    info: dict[str, Any] = field(default_factory=dict)

    def aline_times(self, b: int, s: int) -> np.ndarray:
        """Tiempos absolutos [A, M] de las A-lines del B-scan (b, s) en orden físico."""
        c = self.cfg
        T = c.line_period_s
        A, M = c.alines, c.m_reps
        if c.mode == "MB":
            return self.t_first[b, s][:, None] + np.arange(M)[None, :] * T
        out = np.empty((A, M))
        for m in range(M):
            order = np.arange(A)
            if self.traversal_reversed[b, m, s]:
                order = order[::-1]           # posición física a se adquiere en el paso order[a]
            out[:, m] = self.t_first[b, m, s] + order * T
        return out


def build_plan(cfg: AcquisitionConfig) -> AcquisitionPlan:
    T = cfg.line_period_s
    Tseg = cfg.segment_period_s
    first_offset = cfg.sync_points * T + cfg.camera_phase_offset_us * 1e-6
    B, S, A, M = cfg.bscans, cfg.sweeps, cfg.alines, cfg.m_reps
    positions = np.zeros((B, S, A, 2))
    for b in range(B):
        for s, line in enumerate(sweep_positions(cfg, b)):
            positions[b, s] = line
    triggers: list[float] = []
    q = 0
    if cfg.mode == "MB":
        t_first = np.zeros((B, S, A))
        rev = np.zeros((B, S), dtype=bool)
        for b in range(B):
            for s in range(S):
                reverse = cfg.pattern == "lineal" and b % 2 == 1
                rev[b, s] = reverse
                order = range(A - 1, -1, -1) if reverse else range(A)
                for a in order:
                    t0 = q * Tseg + first_offset
                    t_first[b, s, a] = t0
                    triggers.append(t0 + cfg.bframes_delay_us * 1e-6)
                    q += 1
    else:
        t_first = np.zeros((B, M, S))
        rev = np.zeros((B, M, S), dtype=bool)
        for b in range(B):
            for m in range(M):
                for s in range(S):
                    linear_rev = cfg.pattern == "lineal" and (b * M + m) % 2 == 1
                    raster_rev = cfg.raster_bidirectional and cfg.pattern == "raster" and b % 2 == 1
                    rev[b, m, s] = linear_rev or raster_rev
                    t0 = q * Tseg + first_offset
                    t_first[b, m, s] = t0
                    if s == 0:   # crosshair: PFI13 solo en el barrido X [repo:octoce]
                        triggers.append(t0 + cfg.bframes_delay_us * 1e-6)
                    q += 1
    info = {
        "periodo_linea_us": cfg.cc1_period_us,
        "frecuencia_linea_efectiva_hz": 1e6 / cfg.cc1_period_us,
        "ticks_segmento": cfg.segment_ticks(),
        "periodo_segmento_ms": Tseg * 1e3,
        "hold_oce": cfg.hold_points(),
        "segmentos": cfg.n_segments,
        "a_lines_totales": cfg.total_alines,
        "duracion_adquisicion_s": cfg.duration_s,
    }
    return AcquisitionPlan(cfg, positions, t_first, rev, np.asarray(triggers), info)


def scan_extent_mm(cfg: AcquisitionConfig) -> tuple[float, float, float, float]:
    """Caja (xmin, xmax, ymin, ymax) cubierta por el barrido."""
    pts = np.concatenate([np.concatenate(sweep_positions(cfg, b)) for b in range(cfg.bscans)])
    return (float(pts[:, 0].min()), float(pts[:, 0].max()),
            float(pts[:, 1].min()), float(pts[:, 1].max()))


def mb_window_s(cfg: AcquisitionConfig) -> float:
    """Ventana temporal cubierta por las M repeticiones de un segmento MB."""
    return cfg.m_reps * cfg.line_period_s
