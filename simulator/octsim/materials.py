"""Materiales isótropos viscoelásticos (Kelvin-Voigt) con propiedades ópticas.

Unidades de entrada amigables (kPa, Pa·s, dB) y propiedades derivadas en SI.

Ecuaciones:
* Módulos de Lamé desde (E, nu):
      mu = E / (2 (1 + nu))                     [Singh2022, Ec. (3)]
      lambda = E nu / ((1 + nu)(1 - 2 nu))      (ley de Hooke isótropa, [Singh2022, Ec. (1)])
* Velocidades de onda elásticas:
      c_s = sqrt(mu / rho)                      [Singh2022, Ec. (5)]
      c_p = sqrt((lambda + 2 mu) / rho)         [Singh2022, Ec. (10)]
* Kelvin-Voigt (solo viscosidad de corte):
      mu*(w) = mu + i w eta                     [Singh2022, Ec. (9)]
  La viscosidad volumétrica se toma nula (lambda* = lambda): supuesto explícito.
* Fluido (agua / humor acuoso): mu = 0, lambda = rho c_f^2 (fluido no viscoso).

Supuesto de compresibilidad: el simulador usa nu >= 0.495 en lugar de ~0.4999
para que c_p/c_s ~ 10 y el paso temporal explícito sea viable; es el valor
mínimo recomendado por [Palmeri2017, sec. "Poisson's ratio"] ("Poisson's ratio
must be greater than 0.495" para al menos un orden de magnitud entre c_p y c_s).
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field, fields
from math import isfinite, log, pi, sqrt
from typing import Any

#: Coeficiente para pasar dB a neper: 1 dB = ln(10)/20 Np (definición).
DB_TO_NP = log(10.0) / 20.0


@dataclass
class Material:
    """Propiedades de un medio isótropo homogéneo.

    Campos mecánicos (los que pide el usuario: E, nu, rho, eta) y ópticos
    (n, retrodispersión y atenuación OCT) y acústicos (para la ARF).
    """

    name: str = "Medio"
    E_kPa: float = 12.36                 # módulo de Young
    nu: float = 0.495                    # coeficiente de Poisson usado en la simulación
    rho: float = 1000.0                  # densidad (kg/m^3)
    eta_Pa_s: float = 0.0                # viscosidad de corte Kelvin-Voigt (Pa·s)
    n: float = 1.35                      # índice de refracción de grupo a 1310 nm
    backscatter_db: float = -55.0        # reflectancia media de speckle por celda de resolución
    mu_oct_per_mm: float = 1.0           # atenuación OCT (1/mm), potencia ~ exp(-2 mu z) [Faber2004]
    alpha_db_cm_mhz: float = 0.45        # atenuación ultrasónica (ARF) [Palmeri2017, Tabla I]
    c_acoustic: float = 1540.0           # velocidad del sonido real (m/s) para la ARF
    is_fluid: bool = False               # fluido no viscoso (mu = 0)
    c_fluid_sim: float = 0.0             # c del fluido en la simulación (m/s); 0 = automático
    color: str = "#4c78a8"               # color en las vistas de geometría

    # --- módulos -----------------------------------------------------------------
    @property
    def E(self) -> float:
        return self.E_kPa * 1e3

    @property
    def eta(self) -> float:
        return 0.0 if self.is_fluid else self.eta_Pa_s

    @property
    def mu(self) -> float:
        """Módulo de corte (Pa) [Singh2022, Ec. (3)]: mu = E / (2(1+nu))."""
        if self.is_fluid:
            return 0.0
        return self.E / (2.0 * (1.0 + self.nu))

    def lam(self, c_fluid: float | None = None) -> float:
        """Primer parámetro de Lamé (Pa) [Singh2022, Ec. (1)]."""
        if self.is_fluid:
            c = c_fluid if c_fluid is not None else self.c_fluid_sim
            if c <= 0:
                raise ValueError(f"{self.name}: velocidad de fluido no definida")
            return self.rho * c * c
        return self.E * self.nu / ((1.0 + self.nu) * (1.0 - 2.0 * self.nu))

    # --- velocidades ----------------------------------------------------------------
    @property
    def cs(self) -> float:
        """Velocidad de corte elástica c_s = sqrt(mu/rho) [Singh2022, Ec. (5)]."""
        return sqrt(self.mu / self.rho)

    def cp(self, c_fluid: float | None = None) -> float:
        """Velocidad longitudinal c_p = sqrt(M/rho), M = lambda + 2mu [Singh2022, Ec. (10)]."""
        return sqrt((self.lam(c_fluid) + 2.0 * self.mu) / self.rho)

    def cs_kv(self, f_hz: float) -> float:
        """Velocidad de fase de corte Kelvin-Voigt a la frecuencia f [Chen2004]:

        c(w) = sqrt( 2 (mu^2 + w^2 eta^2) / ( rho (mu + sqrt(mu^2 + w^2 eta^2)) ) ).
        """
        if self.is_fluid:
            return 0.0
        w = 2.0 * pi * f_hz
        mu, eta = self.mu, self.eta
        mag = sqrt(mu * mu + (w * eta) ** 2)
        return sqrt(2.0 * mag * mag / (self.rho * (mu + mag)))

    def cR_approx(self) -> float:
        """Rayleigh (aprox. de Viktorov): c_R ~ c_s (0.87 + 1.12 nu)/(1 + nu) [Viktorov1967]."""
        return self.cs * (0.87 + 1.12 * self.nu) / (1.0 + self.nu)

    def alpha_np_per_m(self, f_hz: float) -> float:
        """Atenuación ultrasónica de amplitud en Np/m a la frecuencia portadora.

        alpha[dB/cm] = alpha0[dB/cm/MHz] * f[MHz]; 1 dB = ln(10)/20 Np.
        """
        return self.alpha_db_cm_mhz * (f_hz / 1e6) * 100.0 * DB_TO_NP

    # --- serialización ----------------------------------------------------------------
    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Material":
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in data.items() if k in known})

    def validate(self) -> list[str]:
        errors = []
        for name in ("E_kPa", "nu", "rho", "eta_Pa_s", "n", "c_acoustic"):
            value = getattr(self, name)
            if not isfinite(value):
                errors.append(f"{self.name}: {name} no es finito")
        if self.rho <= 0:
            errors.append(f"{self.name}: la densidad debe ser > 0")
        if self.n < 1.0:
            errors.append(f"{self.name}: el índice de refracción debe ser >= 1")
        if not self.is_fluid:
            if self.E_kPa <= 0:
                errors.append(f"{self.name}: E debe ser > 0")
            if not 0.0 <= self.nu < 0.5:
                errors.append(f"{self.name}: nu debe estar en [0, 0.5)")
            if self.eta_Pa_s < 0:
                errors.append(f"{self.name}: la viscosidad no puede ser negativa")
        return errors


def clone(material: Material, **changes: Any) -> Material:
    data = material.to_dict()
    data.update(changes)
    return Material.from_dict(data)


@dataclass
class AirProperties:
    """Aire a ~20 °C para la presión de radiación sin contacto [Kinsler2000]."""

    rho: float = 1.21       # kg/m^3 (Kinsler2000, apéndice de constantes, 20 °C)
    c: float = 343.0        # m/s
    extra: dict[str, Any] = field(default_factory=dict)


AIR = AirProperties()
