"""NI-IMAQ camera file (ICD) of the line camera: serial action timeouts.

``imgRingSetup`` replays every serial command of the ICD and waits for each
reply within its action ``Timeout``. The GL2048R needs ~3.06 s for ``OPR 2``
and ~2.7 s for ``RESET`` (measured 2026-10-15) while the stock ICD allows
3000 ms, which makes every acquisition fail with NI-IMAQ error -1074397037.
``diagnostics/camera_serial_timing.py`` measures the camera and raises them.
"""
from __future__ import annotations

import re
import shutil
from datetime import datetime
from pathlib import Path

NI_IMAQ_DATA = Path(r"C:\Users\Public\Documents\National Instruments\NI-IMAQ\Data")
SAFE_TIMEOUT_MS = 10_000
# Below this the slowest command (~3.1 s) has no safety margin.
MIN_SAFE_TIMEOUT_MS = 5_000
_SERIAL_TIMEOUT = re.compile(rb"^(\s*)Timeout \((\d+)\)", re.MULTILINE)


def camera_file(interface: str = "img0") -> Path:
    """ICD assigned to port 0 of the interface in its .iid file."""
    iid = (NI_IMAQ_DATA / f"{interface}.iid").read_text(encoding="latin-1")
    match = re.search(r'\[PORT0\][^\[]*?Channel0\s*=\s*"([^"]+)"', iid)
    if not match:
        raise RuntimeError(f"{interface}.iid no asigna un archivo de cámara al puerto 0.")
    return NI_IMAQ_DATA / match.group(1)


def serial_timeouts(icd: Path) -> list[int]:
    """Timeout (ms) of every serial action; FrameTimeout lines are not included."""
    return [int(value) for _indent, value in _SERIAL_TIMEOUT.findall(icd.read_bytes())]


def raise_timeouts(icd: Path, minimum_ms: int = SAFE_TIMEOUT_MS) -> tuple[int, Path | None]:
    """Raise every serial action timeout below ``minimum_ms``; returns (changed, backup)."""
    raw = icd.read_bytes()
    changed = 0

    def bump(match: re.Match[bytes]) -> bytes:
        nonlocal changed
        if int(match.group(2)) >= minimum_ms:
            return match.group(0)
        changed += 1
        return match.group(1) + f"Timeout ({minimum_ms})".encode()

    patched = _SERIAL_TIMEOUT.sub(bump, raw)
    if not changed:
        return 0, None
    backup = icd.with_name(f"{icd.name}.bak-{datetime.now():%Y%m%d-%H%M%S}")
    shutil.copy2(icd, backup)
    icd.write_bytes(patched)
    return changed, backup


def icd_timeout_warning(interface: str = "img0") -> str | None:
    """Console warning when the ICD serial timeouts leave no margin; None if fine or unknown."""
    try:
        timeouts = serial_timeouts(camera_file(interface))
    except (OSError, RuntimeError):
        return None  # no NI-IMAQ installation or interface file (e.g. simulation PC)
    if timeouts and min(timeouts) < MIN_SAFE_TIMEOUT_MS:
        return (
            f"Cámara: el archivo ICD permite {min(timeouts)} ms por comando serie y la cámara tarda ~3,1 s; "
            "las adquisiciones fallarán (NI-IMAQ -1074397037). Con la GUI y NI MAX cerrados ejecute: "
            "py -3.11 -m diagnostics.camera_serial_timing --fix"
        )
    return None
