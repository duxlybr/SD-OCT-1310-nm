"""Solver elastodinámico 3D: diferencias finitas velocidad-esfuerzo en malla escalonada.

Esquema [Virieux1986] extendido a 3D [Graves1996], segundo orden en espacio y
tiempo (leapfrog). Ubicación de variables en la celda (i, j, k):

    sxx, syy, szz ............ (i,     j,     k)
    vx ....................... (i+1/2, j,     k)
    vy ....................... (i,     j+1/2, k)
    vz ....................... (i,     j,     k+1/2)
    sxy ...................... (i+1/2, j+1/2, k)
    sxz ...................... (i+1/2, j,     k+1/2)
    syz ...................... (i,     j+1/2, k+1/2)

Ecuaciones:
* Conservación del momento:  rho dv_i/dt = d sigma_ij / dx_j + f_i
  [Virieux1986, Ecs. (1)-(2); Graves1996]
* Constitutiva Kelvin-Voigt isótropa (ley de Hooke [Singh2022, Ec. (1)] con
  mu -> mu + eta d/dt por correspondencia con [Singh2022, Ec. (9)]):
      sigma_ij = lambda e_kk delta_ij + 2 mu e_ij + 2 eta de_ij/dt
  Se integra la parte elástica (sigma^e += dt (lambda tr(D) delta + 2 mu D),
  D = tasa de deformación) y se suma la viscosa instantánea 2 eta D.
  Viscosidad volumétrica nula (supuesto explícito).
* Parámetros efectivos en la malla heterogénea [Graves1996; Moczo2002]:
  densidad por promedio aritmético en los nodos de velocidad y módulo de corte
  (y viscosidad) por promedio armónico en los nodos de esfuerzo cortante.
* Superficie libre y fluidos: formalismo de vacío (celdas de aire con
  lambda = mu = rho = 0; el promedio armónico anula el corte en la interfaz)
  [Graves1996; Moczo2002]. En el fluido mu = 0 (deslizamiento libre).
* Bordes absorbentes: C-PML con desplazamiento de frecuencia [Komatitsch2007;
  Roden2000]:  d/dx -> (1/kappa) d/dx + psi,  psi^n = b psi^(n-1) + a (d/dx)^n,
      b = exp(-(d/kappa + alpha) dt),  a = d (b - 1) / (kappa (d + kappa alpha)),
      d(x) = d0 (x/L)^N,  d0 = -(N+1) c_p ln(R) / (2 L),  alpha(x) = alpha_max (1 - x/L).
* Estabilidad (análisis de von Neumann del esquema con amortiguamiento
  viscoso, derivación propia documentada en docs/MODELO_FISICO.md):
      M dt^2 + 2 eta_M dt <= rho h^2 / 3,  M = lambda + 2 mu,  eta_M = 2 eta,
  que con eta = 0 se reduce a c_p dt sqrt(3)/h <= 1 [Graves1996].
"""
from __future__ import annotations

import time
from dataclasses import asdict, dataclass, field, fields
from math import ceil, log, pi, sqrt
from threading import Event
from typing import Any, Callable

import numpy as np

from .backend import Backend, get_backend
from .excitation import (ExcitationConfig, acoustic_intensity, characteristic_width_mm,
                         harmonic_group_signals, lateral_shape, radiation_pressure_air,
                         source_centers_mm, source_phases, transient_force_envelope)
from .geometry import AIR_ID, RIGID_ID, Geometry
from .materials import Material

ProgressFn = Callable[[float, str], None]

#: Versión del modelo físico/numérico; forma parte de la clave de la caché del campo.
#: Debe incrementarse al cambiar cualquier cosa que altere el campo FDTD.
MODEL_VERSION = "2026.10.03-2"


class SimulationCancelled(RuntimeError):
    pass


@dataclass
class FDTDSettings:
    cell_mm: float = 0.0            # 0 = automático
    ppw: float = 10.0               # puntos por longitud de onda de corte a f_max
    f_max_hz: float = 0.0           # 0 = automático (espectro de la fuente, -20 dB)
    courant: float = 0.85           # fracción del límite de estabilidad
    pml_cells: int = 12
    pml_R: float = 1e-4
    duration_ms: float = 0.0        # transitorio: 0 = automático (ventana de adquisición)
    record_margin_mm: float = 0.3
    record_depth_mm: float = 1.5    # profundidad registrada bajo la superficie
    record_stride: int = 0          # 0 = automático
    backend: str = "auto"
    harmonic_window_periods: int = 2
    harmonic_min_periods: int = 6
    harmonic_max_periods: int = 80
    harmonic_tol: float = 0.01
    harmonics: int = 2              # armónicos a extraer (1 = solo f)
    max_cells: int = 30_000_000

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "FDTDSettings":
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in d.items() if k in known})


# --------------------------------------------------------------------------------------
# Malla
# --------------------------------------------------------------------------------------
@dataclass
class Grid:
    h: float                     # m
    nx: int
    ny: int
    nz: int
    x0: float                    # coordenada (m) del nodo normal i = 0
    y0: float
    z0: float
    pml: dict[str, tuple[int, int]]
    ids: np.ndarray              # uint8 (nx, ny, nz) ids de material en nodos normales
    materials: list[Material]
    c_fluid: float

    @property
    def shape(self) -> tuple[int, int, int]:
        return (self.nx, self.ny, self.nz)

    @property
    def cells(self) -> int:
        return self.nx * self.ny * self.nz

    def x(self, half: bool = False) -> np.ndarray:
        return self.x0 + (np.arange(self.nx) + (0.5 if half else 0.0)) * self.h

    def y(self, half: bool = False) -> np.ndarray:
        return self.y0 + (np.arange(self.ny) + (0.5 if half else 0.0)) * self.h

    def z(self, half: bool = False) -> np.ndarray:
        return self.z0 + (np.arange(self.nz) + (0.5 if half else 0.0)) * self.h


def solid_materials(materials: list[Material]) -> list[Material]:
    return [m for m in materials if not m.is_fluid]


def auto_fluid_speed(materials: list[Material]) -> float:
    """Velocidad del fluido en la simulación (supuesto explícito).

    Se reduce de ~1480 m/s a la mayor c_p de los sólidos (>= 10 c_s con
    nu = 0.495); el fluido sigue siendo >> que las ondas guiadas (ver
    validación en theory.py: la curva A0 con c_f = 10 c_s difiere < 0.1 % de la
    obtenida con 1480 m/s).
    """
    solids = solid_materials(materials)
    cp = max(m.cp() for m in solids) if solids else 20.0
    fluids = [m for m in materials if m.is_fluid and m.c_fluid_sim > 0]
    return max([cp] + [m.c_fluid_sim for m in fluids])


def stable_dt(materials: list[Material], h: float, c_fluid: float, courant: float) -> float:
    """Paso temporal máximo estable (ver docstring del módulo)."""
    M = max(m.lam(c_fluid) + 2 * m.mu for m in materials)
    eta_M = max(2 * m.eta for m in materials)
    rho = min(m.rho for m in materials)
    dt = (-eta_M + sqrt(eta_M**2 + M * rho * h * h / 3.0)) / M
    return courant * dt


def source_fmax(exc: ExcitationConfig) -> float:
    """Frecuencia máxima relevante de la fuente (-20 dB del espectro de fuerza)."""
    if exc.regime == "armonico":
        return exc.harmonic_hz * (1 if exc.mode == "anillo_contactos" else 2)
    dt = 2e-6
    t = np.arange(0, 0.05, dt)
    s = transient_force_envelope(exc, t)
    spec = np.abs(np.fft.rfft(s))
    f = np.fft.rfftfreq(t.size, dt)
    if spec.max() <= 0:
        return 2000.0
    above = np.nonzero(spec >= 0.1 * spec.max())[0]
    return float(max(f[above[-1]], 200.0))


def choose_cell_size(geom: Geometry, exc: ExcitationConfig, settings: FDTDSettings) -> tuple[float, dict[str, float]]:
    """Tamaño de celda h (m) y las restricciones que lo determinaron.

    * Dispersión numérica: h <= lambda_s,min / PPW con lambda_s = c_s(f_max)/f_max.
    * Fuente: >= 10 muestras sobre el FWHM de la distribución de fuerza
      [Palmeri2017, sec. "Mesh resolution"] (se relaja a 4 si exige más de 4x celdas).
    * Capas: al menos 4 celdas por capa finita.
    """
    if settings.cell_mm > 0:
        return settings.cell_mm * 1e-3, {"usuario": settings.cell_mm}
    fmax = settings.f_max_hz or source_fmax(exc)
    solids = solid_materials(geom.materials())
    cs_min = min(m.cs_kv(fmax) for m in solids)
    limits = {"dispersion_mm": cs_min / fmax / settings.ppw * 1e3}
    width = characteristic_width_mm(exc, 0.0) or 1.0
    limits["fuente_mm"] = width / 10.0
    finite = [layer.thickness_mm for layer in geom.layers if layer.thickness_mm > 0]
    if finite:
        limits["capas_mm"] = min(finite) / 4.0
    h_mm = min(limits["dispersion_mm"], limits.get("capas_mm", np.inf))
    if limits["fuente_mm"] < h_mm:
        h_mm = max(limits["fuente_mm"], h_mm / 2.0)
    limits["f_max_hz"] = fmax
    return h_mm * 1e-3, limits


def build_grid(geom: Geometry, h: float, settings: FDTDSettings,
               progress: ProgressFn | None = None) -> Grid:
    """Discretiza la geometría en nodos normales (ids de material, aire = 0)."""
    L = settings.pml_cells
    hm = h * 1e3
    absorb_lat = geom.lateral == "absorbente"
    absorb_bot = geom.bottom == "absorbente"
    pad_lat = L if absorb_lat else 2
    nx = int(round(geom.size_x_mm / hm)) + 1 + 2 * pad_lat
    ny = int(round(geom.size_y_mm / hm)) + 1 + 2 * pad_lat
    n_air = 3
    nz_sample = int(round(geom.size_z_mm / hm)) + 1
    nz = n_air + nz_sample + (L if absorb_bot else 2)
    if nx * ny * nz > settings.max_cells:
        raise ValueError(f"La malla tiene {nx * ny * nz / 1e6:.1f} M celdas (> {settings.max_cells / 1e6:.0f} M). "
                         "Aumente la celda o reduzca el dominio.")
    x0 = -geom.size_x_mm / 2 * 1e-3 - pad_lat * h
    y0 = -geom.size_y_mm / 2 * 1e-3 - pad_lat * h
    z0 = -n_air * h
    xs = (x0 + np.arange(nx) * h) * 1e3
    ys = (y0 + np.arange(ny) * h) * 1e3
    zs = (z0 + np.arange(nz) * h) * 1e3
    xh, yh = geom.size_x_mm / 2, geom.size_y_mm / 2
    eps = 1e-9
    ids = np.zeros((nx, ny, nz), dtype=np.uint8)
    Y, Z = np.meshgrid(ys, zs, indexing="ij")
    for i in range(nx):
        x = xs[i]
        xe = np.clip(x, -xh + eps, xh - eps) if absorb_lat else x
        ye = np.clip(Y, -yh + eps, yh - eps) if absorb_lat else Y
        ze = np.minimum(Z, geom.size_z_mm - eps) if absorb_bot else Z
        col = geom.material_id_map(np.full_like(Y, xe), ye, ze)
        if geom.lateral == "empotrado":
            outside = ~geom.in_footprint(np.full_like(Y, x), Y)
            zsurf = geom.surface_z(np.clip(x, -xh, xh), np.clip(Y, -yh, yh))
            col[outside & (Z >= zsurf) & (Z <= geom.size_z_mm)] = RIGID_ID
        if geom.bottom == "rigido":
            col[(Z > geom.size_z_mm) & (np.abs(Y) <= yh + eps) & (abs(x) <= xh + eps)] = RIGID_ID
        ids[i] = col
        if progress and i % max(1, nx // 10) == 0:
            progress(0.02 * i / nx, "Discretizando la geometría")
    pml = {"x": (L, L) if absorb_lat else (0, 0), "y": (L, L) if absorb_lat else (0, 0),
           "z": (0, L if absorb_bot else 0)}
    mats = geom.materials()
    return Grid(h, nx, ny, nz, x0, y0, z0, pml, ids, mats, auto_fluid_speed(mats))


# --------------------------------------------------------------------------------------
# Propiedades efectivas en la malla
# --------------------------------------------------------------------------------------
def material_tables(grid: Grid, carrier_hz: float) -> dict[str, np.ndarray]:
    n = 256
    lam = np.zeros(n, np.float64)
    mu = np.zeros(n, np.float64)
    eta = np.zeros(n, np.float64)
    rho = np.zeros(n, np.float64)
    alpha = np.zeros(n, np.float64)
    cac = np.ones(n, np.float64)
    for idx, m in enumerate(grid.materials, start=1):
        lam[idx] = m.lam(grid.c_fluid)
        mu[idx] = m.mu
        eta[idx] = m.eta
        rho[idx] = m.rho
        alpha[idx] = m.alpha_np_per_m(carrier_hz)
        cac[idx] = m.c_acoustic
    return {"lam": lam, "mu": mu, "eta": eta, "rho": rho, "alpha": alpha, "c": cac}


def _harmonic4(xp, a, b, c, d):
    """Promedio armónico de 4 valores; 0 si alguno es 0 [Graves1996; Moczo2002]."""
    pos = (a > 0) & (b > 0) & (c > 0) & (d > 0)
    safe = lambda v: xp.where(v > 0, v, 1.0)  # noqa: E731
    hm = 4.0 / (1.0 / safe(a) + 1.0 / safe(b) + 1.0 / safe(c) + 1.0 / safe(d))
    return xp.where(pos, hm, 0.0)


def effective_arrays(xp, ids, tables: dict[str, np.ndarray]) -> dict[str, Any]:
    """lam, mu, eta en nodos normales; mu/eta armónicos en nodos de corte;
    flotabilidad b = 1/rho con rho aritmético en nodos de velocidad."""
    ids_d = xp.asarray(ids)
    lut = {k: xp.asarray(v, dtype=xp.float32) for k, v in tables.items()}
    rigid = ids_d == RIGID_ID
    lam = lut["lam"][ids_d]
    mu = lut["mu"][ids_d]
    eta = lut["eta"][ids_d]
    rho = lut["rho"][ids_d]
    # Nodos rígidos: sin esfuerzo propio; en promedios cuentan como mu muy grande.
    big = float(max(tables["mu"].max(), 1.0) * 1e6)
    mu_avg = xp.where(rigid, big, mu)
    eta_avg = xp.where(rigid, float(max(tables["eta"].max(), 0.0) * 1e6 + 1e-30), eta)
    lam = xp.where(rigid, 0.0, lam).astype(xp.float32)
    mu = xp.where(rigid, 0.0, mu).astype(xp.float32)
    eta = xp.where(rigid, 0.0, eta).astype(xp.float32)
    out: dict[str, Any] = {"lam": lam, "mu": mu, "eta": eta}

    def shear(a: Any, ax1: int, ax2: int) -> Any:
        s = xp.zeros_like(a)
        sl = [slice(None)] * 3
        def sh(d1: int, d2: int) -> Any:
            idx = [slice(None)] * 3
            idx[ax1] = slice(d1, a.shape[ax1] - 1 + d1)
            idx[ax2] = slice(d2, a.shape[ax2] - 1 + d2)
            return a[tuple(idx)]
        sl[ax1] = slice(0, a.shape[ax1] - 1)
        sl[ax2] = slice(0, a.shape[ax2] - 1)
        s[tuple(sl)] = _harmonic4(xp, sh(0, 0), sh(1, 0), sh(0, 1), sh(1, 1))
        return s.astype(xp.float32)

    out["mxy"] = shear(mu_avg, 0, 1)
    out["mxz"] = shear(mu_avg, 0, 2)
    out["myz"] = shear(mu_avg, 1, 2)
    out["exy"] = shear(eta_avg, 0, 1)
    out["exz"] = shear(eta_avg, 0, 2)
    out["eyz"] = shear(eta_avg, 1, 2)
    # mu de corte de nodos adyacentes a rígido: limitar al valor de los sólidos
    mmax = float(tables["mu"].max())
    emax = float(tables["eta"].max())
    for key, cap in (("mxy", mmax), ("mxz", mmax), ("myz", mmax), ("exy", emax), ("exz", emax), ("eyz", emax)):
        out[key] = xp.minimum(out[key], 4.0 * cap).astype(xp.float32)

    def buoy(axis: int) -> Any:
        b = xp.zeros_like(rho, dtype=xp.float32)
        a0 = [slice(None)] * 3
        a1 = [slice(None)] * 3
        a0[axis] = slice(0, rho.shape[axis] - 1)
        a1[axis] = slice(1, rho.shape[axis])
        r_avg = 0.5 * (rho[tuple(a0)] + rho[tuple(a1)])
        rg = rigid[tuple(a0)] | rigid[tuple(a1)]
        val = xp.where((r_avg > 0) & ~rg, 1.0 / xp.where(r_avg > 0, r_avg, 1.0), 0.0)
        b[tuple(a0)] = val.astype(xp.float32)
        return b

    out["bx"] = buoy(0)
    out["by"] = buoy(1)
    out["bz"] = buoy(2)
    return out


# --------------------------------------------------------------------------------------
# C-PML
# --------------------------------------------------------------------------------------
def cpml_axis(n: int, lo: int, hi: int, h: float, dt: float, cp_max: float, R: float,
              alpha_max: float, N: int = 2) -> tuple[np.ndarray, np.ndarray]:
    """Coeficientes [aI, bI, kinvI, aH, bH, kinvH] (6n) e índices comprimidos [cI, cH] (2n).

    Perfiles y recursión de [Komatitsch2007] (kappa_max = 1).
    """
    coef = np.zeros((6, n), np.float32)
    coef[2] = 1.0
    coef[5] = 1.0
    cidx = -np.ones((2, n), np.int32)
    if lo == 0 and hi == 0:
        return coef.ravel(), cidx.ravel()
    pos_i = np.arange(n, dtype=float)
    pos_h = pos_i + 0.5
    edge_lo = float(lo)
    edge_hi = float(n - 1 - hi)
    width_lo = max(lo, 1) * h
    width_hi = max(hi, 1) * h
    for row, pos in ((0, pos_i), (3, pos_h)):
        dist = np.zeros(n)
        if lo:
            m = pos < edge_lo
            dist[m] = (edge_lo - pos[m]) * h / width_lo
        if hi:
            m = pos > edge_hi
            dist[m] = (pos[m] - edge_hi) * h / width_hi
        dist = np.clip(dist, 0, 1)
        L = np.where(pos < edge_lo, width_lo, width_hi)
        d0 = -(N + 1) * cp_max * log(R) / (2 * L)
        d = d0 * dist**N
        alpha = alpha_max * (1 - dist)
        b = np.exp(-(d + alpha) * dt)
        a = np.where(d > 0, d * (b - 1) / (d + alpha + 1e-30), 0.0)
        inside = dist > 0
        coef[row] = np.where(inside, a, 0.0)
        coef[row + 1] = np.where(inside, b, 0.0)
    # índices comprimidos (bajo: [0, lo); alto: [lo, lo + hi))
    for i in range(n):
        if i < lo:
            cidx[0, i] = i
            cidx[1, i] = i
        if hi and i >= n - hi:
            cidx[0, i] = lo + i - (n - hi)
        if hi and n - 1 - hi <= i <= n - 2:
            cidx[1, i] = lo + i - (n - 1 - hi)
    return coef.ravel(), cidx.ravel()


# --------------------------------------------------------------------------------------
# Kernels CUDA
# --------------------------------------------------------------------------------------
CUDA_SOURCE = r"""
#define IDX(i,j,k) ((((size_t)(i))*NY + (size_t)(j))*NZ + (size_t)(k))

__device__ __forceinline__ float pml_x(float d, int c, int i, int j, int k, int half, int m,
    const float* __restrict__ f, float* __restrict__ psi, int NX, int NY, int NZ, int LX) {
  if (c < 0) return d;
  int o = half ? 3*NX : 0;
  float a = f[o + i], b = f[o + NX + i], kinv = f[o + 2*NX + i];
  size_t q = (size_t)m*((size_t)LX*NY*NZ) + (((size_t)c)*NY + j)*NZ + k;
  float ps = b*psi[q] + a*d; psi[q] = ps;
  return d*kinv + ps;
}
__device__ __forceinline__ float pml_y(float d, int c, int i, int j, int k, int half, int m,
    const float* __restrict__ f, float* __restrict__ psi, int NX, int NY, int NZ, int LY) {
  if (c < 0) return d;
  int o = half ? 3*NY : 0;
  float a = f[o + j], b = f[o + NY + j], kinv = f[o + 2*NY + j];
  size_t q = (size_t)m*((size_t)NX*LY*NZ) + (((size_t)i)*LY + c)*NZ + k;
  float ps = b*psi[q] + a*d; psi[q] = ps;
  return d*kinv + ps;
}
__device__ __forceinline__ float pml_z(float d, int c, int i, int j, int k, int half, int m,
    const float* __restrict__ f, float* __restrict__ psi, int NX, int NY, int NZ, int LZ) {
  if (c < 0) return d;
  int o = half ? 3*NZ : 0;
  float a = f[o + k], b = f[o + NZ + k], kinv = f[o + 2*NZ + k];
  size_t q = (size_t)m*((size_t)NX*NY*LZ) + (((size_t)i)*NY + j)*LZ + c;
  float ps = b*psi[q] + a*d; psi[q] = ps;
  return d*kinv + ps;
}

extern "C" __global__ void vel_kernel(
    float* __restrict__ vx, float* __restrict__ vy, float* __restrict__ vz,
    const float* __restrict__ sxx, const float* __restrict__ syy, const float* __restrict__ szz,
    const float* __restrict__ sxy, const float* __restrict__ sxz, const float* __restrict__ syz,
    const float* __restrict__ bx, const float* __restrict__ by, const float* __restrict__ bz,
    const int* __restrict__ cx, const int* __restrict__ cy, const int* __restrict__ cz,
    const float* __restrict__ fx, const float* __restrict__ fy, const float* __restrict__ fz,
    float* __restrict__ psx, float* __restrict__ psy, float* __restrict__ psz,
    const int NX, const int NY, const int NZ, const int LX, const int LY, const int LZ,
    const float dt, const float ih)
{
  int k = blockIdx.x*blockDim.x + threadIdx.x;
  int j = blockIdx.y*blockDim.y + threadIdx.y;
  int i = blockIdx.z*blockDim.z + threadIdx.z;
  if (i < 1 || j < 1 || k < 1 || i > NX-2 || j > NY-2 || k > NZ-2) return;
  size_t id = IDX(i,j,k);
  float b;
  b = bx[id];
  if (b != 0.0f) {
    float d1 = (sxx[IDX(i+1,j,k)] - sxx[id])*ih;
    float d2 = (sxy[id] - sxy[IDX(i,j-1,k)])*ih;
    float d3 = (sxz[id] - sxz[IDX(i,j,k-1)])*ih;
    d1 = pml_x(d1, cx[NX+i], i,j,k, 1, 0, fx, psx, NX,NY,NZ,LX);
    d2 = pml_y(d2, cy[j],    i,j,k, 0, 0, fy, psy, NX,NY,NZ,LY);
    d3 = pml_z(d3, cz[k],    i,j,k, 0, 0, fz, psz, NX,NY,NZ,LZ);
    vx[id] += dt*b*(d1 + d2 + d3);
  }
  b = by[id];
  if (b != 0.0f) {
    float d1 = (sxy[id] - sxy[IDX(i-1,j,k)])*ih;
    float d2 = (syy[IDX(i,j+1,k)] - syy[id])*ih;
    float d3 = (syz[id] - syz[IDX(i,j,k-1)])*ih;
    d1 = pml_x(d1, cx[i],    i,j,k, 0, 1, fx, psx, NX,NY,NZ,LX);
    d2 = pml_y(d2, cy[NY+j], i,j,k, 1, 1, fy, psy, NX,NY,NZ,LY);
    d3 = pml_z(d3, cz[k],    i,j,k, 0, 1, fz, psz, NX,NY,NZ,LZ);
    vy[id] += dt*b*(d1 + d2 + d3);
  }
  b = bz[id];
  if (b != 0.0f) {
    float d1 = (sxz[id] - sxz[IDX(i-1,j,k)])*ih;
    float d2 = (syz[id] - syz[IDX(i,j-1,k)])*ih;
    float d3 = (szz[IDX(i,j,k+1)] - szz[id])*ih;
    d1 = pml_x(d1, cx[i],    i,j,k, 0, 2, fx, psx, NX,NY,NZ,LX);
    d2 = pml_y(d2, cy[j],    i,j,k, 0, 2, fy, psy, NX,NY,NZ,LY);
    d3 = pml_z(d3, cz[NZ+k], i,j,k, 1, 2, fz, psz, NX,NY,NZ,LZ);
    vz[id] += dt*b*(d1 + d2 + d3);
  }
}

extern "C" __global__ void stress_kernel(
    const float* __restrict__ vx, const float* __restrict__ vy, const float* __restrict__ vz,
    float* __restrict__ sxx, float* __restrict__ syy, float* __restrict__ szz,
    float* __restrict__ sxy, float* __restrict__ sxz, float* __restrict__ syz,
    float* __restrict__ exx, float* __restrict__ eyy, float* __restrict__ ezz,
    float* __restrict__ exy, float* __restrict__ exz, float* __restrict__ eyz,
    const float* __restrict__ lam, const float* __restrict__ mu, const float* __restrict__ eta,
    const float* __restrict__ mxy, const float* __restrict__ mxz, const float* __restrict__ myz,
    const float* __restrict__ nxy, const float* __restrict__ nxz, const float* __restrict__ nyz,
    const int* __restrict__ cx, const int* __restrict__ cy, const int* __restrict__ cz,
    const float* __restrict__ fx, const float* __restrict__ fy, const float* __restrict__ fz,
    float* __restrict__ psx, float* __restrict__ psy, float* __restrict__ psz,
    const int NX, const int NY, const int NZ, const int LX, const int LY, const int LZ,
    const float dt, const float ih)
{
  int k = blockIdx.x*blockDim.x + threadIdx.x;
  int j = blockIdx.y*blockDim.y + threadIdx.y;
  int i = blockIdx.z*blockDim.z + threadIdx.z;
  if (i < 1 || j < 1 || k < 1 || i > NX-2 || j > NY-2 || k > NZ-2) return;
  size_t id = IDX(i,j,k);
  float L = lam[id], M = mu[id];
  if (L != 0.0f || M != 0.0f) {
    float e1 = (vx[id] - vx[IDX(i-1,j,k)])*ih;
    float e2 = (vy[id] - vy[IDX(i,j-1,k)])*ih;
    float e3 = (vz[id] - vz[IDX(i,j,k-1)])*ih;
    e1 = pml_x(e1, cx[i], i,j,k, 0, 3, fx, psx, NX,NY,NZ,LX);
    e2 = pml_y(e2, cy[j], i,j,k, 0, 3, fy, psy, NX,NY,NZ,LY);
    e3 = pml_z(e3, cz[k], i,j,k, 0, 3, fz, psz, NX,NY,NZ,LZ);
    float tr = e1 + e2 + e3;
    float E2 = 2.0f*eta[id], M2 = 2.0f*M;
    float a = exx[id] + dt*(L*tr + M2*e1); exx[id] = a; sxx[id] = a + E2*e1;
    a = eyy[id] + dt*(L*tr + M2*e2); eyy[id] = a; syy[id] = a + E2*e2;
    a = ezz[id] + dt*(L*tr + M2*e3); ezz[id] = a; szz[id] = a + E2*e3;
  }
  float G = mxy[id];
  if (G != 0.0f) {
    float g1 = (vx[IDX(i,j+1,k)] - vx[id])*ih;
    float g2 = (vy[IDX(i+1,j,k)] - vy[id])*ih;
    g1 = pml_y(g1, cy[NY+j], i,j,k, 1, 4, fy, psy, NX,NY,NZ,LY);
    g2 = pml_x(g2, cx[NX+i], i,j,k, 1, 4, fx, psx, NX,NY,NZ,LX);
    float s = g1 + g2;
    float a = exy[id] + dt*G*s; exy[id] = a; sxy[id] = a + nxy[id]*s;
  }
  G = mxz[id];
  if (G != 0.0f) {
    float g1 = (vx[IDX(i,j,k+1)] - vx[id])*ih;
    float g2 = (vz[IDX(i+1,j,k)] - vz[id])*ih;
    g1 = pml_z(g1, cz[NZ+k], i,j,k, 1, 4, fz, psz, NX,NY,NZ,LZ);
    g2 = pml_x(g2, cx[NX+i], i,j,k, 1, 5, fx, psx, NX,NY,NZ,LX);
    float s = g1 + g2;
    float a = exz[id] + dt*G*s; exz[id] = a; sxz[id] = a + nxz[id]*s;
  }
  G = myz[id];
  if (G != 0.0f) {
    float g1 = (vy[IDX(i,j,k+1)] - vy[id])*ih;
    float g2 = (vz[IDX(i,j+1,k)] - vz[id])*ih;
    g1 = pml_z(g1, cz[NZ+k], i,j,k, 1, 5, fz, psz, NX,NY,NZ,LZ);
    g2 = pml_y(g2, cy[NY+j], i,j,k, 1, 5, fy, psy, NX,NY,NZ,LY);
    float s = g1 + g2;
    float a = eyz[id] + dt*G*s; eyz[id] = a; syz[id] = a + nyz[id]*s;
  }
}

extern "C" __global__ void source_kernel(
    float* __restrict__ vz, const float* __restrict__ bz,
    const long long* __restrict__ idx, const float* __restrict__ w, const int* __restrict__ grp,
    const float* __restrict__ amp, const int nsrc, const float dt)
{
  int s = blockIdx.x*blockDim.x + threadIdx.x;
  if (s >= nsrc) return;
  long long id = idx[s];
  atomicAdd(&vz[id], dt*bz[id]*w[s]*amp[grp[s]]);
}
"""


# --------------------------------------------------------------------------------------
# Fuentes
# --------------------------------------------------------------------------------------
@dataclass
class SourceSet:
    index: np.ndarray       # índices planos de nodos vz (int64)
    weight: np.ndarray      # densidad de fuerza pico (N/m^3) por nodo
    group: np.ndarray       # grupo (fase) de cada nodo
    n_groups: int
    description: str


def surface_k_index(ids: np.ndarray) -> np.ndarray:
    """Para cada columna (i, j), índice k del nodo vz de la interfaz aire/sólido
    (entre el último nodo de aire k y el primer nodo sólido k+1); -1 si no hay."""
    solid = (ids != AIR_ID) & (ids != RIGID_ID)
    first = np.argmax(solid, axis=2)
    has = solid.any(axis=2)
    k = first - 1
    k[~has | (first == 0)] = -1
    return k


def build_sources(grid: Grid, geom: Geometry, exc: ExcitationConfig,
                  tables: dict[str, np.ndarray]) -> SourceSet:
    h = grid.h
    hm = h * 1e3
    xs = grid.x() * 1e3
    ys = grid.y() * 1e3
    zh = grid.z(half=True) * 1e3      # profundidad de nodos vz (mm)
    X, Y = np.meshgrid(xs, ys, indexing="ij")
    centers = source_centers_mm(exc)
    ksurf = surface_k_index(grid.ids)
    p0 = exc.pressure_MPa * 1e6
    idx_list, w_list, g_list = [], [], []
    top = geom.layers[0].material
    for g, (cx, cy) in enumerate(centers):
        S = lateral_shape(exc, X, Y, cx, cy, hm)
        cols = np.argwhere((S > 1e-3) & (ksurf >= 0))
        if cols.size == 0:
            continue
        if exc.mode == "arf_contacto":
            # Fuerza de volumen 2 alpha I / c [Palmeri2017, Ec. (1)]
            zf = float(geom.surface_z(cx, cy)) + exc.focal_depth_mm
            ids_cols = grid.ids[cols[:, 0], cols[:, 1], :]            # (ncol, nz)
            alpha = tables["alpha"][ids_cols]                         # Np/m por nodo
            c_ac = tables["c"][ids_cols]
            solid = (ids_cols != AIR_ID) & (ids_cols != RIGID_ID)
            # atenuación de intensidad acumulada desde el foco: exp(-2 int alpha dz)
            cum = np.cumsum(alpha * h, axis=1)
            kf = int(np.clip(np.searchsorted(zh, zf), 0, grid.nz - 1))
            atten = np.exp(-2.0 * (cum - cum[:, kf:kf + 1]))
            gz = np.exp(-4 * log(2) * (zh[None, :] - zf) ** 2 / max(exc.dof_mm, hm) ** 2)
            I0 = acoustic_intensity(p0, top.rho, top.c_acoustic)       # [Kinsler2000]
            # nodo vz (k+1/2) sólido si ambos vecinos normales son sólidos
            solid_v = solid.copy()
            solid_v[:, :-1] &= solid[:, 1:]
            F = 2.0 * alpha * I0 * S[cols[:, 0], cols[:, 1]][:, None] * gz * atten / c_ac
            F = np.where(solid_v, F, 0.0)
            sel = np.nonzero(F > F.max() * 1e-3)
            ii = cols[sel[0], 0]
            jj = cols[sel[0], 1]
            kk = sel[1]
            idx_list.append((ii.astype(np.int64) * grid.ny + jj) * grid.nz + kk)
            w_list.append(F[sel])
            g_list.append(np.full(ii.size, g, np.int32))
        else:
            ii, jj = cols[:, 0], cols[:, 1]
            kk = ksurf[ii, jj]
            if exc.mode == "arf_sin_contacto":
                P = radiation_pressure_air(p0, top)                   # [Ambrozinski2016]
            else:
                P = p0                                                # esfuerzo de contacto
            # tracción superficial como fuerza de volumen equivalente P/h en una celda
            w = P * S[ii, jj] / h
            idx_list.append((ii.astype(np.int64) * grid.ny + jj) * grid.nz + kk)
            w_list.append(w)
            g_list.append(np.full(ii.size, g, np.int32))
    if not idx_list:
        raise ValueError("La excitación no toca la muestra: revise posición y tamaño.")
    index = np.concatenate(idx_list)
    weight = np.concatenate(w_list).astype(np.float64)
    group = np.concatenate(g_list)
    desc = f"{index.size} nodos fuente en {len(centers)} grupo(s); F pico = {weight.max():.4g} N/m³"
    return SourceSet(index, weight, group, len(centers), desc)


# --------------------------------------------------------------------------------------
# Registro de campos
# --------------------------------------------------------------------------------------
@dataclass
class RecordRegion:
    i: tuple[int, int, int]     # inicio, fin, paso
    j: tuple[int, int, int]
    k: tuple[int, int]

    def view(self, a: Any) -> Any:
        return a[self.i[0]:self.i[1]:self.i[2], self.j[0]:self.j[1]:self.j[2], self.k[0]:self.k[1]]

    def shape(self) -> tuple[int, int, int]:
        ni = len(range(*self.i))
        nj = len(range(*self.j))
        return (ni, nj, self.k[1] - self.k[0])


@dataclass
class FieldRecord:
    """Campo de desplazamiento u_z registrado (verdad del FDTD)."""

    regime: str
    x_m: np.ndarray             # coordenadas del registro (nodos vz)
    y_m: np.ndarray
    z_m: np.ndarray
    times_s: np.ndarray | None = None          # transitorio: [nt]
    uz: np.ndarray | None = None               # transitorio: [nt, nx, ny, nz] float32
    freq_hz: float = 0.0                       # armónico
    U: dict[int, np.ndarray] = field(default_factory=dict)   # armónico h -> [nx, ny, nz] complejo
    slice_x_m: np.ndarray | None = None        # corte xz central (dominio completo)
    slice_z_m: np.ndarray | None = None
    slice_uz: np.ndarray | None = None         # [nt, nx, nz] o None
    slice_U: dict[int, np.ndarray] = field(default_factory=dict)
    slice_ids: np.ndarray | None = None
    surface_k: np.ndarray | None = None        # índice k de superficie en el registro [nx, ny]
    info: dict[str, Any] = field(default_factory=dict)

    # ------------------------------------------------------------------ caché
    def save(self, path: Any, key: str) -> None:
        import json  # noqa: PLC0415
        data: dict[str, Any] = {"key": np.array(key), "regime": np.array(self.regime),
                                "x_m": self.x_m, "y_m": self.y_m, "z_m": self.z_m,
                                "freq_hz": np.array(self.freq_hz), "slice_x_m": self.slice_x_m,
                                "slice_z_m": self.slice_z_m, "slice_ids": self.slice_ids,
                                "surface_k": self.surface_k,
                                "info": np.array(json.dumps(self.info, default=str))}
        if self.regime == "transitorio":
            data.update(times_s=self.times_s, uz=self.uz, slice_uz=self.slice_uz)
        else:
            for h, U in self.U.items():
                data[f"U{h}"] = U
                data[f"SU{h}"] = self.slice_U[h]
        np.savez(path, **data)

    @classmethod
    def load(cls, path: Any, key: str) -> "FieldRecord | None":
        import json  # noqa: PLC0415
        try:
            d = np.load(path, allow_pickle=False)
        except (OSError, ValueError):
            return None
        if str(d["key"]) != key:
            return None
        rec = cls(regime=str(d["regime"]), x_m=d["x_m"], y_m=d["y_m"], z_m=d["z_m"],
                  freq_hz=float(d["freq_hz"]), slice_x_m=d["slice_x_m"], slice_z_m=d["slice_z_m"],
                  slice_ids=d["slice_ids"], surface_k=d["surface_k"], info=json.loads(str(d["info"])))
        if rec.regime == "transitorio":
            rec.times_s, rec.uz, rec.slice_uz = d["times_s"], d["uz"], d["slice_uz"]
        else:
            for name in d.files:
                if name.startswith("U"):
                    h = int(name[1:])
                    rec.U[h] = d[name]
                    rec.slice_U[h] = d[f"SU{h}"]
        rec.info["desde_cache"] = True
        return rec

    def uz_harmonic(self, t: np.ndarray | float, region: tuple[slice, ...] = ()) -> np.ndarray:
        """u_z(t) = Re sum_h U_h exp(i h w t) para el régimen armónico."""
        w = 2 * pi * self.freq_hz
        out = 0.0
        for hk, Uh in self.U.items():
            arr = Uh[region] if region else Uh
            out = out + np.real(arr * np.exp(1j * hk * w * t))
        return out


# --------------------------------------------------------------------------------------
# Solver
# --------------------------------------------------------------------------------------
class FDTDSolver:
    def __init__(self, geom: Geometry, exc: ExcitationConfig, settings: FDTDSettings,
                 record_box_mm: tuple[float, float, float, float],
                 progress: ProgressFn | None = None, cancel: Event | None = None):
        self.geom = geom
        self.exc = exc
        self.settings = settings
        self.progress = progress or (lambda f, m: None)
        self.cancel = cancel or Event()
        self.backend: Backend = get_backend(settings.backend)
        self.h, self.h_limits = choose_cell_size(geom, exc, settings)
        self.grid = build_grid(geom, self.h, settings, self.progress)
        self.tables = material_tables(self.grid, exc.carrier_hz)
        mats = self.grid.materials
        self.dt_max = stable_dt(mats, self.h, self.grid.c_fluid, settings.courant)
        self.sources = build_sources(self.grid, geom, exc, self.tables)
        self.region = self._record_region(record_box_mm)
        self.warnings: list[str] = []
        width = characteristic_width_mm(exc, self.h * 1e3)
        if width / (self.h * 1e3) < 10:
            self.warnings.append(
                f"La fuente tiene {width / (self.h * 1e3):.1f} muestras por FWHM (< 10 recomendadas "
                "[Palmeri2017]); la distribución de fuerza queda sub-muestreada.")

    # ------------------------------------------------------------------ utilidades
    def _record_region(self, box: tuple[float, float, float, float]) -> RecordRegion:
        g = self.grid
        s = self.settings
        hm = g.h * 1e3
        xmin, xmax, ymin, ymax = box
        m = s.record_margin_mm
        xs = g.x() * 1e3
        ys = g.y() * 1e3
        i0 = int(np.clip(np.searchsorted(xs, xmin - m) - 1, 1, g.nx - 2))
        i1 = int(np.clip(np.searchsorted(xs, xmax + m) + 1, i0 + 1, g.nx - 1))
        j0 = int(np.clip(np.searchsorted(ys, ymin - m) - 1, 1, g.ny - 2))
        j1 = int(np.clip(np.searchsorted(ys, ymax + m) + 1, j0 + 1, g.ny - 1))
        stride = s.record_stride
        if stride <= 0:
            stride = max(1, int(round(0.04 / hm)))   # ~40 um entre muestras registradas
        xx, yy = np.meshgrid(np.linspace(xmin, xmax, 9), np.linspace(ymin, ymax, 9))
        zs_max = float(self.geom.surface_z(xx, yy).max())
        zh = g.z(half=True) * 1e3
        k0 = int(np.clip(np.searchsorted(zh, 0.0) - 2, 1, g.nz - 2))   # el ápice está en z = 0
        k1 = int(np.clip(np.searchsorted(zh, zs_max + s.record_depth_mm) + 1, k0 + 1, g.nz - 1))
        return RecordRegion((i0, i1, stride), (j0, j1, stride), (k0, k1))

    def memory_bytes(self) -> int:
        g = self.grid
        n = g.cells
        L = self.settings.pml_cells
        psi = 6 * 4 * (2 * L * g.ny * g.nz * (g.pml["x"][0] > 0) + 2 * L * g.nx * g.nz * (g.pml["y"][0] > 0)
                       + L * g.nx * g.ny * (g.pml["z"][1] > 0))
        return int(n * 4 * 28 + psi + np.prod(self.region.shape()) * 4 * 4)

    def describe(self) -> dict[str, Any]:
        g = self.grid
        return {
            "backend": self.backend.describe(),
            "celda_mm": g.h * 1e3,
            "restricciones_celda": self.h_limits,
            "malla": [g.nx, g.ny, g.nz],
            "celdas_M": g.cells / 1e6,
            "dt_max_us": self.dt_max * 1e6,
            "c_fluido_sim": g.c_fluid,
            "memoria_GB": self.memory_bytes() / 2**30,
            "fuentes": self.sources.description,
            "registro": self.region.shape(),
            "pml": g.pml,
        }

    def _check_cancel(self) -> None:
        if self.cancel.is_set():
            raise SimulationCancelled("Simulación cancelada por el usuario.")

    # ------------------------------------------------------------------ inicialización
    def _allocate(self, dt: float, alpha_max: float) -> None:
        xp = self.backend.xp
        g = self.grid
        shape = g.shape
        self.dt = dt
        self.f = {name: xp.zeros(shape, dtype=xp.float32)
                  for name in ("vx", "vy", "vz", "sxx", "syy", "szz", "sxy", "sxz", "syz",
                               "exx", "eyy", "ezz", "exy", "exz", "eyz")}
        self.m = effective_arrays(xp, g.ids, self.tables)
        cp_max = max(m.cp(g.c_fluid) for m in g.materials)
        coefs, cidx, Ls = {}, {}, {}
        for ax, n in (("x", g.nx), ("y", g.ny), ("z", g.nz)):
            lo, hi = g.pml[ax]
            c, ci = cpml_axis(n, lo, hi, g.h, dt, cp_max, self.settings.pml_R, alpha_max)
            coefs[ax] = xp.asarray(c)
            cidx[ax] = xp.asarray(ci)
            Ls[ax] = lo + hi
        self.coefs, self.cidx, self.L = coefs, cidx, Ls
        if self.backend.is_gpu:
            self.psi = {
                "x": xp.zeros(max(1, 6 * Ls["x"] * g.ny * g.nz), dtype=xp.float32),
                "y": xp.zeros(max(1, 6 * g.nx * Ls["y"] * g.nz), dtype=xp.float32),
                "z": xp.zeros(max(1, 6 * g.nx * g.ny * Ls["z"]), dtype=xp.float32),
            }
            import cupy as cp  # noqa: PLC0415
            module = cp.RawModule(code=CUDA_SOURCE, options=("--use_fast_math",))
            self._vel = module.get_function("vel_kernel")
            self._str = module.get_function("stress_kernel")
            self._src = module.get_function("source_kernel")
            self._block = (32, 4, 2)
            self._grid3 = (ceil(g.nz / 32), ceil(g.ny / 4), ceil(g.nx / 2))
        else:
            self._np_pml = self._numpy_pml_setup()
        self.src_idx = xp.asarray(self.sources.index.astype(np.int64))
        self.src_w = xp.asarray(self.sources.weight.astype(np.float32))
        self.src_g = xp.asarray(self.sources.group.astype(np.int32))

    def _numpy_pml_setup(self) -> dict[str, Any]:
        g = self.grid
        out = {}
        for ax, n in (("x", g.nx), ("y", g.ny), ("z", g.nz)):
            c = self.backend.asnumpy(self.coefs[ax]).reshape(6, n)
            shape = [1, 1, 1]
            shape[{"x": 0, "y": 1, "z": 2}[ax]] = n
            out[ax] = {"aI": c[0].reshape(shape), "bI": c[1].reshape(shape), "kI": c[2].reshape(shape),
                       "aH": c[3].reshape(shape), "bH": c[4].reshape(shape), "kH": c[5].reshape(shape)}
            out["psi_" + ax] = np.zeros((6,) + g.shape, dtype=np.float32)
        return out

    # ------------------------------------------------------------------ paso temporal
    def _step(self, amp: Any) -> None:
        if self.backend.is_gpu:
            self._step_gpu(amp)
        else:
            self._step_numpy(amp)

    def _step_gpu(self, amp: Any) -> None:
        import cupy as cp  # noqa: PLC0415
        g = self.grid
        f, m = self.f, self.m
        ints = (np.int32(g.nx), np.int32(g.ny), np.int32(g.nz),
                np.int32(self.L["x"]), np.int32(self.L["y"]), np.int32(self.L["z"]),
                np.float32(self.dt), np.float32(1.0 / g.h))
        pml = (self.cidx["x"], self.cidx["y"], self.cidx["z"],
               self.coefs["x"], self.coefs["y"], self.coefs["z"],
               self.psi["x"], self.psi["y"], self.psi["z"])
        self._vel(self._grid3, self._block,
                  (f["vx"], f["vy"], f["vz"], f["sxx"], f["syy"], f["szz"], f["sxy"], f["sxz"], f["syz"],
                   m["bx"], m["by"], m["bz"]) + pml + ints)
        nsrc = int(self.src_idx.size)
        self._src((ceil(nsrc / 256),), (256,),
                  (f["vz"], m["bz"], self.src_idx, self.src_w, self.src_g, amp,
                   np.int32(nsrc), np.float32(self.dt)))
        self._str(self._grid3, self._block,
                  (f["vx"], f["vy"], f["vz"], f["sxx"], f["syy"], f["szz"], f["sxy"], f["sxz"], f["syz"],
                   f["exx"], f["eyy"], f["ezz"], f["exy"], f["exz"], f["eyz"],
                   m["lam"], m["mu"], m["eta"], m["mxy"], m["mxz"], m["myz"],
                   m["exy"], m["exz"], m["eyz"]) + pml + ints)
        del cp

    def _step_numpy(self, amp: Any) -> None:
        """Implementación de referencia en NumPy (misma aritmética que los kernels)."""
        f, m, P = self.f, self.m, self._np_pml
        ih = np.float32(1.0 / self.grid.h)
        dt = np.float32(self.dt)
        I = slice(1, -1)
        C = (I, I, I)

        def pml(d: np.ndarray, ax: str, half: bool, mi: int) -> np.ndarray:
            c = P[ax]
            a = _crop(c["aH"] if half else c["aI"])
            b = _crop(c["bH"] if half else c["bI"])
            k = _crop(c["kH"] if half else c["kI"])
            psi = P["psi_" + ax][mi][C]
            psi *= b
            psi += a * d
            return d * k + psi

        sxx, syy, szz, sxy, sxz, syz = (f[n] for n in ("sxx", "syy", "szz", "sxy", "sxz", "syz"))
        # vx (i+1/2, j, k)
        d1 = pml((sxx[2:, 1:-1, 1:-1] - sxx[C]) * ih, "x", True, 0)
        d2 = pml((sxy[C] - sxy[1:-1, :-2, 1:-1]) * ih, "y", False, 0)
        d3 = pml((sxz[C] - sxz[1:-1, 1:-1, :-2]) * ih, "z", False, 0)
        f["vx"][C] += dt * m["bx"][C] * (d1 + d2 + d3)
        d1 = pml((sxy[C] - sxy[:-2, 1:-1, 1:-1]) * ih, "x", False, 1)
        d2 = pml((syy[1:-1, 2:, 1:-1] - syy[C]) * ih, "y", True, 1)
        d3 = pml((syz[C] - syz[1:-1, 1:-1, :-2]) * ih, "z", False, 1)
        f["vy"][C] += dt * m["by"][C] * (d1 + d2 + d3)
        d1 = pml((sxz[C] - sxz[:-2, 1:-1, 1:-1]) * ih, "x", False, 2)
        d2 = pml((syz[C] - syz[1:-1, :-2, 1:-1]) * ih, "y", False, 2)
        d3 = pml((szz[1:-1, 1:-1, 2:] - szz[C]) * ih, "z", True, 2)
        f["vz"][C] += dt * m["bz"][C] * (d1 + d2 + d3)
        # fuentes
        vz_flat = f["vz"].reshape(-1)
        bz_flat = m["bz"].reshape(-1)
        idx = self.src_idx
        np.add.at(vz_flat, idx, dt * bz_flat[idx] * self.src_w * amp[self.src_g])
        vx, vy, vz = f["vx"], f["vy"], f["vz"]
        # normales
        e1 = pml((vx[C] - vx[:-2, 1:-1, 1:-1]) * ih, "x", False, 3)
        e2 = pml((vy[C] - vy[1:-1, :-2, 1:-1]) * ih, "y", False, 3)
        e3 = pml((vz[C] - vz[1:-1, 1:-1, :-2]) * ih, "z", False, 3)
        tr = e1 + e2 + e3
        L, M2, E2 = m["lam"][C], 2 * m["mu"][C], 2 * m["eta"][C]
        for e_name, s_name, e in (("exx", "sxx", e1), ("eyy", "syy", e2), ("ezz", "szz", e3)):
            f[e_name][C] += dt * (L * tr + M2 * e)
            f[s_name][C] = f[e_name][C] + E2 * e
        g1 = pml((vx[1:-1, 2:, 1:-1] - vx[C]) * ih, "y", True, 4)
        g2 = pml((vy[2:, 1:-1, 1:-1] - vy[C]) * ih, "x", True, 4)
        s = g1 + g2
        f["exy"][C] += dt * m["mxy"][C] * s
        f["sxy"][C] = f["exy"][C] + m["exy"][C] * s
        g1 = pml((vx[1:-1, 1:-1, 2:] - vx[C]) * ih, "z", True, 4)
        g2 = pml((vz[2:, 1:-1, 1:-1] - vz[C]) * ih, "x", True, 5)
        s = g1 + g2
        f["exz"][C] += dt * m["mxz"][C] * s
        f["sxz"][C] = f["exz"][C] + m["exz"][C] * s
        g1 = pml((vy[1:-1, 1:-1, 2:] - vy[C]) * ih, "z", True, 5)
        g2 = pml((vz[1:-1, 2:, 1:-1] - vz[C]) * ih, "y", True, 5)
        s = g1 + g2
        f["eyz"][C] += dt * m["myz"][C] * s
        f["syz"][C] = f["eyz"][C] + m["eyz"][C] * s

    # ------------------------------------------------------------------ ejecución
    def _coords(self) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        g, r = self.grid, self.region
        return (g.x()[slice(*r.i)], g.y()[slice(*r.j)], g.z(half=True)[r.k[0]:r.k[1]])

    def _slice_index(self) -> int:
        g = self.grid
        cy = self.exc.center_y_mm * 1e-3
        return int(np.clip(np.argmin(np.abs(g.y() - cy)), 1, g.ny - 2))

    def run_transient(self, duration_s: float, record_dt_s: float) -> FieldRecord:
        xp = self.backend.xp
        n_sub = max(1, ceil(record_dt_s / self.dt_max))
        dt = record_dt_s / n_sub
        f_dom = max(self.exc.ch2_freq_hz, 200.0)
        self._allocate(dt, pi * f_dom)
        n_rec = int(ceil(duration_s / record_dt_s)) + 1
        n_steps = (n_rec - 1) * n_sub
        t_half = (np.arange(n_steps) + 0.5) * dt
        stf = transient_force_envelope(self.exc, t_half).astype(np.float32)   # [n_steps]
        rshape = self.region.shape()
        rec = np.zeros((n_rec,) + rshape, dtype=np.float32)
        uz_r = xp.zeros(rshape, dtype=xp.float32)
        jc = self._slice_index()
        k_all = slice(0, self.grid.nz)
        slice_rec = np.zeros((n_rec, self.grid.nx, self.grid.nz), dtype=np.float32)
        uz_slice = xp.zeros((self.grid.nx, self.grid.nz), dtype=xp.float32)
        stf_d = xp.asarray(stf)
        t0 = time.perf_counter()
        r = 0
        peak = 0.0
        for n in range(n_steps):
            if n % 200 == 0:
                self._check_cancel()
            self._step(stf_d[n:n + 1])      # un solo grupo: amplitud m(t)^2 del paso
            vz_view = self.region.view(self.f["vz"])
            uz_r += np.float32(dt) * vz_view
            uz_slice += np.float32(dt) * self.f["vz"][:, jc, k_all]
            if (n + 1) % n_sub == 0:
                r += 1
                rec[r] = self.backend.asnumpy(uz_r)
                slice_rec[r] = self.backend.asnumpy(uz_slice)
                if r % 10 == 0:
                    pk = float(np.abs(rec[r]).max())
                    if not np.isfinite(pk):
                        raise FloatingPointError("Inestabilidad numérica (NaN/Inf) en el FDTD.")
                    peak = max(peak, pk)
                    el = time.perf_counter() - t0
                    frac = (n + 1) / n_steps
                    eta_s = el / frac * (1 - frac)
                    self.progress(0.05 + 0.6 * frac,
                                  f"FDTD {frac * 100:4.1f} % (t = {(n + 1) * dt * 1e3:.2f} ms, "
                                  f"quedan ~{eta_s:.0f} s)")
        self.backend.synchronize()
        elapsed = time.perf_counter() - t0
        final = float(np.abs(rec[-1]).max())
        peak = max(peak, float(np.abs(rec).max()))
        x, y, z = self._coords()
        info = self.describe() | {"dt_us": dt * 1e6, "pasos": n_steps, "tiempo_s": elapsed,
                                  "residual_final_rel": final / peak if peak > 0 else 0.0,
                                  "advertencias": list(self.warnings)}
        if peak > 0 and final / peak > 0.2:
            self.warnings.append(
                f"Al final de la simulación el desplazamiento es {100 * final / peak:.0f} % del pico; "
                "la vibración residual no se extingue (ver superposición de disparos).")
        info["advertencias"] = list(self.warnings)
        return FieldRecord(
            regime="transitorio", x_m=x, y_m=y, z_m=z,
            times_s=np.arange(n_rec) * record_dt_s, uz=rec,
            slice_x_m=self.grid.x(), slice_z_m=self.grid.z(half=True), slice_uz=slice_rec,
            slice_ids=self.grid.ids[:, jc, :].copy(),
            surface_k=self._region_surface_k(), info=info)

    def run_harmonic(self) -> FieldRecord:
        xp = self.backend.xp
        s = self.settings
        f0 = self.exc.harmonic_hz
        T = 1.0 / f0
        n_per = max(8, ceil(T / self.dt_max))
        dt = T / n_per
        self._allocate(dt, pi * f0)
        phases = source_phases(self.exc)
        H = max(1, s.harmonics if self.exc.mode != "anillo_contactos" else 1)
        rshape = self.region.shape()
        jc = self._slice_index()
        W = s.harmonic_window_periods * n_per
        acc = {h: xp.zeros(rshape, dtype=xp.complex64) for h in range(1, H + 1)}
        acc_s = {h: xp.zeros((self.grid.nx, self.grid.nz), dtype=xp.complex64) for h in range(1, H + 1)}
        prev = None
        max_steps = s.harmonic_max_periods * n_per
        min_steps = s.harmonic_min_periods * n_per
        t0 = time.perf_counter()
        amp = xp.zeros(phases.size, dtype=xp.float32)
        converged = False
        w0 = 2 * pi * f0
        result_V: dict[int, Any] = {}
        result_S: dict[int, Any] = {}
        n = 0
        rel = np.inf
        while n < max_steps:
            if n % 200 == 0:
                self._check_cancel()
            t = (n + 0.5) * dt
            sig = harmonic_group_signals(self.exc, np.array([t]), phases)[:, 0]
            amp[...] = xp.asarray(sig.astype(np.float32))
            self._step(amp)
            # demodulación síncrona (DFT a h*f0 sobre un número entero de periodos) de la velocidad,
            # V_h = (2/W) sum v(t) exp(-i h w0 t) [Oppenheim2010]; t en el instante de vz: (n+1/2) dt
            vz_view = self.region.view(self.f["vz"])
            vz_sl = self.f["vz"][:, jc, :]
            for h in range(1, H + 1):
                ph = np.complex64(np.exp(-1j * h * w0 * t) * 2.0 / W)
                acc[h] += ph * vz_view
                acc_s[h] += ph * vz_sl
            n += 1
            if n % W == 0:
                V1 = self.backend.asnumpy(acc[1])
                if prev is not None:
                    num = np.linalg.norm(V1 - prev)
                    den = np.linalg.norm(V1) + 1e-30
                    rel = num / den
                    if not np.isfinite(den):
                        raise FloatingPointError("Inestabilidad numérica (NaN/Inf) en el FDTD.")
                    if n >= min_steps and rel < s.harmonic_tol:
                        converged = True
                result_V = {h: self.backend.asnumpy(acc[h]) for h in acc}
                result_S = {h: self.backend.asnumpy(acc_s[h]) for h in acc_s}
                prev = V1
                for h in acc:
                    acc[h].fill(0)
                    acc_s[h].fill(0)
                el = time.perf_counter() - t0
                self.progress(0.05 + 0.6 * min(1.0, n / max(min_steps, 1) * 0.5),
                              f"FDTD armónico: {n / n_per:.0f} periodos, cambio {rel * 100:.2f} % "
                              f"({el:.0f} s)")
                if converged:
                    break
        self.backend.synchronize()
        if not converged:
            self.warnings.append(
                f"El campo estacionario no convergió a {s.harmonic_tol * 100:.1f} % en "
                f"{s.harmonic_max_periods} periodos (último cambio {rel * 100:.2f} %).")
        # desplazamiento U_h = V_h / (i h w): derivada temporal en el dominio de Fourier [Oppenheim2010]
        U = {h: (result_V[h] / (1j * h * w0)).astype(np.complex64) for h in result_V}
        US = {h: (result_S[h] / (1j * h * w0)).astype(np.complex64) for h in result_S}
        x, y, z = self._coords()
        info = self.describe() | {"dt_us": dt * 1e6, "pasos": n, "periodos": n / n_per,
                                  "convergencia_rel": float(rel), "tiempo_s": time.perf_counter() - t0,
                                  "advertencias": list(self.warnings)}
        return FieldRecord(
            regime="armonico", x_m=x, y_m=y, z_m=z, freq_hz=f0, U=U,
            slice_x_m=self.grid.x(), slice_z_m=self.grid.z(half=True), slice_U=US,
            slice_ids=self.grid.ids[:, jc, :].copy(),
            surface_k=self._region_surface_k(), info=info)

    def _region_surface_k(self) -> np.ndarray:
        ks = surface_k_index(self.grid.ids)
        r = self.region
        sub = ks[slice(*r.i), slice(*r.j)]
        return sub - r.k[0]

    def release(self) -> None:
        for name in ("f", "m", "psi", "coefs", "cidx", "src_idx", "src_w", "src_g"):
            if hasattr(self, name):
                delattr(self, name)
        self.backend.free_memory()


def _crop(a: np.ndarray) -> np.ndarray:
    """Recorta un arreglo de coeficientes (forma n x 1 x 1, etc.) al interior [1:-1]."""
    sl = tuple(slice(1, -1) if s > 1 else slice(None) for s in a.shape)
    return a[sl]
