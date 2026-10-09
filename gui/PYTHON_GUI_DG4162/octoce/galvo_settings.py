"""Explicitly saved XY starting offsets shared by the maintained GUIs."""
from __future__ import annotations

import json
import math
import os
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

from .config import ConfigurationError, LSM04_FOV_MM
from .paths import CONFIG_DIR

GALVO_DEFAULTS_PATH = CONFIG_DIR / "galvo_offsets.json"


@dataclass(frozen=True, slots=True)
class GalvoOffsets:
    x_mm: float = 0.0
    y_mm: float = 0.0

    def validate(self) -> None:
        if not all(math.isfinite(v) and abs(v) <= LSM04_FOV_MM / 2 for v in (self.x_mm, self.y_mm)):
            raise ConfigurationError("Los offsets X/Y deben ser finitos y estar entre −7.05 y +7.05 mm.")

    @classmethod
    def load(cls, path: Path = GALVO_DEFAULTS_PATH) -> GalvoOffsets:
        if not path.exists():
            return cls()
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict) or data.get("schema_version") != 1:
            raise ValueError("Formato de offsets de galvo no válido.")
        offsets = cls(float(data["x_mm"]), float(data["y_mm"]))
        offsets.validate()
        return offsets

    def save(self, path: Path = GALVO_DEFAULTS_PATH) -> None:
        self.validate()
        path.parent.mkdir(parents=True, exist_ok=True)
        data = {"schema_version": 1, "scan_lens": "LSM04", **asdict(self)}
        # An interrupted write must not destroy a previously accepted setting.
        descriptor, temporary = tempfile.mkstemp(prefix="galvo_offsets_", suffix=".tmp", dir=path.parent)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                json.dump(data, handle, indent=2, allow_nan=False)
                handle.write("\n")
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
