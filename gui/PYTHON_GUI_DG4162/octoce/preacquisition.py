"""High-resolution raster pre-acquisition saved before an MB acquisition.

Before an MB (OCE) acquisition — or once at the start of an Excel series that
contains MB rows — the GUI can store a structural raster volume of the area
that is about to be measured. It is a plain BM raster with M = 1 and no PFI13
(the DG4162 is not fired), sampled at the lateral optical resolution:

* A-lines per B-scan = X window / 0.02 mm
* B-scans            = Y window / 0.02 mm   (isotropic 20 µm sampling)

The requested window (15 × 15 mm by default) is reduced automatically to the
largest window, centred on the galvo offset, that passes the same FOV, AO and
GVS002 checks as every other acquisition (``HardwareConfig.validate``).
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from math import floor, isfinite

from .config import (
    AcquisitionMode,
    ConfigurationError,
    HardwareConfig,
    ScanParameters,
    ScanPattern,
)

DEFAULT_WINDOW_MM = 15.0
# Lateral optical resolution of the system (user, 2026-11-04): 20 µm.
LATERAL_SAMPLING_MM = 0.02
# Transition (flyback) between consecutive B-scans: 2 ms at 50 klps for a
# full-field line return, well above the 300 µs GVS002 small-step response.
SYNC_POINTS = 100
FILE_SUFFIX = "preraster"


def window_steps(length_mm: float) -> int:
    """Number of 20 µm steps in ``length_mm`` (rounded, tolerant to 0.1 µm)."""
    return int(floor(length_mm / LATERAL_SAMPLING_MM + 1e-6))


def alines_for_window(length_mm: float) -> int:
    """A-lines (or B-scans) for a window: millimetres / 0.02 mm."""
    return max(2, window_steps(length_mm))


@dataclass(frozen=True, slots=True)
class PreacquisitionPlan:
    scan: ScanParameters
    hardware: HardwareConfig
    requested_x_mm: float
    requested_y_mm: float

    @property
    def reduced(self) -> bool:
        return (
            abs(self.scan.x_length_mm - self.requested_x_mm) > 1e-9
            or abs(self.scan.y_length_mm - self.requested_y_mm) > 1e-9
        )

    def describe(self) -> str:
        s = self.scan
        text = (
            f"raster BM {s.x_length_mm:g} × {s.y_length_mm:g} mm · {s.alines} A-lines × "
            f"{s.bscans} B-scans · M=1 · sync {s.sync_points} · sin PFI13"
        )
        if self.reduced:
            text += (
                f" (pedido {self.requested_x_mm:g} × {self.requested_y_mm:g} mm, reducido al "
                "máximo permitido por el FOV LSM04 / límites del galvo con el offset actual)"
            )
        return text

    def header(self) -> dict[str, object]:
        """Top-level 'preacquisition' section of the .bin header."""
        return {
            "purpose": "high-resolution structural raster saved before the MB/OCE acquisition",
            "lateral_sampling_mm": LATERAL_SAMPLING_MM,
            "rule": "alines = x_mm / 0.02, bscans = y_mm / 0.02",
            "requested_window_mm": [self.requested_x_mm, self.requested_y_mm],
            "window_mm": [self.scan.x_length_mm, self.scan.y_length_mm],
            "reduced_to_limits": self.reduced,
            "oce_trigger": False,
        }


def _scan(x_mm: float, y_mm: float, center_x_mm: float, center_y_mm: float) -> ScanParameters:
    return ScanParameters(
        alines=alines_for_window(x_mm),
        bscans=alines_for_window(y_mm),
        m_repetitions=1,
        sync_points=SYNC_POINTS,
        x_length_mm=x_mm,
        y_length_mm=y_mm,
        mode=AcquisitionMode.BM,
        pattern=ScanPattern.RASTER,
        center_x_mm=center_x_mm,
        center_y_mm=center_y_mm,
    )


def _valid(scan: ScanParameters, hardware: HardwareConfig) -> bool:
    try:
        scan.validate()
        hardware.validate(scan)
    except ConfigurationError:
        return False
    return True


def _largest_steps(requested_steps: int, fits) -> int:
    """Largest n ≤ requested_steps with fits(n) (fits is monotone); 0 if none."""
    if requested_steps >= 2 and fits(requested_steps):
        return requested_steps
    low, high, best = 2, requested_steps - 1, 0
    while low <= high:
        middle = (low + high) // 2
        if fits(middle):
            best, low = middle, middle + 1
        else:
            high = middle - 1
    return best


def plan_preacquisition(
    requested_x_mm: float,
    requested_y_mm: float,
    center_x_mm: float,
    center_y_mm: float,
    hardware: HardwareConfig,
) -> PreacquisitionPlan:
    """Raster plan for the requested window, reduced to the valid limits."""
    for label, value in (("X", requested_x_mm), ("Y", requested_y_mm)):
        if not isfinite(value) or value < 2 * LATERAL_SAMPLING_MM:
            raise ConfigurationError(
                f"Pre-adquisición: la ventana {label} debe ser ≥ {2 * LATERAL_SAMPLING_MM:g} mm."
            )
    hardware = replace(hardware, oce_enabled=False)  # structural volume: no PFI13 / DG4162 burst
    step = LATERAL_SAMPLING_MM
    probe = 2 * step  # the other axis while one axis is searched

    def x_fits(n: int) -> bool:
        return _valid(_scan(n * step, probe, center_x_mm, center_y_mm), hardware)

    def y_fits(n: int) -> bool:
        return _valid(_scan(probe, n * step, center_x_mm, center_y_mm), hardware)

    nx = _largest_steps(window_steps(requested_x_mm), x_fits)
    ny = _largest_steps(window_steps(requested_y_mm), y_fits)
    if nx < 2 or ny < 2:
        raise ConfigurationError(
            "Pre-adquisición: con el offset actual no cabe ninguna ventana raster dentro del FOV "
            "LSM04 / límites del galvo. Acerque el offset al centro o desactive la pre-adquisición."
        )
    # Axis limits are independent; shrink both together if the pair still fails.
    while nx >= 2 and ny >= 2 and not _valid(_scan(nx * step, ny * step, center_x_mm, center_y_mm), hardware):
        nx, ny = nx - 1, ny - 1
    if nx < 2 or ny < 2:
        raise ConfigurationError("Pre-adquisición: no se encontró una ventana raster válida.")
    x_mm = round(nx * step, 6)
    y_mm = round(ny * step, 6)
    # Keep the exact request when it already fits (e.g. 15 mm, not 14.999999).
    if nx == window_steps(requested_x_mm):
        x_mm = requested_x_mm
    if ny == window_steps(requested_y_mm):
        y_mm = requested_y_mm
    scan = _scan(x_mm, y_mm, center_x_mm, center_y_mm)
    scan.validate()
    hardware.validate(scan)
    return PreacquisitionPlan(scan, hardware, requested_x_mm, requested_y_mm)
