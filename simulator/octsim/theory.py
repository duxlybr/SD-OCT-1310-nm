"""Curvas de dispersión analíticas usadas como referencia de validación.

* Onda de corte Kelvin-Voigt ............. [Chen2004]
* Onda de Rayleigh (semiespacio libre) ... [Rayleigh1885]; viscoelástica por el
  principio de correspondencia (mu -> mu + i w eta) [Christensen1982]
* Lamb A0 en placa libre ................. [Lamb1917] (caso rho_f = 0 de la mRLFE)
* Lamb A0 en placa con fluido debajo ..... ecuación de Rayleigh-Lamb modificada
  (mRLFE) [Han2017], matriz 5x5 portada de repo:OCE_workflow/inherited/Codes/mRLFE.m
* Aproximaciones: c_R ~ 0.955 c_s [Singh2022, Ec. (12)], Scholte ~ 0.846 c_s
  [Singh2022, Ec. (13)], c_R ~ c_s (0.87+1.12 nu)/(1+nu) [Viktorov1967].
"""
from __future__ import annotations

from dataclasses import dataclass
from math import pi

import numpy as np
from scipy.optimize import brentq, minimize_scalar

from .materials import Material


# --------------------------------------------------------------------------------------
# Onda de corte
# --------------------------------------------------------------------------------------
def shear_phase_velocity(material: Material, f_hz: np.ndarray | float) -> np.ndarray:
    """c_s(w) Kelvin-Voigt [Chen2004]: sqrt(2(mu^2+w^2eta^2)/(rho(mu+sqrt(mu^2+w^2eta^2))))."""
    f = np.asarray(f_hz, dtype=float)
    w = 2 * pi * f
    mag = np.sqrt(material.mu**2 + (w * material.eta) ** 2)
    return np.sqrt(2 * mag**2 / (material.rho * (material.mu + mag)))


# --------------------------------------------------------------------------------------
# Rayleigh
# --------------------------------------------------------------------------------------
def rayleigh_ratio_elastic(nu: float) -> float:
    """Raíz real xi = c_R/c_s de la ecuación secular de Rayleigh [Rayleigh1885]:

        (2 - xi^2)^2 - 4 sqrt(1 - gamma^2 xi^2) sqrt(1 - xi^2) = 0,
        gamma^2 = c_s^2/c_p^2 = (1 - 2 nu) / (2 (1 - nu)).
    """
    g2 = (1 - 2 * nu) / (2 * (1 - nu))

    def secular(xi: float) -> float:
        return (2 - xi**2) ** 2 - 4 * np.sqrt(1 - g2 * xi**2) * np.sqrt(1 - xi**2)

    return brentq(secular, 0.5, 0.999999)


def _rayleigh_complex_root(mu_c: complex, lam: float, rho: float, xi0: float) -> complex:
    """Newton en el plano complejo para la misma ecuación con módulos complejos.

    Por el principio de correspondencia [Christensen1982] la ecuación de Rayleigh
    [Rayleigh1885] vale con mu* = mu + i w eta y lambda* = lambda (sin viscosidad
    volumétrica, supuesto del simulador). Incógnita: xi = c_R*/c_s*.
    """
    cs2 = mu_c / rho
    cp2 = (lam + 2 * mu_c) / rho
    g2 = cs2 / cp2

    def F(xi: complex) -> complex:
        return (2 - xi**2) ** 2 - 4 * np.sqrt(1 - g2 * xi**2) * np.sqrt(1 - xi**2)

    xi = complex(xi0)
    for _ in range(60):
        h = 1e-7 * (1 + abs(xi))
        dF = (F(xi + h) - F(xi - h)) / (2 * h)
        step = F(xi) / dF
        xi -= step
        if abs(step) < 1e-13:
            break
    return xi


def rayleigh_phase_velocity(material: Material, f_hz: np.ndarray | float) -> np.ndarray:
    """Velocidad de fase de Rayleigh viscoelástica, c = w / Re(k) = 1 / Re(1/c_R*)."""
    f = np.atleast_1d(np.asarray(f_hz, dtype=float))
    xi0 = rayleigh_ratio_elastic(material.nu)
    lam = material.lam()
    out = np.empty_like(f)
    for i, fi in enumerate(f):
        w = 2 * pi * fi
        mu_c = complex(material.mu, w * material.eta)
        xi = _rayleigh_complex_root(mu_c, lam, material.rho, xi0)
        c_complex = xi * np.sqrt(mu_c / material.rho)
        out[i] = 1.0 / np.real(1.0 / c_complex)
    return out if np.ndim(f_hz) else out[:1]


def rayleigh_speed_approx(material: Material) -> float:
    """c_R ~ 0.955 c_s para medio casi incompresible [Singh2022, Ec. (12)]."""
    return 0.955 * material.cs


def scholte_speed_approx(material: Material) -> float:
    """Onda de Scholte (interfaz tejido-fluido): c_Sc ~ 0.846 c_s [Singh2022, Ec. (13)]."""
    return 0.846 * material.cs


# --------------------------------------------------------------------------------------
# Lamb: ecuación de Rayleigh-Lamb modificada (placa + fluido inferior)
# --------------------------------------------------------------------------------------
def mrlfe_matrix(k: float, w: float, c1: complex, mu: complex, rho_s: float,
                 cf: float, rho_f: float, d: float) -> np.ndarray:
    """Matriz 5x5 de la mRLFE [Han2017], portada término a término de repo:mRLFE.

    k: número de onda (rad/m); w: frecuencia angular (rad/s); c1: velocidad
    longitudinal de la placa; mu: módulo de corte (complejo si Kelvin-Voigt);
    rho_s: densidad de la placa; cf, rho_f: fluido; d: parámetro de espesor tal
    como aparece en repo:mRLFE (las funciones hiperbólicas se evalúan en alpha*d
    y beta*d). Con rho_f = 0 el bloque 4x4 superior da la placa libre [Lamb1917].
    """
    c2 = np.sqrt(mu / rho_s)
    alpha_f = np.sqrt(complex(k**2 - (w / cf) ** 2)) if cf > 0 else complex(k)
    alpha = np.sqrt(k**2 - (w / c1) ** 2 + 0j)
    beta = np.sqrt(k**2 - (w / c2) ** 2 + 0j)
    kb = k**2 + beta**2
    sa, ca = np.sinh(alpha * d), np.cosh(alpha * d)
    sb, cb = np.sinh(beta * d), np.cosh(beta * d)
    M = np.zeros((5, 5), dtype=complex)
    M[0] = [kb * sa, 2 * k * beta * sb, kb * ca, 2 * k * beta * cb, 0]
    M[1] = [2 * k * alpha * ca, kb * cb, 2 * k * alpha * sa, kb * sb, 0]
    M[2] = [-kb * sa, -2 * k * beta * sb, kb * ca, 2 * k * beta * cb, rho_f * w**2 / mu]
    M[3] = [2 * k * alpha * ca, kb * cb, -2 * k * alpha * sa, -kb * sb, 0]
    M[4] = [alpha * ca, k * cb, -alpha * sa, -k * sb, -alpha_f]
    return M


def _inverse_condition(M: np.ndarray) -> float:
    """1/cond(M) con filas normalizadas; tiende a 0 en las raíces (det M = 0).

    repo:FindZeros_mRLFE busca picos de cond(M); aquí se minimiza su inverso.
    """
    scale = np.max(np.abs(M), axis=1, keepdims=True)
    scale[scale == 0] = 1
    s = np.linalg.svd(M / scale, compute_uv=False)
    return float(s[-1] / s[0])


@dataclass
class LambConfig:
    plate: Material
    thickness_m: float
    fluid: Material | None = None      # None = placa libre (aire debajo)
    c_fluid: float | None = None       # velocidad del fluido a usar (simulación o real)


def lamb_a0_phase_velocity(cfg: LambConfig, f_hz: np.ndarray, n_scan: int = 600) -> np.ndarray:
    """Modo A0 (el más lento) de la placa, libre o con fluido debajo [Han2017; Lamb1917].

    Para cada f se barre la velocidad de fase c en [0.02 c_s, 1.2 c_s], se buscan
    mínimos locales de 1/cond(M) y se refina el de mayor k (modo más lento).
    El parámetro d de repo:mRLFE es el semiespesor (las ecuaciones de Rayleigh-Lamb
    usan +-h/2), por lo que d = h/2.
    """
    plate = cfg.plate
    rho_f = cfg.fluid.rho if cfg.fluid is not None else 0.0
    cf = (cfg.c_fluid if cfg.c_fluid is not None
          else (cfg.fluid.c_acoustic if cfg.fluid is not None else 0.0))
    d = cfg.thickness_m / 2.0
    lam = plate.lam()
    out = np.full(np.shape(f_hz), np.nan)
    for i, f in enumerate(np.atleast_1d(f_hz)):
        if f <= 0:
            continue
        w = 2 * pi * f
        mu_c = complex(plate.mu, w * plate.eta)
        c1 = np.sqrt((lam + 2 * mu_c) / plate.rho)
        cs = abs(np.sqrt(mu_c / plate.rho))
        c_grid = np.linspace(0.02 * cs, 1.2 * cs, n_scan)
        k_grid = w / c_grid

        def g(k: float) -> float:
            return _inverse_condition(mrlfe_matrix(k, w, c1, mu_c, plate.rho, cf, rho_f, d))

        vals = np.array([g(k) for k in k_grid])
        minima = [j for j in range(1, n_scan - 1) if vals[j] < vals[j - 1] and vals[j] <= vals[j + 1]]
        if not minima:
            continue
        # modo más lento = mínimo con c más pequeño que sea un cero claro
        best = None
        floor = np.median(vals)
        for j in minima:
            if vals[j] < 0.2 * floor:
                best = j
                break
        if best is None:
            best = minima[int(np.argmin(vals[minima]))]
        lo, hi = k_grid[best + 1], k_grid[best - 1]
        res = minimize_scalar(g, bounds=(min(lo, hi), max(lo, hi)), method="bounded",
                              options={"xatol": 1e-9 * k_grid[best]})
        out[i] = w / res.x
    return out


def lamb_all_modes(cfg: LambConfig, f_hz: np.ndarray, c_min: float = 0.2, c_max: float = 8.0,
                   n_scan: int = 1500, max_modes: int = 4) -> np.ndarray:
    """Todas las raíces (velocidad de fase) de la mRLFE [Han2017] en [c_min, c_max].

    Devuelve [nf, max_modes] ordenado de menor a mayor velocidad (NaN si no hay).
    Sirve para identificar qué modo domina la superficie medida: en placas de
    espesor comparable a la longitud de onda el modo más lento se concentra en la
    interfaz con el fluido (tipo Scholte) y la superficie libre ve otro modo.
    """
    plate = cfg.plate
    rho_f = cfg.fluid.rho if cfg.fluid is not None else 0.0
    cf = (cfg.c_fluid if cfg.c_fluid is not None
          else (cfg.fluid.c_acoustic if cfg.fluid is not None else 0.0))
    d = cfg.thickness_m / 2.0
    lam = plate.lam()
    out = np.full((np.size(f_hz), max_modes), np.nan)
    for i, f in enumerate(np.atleast_1d(f_hz)):
        w = 2 * pi * f
        mu_c = complex(plate.mu, w * plate.eta)
        c1 = np.sqrt((lam + 2 * mu_c) / plate.rho)
        cg = np.linspace(c_min, c_max, n_scan)
        vals = np.array([_inverse_condition(mrlfe_matrix(w / c, w, c1, mu_c, plate.rho, cf, rho_f, d))
                         for c in cg])
        med = np.median(vals)
        mins = [j for j in range(1, n_scan - 1)
                if vals[j] < vals[j - 1] and vals[j] <= vals[j + 1] and vals[j] < 0.3 * med]
        roots = []
        for j in mins[:max_modes]:
            res = minimize_scalar(lambda c: _inverse_condition(mrlfe_matrix(w / c, w, c1, mu_c, plate.rho,
                                                                            cf, rho_f, d)),
                                  bounds=(cg[j - 1], cg[j + 1]), method="bounded")
            roots.append(res.x)
        out[i, :len(roots)] = roots
    return out


def lamb_a0_low_frequency(material: Material, thickness_m: float, f_hz: np.ndarray) -> np.ndarray:
    """Límite flexural de placa delgada (Kirchhoff) para orientar la búsqueda.

    c = sqrt(w) (D/(rho h))^(1/4), D = E h^3/(12(1-nu^2)) [Viktorov1967, placas delgadas].
    """
    D = material.E * thickness_m**3 / (12 * (1 - material.nu**2))
    w = 2 * pi * np.asarray(f_hz, dtype=float)
    return np.sqrt(w) * (D / (material.rho * thickness_m)) ** 0.25


# --------------------------------------------------------------------------------------
# Selección del modelo de referencia para validar
# --------------------------------------------------------------------------------------
def reference_curve(model: str, f_hz: np.ndarray, *, material: Material,
                    thickness_m: float | None = None, fluid: Material | None = None,
                    c_fluid: float | None = None) -> np.ndarray:
    """Curva teórica de velocidad de fase para el modelo indicado.

    model: "shear" | "rayleigh" | "lamb_free" | "lamb_fluid".
    """
    f_hz = np.asarray(f_hz, dtype=float)
    if model == "shear":
        return shear_phase_velocity(material, f_hz)
    if model == "rayleigh":
        return rayleigh_phase_velocity(material, f_hz)
    if model == "lamb_free":
        return lamb_a0_phase_velocity(LambConfig(material, thickness_m, None), f_hz)
    if model == "lamb_fluid":
        return lamb_a0_phase_velocity(LambConfig(material, thickness_m, fluid, c_fluid), f_hz)
    raise ValueError(f"Modelo teórico desconocido: {model}")
