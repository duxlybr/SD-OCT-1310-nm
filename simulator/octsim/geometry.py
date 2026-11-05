"""Geometría del medio: bloque X·Y·Z, capas, superficie plana o domo, inclusiones.

Convenciones (explícitas en la GUI):
* x, y laterales centrados en 0; z es la profundidad física, positiva hacia
  dentro de la muestra (dirección del haz OCT y del empuje ARF). z = 0 es el
  plano superior (o el ápice del domo).
* Las capas son conformes a la superficie superior: un punto pertenece a la
  capa j si su profundidad bajo la superficie local, z - z_s(x, y), cae en el
  intervalo acumulado de espesores de esa capa. La última capa con espesor 0
  rellena hasta el fondo del bloque.
* Domo: casquete esférico de radio R; altura de la superficie (sagita)
      z_s(r) = R - sqrt(R^2 - r^2),  r^2 = x^2 + y^2   (geometría del círculo).
  Su huella lateral es un disco de diámetro min(X, Y) (limbo circular).
  Radio corneal típico R = 7.8 mm (ojo teórico de Le Grand); es un supuesto
  editable del preset de córnea.
* Inclusiones: esfera, elipsoide, cilindro (eje x, y o z) o caja; sus
  propiedades reemplazan a las de la capa dentro de su volumen, solo dentro de
  la muestra.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

import numpy as np

from .materials import Material

SURFACES = ("plana", "domo")
BOTTOMS = ("libre", "rigido", "absorbente")
LATERALS = ("libre", "absorbente", "empotrado")
INCLUSION_SHAPES = ("esfera", "elipsoide", "cilindro", "caja")

# Códigos del mapa de materiales en la malla
AIR_ID = 0
RIGID_ID = 255


@dataclass
class Layer:
    material: Material
    thickness_mm: float = 0.0      # 0 => rellena hasta el fondo (solo la última)

    def to_dict(self) -> dict[str, Any]:
        return {"material": self.material.to_dict(), "thickness_mm": self.thickness_mm}

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Layer":
        return cls(Material.from_dict(d["material"]), float(d.get("thickness_mm", 0.0)))


@dataclass
class Inclusion:
    material: Material
    shape: str = "esfera"
    center_mm: tuple[float, float, float] = (0.0, 0.0, 0.5)
    # esfera: (r, -, -); elipsoide: semiejes (a, b, c); cilindro: (radio, -, semilongitud);
    # caja: semilados (a, b, c)
    size_mm: tuple[float, float, float] = (0.4, 0.4, 0.4)
    axis: str = "y"                # eje del cilindro
    relative_to_surface: bool = True  # z del centro medido desde la superficie local

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["material"] = self.material.to_dict()
        return d

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Inclusion":
        return cls(
            material=Material.from_dict(d["material"]),
            shape=d.get("shape", "esfera"),
            center_mm=tuple(d.get("center_mm", (0, 0, 0.5))),
            size_mm=tuple(d.get("size_mm", (0.4, 0.4, 0.4))),
            axis=d.get("axis", "y"),
            relative_to_surface=bool(d.get("relative_to_surface", True)),
        )

    def contains(self, x: np.ndarray, y: np.ndarray, z: np.ndarray,
                 zs_center: float = 0.0) -> np.ndarray:
        """Máscara booleana de puntos (en mm) dentro de la inclusión."""
        cx, cy, cz = self.center_mm
        if self.relative_to_surface:
            cz = cz + zs_center
        a, b, c = self.size_mm
        dx, dy, dz = x - cx, y - cy, z - cz
        if self.shape == "esfera":
            return dx * dx + dy * dy + dz * dz <= a * a
        if self.shape == "elipsoide":
            return (dx / a) ** 2 + (dy / b) ** 2 + (dz / c) ** 2 <= 1.0
        if self.shape == "caja":
            return (np.abs(dx) <= a) & (np.abs(dy) <= b) & (np.abs(dz) <= c)
        if self.shape == "cilindro":
            r = a
            half = c if c > 0 else 1e9
            if self.axis == "x":
                return (dy * dy + dz * dz <= r * r) & (np.abs(dx) <= half)
            if self.axis == "y":
                return (dx * dx + dz * dz <= r * r) & (np.abs(dy) <= half)
            return (dx * dx + dy * dy <= r * r) & (np.abs(dz) <= half)
        raise ValueError(f"Forma de inclusión desconocida: {self.shape}")


@dataclass
class Geometry:
    size_x_mm: float = 8.0
    size_y_mm: float = 8.0
    size_z_mm: float = 3.0
    surface: str = "plana"
    dome_radius_mm: float = 7.8
    layers: list[Layer] = field(default_factory=list)
    inclusions: list[Inclusion] = field(default_factory=list)
    bottom: str = "absorbente"
    lateral: str = "absorbente"

    # ------------------------------------------------------------------ superficie
    def surface_z(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        """Profundidad de la superficie superior z_s(x, y) en mm (sagita del domo)."""
        x = np.asarray(x, dtype=float)
        y = np.asarray(y, dtype=float)
        if self.surface == "plana":
            return np.zeros(np.broadcast(x, y).shape)
        R = self.dome_radius_mm
        r2 = np.minimum(x * x + y * y, R * R)
        return R - np.sqrt(R * R - r2)

    def surface_normal_tilt(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        """Ángulo (rad) entre la normal local y el eje z (0 en superficie plana)."""
        if self.surface == "plana":
            return np.zeros(np.broadcast(np.asarray(x), np.asarray(y)).shape)
        r = np.sqrt(np.asarray(x) ** 2 + np.asarray(y) ** 2)
        return np.arcsin(np.clip(r / self.dome_radius_mm, 0, 1))

    # ---------------------------------------------------------------------- capas
    def layer_bounds(self) -> list[tuple[float, float]]:
        """Intervalos [d0, d1) de profundidad bajo la superficie local, por capa."""
        bounds = []
        d0 = 0.0
        for layer in self.layers:
            # Espesor 0 (solo permitido en la última capa) = semi-infinita hasta el fondo.
            d1 = np.inf if layer.thickness_mm <= 0 else d0 + layer.thickness_mm
            bounds.append((d0, d1))
            d0 = d1
        return bounds

    def materials(self) -> list[Material]:
        """Lista de materiales; el id en la malla es índice + 1."""
        return [layer.material for layer in self.layers] + [inc.material for inc in self.inclusions]

    def material_id_map(self, x: np.ndarray, y: np.ndarray, z: np.ndarray) -> np.ndarray:
        """Mapa de ids de material en puntos (mm). 0 = aire (fuera de la muestra).

        Fuera del bloque lateral o bajo z = size_z se devuelve aire; los bordes
        laterales/fondo se reemplazan luego según las condiciones de contorno.
        """
        x, y, z = np.broadcast_arrays(np.asarray(x, float), np.asarray(y, float),
                                      np.asarray(z, float))
        zs = self.surface_z(x, y)
        depth = z - zs
        ids = np.zeros(x.shape, dtype=np.uint8)
        inside = self.in_footprint(x, y) & (depth >= 0) & (z <= self.size_z_mm)
        for idx, (d0, d1) in enumerate(self.layer_bounds()):
            sel = inside & (depth >= d0) & (depth < d1)
            ids[sel] = idx + 1
        n_layers = len(self.layers)
        zs0 = float(self.surface_z(0.0, 0.0))
        for j, inc in enumerate(self.inclusions):
            cx, cy, _ = inc.center_mm
            zs_c = float(self.surface_z(cx, cy)) if inc.relative_to_surface else zs0
            sel = inside & inc.contains(x, y, z, zs_c)
            ids[sel] = n_layers + j + 1
        return ids

    def in_footprint(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        """Huella lateral de la muestra: rectángulo X x Y, o disco de diámetro min(X, Y)
        para el domo (córnea con limbo circular)."""
        if self.surface == "domo":
            r = min(self.size_x_mm, self.size_y_mm) / 2
            return x * x + y * y <= r * r
        return (np.abs(x) <= self.size_x_mm / 2) & (np.abs(y) <= self.size_y_mm / 2)

    def total_thickness_mm(self) -> float:
        bounds = self.layer_bounds()
        return bounds[-1][1] if bounds else 0.0

    # ----------------------------------------------------------------- validación
    def validate(self) -> list[str]:
        errors: list[str] = []
        if min(self.size_x_mm, self.size_y_mm, self.size_z_mm) <= 0:
            errors.append("Las dimensiones X, Y, Z deben ser > 0.")
        if self.surface not in SURFACES:
            errors.append(f"Superficie desconocida: {self.surface}")
        if self.surface == "domo" and self.dome_radius_mm <= max(self.size_x_mm, self.size_y_mm) / 2:
            errors.append("El radio del domo debe superar la mitad del ancho del bloque.")
        if self.bottom not in BOTTOMS:
            errors.append(f"Condición de fondo desconocida: {self.bottom}")
        if self.lateral not in LATERALS:
            errors.append(f"Condición lateral desconocida: {self.lateral}")
        if not self.layers:
            errors.append("Debe definirse al menos una capa.")
        for k, layer in enumerate(self.layers[:-1]):
            if layer.thickness_mm <= 0:
                errors.append(f"La capa {k + 1} necesita un espesor > 0 (solo la última puede ser 0).")
        if self.layers and self.layers[0].material.is_fluid:
            errors.append("La capa superior no puede ser un fluido.")
        for m in self.materials():
            errors.extend(m.validate())
        for inc in self.inclusions:
            if inc.shape not in INCLUSION_SHAPES:
                errors.append(f"Forma de inclusión desconocida: {inc.shape}")
            if min(v for v in inc.size_mm if v != 0) <= 0:
                errors.append("Las dimensiones de la inclusión deben ser > 0.")
        if len(self.materials()) > 250:
            errors.append("Demasiados materiales (máx. 250).")
        return errors

    # -------------------------------------------------------------- serialización
    def to_dict(self) -> dict[str, Any]:
        return {
            "size_x_mm": self.size_x_mm, "size_y_mm": self.size_y_mm, "size_z_mm": self.size_z_mm,
            "surface": self.surface, "dome_radius_mm": self.dome_radius_mm,
            "layers": [layer.to_dict() for layer in self.layers],
            "inclusions": [inc.to_dict() for inc in self.inclusions],
            "bottom": self.bottom, "lateral": self.lateral,
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Geometry":
        return cls(
            size_x_mm=float(d["size_x_mm"]), size_y_mm=float(d["size_y_mm"]),
            size_z_mm=float(d["size_z_mm"]), surface=d.get("surface", "plana"),
            dome_radius_mm=float(d.get("dome_radius_mm", 7.8)),
            layers=[Layer.from_dict(v) for v in d.get("layers", [])],
            inclusions=[Inclusion.from_dict(v) for v in d.get("inclusions", [])],
            bottom=d.get("bottom", "absorbente"), lateral=d.get("lateral", "absorbente"),
        )

    # ------------------------------------------------------------ perfil por columna
    def column_profile(self, x: float, y: float, z_mm: np.ndarray) -> np.ndarray:
        """Ids de material a lo largo de una columna vertical (para la señal OCT)."""
        return self.material_id_map(np.full_like(z_mm, x), np.full_like(z_mm, y), z_mm)
