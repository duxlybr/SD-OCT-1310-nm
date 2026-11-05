"""Procesamiento OCE de los B-scans complejos simulados.

Pasos (siguiendo el flujo mantenido en repo:OCE_workflow):
1. Incremento de fase temporal con el estimador de Loupas [Loupas1995],
   portado línea a línea de repo:Loupas (sin unwrap, sin máscara).
2. Fase -> desplazamiento: du = -dphi lambda0 / (4 pi n)  [Nguyen2014, Ec. (1)]
   (el signo menos se debe a que Loupas devuelve phi_actual - phi_siguiente; el
   resultado es positivo hacia +z, lejos de la sonda, dirección del empuje).
   Corrección opcional del artefacto de movimiento superficial por desajuste de
   índice [Song2013]: du(z) = [dOPL(z) + (n - 1) dOPL_sup] / n, y en la
   superficie du_sup = dOPL_sup (el camino cambia en aire, n = 1).
3. Filtro temporal FIR pasabanda de fase cero (ventana de Hamming, filtfilt)
   [Oppenheim2010] y remoción de la media temporal (como repo:OCE_workflow).
4. Superficie: primer bin cuya intensidad media suavizada supera el piso de
   ruido + umbral; refinamiento por máximo gradiente.
5. Filtro espacial de velocidades: conserva componentes con
   c = f/|k| en [c_min, c_max]. En armónico es el anillo ("donut") en el
   espacio k con bordes gaussianos de [Zvietcovich2019, Métodos: "donut-shaped
   ring with Gaussian borders", 0.2-10 m/s]; en transitorio se aplica la misma
   condición como cono en (k, f).
6. En-face: raster -> malla directa; meridianos/crosshair/lineal -> interpolación
   lineal (Delaunay) o cúbica (Clough-Tocher) sobre una malla cartesiana.
7. Fasor armónico: P(p) = (2/M) sum_m u(p, t_m) exp(-i w t_m) con los tiempos
   reales de cada muestra [Zvietcovich2019, Ec. (7)]; en MB el fasor se refiere a
   un instante común multiplicando por exp(-i w t_inicio(p)) (equivalente a la
   sincronización por número entero de ciclos usada en [Zvietcovich2019, "Data
   acquisition"]).
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, fields
from math import pi
from typing import Any

import numpy as np
from scipy import signal
from scipy.interpolate import CloughTocher2DInterpolator, LinearNDInterpolator
from scipy.ndimage import gaussian_filter1d


@dataclass
class ProcessingConfig:
    loupas_window: int = 4              # muestras axiales del estimador de Loupas
    n_processing: float = 0.0           # índice para fase->desplazamiento (0 = capa superior)
    surface_correction: bool = True     # corrección de [Song2013]
    surface_threshold_db: float = 10.0
    surface_samples: int = 3            # bins bajo la superficie promediados
    filter_low_hz: float = 150.0
    filter_high_hz: float = 4000.0
    remove_temporal_mean: bool = True
    speed_filter: bool = True
    speed_min_m_s: float = 0.2          # [Zvietcovich2019]
    speed_max_m_s: float = 10.0         # [Zvietcovich2019]
    enface_method: str = "lineal"       # "lineal" | "cubica" | "vecino"
    enface_pixel_mm: float = 0.04
    enface_depths_mm: tuple[float, ...] = ()   # profundidades extra bajo la superficie
    bmode_bscans: tuple[int, ...] = ()        # B-scans con video en profundidad (vacío = central)
    intensity_mask_db: float = 6.0             # máscara del video B-mode sobre el ruido

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["enface_depths_mm"] = list(self.enface_depths_mm)
        d["bmode_bscans"] = list(self.bmode_bscans)
        return d

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "ProcessingConfig":
        known = {f.name for f in fields(cls)}
        kw = {k: v for k, v in d.items() if k in known}
        for key in ("enface_depths_mm", "bmode_bscans"):
            if key in kw:
                kw[key] = tuple(kw[key])
        return cls(**kw)


# --------------------------------------------------------------------------------------
# 1. Loupas
# --------------------------------------------------------------------------------------
def loupas_phase_increment(iq: np.ndarray, window: int) -> np.ndarray:
    """Incremento de fase temporal (rad) [Loupas1995], port de repo:Loupas.

    iq: [..., depth, time] complejo. Salida: [..., depth - window + 1, time - 1].
    """
    cur = iq[..., :-1]
    nxt = iq[..., 1:]
    ci, cq = cur.real.astype(np.float64), cur.imag.astype(np.float64)
    ni, nq = nxt.real.astype(np.float64), nxt.imag.astype(np.float64)
    num_t = cq * ni - ci * nq
    den_t = ci * ni + cq * nq
    num_a = ((cq[..., :-1, :] * ci[..., 1:, :] - ci[..., :-1, :] * cq[..., 1:, :])
             + (nq[..., :-1, :] * ni[..., 1:, :] - ni[..., :-1, :] * nq[..., 1:, :]))
    den_a = ((ci[..., :-1, :] * ci[..., 1:, :] + cq[..., :-1, :] * cq[..., 1:, :])
             + (ni[..., :-1, :] * ni[..., 1:, :] + nq[..., :-1, :] * nq[..., 1:, :]))

    def box(a: np.ndarray, w: int) -> np.ndarray:
        c = np.cumsum(a, axis=-2)
        pad = np.zeros_like(c[..., :1, :])
        c = np.concatenate((pad, c), axis=-2)
        return c[..., w:, :] - c[..., :-w, :]

    st_n, st_d = box(num_t, window), box(den_t, window)
    sa_n, sa_d = box(num_a, window - 1), box(den_a, window - 1)
    return np.arctan2(st_n, st_d) / (1.0 + np.arctan2(sa_n, sa_d) / (2 * pi))


# --------------------------------------------------------------------------------------
# 2-4. Desplazamiento, superficie, filtros temporales
# --------------------------------------------------------------------------------------
def detect_surface(intensity_db: np.ndarray, threshold_db: float) -> np.ndarray:
    """Índice de bin de superficie por A-line. intensity_db: [A, Z].

    Heurística propia (sin ecuación de bibliografía): primer bin cuya intensidad
    suavizada supera el piso de ruido + umbral, refinado al máximo gradiente.
    """
    sm = gaussian_filter1d(intensity_db, 1.0, axis=1)
    floor = np.median(sm[:, : max(3, sm.shape[1] // 20)], axis=1, keepdims=True)
    above = sm > floor + threshold_db
    first = np.where(above.any(axis=1), np.argmax(above, axis=1), sm.shape[1] - 1)
    grad = np.diff(sm, axis=1)
    out = first.copy()
    for a in range(sm.shape[0]):
        lo = max(0, first[a] - 3)
        hi = min(grad.shape[1], first[a] + 3)
        if hi > lo:
            out[a] = lo + int(np.argmax(grad[a, lo:hi])) + 1
    return out


def surface_window_start(intensity_db: np.ndarray, surface_idx: np.ndarray, window: int,
                         search: int = 6) -> np.ndarray:
    """Inicio de la ventana de Loupas centrada en el pico de intensidad de la superficie.

    La fase superficial se toma de la reflexión más brillante dentro de ``search``
    bins bajo el borde detectado (reflexión especular o primer speckle), con la
    ventana axial centrada en ese pico; así no se mezcla con speckle interno de
    menor SNR que se mueve distinto (ver Song2013 sobre el movimiento superficial).
    """
    A, Z = intensity_db.shape
    out = np.empty(A, dtype=int)
    for a in range(A):
        lo = int(np.clip(surface_idx[a], 0, Z - 1))
        hi = int(min(Z, lo + search))
        peak = lo + int(np.argmax(intensity_db[a, lo:hi])) if hi > lo else lo
        out[a] = peak - (window - 1) // 2
    return out


def phase_to_displacement(dphi: np.ndarray, lambda0_m: float, n: float,
                          surface_start: np.ndarray | None, surface_correction: bool,
                          surface_samples: int) -> tuple[np.ndarray, np.ndarray]:
    """Incrementos de desplazamiento (m) [A, Zl, T] y de la superficie [A, T].

    dOPL = -dphi lambda0/(4 pi)  (Loupas devuelve phi_actual - phi_siguiente)
    du   = dOPL / n                       [Nguyen2014, Ec. (1)]
    du   = (dOPL + (n-1) dOPL_sup) / n    con corrección [Song2013]
    surface_start: índice de salida de Loupas centrado en la superficie (surface_window_start);
    se promedian ``surface_samples`` salidas alrededor de él.
    """
    dopl = -dphi * lambda0_m / (4 * pi)
    A, Zl, T = dopl.shape
    if surface_start is None:
        return dopl / n, np.zeros((A, T))
    rows = np.arange(A)
    s_idx = np.clip(surface_start, 0, Zl - 1)
    half = max(1, surface_samples) // 2
    offs = range(-half, -half + max(1, surface_samples))
    stack = np.stack([dopl[rows, np.clip(s_idx + j, 0, Zl - 1)] for j in offs])
    dopl_s = stack.mean(axis=0)                                           # [A, T]
    if surface_correction:
        du = (dopl + (n - 1) * dopl_s[:, None, :]) / n
        du_s = dopl_s                                                     # la superficie se mueve en aire
    else:
        du = dopl / n
        du_s = dopl_s / n
    return du, du_s


def design_bandpass(fs: float, f_lo: float, f_hi: float, n_samples: int) -> np.ndarray | None:
    """FIR pasabanda (ventana de Hamming) con longitud compatible con filtfilt [Oppenheim2010]."""
    nyq = fs / 2
    lo = max(f_lo, 1e-3) / nyq
    hi = min(f_hi, 0.95 * nyq) / nyq
    if hi <= lo:
        return None
    numtaps = int(min(max(3 * fs / max(f_lo, 1.0), 31), (n_samples - 1) // 3))
    numtaps -= 1 - numtaps % 2       # impar
    if numtaps < 15:
        return None
    return signal.firwin(numtaps, [lo, hi], pass_zero=False, window="hamming")


def temporal_filter(x: np.ndarray, fs: float, cfg: ProcessingConfig, axis: int = -1) -> np.ndarray:
    y = x - x.mean(axis=axis, keepdims=True) if cfg.remove_temporal_mean else x
    taps = design_bandpass(fs, cfg.filter_low_hz, cfg.filter_high_hz, x.shape[axis])
    if taps is None:
        return y
    return signal.filtfilt(taps, [1.0], y, axis=axis)


# --------------------------------------------------------------------------------------
# 5. Filtro espacial de velocidades
# --------------------------------------------------------------------------------------
def _soft_band(c: np.ndarray, cmin: float, cmax: float, soft: float = 0.15) -> np.ndarray:
    """Máscara suave (bordes gaussianos en log c) para cmin <= c <= cmax."""
    lc = np.log(np.maximum(c, 1e-12))
    m = np.ones_like(lc)
    lo, hi = np.log(cmin), np.log(cmax)
    m = np.where(lc < lo, np.exp(-0.5 * ((lc - lo) / soft) ** 2), m)
    m = np.where(lc > hi, np.exp(-0.5 * ((lc - hi) / soft) ** 2), m)
    return m


def donut_filter_phasor(P: np.ndarray, dx_m: float, dy_m: float, f_hz: float,
                        cmin: float, cmax: float) -> np.ndarray:
    """Filtro anular en k para un fasor 2D a la frecuencia f [Zvietcovich2019]."""
    ny, nx = P.shape
    ky = np.fft.fftfreq(ny, dy_m)
    kx = np.fft.fftfreq(nx, dx_m)
    K = np.sqrt(ky[:, None] ** 2 + kx[None, :] ** 2)     # ciclos/m
    with np.errstate(divide="ignore"):
        c = np.where(K > 0, f_hz / K, np.inf)
    mask = _soft_band(c, cmin, cmax)
    Pn = np.where(np.isfinite(P), P, 0)
    return np.fft.ifft2(np.fft.fft2(Pn) * mask)


def cone_filter(v: np.ndarray, spacings_m: tuple[float, ...], dt: float,
                cmin: float, cmax: float) -> np.ndarray:
    """Filtro de velocidades en (k, f) para un campo [..espacio.., t] (transitorio).

    Todos los ejes (espaciales y temporal) se rellenan con ceros (50 %) para evitar el
    envolvimiento circular de la FFT en los bordes.
    """
    vv = np.where(np.isfinite(v), v, 0)
    pads = [(0, max(1, n // 2)) for n in v.shape]
    vv = np.pad(vv, pads)
    F = np.fft.fftn(vv)
    shape = vv.shape
    freqs = [np.fft.fftfreq(n, d) for n, d in zip(shape[:-1], spacings_m)]
    ft = np.fft.fftfreq(shape[-1], dt)
    grids = np.meshgrid(*freqs, ft, indexing="ij", sparse=True)
    K = np.sqrt(sum(g**2 for g in grids[:-1]))
    with np.errstate(divide="ignore", invalid="ignore"):
        c = np.where(K > 0, np.abs(grids[-1]) / K, np.inf)
    mask = _soft_band(c, cmin, cmax)
    mask = np.where(grids[-1] == 0, 1.0, mask)
    out = np.real(np.fft.ifftn(F * mask))
    return out[tuple(slice(0, n) for n in v.shape)]


# --------------------------------------------------------------------------------------
# 6. En-face
# --------------------------------------------------------------------------------------
def enface_grid(points_mm: np.ndarray, pixel_mm: float) -> tuple[np.ndarray, np.ndarray]:
    x = np.arange(points_mm[:, 0].min(), points_mm[:, 0].max() + pixel_mm / 2, pixel_mm)
    y = np.arange(points_mm[:, 1].min(), points_mm[:, 1].max() + pixel_mm / 2, pixel_mm)
    return x, y


def interpolate_enface(points_mm: np.ndarray, values: np.ndarray, x: np.ndarray, y: np.ndarray,
                       method: str) -> np.ndarray:
    """Interpola valores [N, ...] dados en puntos dispersos a la malla (y, x, ...)."""
    pts, idx = np.unique(np.round(points_mm, 9), axis=0, return_index=True)
    vals = values[idx]
    X, Y = np.meshgrid(x, y)
    flat = vals.reshape(vals.shape[0], -1)
    if method == "cubica":
        interp = CloughTocher2DInterpolator(pts, flat)
    elif method == "vecino":
        from scipy.interpolate import NearestNDInterpolator  # noqa: PLC0415
        interp = NearestNDInterpolator(pts, flat)
    else:
        interp = LinearNDInterpolator(pts, flat)
    out = interp(X, Y)
    return out.reshape(X.shape + vals.shape[1:])


def harmonic_phasor(u: np.ndarray, times: np.ndarray, f_hz: float) -> np.ndarray:
    """Fasor de u(t) a f con tiempos reales [Zvietcovich2019, Ec. (7)] (DFT directa).

    u: [..., M]; times: misma forma (s). Devuelve el fasor complejo (amplitud de pico).
    """
    w = 2 * pi * f_hz
    uu = u - u.mean(axis=-1, keepdims=True)
    return 2.0 * np.mean(uu * np.exp(-1j * w * times), axis=-1)
