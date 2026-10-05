"""Selección del módulo de arreglos: CuPy (GPU NVIDIA) o NumPy (CPU).

El solver FDTD usa kernels CUDA propios cuando hay GPU; el resto del flujo
(señal OCT, procesamiento) es agnóstico y recibe ``xp`` como parámetro.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import numpy as np

try:  # pragma: no cover - depende del hardware
    import cupy as _cp

    _cp.cuda.runtime.getDeviceCount()
    GPU_AVAILABLE = True
except Exception:  # noqa: BLE001 - cualquier fallo de CUDA implica CPU
    _cp = None
    GPU_AVAILABLE = False


@dataclass(frozen=True)
class Backend:
    name: str          # "gpu" o "cpu"
    xp: Any            # cupy o numpy

    @property
    def is_gpu(self) -> bool:
        return self.name == "gpu"

    def asnumpy(self, array: Any) -> np.ndarray:
        if self.is_gpu:
            return _cp.asnumpy(array)
        return np.asarray(array)

    def asarray(self, array: Any, dtype: Any = None) -> Any:
        return self.xp.asarray(array, dtype=dtype)

    def synchronize(self) -> None:
        if self.is_gpu:
            _cp.cuda.Device().synchronize()

    def free_memory(self) -> None:
        if self.is_gpu:
            _cp.get_default_memory_pool().free_all_blocks()
            _cp.get_default_pinned_memory_pool().free_all_blocks()

    def memory_info(self) -> tuple[int, int] | None:
        """(libre, total) en bytes para la GPU; None en CPU."""
        if self.is_gpu:
            return _cp.cuda.Device().mem_info
        return None

    def describe(self) -> str:
        if self.is_gpu:
            props = _cp.cuda.runtime.getDeviceProperties(0)
            name = props["name"].decode() if isinstance(props["name"], bytes) else props["name"]
            free, total = _cp.cuda.Device().mem_info
            return f"GPU {name} ({free / 2**30:.1f} de {total / 2**30:.1f} GB libres)"
        return "CPU (NumPy)"


def get_backend(prefer: str = "auto") -> Backend:
    """``prefer``: "auto" (GPU si existe), "gpu" (error si no hay) o "cpu"."""
    prefer = prefer.lower()
    if prefer not in ("auto", "gpu", "cpu"):
        raise ValueError(f"Backend desconocido: {prefer}")
    if prefer == "cpu":
        return Backend("cpu", np)
    if GPU_AVAILABLE:
        return Backend("gpu", _cp)
    if prefer == "gpu":
        raise RuntimeError("Se pidió GPU, pero CuPy/CUDA no está disponible.")
    return Backend("cpu", np)
