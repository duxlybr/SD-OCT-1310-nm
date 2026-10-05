from __future__ import annotations

from dataclasses import dataclass, replace
from hashlib import sha256
from typing import Iterator

import numpy as np
from numpy.typing import NDArray

from .config import POLAR_PATTERNS, AcquisitionMode, HardwareConfig, Orientation, ScanParameters, ScanPattern


FloatArray = NDArray[np.float64]


@dataclass(frozen=True, slots=True)
class ScanSegment:
    sequence_index: int
    bscan_index: int
    repetition_index: int | None
    aline_index: int | None
    label: str
    xy_mm: FloatArray
    xy_volts: FloatArray
    active_start: int
    active_count: int
    logical_reverse: bool = False
    sweep_index: int | None = None
    oce_trigger_count: int = 1
    bframes_delay_us: float = 0.0

    @property
    def ticks(self) -> int:
        return int(self.xy_mm.shape[0])

    @property
    def active_xy_mm(self) -> FloatArray:
        return self.xy_mm[self.active_start : self.active_start + self.active_count]

    @property
    def active_xy_volts(self) -> FloatArray:
        return self.xy_volts[self.active_start : self.active_start + self.active_count]


def quintic_transition(start_xy: FloatArray, end_xy: FloatArray, count: int) -> FloatArray:
    """Return `count` intermediate points with a minimum-jerk interpolation."""
    if count <= 0:
        return np.empty((0, 2), dtype=np.float64)
    t = np.arange(1, count + 1, dtype=np.float64) / (count + 1)
    smooth = 6.0 * t**5 - 15.0 * t**4 + 10.0 * t**3
    return start_xy[None, :] + (end_xy - start_xy)[None, :] * smooth[:, None]


class ScanPlanner:
    """Lazily generates hardware segments and their logical acquisition indices."""

    def __init__(self, scan: ScanParameters, hardware: HardwareConfig):
        scan.validate()
        hardware.validate(scan)
        self.scan = scan
        self.hardware = hardware

    def _line(self, bscan_index: int) -> FloatArray:
        p = self.scan
        u = np.linspace(-1.0, 1.0, p.alines, dtype=np.float64)
        cx, cy = p.center_x_mm, p.center_y_mm

        if p.pattern is ScanPattern.RASTER:
            y_offsets = np.linspace(-p.y_length_mm / 2.0, p.y_length_mm / 2.0, p.bscans)
            y = cy + (float(y_offsets[bscan_index]) if p.bscans > 1 else 0.0)
            line = np.column_stack((cx + u * p.x_length_mm / 2.0, np.full_like(u, y)))
        elif p.pattern is ScanPattern.LINEAR:
            if p.orientation is Orientation.HORIZONTAL:
                line = np.column_stack((cx + u * p.x_length_mm / 2.0, np.full_like(u, cy)))
            else:
                line = np.column_stack((np.full_like(u, cx), cy + u * p.y_length_mm / 2.0))
        elif p.pattern is ScanPattern.MERIDIANS:
            theta = np.pi * bscan_index / p.bscans
            line = np.column_stack(
                (
                    cx + u * (p.x_length_mm / 2.0) * np.cos(theta),
                    cy + u * (p.y_length_mm / 2.0) * np.sin(theta),
                )
            )
        elif p.pattern in POLAR_PATTERNS:
            # One B-scan = one full turn sampled at equal angles (the closing
            # point is the next turn's start, so it is not repeated).
            count = p.alines_in_bscan(bscan_index)
            a = np.arange(count, dtype=np.float64)
            if p.pattern is ScanPattern.RINGS:
                # Rings b = 0..B-1 at radius (b+1)/B: uniform radial spacing,
                # including the gap to the centre; the outermost ring is L/2.
                # (b+1)·A points per ring keep the arc spacing constant.
                theta = 2.0 * np.pi * a / count
                rho = np.full_like(a, (bscan_index + 1) / p.bscans)
            else:
                # Archimedean spiral at constant angular speed: the radius
                # grows linearly from the centre (first A-line) to L/2 (last).
                k = bscan_index * p.alines + a
                theta = 2.0 * np.pi * k / p.alines
                rho = k / max(1, p.alines * p.bscans - 1)
            line = np.column_stack(
                (
                    cx + rho * (p.x_length_mm / 2.0) * np.cos(theta),
                    cy + rho * (p.y_length_mm / 2.0) * np.sin(theta),
                )
            )
        else:  # pragma: no cover - exhaustive guard for future enum members
            raise ValueError(f"Patrón no implementado: {p.pattern}")

        if p.raster_bidirectional and p.pattern is ScanPattern.RASTER and bscan_index % 2:
            return line[::-1].copy()
        return line

    def _sweeps(self, bscan_index: int) -> list[tuple[str | None, FloatArray]]:
        p = self.scan
        if p.pattern is ScanPattern.RINGS:
            # One sweep (camera frame in BM) per arc of A consecutive points.
            ring = self._line(bscan_index)
            return [
                (f"arco{j + 1}", ring[j * p.alines : (j + 1) * p.alines])
                for j in range(p.sweeps_in_bscan(bscan_index))
            ]
        if p.pattern is not ScanPattern.CROSSHAIR:
            return [(None, self._line(bscan_index))]
        u = np.linspace(-1.0, 1.0, p.alines, dtype=np.float64)
        horizontal = np.column_stack(
            (
                p.center_x_mm + u * p.x_length_mm / 2.0,
                np.full_like(u, p.center_y_mm),
            )
        )
        vertical = np.column_stack(
            (
                np.full_like(u, p.center_x_mm),
                p.center_y_mm + u * p.y_length_mm / 2.0,
            )
        )
        return [("X", horizontal), ("Y", vertical)]

    def _append_oce_hold(
        self,
        xy_mm: FloatArray,
        endpoint: FloatArray,
        oce_trigger_count: int,
    ) -> FloatArray:
        if oce_trigger_count < 1:
            return xy_mm
        count = self.hardware.oce_post_hold_points(self.scan)
        if count < 1:
            return xy_mm
        hold = np.repeat(endpoint[None, :], count, axis=0)
        return np.concatenate((xy_mm, hold), axis=0)

    def iter_segments(self, initial_xy_mm: FloatArray | None = None) -> Iterator[ScanSegment]:
        p = self.scan
        h = self.hardware
        previous = np.asarray(
            (h.park_x_mm, h.park_y_mm) if initial_xy_mm is None else initial_xy_mm,
            dtype=np.float64,
        )
        if previous.shape != (2,) or not np.all(np.isfinite(previous)):
            raise ValueError("La posición inicial del galvo debe ser un par XY finito.")
        sequence = 0

        if p.mode is AcquisitionMode.BM:
            for b in range(p.bscans):
                for m in range(p.m_repetitions):
                    for sweep_index, (sweep_label, physical_line) in enumerate(self._sweeps(b)):
                        linear_reverse = bool(
                            p.pattern is ScanPattern.LINEAR
                            and (b * p.m_repetitions + m) % 2
                        )
                        active = physical_line[::-1].copy() if linear_reverse else physical_line
                        transition = quintic_transition(previous, active[0], p.sync_points)
                        xy_mm = np.concatenate((transition, active), axis=0)
                        reverse = linear_reverse or bool(
                            p.raster_bidirectional
                            and p.pattern is ScanPattern.RASTER
                            and b % 2
                        )
                        label = f"B{b + 1}/M{m + 1}"
                        if sweep_label is not None:
                            label += f"/{sweep_label}"
                        oce_trigger_count = (
                            1 if sweep_index == 0 or p.pattern is not ScanPattern.CROSSHAIR else 0
                        )
                        xy_mm = self._append_oce_hold(
                            xy_mm, active[-1], oce_trigger_count
                        )
                        xy_v = self._to_volts(xy_mm)
                        yield ScanSegment(
                            sequence_index=sequence,
                            bscan_index=b,
                            repetition_index=m,
                            aline_index=None,
                            label=label,
                            xy_mm=xy_mm,
                            xy_volts=xy_v,
                            active_start=p.sync_points,
                            active_count=p.alines,
                            logical_reverse=reverse,
                            sweep_index=sweep_index if sweep_label is not None else None,
                            # Crosshair X+Y is one logical B-scan: PFI13 fires
                            # on X only, once for each M repetition. Ring arcs
                            # are separate frames, each with its own pulse.
                            oce_trigger_count=oce_trigger_count,
                            bframes_delay_us=p.bframes_delay_us,
                        )
                        previous = active[-1]
                        sequence += 1
        else:
            for b in range(p.bscans):
                for sweep_index, (sweep_label, physical_line) in enumerate(self._sweeps(b)):
                    # MB keeps every M-sample waveform at one position intact.
                    # Reverse the position traversal, never the M time axis.
                    if p.pattern is ScanPattern.LINEAR and b % 2:
                        physical_line = physical_line[::-1].copy()
                    for logical_a, point in enumerate(physical_line):
                        active = np.repeat(point[None, :], p.m_repetitions, axis=0)
                        transition = quintic_transition(previous, point, p.sync_points)
                        xy_mm = np.concatenate((transition, active), axis=0)
                        xy_mm = self._append_oce_hold(xy_mm, point, 1)
                        xy_v = self._to_volts(xy_mm)
                        label = f"B{b + 1}/A{logical_a + 1}"
                        if sweep_label is not None:
                            label += f"/{sweep_label}"
                        yield ScanSegment(
                            sequence_index=sequence,
                            bscan_index=b,
                            repetition_index=None,
                            aline_index=logical_a,
                            label=label,
                            xy_mm=xy_mm,
                            xy_volts=xy_v,
                            active_start=p.sync_points,
                            active_count=p.m_repetitions,
                            logical_reverse=False,
                            sweep_index=sweep_index if sweep_label is not None else None,
                            # One trigger starts the externally configured OCE
                            # waveform captured by this group of M A-lines.
                            oce_trigger_count=1,
                            bframes_delay_us=p.bframes_delay_us,
                        )
                        previous = point
                        sequence += 1

    def _to_volts(self, xy_mm: FloatArray) -> FloatArray:
        scale = np.asarray((self.hardware.x_v_per_mm, self.hardware.y_v_per_mm), dtype=np.float64)
        volts = np.ascontiguousarray(xy_mm * scale[None, :])
        peak = float(np.max(np.abs(volts))) if volts.size else 0.0
        if peak > self.hardware.max_galvo_abs_v + 1e-12:
            raise ValueError(
                f"Trayectoria fuera del límite: {peak:.4f} V > {self.hardware.max_galvo_abs_v:.4f} V"
            )
        return volts

    def overview_lines(self, max_lines: int = 160) -> list[FloatArray]:
        if self.scan.bscans <= max_lines:
            indices = range(self.scan.bscans)
        else:
            indices = np.linspace(0, self.scan.bscans - 1, max_lines, dtype=int)
        lines = []
        for i in indices:
            for _label, line in self._sweeps(int(i)):
                if self.scan.pattern is ScanPattern.LINEAR:
                    reverse = (
                        int(i) % 2 if self.scan.mode is AcquisitionMode.MB
                        else (int(i) * self.scan.m_repetitions) % 2
                    )
                    if reverse:
                        line = line[::-1].copy()
                lines.append(line)
        return lines

    def overview_sync_paths(self, max_segments: int = 160, max_points: int = 64) -> list[tuple[int, FloatArray]]:
        """Sample actual sync trajectories throughout the plan, without allocating frames.

        Includes the previous endpoint and next acquired position so direction
        is visible. Each interior vertex is an actual quintic sync sample.
        Segment selection spans the full plan, including M repetitions and MB
        positions, rather than displaying only its initial portion.
        """
        p = self.scan
        if p.sync_points == 0 or max_segments < 1 or max_points < 3:
            return []
        # Straight sweeps are interpolated from their endpoints; polar turns
        # need the actual positions.
        curved = p.pattern in POLAR_PATTERNS
        endpoints = self if curved else ScanPlanner(replace(p, alines=2), self.hardware)
        cache: dict[int, list[tuple[str | None, FloatArray]]] = {}

        per_sweep = p.m_repetitions if p.mode is AcquisitionMode.BM else p.alines
        if p.pattern is ScanPattern.RINGS:  # ring b holds b+1 sweeps
            starts = per_sweep * np.arange(p.bscans + 1) * (np.arange(p.bscans + 1) + 1) // 2

        def position(sequence: int, end: bool) -> FloatArray:
            if p.pattern is ScanPattern.RINGS:
                b = int(np.searchsorted(starts, sequence, side="right")) - 1
                local = sequence - int(starts[b])
            else:
                b, local = divmod(sequence, per_sweep * p.sweeps_per_bscan)
            sweeps = p.sweeps_in_bscan(b)
            if p.mode is AcquisitionMode.BM:
                m, sweep = divmod(local, sweeps)
            else:
                sweep, a = divmod(local, p.alines)
            if b not in cache:
                cache[b] = endpoints._sweeps(b)
            line = cache[b][sweep][1]
            if p.pattern is ScanPattern.LINEAR and (
                (b * p.m_repetitions + m) % 2 if p.mode is AcquisitionMode.BM else b % 2
            ):
                line = line[::-1]
            if p.mode is AcquisitionMode.BM:
                return line[-1 if end else 0]
            if curved:
                return line[a]
            t = a / (p.alines - 1) if p.alines > 1 else 0.0
            return line[0] + (line[-1] - line[0]) * t

        indices = np.unique(np.linspace(0, p.total_segments - 1, min(max_segments, p.total_segments), dtype=int))
        ticks = np.unique(np.linspace(1, p.sync_points, min(max_points - 2, p.sync_points), dtype=int))
        t = ticks.astype(np.float64) / (p.sync_points + 1)
        smooth = 6.0 * t**5 - 15.0 * t**4 + 10.0 * t**3
        paths = []
        for index in indices:
            previous = position(int(index) - 1, True) if index else np.asarray(
                (self.hardware.park_x_mm, self.hardware.park_y_mm), dtype=np.float64)
            target = position(int(index), False)
            if np.allclose(previous, target, atol=1e-12, rtol=0):
                continue
            middle = previous[None, :] + (target - previous)[None, :] * smooth[:, None]
            paths.append((int(index), np.vstack((previous, middle, target))))
        return paths

    def trajectory_digest(self) -> str:
        digest = sha256()
        digest.update(repr(self.scan.to_dict()).encode("utf-8"))
        digest.update(repr(self.hardware.to_dict()).encode("utf-8"))
        for line in self.overview_lines(max_lines=min(self.scan.bscans, 512)):
            digest.update(np.ascontiguousarray(line, dtype="<f8").tobytes())
        return digest.hexdigest()
