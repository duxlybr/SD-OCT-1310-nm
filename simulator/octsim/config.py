"""Configuración completa de una simulación, serialización JSON y supuestos explícitos."""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field, fields
from pathlib import Path
from typing import Any

from .acquisition import AcquisitionConfig
from .excitation import ExcitationConfig, describe_load
from .fdtd import FDTDSettings
from .geometry import Geometry
from .oct_signal import OCTSystem
from .processing import ProcessingConfig
from .speed import SpeedConfig


@dataclass
class ValidationSpec:
    """Comprobaciones cuantitativas contra la teoría (ver validation.py).

    model: "auto" | "rayleigh" | "lamb_libre" | "lamb_fluido" | "corte" | "ninguno"
    checks: lista de dicts {"nombre", "plano": "enface"|"bmode", "metodo",
        "region": "fondo" | "inclusion:<i>" | [x0, x1, a0, a1] (mm; a = y o z),
        "esperado": "teoria" | "corte:<capa>" | "rayleigh:<capa>" | número (m/s),
        "tol_pct": número}
    """

    model: str = "auto"
    layer: int = 0
    band_hz: tuple[float, float] = (0.0, 0.0)
    tolerance_pct: float = 7.0
    checks: list[dict[str, Any]] = field(default_factory=list)
    oct_chain_min_r: float = 0.9

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["band_hz"] = list(self.band_hz)
        return d

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "ValidationSpec":
        known = {f.name for f in fields(cls)}
        kw = {k: v for k, v in d.items() if k in known}
        if "band_hz" in kw:
            kw["band_hz"] = tuple(kw["band_hz"])
        return cls(**kw)


@dataclass
class OutputConfig:
    root: str = "results"
    fps: float = 15.0
    max_video_frames: int = 150
    save_npz: bool = True

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "OutputConfig":
        known = {f.name for f in fields(cls)}
        return cls(**{k: v for k, v in d.items() if k in known})


@dataclass
class SimulationConfig:
    name: str = "simulacion"
    description: str = ""
    sources: list[str] = field(default_factory=list)       # claves de references.py del preset
    geometry: Geometry = field(default_factory=Geometry)
    excitation: ExcitationConfig = field(default_factory=ExcitationConfig)
    acquisition: AcquisitionConfig = field(default_factory=AcquisitionConfig)
    oct: OCTSystem = field(default_factory=OCTSystem)
    fdtd: FDTDSettings = field(default_factory=FDTDSettings)
    processing: ProcessingConfig = field(default_factory=ProcessingConfig)
    speed: SpeedConfig = field(default_factory=SpeedConfig)
    validation: ValidationSpec = field(default_factory=ValidationSpec)
    output: OutputConfig = field(default_factory=OutputConfig)

    # ------------------------------------------------------------ serialización
    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name, "description": self.description, "sources": list(self.sources),
            "geometry": self.geometry.to_dict(), "excitation": self.excitation.to_dict(),
            "acquisition": self.acquisition.to_dict(), "oct": self.oct.to_dict(),
            "fdtd": self.fdtd.to_dict(), "processing": self.processing.to_dict(),
            "speed": self.speed.to_dict(), "validation": self.validation.to_dict(),
            "output": self.output.to_dict(),
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "SimulationConfig":
        return cls(
            name=d.get("name", "simulacion"), description=d.get("description", ""),
            sources=list(d.get("sources", [])),
            geometry=Geometry.from_dict(d["geometry"]),
            excitation=ExcitationConfig.from_dict(d.get("excitation", {})),
            acquisition=AcquisitionConfig.from_dict(d.get("acquisition", {})),
            oct=OCTSystem.from_dict(d.get("oct", {})),
            fdtd=FDTDSettings.from_dict(d.get("fdtd", {})),
            processing=ProcessingConfig.from_dict(d.get("processing", {})),
            speed=SpeedConfig.from_dict(d.get("speed", {})),
            validation=ValidationSpec.from_dict(d.get("validation", {})),
            output=OutputConfig.from_dict(d.get("output", {})),
        )

    def save_json(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(self.to_dict(), indent=2, ensure_ascii=False), encoding="utf-8")

    @classmethod
    def load_json(cls, path: str | Path) -> "SimulationConfig":
        return cls.from_dict(json.loads(Path(path).read_text(encoding="utf-8")))

    # -------------------------------------------------------------- validación
    def validate(self) -> list[str]:
        errors = []
        errors += self.geometry.validate()
        errors += self.excitation.validate()
        errors += self.acquisition.validate()
        if self.processing.loupas_window < 2:
            errors.append("La ventana de Loupas debe ser >= 2 muestras.")
        if self.excitation.regime == "transitorio" and self.acquisition.mode == "MB":
            delay = self.excitation.ch2_delay_ms * 1e-3 + self.acquisition.bframes_delay_us * 1e-6
            if delay >= self.acquisition.m_reps * self.acquisition.line_period_s:
                errors.append("La ventana MB (M / f_linea) termina antes de que empiece la excitación "
                              "(retardo CH2 + BFramesDelay). Aumente M o reduzca los retardos.")
        return errors


def explicit_assumptions(cfg: SimulationConfig) -> list[str]:
    """Supuestos del modelo, generados a partir de la configuración actual."""
    g, e, a = cfg.geometry, cfg.excitation, cfg.acquisition
    top = g.layers[0].material if g.layers else None
    nus = sorted({m.nu for m in g.materials() if not m.is_fluid})
    lst = [
        "Medios isótropos, lineales (pequeñas deformaciones), viscoelásticos de Kelvin-Voigt con "
        "viscosidad de corte eta y viscosidad volumétrica nula [Singh2022, Ec. (9)].",
        f"Coeficiente de Poisson de simulación nu = {', '.join(f'{v:g}' for v in nus)} (c_p/c_s ~ 10): "
        "mínimo recomendado por [Palmeri2017]; con nu = 0.495 la razón c_R/c_s es 0.9547 frente a "
        "0.9553 con nu = 0.4999 (sesgo 0.06 %, [Rayleigh1885]). Las ondas P son más lentas que en "
        "el tejido real y pueden aparecer donde la onda de corte ya se atenuó.",
        "Fluidos (agua, humor acuoso) modelados como no viscosos con velocidad del sonido reducida a la "
        "mayor c_p de los sólidos; el modo A0 calculado con esa c_f difiere < 0.1 % del obtenido con "
        "1480 m/s (validado con la mRLFE [Han2017]).",
        "Superficie libre por formalismo de vacío y promedios armónico/aritmético en interfaces "
        "[Graves1996; Moczo2002]; la superficie curva se aproxima en escalera con la celda elegida.",
        "Bordes absorbentes con C-PML [Komatitsch2007] cuando la condición es 'absorbente'.",
    ]
    if e.mode == "arf_contacto":
        lst.append("ARF con contacto: F = 2 alpha I / c [Palmeri2017, Ec. (1)], absorción = atenuación, "
                   "I = p0^2/(2 rho c) [Kinsler2000]; foco gaussiano lateral (forma elegida) y axial "
                   f"(FWHM = {e.dof_mm:g} mm), atenuación exponencial acumulada desde el foco.")
    elif e.mode == "arf_sin_contacto":
        lst.append("ARF sin contacto (micro-tapping): P = (1 + R) I / c_aire con R ~ 1 [Ambrozinski2016]; "
                   "empuje vertical aplicado en la primera celda sólida (se ignora la inclinación local).")
    else:
        lst.append("Anillo de contactos: esfuerzo normal armónico sobre discos gaussianos de radio "
                   f"{e.tip_radius_mm:g} mm, todos con la misma fase salvo que se elija fase aleatoria "
                   "[Zvietcovich2019].")
    if e.regime == "transitorio":
        lst.append(f"Envolvente CH2 '{e.ch2_waveform}' normalizada en [0, 1], ARF ~ envolvente^2 (AM 100 %, "
                   f"[repo:dg4162]); subida finita de {e.rise_time_us:g} us (ancho de banda del transductor).")
        lst.append("Cada disparo PFI13 repite la misma excitación; el campo en un instante es la suma lineal "
                   "de las respuestas a los disparos anteriores dentro de la duración simulada (sistema "
                   "lineal e invariante); la respuesta se desvanece con un coseno en sus últimos 0.5 ms.")
    else:
        lst.append("Régimen armónico estacionario: el generador corre libre y en fase con el reloj de "
                   "adquisición (t = 0 al inicio); se extraen los armónicos f (y 2f para ARF) del campo; la "
                   "componente estática de la ARF no se modela.")
    lst += [
        "Galvanómetros ideales (sin error dinámico) y temporización uniforme de segmento de octoce "
        "[repo:octoce]; la transición sync no adquiere datos.",
        "Señal OCT: speckle gaussiano complejo [Schmitt1999], PSF axial/lateral, sensibilidad, roll-off y "
        "estabilidad de fase medidos [repo:LATEST]; desplazamiento de envolvente a primer orden; "
        "reflexión especular de Fresnel [BornWolf1999].",
        "Fase -> desplazamiento con el índice nominal de procesamiento y corrección del artefacto de "
        "superficie [Song2013]; no se corrigen interfaces de índice internas.",
        "El haz OCT es telecéntrico y paralelo a z (LSM04); se mide la componente u_z.",
    ]
    if a.mode == "BM" and e.regime == "transitorio":
        lst.append("BM transitorio: cada repetición se re-dispara, así que cada posición ve el mismo "
                   "instante relativo en todas las repeticiones; no hay evolución temporal por posición "
                   "(use MB para OCE).")
    if top is not None:
        lst.append(describe_load(e, top))
    return lst
