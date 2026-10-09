"""Acquisition file names: default name from parameters and no-overwrite suffixes."""
from __future__ import annotations

import re
from pathlib import Path

from .config import AcquisitionMode

MODE_PREFIX = {AcquisitionMode.MB: "OCE", AcquisitionMode.BM: "OCT"}
_INVALID_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_RESERVED = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}
_PARAMETER_NAME = re.compile(
    r"^(?:OCE|OCT)_\d+A_\d+B_\d+M_\d+SS"
    r"(?:_[+-]?\d+(?:p\d+)?mVpp)?(?:_[+-]?\d+(?:p\d+)?Hz)?(?=_|$)"
)


def _number(value: float) -> str:
    """2000 → '2000', 2.5 → '2p5' (no dots inside the stem)."""
    text = f"{float(value):.6g}"
    if "e" in text:
        text = f"{float(value):f}".rstrip("0").rstrip(".")
    return text.replace(".", "p")


def default_stem(
    mode: AcquisitionMode,
    alines: int,
    bscans: int,
    m_repetitions: int,
    sync_points: int,
    *,
    ch1_vpp: float | None = None,
    ch2_frequency_hz: float | None = None,
) -> str:
    """E.g. ``OCE_100A_100B_400M_200SS_300mVpp_2000Hz``."""
    parts = [
        MODE_PREFIX[mode],
        f"{int(alines)}A",
        f"{int(bscans)}B",
        f"{int(m_repetitions)}M",
        f"{int(sync_points)}SS",
    ]
    if ch1_vpp is not None:
        parts.append(f"{_number(ch1_vpp * 1000.0)}mVpp")
    if ch2_frequency_hz is not None:
        parts.append(f"{_number(ch2_frequency_hz)}Hz")
    return "_".join(parts)


def clean_stem(name: str) -> str:
    """Validate a user-typed name; drops a trailing .bin. Empty → ''."""
    stem = name.strip()
    if stem.lower().endswith(".bin"):
        stem = stem[:-4].rstrip()
    if not stem:
        return ""
    if _INVALID_CHARS.search(stem):
        raise ValueError('El nombre no puede contener < > : " / \\ | ? *')
    if stem.endswith((".", " ")) or stem.upper() in _RESERVED:
        raise ValueError(f"Nombre de archivo no válido en Windows: {stem!r}")
    return stem


def refresh_parameter_stem(name: str, current_default: str) -> str:
    """Refresh the generated prefix, retaining the user's specimen suffix."""
    stem = clean_stem(name)
    match = _PARAMETER_NAME.match(stem)
    if match is not None:
        return current_default + stem[match.end():]
    return stem or current_default


def unique_path(folder: Path, stem: str, extension: str = ".bin", *, taken: set[Path] | None = None) -> Path:
    """``folder/stem.bin``, or ``stem_1``, ``stem_2``… if it exists (never overwrite)."""
    taken = taken or set()
    candidate = folder / f"{stem}{extension}"
    number = 1
    while candidate.exists() or candidate in taken:
        candidate = folder / f"{stem}_{number}{extension}"
        number += 1
    return candidate
