"""Persistent camera calibration and acquisition outlines in sensor coordinates."""
from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import ImageDraw

from .config import Orientation, ScanParameters, ScanPattern
from .paths import CONFIG_DIR

DEFAULT_ROI_PATH = CONFIG_DIR / "camera_roi.json"


@dataclass(frozen=True)
class CameraROI:
    camera_index: int
    frame_width: int
    frame_height: int
    pixels_per_mm: float
    center_x: float
    center_y: float
    flip_x: bool = False
    flip_y: bool = False

    def bounds(self, width: int, height: int) -> tuple[int, int, int, int]:
        if any(type(v) is not int for v in (self.camera_index, self.frame_width, self.frame_height)) or self.camera_index < 0 or min(self.frame_width, self.frame_height) < 2:
            raise ValueError("Identificador de cámara o resolución inválidos.")
        if type(self.flip_x) is not bool or type(self.flip_y) is not bool:
            raise ValueError("La orientación debe usar valores booleanos.")
        if (width, height) != (self.frame_width, self.frame_height):
            raise ValueError("Resolución distinta a la calibrada; repita el setup ROI.")
        if not all(math.isfinite(v) for v in (self.pixels_per_mm, self.center_x, self.center_y)) or self.pixels_per_mm <= 0:
            raise ValueError("Escala y centro de ROI inválidos.")
        if self.pixels_per_mm > min(width, height) / 15 + 1 / 15:
            raise ValueError("La ROI de 15 × 15 mm excede la resolución de la cámara.")
        side = round(15 * self.pixels_per_mm)
        if side < 2:
            raise ValueError("La ROI debe ocupar al menos dos píxeles.")
        left = round(self.center_x - side / 2)
        top = round(self.center_y - side / 2)
        if left < 0 or top < 0 or left + side > width or top + side > height:
            raise ValueError("La ROI de 15 × 15 mm no cabe centrada en la imagen.")
        return left, top, left + side, top + side

    def crop(self, frame: np.ndarray) -> np.ndarray:
        left, top, right, bottom = self.bounds(frame.shape[1], frame.shape[0])
        return frame[top:bottom, left:right]

    def save(self, path: Path = DEFAULT_ROI_PATH) -> None:
        self.bounds(self.frame_width, self.frame_height)
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps({"version": 1, **asdict(self)}, indent=2), encoding="utf-8")
        temporary.replace(path)

    @classmethod
    def load(cls, path: Path = DEFAULT_ROI_PATH) -> CameraROI | None:
        if not path.exists():
            return None
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.pop("version", None) != 1:
            raise ValueError("Versión de calibración ROI no compatible.")
        roi = cls(**data)
        roi.bounds(roi.frame_width, roi.frame_height)
        return roi


# Extensible registry: future patterns can register a renderer returning
# (canvas primitive, coordinates in mm). No acquisition waveform is modified.
Outline = list[tuple[str, tuple[float, ...]]]
OUTLINE_RENDERERS: dict[ScanPattern, Callable[[ScanParameters], Outline]] = {}


def pattern_outline(scan: ScanParameters) -> Outline:
    cx, cy = scan.center_x_mm, scan.center_y_mm
    x, y = scan.x_length_mm / 2, scan.y_length_mm / 2
    if scan.is_stationary:
        return [("point", (cx, cy))]
    if scan.pattern in OUTLINE_RENDERERS:
        return OUTLINE_RENDERERS[scan.pattern](scan)
    if scan.pattern is ScanPattern.MERIDIANS:
        return [("oval", (cx - x, cy - y, cx + x, cy + y))]
    if scan.pattern is ScanPattern.RASTER:
        return [("rectangle", (cx - x, cy - y, cx + x, cy + y))]
    if scan.pattern is ScanPattern.CROSSHAIR:
        return [("line", (cx - x, cy, cx + x, cy)), ("line", (cx, cy - y, cx, cy + y))]
    if scan.pattern is ScanPattern.LINEAR:
        return [("line", (cx - x, cy, cx + x, cy))] if scan.orientation is Orientation.HORIZONTAL else [("line", (cx, cy - y, cx, cy + y))]
    return []  # Unknown geometry must never be represented by a misleading outline.


def draw_pattern(canvas, scan: ScanParameters, roi: CameraROI, origin: tuple[float, float], scale: float) -> None:
    left, top, _, _ = roi.bounds(roi.frame_width, roi.frame_height)
    for kind, coords in pattern_outline(scan):
        mapped = []
        for x, y in zip(coords[::2], coords[1::2]):
            mapped.extend((origin[0] + (roi.center_x - left + x * roi.pixels_per_mm * (-1 if roi.flip_x else 1)) * scale,
                           origin[1] + (roi.center_y - top + y * roi.pixels_per_mm * (-1 if roi.flip_y else 1)) * scale))
        if kind == "point":
            x, y = mapped
            canvas.create_oval(x - 4, y - 4, x + 4, y + 4, fill="red", outline="red", tags="pattern")
        else:
            if kind in ("oval", "rectangle"):
                mapped = [min(mapped[0], mapped[2]), min(mapped[1], mapped[3]), max(mapped[0], mapped[2]), max(mapped[1], mapped[3])]
            options = {"fill": "red"} if kind == "line" else {"outline": "red"}
            getattr(canvas, "create_" + kind)(*mapped, width=2, tags="pattern", **options)


def render_pattern(image, scan: ScanParameters, roi: CameraROI, scale: float, *, cropped: bool):
    """Draw on the displayed bitmap so outlines are clipped at its borders."""
    image = image.copy()
    painter = ImageDraw.Draw(image)

    class BitmapCanvas:
        def create_line(self, *coords, **options):
            painter.line(coords, fill="red", width=2)

        def create_oval(self, *coords, **options):
            painter.ellipse(coords, outline="red", fill=options.get("fill"), width=2)

        def create_rectangle(self, *coords, **options):
            painter.rectangle(coords, outline="red", width=2)

    left, top, _, _ = roi.bounds(roi.frame_width, roi.frame_height)
    origin = (0, 0) if cropped else (left * scale, top * scale)
    draw_pattern(BitmapCanvas(), scan, roi, origin, scale)
    return image
