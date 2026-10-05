"""Estimadores de velocidad de onda (mapas en B-mode o en-face).

* Gradiente de fase local: ajuste de plano phi = p00 + p10 x + p01 z a la fase
  desenvuelta del fasor a f en ventanas deslizantes; K = sqrt(p10^2 + p01^2),
  c = 2 pi f / K; se descarta una componente si su intervalo de confianza del
  95 % supera el umbral relativo. Port de repo:PhaseDeriv; método comparado en
  [Zvietcovich2017].
* Tiempo de vuelo: tiempo de llegada T(x) (pico de la velocidad filtrada) y
  ecuación eikonal |grad T| = 1/c [McLaughlin2006]; TOF en OCE [WangLarin2014].
* Número de onda local (LFE): banco de filtros radiales log-normales
  R_i(rho) = exp(-(4/(B^2 ln 2)) ln^2(rho/rho_i)) con rho_{i+1} = 2 rho_i; para
  una onda de número de onda rho, R_{i+1}/R_i = (rho/sqrt(rho_i rho_{i+1}))^(8/B^2),
  de donde rho = sqrt(rho_i rho_{i+1}) (q_{i+1}/q_i)^(B^2/8) (derivación a partir
  de la definición del filtro; con B = 2 sqrt(2) octavas el cociente es lineal)
  [Knutsson1994; Manduca2001]. c = f / rho (rho en ciclos/m).
* Dispersión k-f global: U(k, w) = FFT2{u(x, t)} [Singh2022, Ec. (19)];
  c(w) = w / k_pico(w) [Singh2022, Ec. (20)]; [Bernal2011].
* Campo reverberante: autocorrelación espacial local del fasor a f,
  corregida por el número de muestras solapadas (repo:Reverb, correc =
  xcorr2(ones)), ajustada al perfil teórico normalizado:
      perpendicular al movimiento: (3/2) [j0(kD) - j1(kD)/(kD)]  [Zvietcovich2019, Ec. (2)]
      paralelo al movimiento:      3 j1(kD)/(kD)                 [Zvietcovich2019, Ec. (3)]
      onda superficial 2D:         J0(kD)                         [Aki1957]
  c = w / k [Zvietcovich2019]. Opción de solo fase (|P| = 1) [Ormachea2018].
  Estimador rápido por curvatura en el origen: con B(D)/B(D1) = r y el
  desarrollo B ~ 1 - (kD)^2/C (C = 5, 10, 4 para los tres modelos),
      k^2 = C (1 - r) / (D^2 - r D1^2)   [Hoyt2008; repo:Reverb localloop_xy].
* Módulos: mu = rho c_s^2 [Singh2022, Ec. (5)], E ~ 3 mu [Singh2022, Ec. (4)];
  para Rayleigh c_s = c_R / 0.955 [Singh2022, Ec. (12)].
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, fields
from math import log, pi, sqrt
from typing import Any

import numpy as np
from scipy import stats
from scipy.optimize import least_squares
from scipy.signal import hilbert
from scipy.special import j0 as bessel_j0
from scipy.special import spherical_jn


@dataclass
class SpeedConfig:
    methods: tuple[str, ...] = ("gradiente_fase", "tiempo_vuelo", "lfe", "kf")
    frequencies_hz: tuple[float, ...] = ()        # vacío = automático
    window_mm: float = 1.0                        # ventana lateral (x, y) en mm
    window_z_mm: float = 0.25                     # ventana en profundidad para B-mode; [repo:PhaseDeriv]
                                                  # usa WinSize = [2 0.2] mm (x, z) en Elastogram.m
    ci_threshold_pct: float = 15.0                # [repo:PhaseDeriv] Threshold = [15 15]
    tof_r2_min: float = 0.6
    lfe_bandwidth_oct: float = 2 * sqrt(2)        # [Knutsson1994]
    reverb_model: str = "auto"                    # auto | 3D | 2D
    reverb_phase_only: bool = False               # [Ormachea2018]
    reverb_estimator: str = "ajuste"              # ajuste | curvatura
    c_min: float = 0.2
    c_max: float = 10.0
    exclude_radius_mm: float = 0.0                # radio excluido alrededor de la fuente (TOF)

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["methods"] = list(self.methods)
        d["frequencies_hz"] = list(self.frequencies_hz)
        return d

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "SpeedConfig":
        known = {f.name for f in fields(cls)}
        kw = {k: v for k, v in d.items() if k in known}
        for key in ("methods", "frequencies_hz"):
            if key in kw:
                kw[key] = tuple(kw[key])
        return cls(**kw)


@dataclass
class SpeedMap:
    method: str
    c: np.ndarray                  # m/s en la malla completa (NaN fuera de soporte)
    axis1_mm: np.ndarray           # eje de filas (y o z)
    axis2_mm: np.ndarray           # eje de columnas (x)
    plane: str                     # "enface" o "bmode"
    note: str = ""


# --------------------------------------------------------------------------------------
# utilidades
# --------------------------------------------------------------------------------------
def _windows(n: int, w: int) -> np.ndarray:
    step = max(1, w // 4)          # [repo:PhaseDeriv] paso = ventana/4
    return np.arange(w // 2, n - w // 2 + 1, step)


def _upsample(cw: np.ndarray, centers1: np.ndarray, centers2: np.ndarray,
              n1: int, n2: int) -> np.ndarray:
    """Interpolación del mapa de ventanas a la malla completa (como interp2 en
    repo:OCE_workflow/inherited/Codes/Elastogram.m)."""
    from scipy.interpolate import RegularGridInterpolator  # noqa: PLC0415
    if cw.shape[0] < 2 or cw.shape[1] < 2:
        out = np.full((n1, n2), np.nanmedian(cw) if np.isfinite(cw).any() else np.nan)
        return out
    filled = cw.copy()
    if np.isnan(filled).any():
        med = np.nanmedian(filled) if np.isfinite(filled).any() else 0.0
        mask = np.isnan(filled)
        filled[mask] = med
    else:
        mask = np.zeros_like(filled, dtype=bool)
    rgi = RegularGridInterpolator((centers1, centers2), filled, bounds_error=False, fill_value=None)
    nanr = RegularGridInterpolator((centers1, centers2), mask.astype(float), bounds_error=False, fill_value=None)
    g1, g2 = np.meshgrid(np.arange(n1), np.arange(n2), indexing="ij")
    pts = np.stack([np.clip(g1, centers1[0], centers1[-1]), np.clip(g2, centers2[0], centers2[-1])], -1)
    out = rgi(pts)
    out[nanr(pts) > 0.5] = np.nan
    # sin extrapolación fuera de los centros de ventana (soporte incompleto)
    outside = (g1 < centers1[0]) | (g1 > centers1[-1]) | (g2 < centers2[0]) | (g2 > centers2[-1])
    out[outside] = np.nan
    return out


def _to_modulus(c: np.ndarray, rho: float, rayleigh: bool) -> np.ndarray:
    cs = c / 0.955 if rayleigh else c          # [Singh2022, Ec. (12)]
    return 3.0 * rho * cs**2                   # E ~ 3 rho c_s^2 [Singh2022, Ecs. (4)-(5)]


def youngs_modulus_kpa(c: np.ndarray, rho: float = 1000.0, rayleigh: bool = True) -> np.ndarray:
    return _to_modulus(c, rho, rayleigh) / 1e3


# --------------------------------------------------------------------------------------
# Gradiente de fase
# --------------------------------------------------------------------------------------
def phase_gradient_speed(P: np.ndarray, d1_m: float, d2_m: float, f_hz: float,
                         cfg: SpeedConfig, win1_mm: float | None = None,
                         ) -> tuple[np.ndarray, dict[str, np.ndarray]]:
    """Mapa c = 2 pi f / |K| por ajuste de plano en ventanas [repo:PhaseDeriv].

    win1_mm: ventana en el eje 1 (filas: y en-face, z en B-mode); por defecto window_mm.
    """
    n1, n2 = P.shape
    win1_mm = win1_mm or cfg.window_mm
    w1 = min(n1, max(4, int(round(win1_mm * 1e-3 / d1_m)))) if n1 > 1 else 1
    w2 = max(4, int(round(cfg.window_mm * 1e-3 / d2_m)))
    w1 -= w1 % 2
    w2 -= w2 % 2
    c1 = _windows(n1, w1) if n1 > 1 else np.array([0])
    c2 = _windows(n2, w2)
    out = np.full((c1.size, c2.size), np.nan)
    tcrit = stats.t.ppf(0.975, max(1, w1 * w2 - 3))
    for a, i in enumerate(c1):
        sl1 = slice(max(0, i - w1 // 2), i + w1 // 2) if n1 > 1 else slice(0, 1)
        for b, j in enumerate(c2):
            roi = P[sl1, j - w2 // 2: j + w2 // 2]
            if not np.isfinite(roi).all() or np.abs(roi).min() == 0:
                continue
            ph = np.unwrap(np.unwrap(np.angle(roi), axis=0), axis=1)
            Z, X = np.meshgrid(np.arange(roi.shape[0]) * d1_m, np.arange(roi.shape[1]) * d2_m, indexing="ij")
            G = np.column_stack((np.ones(ph.size), X.ravel(), Z.ravel()))
            coef, res, rank, _ = np.linalg.lstsq(G, ph.ravel(), rcond=None)
            dof = ph.size - 3
            if dof <= 0 or rank < (3 if n1 > 1 else 2):
                if n1 == 1:   # perfil 1D (una sola fila): solo x
                    k = abs(coef[1])
                    out[a, b] = 2 * pi * f_hz / k if k > 0 else np.nan
                continue
            resid = ph.ravel() - G @ coef
            s2 = resid @ resid / dof
            cov = s2 * np.linalg.pinv(G.T @ G)
            half = tcrit * np.sqrt(np.diag(cov))
            kx, kz = coef[1], coef[2]
            # rechazo por intervalo de confianza relativo (umbral 15 % [repo:PhaseDeriv])
            if abs(kx) == 0 or 200 * half[1] / abs(kx) > cfg.ci_threshold_pct:
                kx = 0.0
            if abs(kz) == 0 or 200 * half[2] / abs(kz) > cfg.ci_threshold_pct:
                kz = 0.0
            k = sqrt(kx * kx + kz * kz)
            if k > 0:
                out[a, b] = 2 * pi * f_hz / k
    out[(out < cfg.c_min) | (out > cfg.c_max)] = np.nan
    return _upsample(out, c1, c2, n1, n2), {"centers1": c1, "centers2": c2}


# --------------------------------------------------------------------------------------
# Tiempo de vuelo
# --------------------------------------------------------------------------------------
def arrival_times(v: np.ndarray, times: np.ndarray, t_min: float = 0.0) -> np.ndarray:
    """Tiempo del máximo de la envolvente de Hilbert de v [..., T] para t >= t_min
    (inicio conocido de la excitación), con interpolación parabólica."""
    env = np.abs(hilbert(np.nan_to_num(v), axis=-1))
    env[..., times < t_min] = 0.0
    i = np.argmax(env, axis=-1)
    i = np.clip(i, 1, env.shape[-1] - 2)
    take = lambda k: np.take_along_axis(env, k[..., None], -1)[..., 0]  # noqa: E731
    y0, y1, y2 = take(i - 1), take(i), take(i + 1)
    den = y0 - 2 * y1 + y2
    frac = np.where(np.abs(den) > 0, 0.5 * (y0 - y2) / den, 0.0)
    dt = times[1] - times[0]
    return times[0] + (i + np.clip(frac, -1, 1)) * dt


def tof_speed(T: np.ndarray, d1_m: float, d2_m: float, cfg: SpeedConfig,
              valid: np.ndarray | None = None, win1_mm: float | None = None) -> np.ndarray:
    """c = 1/|grad T| con ajuste de plano local de T [McLaughlin2006]."""
    n1, n2 = T.shape
    win1_mm = win1_mm or cfg.window_mm
    w1 = min(n1, max(3, int(round(win1_mm * 1e-3 / d1_m)))) if n1 > 1 else 1
    w2 = max(3, int(round(cfg.window_mm * 1e-3 / d2_m)))
    c1 = _windows(n1, w1) if n1 > 1 else np.array([0])
    c2 = _windows(n2, w2)
    out = np.full((c1.size, c2.size), np.nan)
    for a, i in enumerate(c1):
        sl1 = slice(max(0, i - w1 // 2), i + w1 // 2 + 1) if n1 > 1 else slice(0, 1)
        for b, j in enumerate(c2):
            sl2 = slice(max(0, j - w2 // 2), j + w2 // 2 + 1)
            roi = T[sl1, sl2]
            ok = np.isfinite(roi)
            if valid is not None:
                ok &= valid[sl1, sl2]
            if ok.sum() < 4:
                continue
            Z, X = np.meshgrid(np.arange(roi.shape[0]) * d1_m, np.arange(roi.shape[1]) * d2_m, indexing="ij")
            if n1 > 1:
                G = np.column_stack((np.ones(ok.sum()), X[ok], Z[ok]))
            else:
                G = np.column_stack((np.ones(ok.sum()), X[ok]))
            y = roi[ok]
            coef, *_ = np.linalg.lstsq(G, y, rcond=None)
            pred = G @ coef
            ss = np.sum((y - y.mean()) ** 2)
            r2 = 1 - np.sum((y - pred) ** 2) / ss if ss > 0 else 0
            slow = np.linalg.norm(coef[1:])
            if r2 >= cfg.tof_r2_min and slow > 0:
                out[a, b] = 1.0 / slow
    out[(out < cfg.c_min) | (out > cfg.c_max)] = np.nan
    return _upsample(out, c1, c2, n1, n2)


# --------------------------------------------------------------------------------------
# LFE
# --------------------------------------------------------------------------------------
def lfe_speed(P: np.ndarray, d1_m: float, d2_m: float, f_hz: float, cfg: SpeedConfig) -> np.ndarray:
    """Velocidad por estimación de frecuencia local [Knutsson1994; Manduca2001]."""
    n1, n2 = P.shape
    B = cfg.lfe_bandwidth_oct
    Pn = np.where(np.isfinite(P), P, 0)
    pad1, pad2 = (n1 // 2 if n1 > 1 else 0), n2 // 2
    Pp = np.pad(Pn, ((pad1, pad1), (pad2, pad2)), mode="reflect")
    k1 = np.fft.fftfreq(Pp.shape[0], d1_m) if n1 > 1 else np.zeros(1)
    k2 = np.fft.fftfreq(Pp.shape[1], d2_m)
    rho = np.sqrt(k1[:, None] ** 2 + k2[None, :] ** 2)
    rho_lo = f_hz / cfg.c_max
    rho_hi = f_hz / cfg.c_min
    centers = rho_lo * 2.0 ** np.arange(0, np.ceil(np.log2(rho_hi / rho_lo)) + 1)
    FP = np.fft.fft2(Pp)
    C = 4.0 / (B * B * log(2))
    q = []
    for rc in centers:
        with np.errstate(divide="ignore"):
            R = np.where(rho > 0, np.exp(-C * np.log(np.maximum(rho, 1e-12) / rc) ** 2), 0.0)
        qi = np.abs(np.fft.ifft2(FP * R))
        q.append(qi[pad1:pad1 + n1, pad2:pad2 + n2])
    num = np.zeros((n1, n2))
    den = np.zeros((n1, n2))
    expo = B * B / 8.0
    for i in range(len(centers) - 1):
        w = q[i] * q[i + 1]
        with np.errstate(divide="ignore", invalid="ignore"):
            est = np.sqrt(centers[i] * centers[i + 1]) * (q[i + 1] / q[i]) ** expo
        est = np.where(np.isfinite(est), est, 0)
        num += w * est
        den += w
    with np.errstate(divide="ignore", invalid="ignore"):
        rho_loc = num / den
        c = f_hz / rho_loc
    c[(c < cfg.c_min) | (c > cfg.c_max) | ~np.isfinite(c)] = np.nan
    c[~np.isfinite(P)] = np.nan
    # borde de media ventana sin soporte completo (como en los demás estimadores)
    b1 = int(round(cfg.window_mm * 1e-3 / d1_m / 2)) if n1 > 1 else 0
    b2 = int(round(cfg.window_mm * 1e-3 / d2_m / 2))
    if b1:
        c[:b1] = np.nan
        c[-b1:] = np.nan
    if b2:
        c[:, :b2] = np.nan
        c[:, -b2:] = np.nan
    return c


# --------------------------------------------------------------------------------------
# Dispersión k-f
# --------------------------------------------------------------------------------------
def kf_dispersion(u: np.ndarray, x_m: np.ndarray, dt: float, cfg: SpeedConfig,
                  direction: int = +1, nfft: int = 4097,
                  start_band_hz: tuple[float, float] | None = None) -> dict[str, np.ndarray]:
    """c(f) = f / k_pico(f) de u(x, t) [Singh2022, Ecs. (19)-(20); Bernal2011].

    u: [Nx, Nt]; direction +1 para propagación hacia +x. Con la convención de
    numpy (exp(-i(kx + wt)) en la FFT directa) una onda exp(i(kx - wt)) aparece
    en (k < 0, f > 0); se elige el semiplano correspondiente a ``direction``.
    """
    dx = float(np.median(np.diff(x_m)))
    U = np.fft.fft2(np.nan_to_num(u) * np.hanning(u.shape[1])[None, :], s=(nfft, nfft))
    k = np.fft.fftfreq(nfft, dx)
    f = np.fft.fftfreq(nfft, dt)
    pos_f = f > 0
    A = np.abs(U[:, pos_f])                      # [k, f]
    fpos = f[pos_f]
    half = (k < 0) if direction > 0 else (k > 0)
    kabs = np.abs(k)
    c_out = np.full(fpos.size, np.nan)
    mag = np.zeros(fpos.size)
    # Cresta: se parte del máximo global y se sigue en frecuencia con un salto máximo
    # en k entre frecuencias vecinas (como maximum_wavenumber_jump_per_m de
    # repo:OCE_workflow computeDispersionSpectrum).
    allowed = np.zeros_like(A, dtype=bool)
    for i, fi in enumerate(fpos):
        allowed[:, i] = half & (kabs >= fi / cfg.c_max) & (kabs <= fi / cfg.c_min)
    Am = np.where(allowed, A, 0.0)
    if Am.max() <= 0:
        return {"f_hz": fpos, "c_m_s": c_out, "magnitude": mag, "kf_map": A, "k_cyc_m": k}
    # inicio de la cresta: máximo dentro de la banda de arranque (por defecto todo el espectro);
    # a baja frecuencia domina el modo fundamental excitado por un empuje superficial.
    colmax = Am.max(axis=0)
    fsel = colmax >= 0.3 * colmax.max()
    if start_band_hz is not None:
        fsel &= (fpos >= start_band_hz[0]) & (fpos <= start_band_hz[1])
    if not fsel.any():
        fsel = colmax > 0
    i0 = int(np.nonzero(fsel)[0][0])            # frecuencia más baja con energía significativa
    j0 = int(np.argmax(Am[:, i0]))
    df = fpos[1] - fpos[0]
    for direction_f in (+1, -1):
        jprev = j0
        i = i0
        while 0 <= i < fpos.size:
            fi = fpos[i]
            kprev = kabs[jprev]
            # salto máximo: 2 % de k + lo que permite c_min en un paso de frecuencia
            jump = 0.02 * kprev + df / cfg.c_min + 2 * abs(k[1] - k[0])
            near = allowed[:, i] & (np.abs(kabs - kprev) <= jump)
            if near.any() and Am[near, i].max() > 0:
                col = np.where(near, Am[:, i], 0.0)
                j = int(np.argmax(col))
                c_out[i] = fi / kabs[j]
                mag[i] = col[j]
                jprev = j
            i += direction_f
    return {"f_hz": fpos, "c_m_s": c_out, "magnitude": mag, "kf_map": A, "k_cyc_m": k}


# --------------------------------------------------------------------------------------
# Reverberante
# --------------------------------------------------------------------------------------
def reverb_model_profile(model: str, x: np.ndarray) -> np.ndarray:
    """Perfiles normalizados (=1 en el origen) de [Zvietcovich2019, Ecs. (2)-(3)] y J0 [Aki1957]."""
    x = np.maximum(np.asarray(x, dtype=float), 1e-9)
    if model == "3D_perp":
        return 1.5 * (spherical_jn(0, x) - spherical_jn(1, x) / x)
    if model == "3D_par":
        return 3.0 * spherical_jn(1, x) / x
    if model == "2D":
        return bessel_j0(x)
    raise ValueError(model)


CURVATURE_C = {"3D_perp": 5.0, "3D_par": 10.0, "2D": 4.0}


def _autocorr2(win: np.ndarray) -> np.ndarray:
    """Autocorrelación 2D por Wiener-Khinchin, R = IFFT(|FFT(P)|^2) con relleno a 2N-1
    (correlación lineal, no circular) [Oppenheim2010], dividida por el número de muestras
    solapadas en cada desfase (correc = xcorr2(ones), repo:Reverb)."""
    n1, n2 = win.shape
    F = np.fft.fft2(win, s=(2 * n1 - 1, 2 * n2 - 1))
    R = np.fft.fftshift(np.fft.ifft2(F * np.conj(F)))
    ones = np.fft.fft2(np.ones_like(win, dtype=float), s=(2 * n1 - 1, 2 * n2 - 1))
    corr = np.real(np.fft.fftshift(np.fft.ifft2(ones * np.conj(ones))))
    return np.real(R) / np.maximum(corr, 1)


def _radial_profile(R: np.ndarray, d1: float, d2: float, rmax: float, dr: float) -> tuple[np.ndarray, np.ndarray]:
    c1, c2 = R.shape[0] // 2, R.shape[1] // 2
    i1 = (np.arange(R.shape[0]) - c1) * d1
    i2 = (np.arange(R.shape[1]) - c2) * d2
    rr = np.sqrt(i1[:, None] ** 2 + i2[None, :] ** 2)
    bins = np.arange(0, rmax + dr, dr)
    idx = np.digitize(rr.ravel(), bins) - 1
    prof = np.bincount(idx[idx < bins.size - 1], R.ravel()[idx < bins.size - 1], bins.size - 1)
    cnt = np.bincount(idx[idx < bins.size - 1], minlength=bins.size - 1)
    centers = 0.5 * (bins[:-1] + bins[1:])
    with np.errstate(invalid="ignore"):
        return centers, prof / np.maximum(cnt, 1)


def _fit_k(lags: np.ndarray, prof: np.ndarray, model: str, kmin: float, kmax: float,
           estimator: str) -> float:
    ok = (lags > 0) & np.isfinite(prof)
    lags, prof = lags[ok], prof[ok]
    if lags.size < 3:
        return np.nan
    if estimator == "curvatura":
        r = prof[min(3, lags.size - 1)] / prof[0]
        D, D1 = lags[min(3, lags.size - 1)], lags[0]
        k2 = CURVATURE_C[model] * (1 - r) / (D * D - r * D1 * D1)
        return sqrt(k2) if k2 > 0 else np.nan
    best = (np.inf, np.nan, 1.0)
    for kg in np.geomspace(kmin, kmax, 60):
        sel = lags * kg <= 4.0                     # lóbulo principal y primer mínimo
        if sel.sum() < 3:
            continue
        m = reverb_model_profile(model, kg * lags[sel])
        a = float(np.dot(m, prof[sel]) / max(np.dot(m, m), 1e-30))
        err = np.mean((prof[sel] - a * m) ** 2) / max(np.mean(prof[sel] ** 2), 1e-30)
        if err < best[0]:
            best = (err, kg, a)
    if not np.isfinite(best[1]):
        return np.nan
    kg = best[1]
    sel = lags * kg <= 4.0

    def res(p: np.ndarray) -> np.ndarray:
        return p[0] * reverb_model_profile(model, p[1] * lags[sel]) - prof[sel]

    try:
        sol = least_squares(res, x0=[best[2], kg], bounds=([0, kmin], [np.inf, kmax]))
        return float(sol.x[1])
    except ValueError:
        return float(kg)


def reverberant_speed(P: np.ndarray, d1_m: float, d2_m: float, f_hz: float, cfg: SpeedConfig,
                      plane: str) -> tuple[np.ndarray, dict[str, Any]]:
    """Mapa de velocidad por autocorrelación local del campo reverberante.

    plane = "enface": autocorrelación radial (ambos ejes perpendiculares a z).
    plane = "bmode": perfil en x (perpendicular, Ec. 2) y en z (paralelo, Ec. 3).
    """
    w = 2 * pi * f_hz
    Pn = np.where(np.isfinite(P), P, np.nan)
    if cfg.reverb_phase_only:
        Pn = np.exp(1j * np.angle(Pn))
    n1, n2 = Pn.shape
    w1 = max(6, int(round(cfg.window_mm * 1e-3 / d1_m)))
    w2 = max(6, int(round(cfg.window_mm * 1e-3 / d2_m)))
    c1 = _windows(n1, w1)
    c2 = _windows(n2, w2)
    kmin, kmax = w / cfg.c_max, w / cfg.c_min
    if cfg.reverb_model == "2D":
        model_xy = "2D"
    else:
        model_xy = "3D_perp" if (cfg.reverb_model == "3D" or plane == "bmode") else "2D"
    out = np.full((c1.size, c2.size), np.nan)
    example = None
    for a, i in enumerate(c1):
        for b, j in enumerate(c2):
            win = Pn[i - w1 // 2: i + w1 // 2, j - w2 // 2: j + w2 // 2]
            if win.size == 0 or not np.isfinite(win).all():
                continue
            # sin restar la media: con ventanas del orden de lambda la resta sesga k hacia
            # arriba (~20 % con ventana = 0.8 lambda); repo:Reverb usa xcorr2 sobre el campo crudo.
            R = _autocorr2(win)
            m1, m2 = R.shape[0] // 2, R.shape[1] // 2
            if plane.startswith("enface"):
                lags, prof = _radial_profile(R, d1_m, d2_m, min(w1 * d1_m, w2 * d2_m) * 0.6,
                                             min(d1_m, d2_m))
                k = _fit_k(lags, prof, model_xy, kmin, kmax, cfg.reverb_estimator)
            else:
                lx = np.arange(R.shape[1] - m2) * d2_m
                kx = _fit_k(lx, R[m1, m2:], "3D_perp", kmin, kmax, cfg.reverb_estimator)
                lz = np.arange(R.shape[0] - m1) * d1_m
                kz = _fit_k(lz, R[m1:, m2], "3D_par", kmin, kmax, cfg.reverb_estimator)
                k = np.nanmean([kx, kz])
            if np.isfinite(k) and k > 0:
                out[a, b] = w / k
            if example is None and np.isfinite(k):
                example = {"R": R, "k": k}
    out[(out < cfg.c_min) | (out > cfg.c_max)] = np.nan
    return _upsample(out, c1, c2, n1, n2), {"modelo": model_xy, "ejemplo": example}
