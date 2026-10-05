from __future__ import annotations

import unittest
from dataclasses import replace

import numpy as np

from octoce.config import (
    AcquisitionMode, ConfigurationError, HardwareConfig, Orientation, ScanParameters, ScanPattern,
    stationary_alignment_timing,
)
from octoce.scan import ScanPlanner, quintic_transition


class ScanPlannerTests(unittest.TestCase):
    def test_sync_overview_matches_actual_bm_mb_transitions(self) -> None:
        hardware = HardwareConfig(spectral_samples=64, oce_enabled=False, park_x_mm=1.2, park_y_mm=-0.7)
        for mode in AcquisitionMode:
            for pattern in ScanPattern:
                with self.subTest(mode=mode, pattern=pattern):
                    scan = ScanParameters(alines=5, bscans=3, m_repetitions=2, sync_points=5,
                                          x_length_mm=4, y_length_mm=3, mode=mode,
                                          pattern=pattern, raster_bidirectional=True)
                    planner = ScanPlanner(scan, hardware)
                    paths = dict(planner.overview_sync_paths(max_segments=1000))
                    previous = np.asarray((hardware.park_x_mm, hardware.park_y_mm))
                    for segment in planner.iter_segments():
                        if not np.allclose(previous, segment.active_xy_mm[0]):
                            expected = np.vstack((previous, segment.xy_mm[:segment.active_start], segment.active_xy_mm[0]))
                            np.testing.assert_allclose(paths[segment.sequence_index], expected, atol=1e-12)
                        else:
                            self.assertNotIn(segment.sequence_index, paths)
                        previous = segment.active_xy_mm[-1]

    def test_sync_overview_is_bounded_and_samples_entire_large_plan(self) -> None:
        scan = ScanParameters(alines=1000, bscans=500, m_repetitions=100, sync_points=1_000_000)
        planner = ScanPlanner(scan, self.hardware)
        paths = planner.overview_sync_paths(max_segments=7, max_points=9)
        self.assertEqual(len(paths), 7)
        self.assertEqual(paths[0][0], 0)
        self.assertEqual(paths[-1][0], scan.total_segments - 1)
        self.assertTrue(all(path.shape == (9, 2) for _, path in paths))
        self.assertEqual(ScanPlanner(replace(scan, sync_points=0), self.hardware).overview_sync_paths(), [])

    def setUp(self) -> None:
        self.hardware = HardwareConfig(spectral_samples=64, oce_enabled=False)

    def test_current_calibration_defaults(self) -> None:
        hardware = HardwareConfig()
        # Optimized with FWHM_80_ALines_TDMS.m (mirror at 4.05 mm, 2026-10-01)
        self.assertEqual((hardware.k_start_nm, hardware.k_end_nm), (1466.61, 1263.79))
        self.assertEqual((hardware.dispersion_d2_rad, hardware.dispersion_d3_rad), (-1.7, -2.5))
        with self.assertRaises(ConfigurationError):
            replace(hardware, dispersion_d2_rad=float("nan")).validate()
        self.assertEqual(
            (hardware.x_v_per_mm, hardware.y_v_per_mm),
            (0.40607082, 0.40631516),
        )

    def test_stationary_alignment_reserves_camera_idle_time_at_50_hz(self) -> None:
        original = HardwareConfig()
        capture, block_rate_hz = stationary_alignment_timing(original, 1000)
        self.assertAlmostEqual(block_rate_hz, 50.0)
        self.assertAlmostEqual(capture.effective_line_rate_hz, 52_631.5789, places=3)
        self.assertGreater(
            1 / block_rate_hz - 1000 / capture.effective_line_rate_hz,
            0.0009,
        )
        self.assertEqual(original.line_rate_hz, 50_000.0)

    def test_bm_order_and_shape(self) -> None:
        scan = ScanParameters(
            alines=5,
            bscans=3,
            m_repetitions=2,
            sync_points=4,
            x_length_mm=4.0,
            y_length_mm=2.0,
            mode=AcquisitionMode.BM,
            pattern=ScanPattern.RASTER,
        )
        segments = list(ScanPlanner(scan, self.hardware).iter_segments())
        self.assertEqual(len(segments), 6)
        self.assertEqual(scan.axis_order, ("bscan", "m_repetition", "aline", "pixel"))
        self.assertEqual((segments[0].bscan_index, segments[0].repetition_index), (0, 0))
        self.assertEqual((segments[1].bscan_index, segments[1].repetition_index), (0, 1))
        self.assertEqual(segments[0].xy_mm.shape, (9, 2))
        self.assertEqual(segments[0].active_start, 4)
        self.assertEqual(segments[0].active_count, 5)
        self.assertEqual(sum(segment.oce_trigger_count for segment in segments), 6)
        np.testing.assert_allclose(segments[0].active_xy_mm[:, 0], [-2, -1, 0, 1, 2])
        np.testing.assert_allclose(segments[0].active_xy_mm[:, 1], -1.0)

    def test_mb_order_and_stationary_repetitions(self) -> None:
        scan = ScanParameters(
            alines=4,
            bscans=2,
            m_repetitions=3,
            sync_points=2,
            x_length_mm=3.0,
            y_length_mm=1.0,
            mode=AcquisitionMode.MB,
            pattern=ScanPattern.RASTER,
        )
        segments = list(ScanPlanner(scan, self.hardware).iter_segments())
        self.assertEqual(len(segments), 8)
        self.assertEqual(scan.axis_order, ("bscan", "aline", "m_repetition", "pixel"))
        self.assertEqual((segments[0].bscan_index, segments[0].aline_index), (0, 0))
        self.assertEqual((segments[1].bscan_index, segments[1].aline_index), (0, 1))
        self.assertEqual(segments[0].xy_mm.shape, (5, 2))
        expected = np.repeat(segments[0].active_xy_mm[:1], 3, axis=0)
        np.testing.assert_allclose(segments[0].active_xy_mm, expected)

    def test_crosshair_contains_x_and_y_in_each_logical_bscan(self) -> None:
        scan = ScanParameters(
            alines=5,
            bscans=2,
            m_repetitions=1,
            sync_points=0,
            x_length_mm=4.0,
            y_length_mm=6.0,
            pattern=ScanPattern.CROSSHAIR,
        )
        planner = ScanPlanner(scan, self.hardware)
        lines = planner.overview_lines()
        self.assertEqual(len(lines), 4)
        np.testing.assert_allclose(lines[0][:, 1], 0.0)
        np.testing.assert_allclose(lines[1][:, 0], 0.0)
        self.assertAlmostEqual(float(np.ptp(lines[0][:, 0])), 4.0)
        self.assertAlmostEqual(float(np.ptp(lines[1][:, 1])), 6.0)
        segments = list(planner.iter_segments())
        self.assertEqual(len(segments), 4)
        self.assertEqual(scan.expected_alines, 20)
        self.assertEqual(scan.axis_order, ("bscan", "m_repetition", "sweep_xy", "aline", "pixel"))
        self.assertEqual(scan.logical_shape_without_pixels, (2, 1, 2, 5))
        self.assertEqual([segment.oce_trigger_count for segment in segments], [1, 0, 1, 0])

    def test_vertical_linear(self) -> None:
        scan = ScanParameters(
            alines=4,
            bscans=1,
            x_length_mm=0.0,
            y_length_mm=8.0,
            pattern=ScanPattern.LINEAR,
            orientation=Orientation.VERTICAL,
        )
        line = ScanPlanner(scan, self.hardware).overview_lines()[0]
        np.testing.assert_allclose(line[:, 0], 0.0)
        self.assertAlmostEqual(float(np.ptp(line[:, 1])), 8.0)

    def test_linear_bm_alternates_every_m_sweep_without_flyback(self) -> None:
        for orientation, axis, length in (
            (Orientation.HORIZONTAL, 0, 4.0),
            (Orientation.VERTICAL, 1, 6.0),
        ):
            with self.subTest(orientation=orientation):
                scan = ScanParameters(
                    alines=5, bscans=2, m_repetitions=3, sync_points=4,
                    x_length_mm=4.0, y_length_mm=6.0,
                    mode=AcquisitionMode.BM, pattern=ScanPattern.LINEAR,
                    orientation=orientation,
                )
                segments = list(ScanPlanner(scan, self.hardware).iter_segments())
                self.assertEqual(len(segments), 6)
                self.assertTrue(scan.to_dict()["linear_bidirectional"])
                forward = np.linspace(-length / 2, length / 2, 5)
                for index, segment in enumerate(segments):
                    expected = forward[::-1] if index % 2 else forward
                    np.testing.assert_allclose(segment.active_xy_mm[:, axis], expected)
                    self.assertEqual(segment.logical_reverse, bool(index % 2))
                    if index:
                        np.testing.assert_allclose(
                            segment.xy_mm[:scan.sync_points],
                            np.repeat(segments[index - 1].active_xy_mm[-1:], scan.sync_points, axis=0),
                        )

    def test_linear_mb_reverses_position_order_not_m_time_axis(self) -> None:
        scan = ScanParameters(
            alines=4, bscans=2, m_repetitions=3, sync_points=2,
            x_length_mm=4.0, y_length_mm=0.0,
            mode=AcquisitionMode.MB, pattern=ScanPattern.LINEAR,
        )
        segments = list(ScanPlanner(scan, self.hardware).iter_segments())
        self.assertEqual(len(segments), 8)
        first = [float(s.active_xy_mm[0, 0]) for s in segments[:4]]
        second = [float(s.active_xy_mm[0, 0]) for s in segments[4:]]
        np.testing.assert_allclose(first, np.linspace(-2, 2, 4))
        np.testing.assert_allclose(second, np.linspace(2, -2, 4))
        self.assertEqual([s.aline_index for s in segments[4:]], [0, 1, 2, 3])
        self.assertFalse(any(s.logical_reverse for s in segments))
        for segment in segments:
            np.testing.assert_allclose(
                segment.active_xy_mm,
                np.repeat(segment.active_xy_mm[:1], scan.m_repetitions, axis=0),
            )
        np.testing.assert_allclose(
            segments[4].xy_mm[:scan.sync_points],
            np.repeat(segments[3].active_xy_mm[-1:], scan.sync_points, axis=0),
        )

    def test_zero_by_zero_is_valid_stationary_center(self) -> None:
        for pattern in ScanPattern:
            with self.subTest(pattern=pattern):
                scan = ScanParameters(
                    alines=1, bscans=1, m_repetitions=4, sync_points=3,
                    x_length_mm=0.0, y_length_mm=0.0,
                    mode=AcquisitionMode.MB, pattern=pattern,
                )
                self.assertTrue(scan.is_stationary)
                segments = list(ScanPlanner(scan, self.hardware).iter_segments())
                self.assertTrue(segments)
                for segment in segments:
                    np.testing.assert_allclose(segment.active_xy_mm, 0.0)
                    np.testing.assert_allclose(segment.active_xy_volts, 0.0)

    def test_meridians_are_half_turn_unique_diameters(self) -> None:
        scan = ScanParameters(
            alines=3,
            bscans=4,
            x_length_mm=4.0,
            y_length_mm=4.0,
            pattern=ScanPattern.MERIDIANS,
        )
        lines = ScanPlanner(scan, self.hardware).overview_lines()
        np.testing.assert_allclose(lines[0][:, 1], 0.0, atol=1e-12)
        np.testing.assert_allclose(lines[2][:, 0], 0.0, atol=1e-12)

    def test_rings_have_alines_proportional_to_radius(self) -> None:
        scan = ScanParameters(alines=8, bscans=4, m_repetitions=2, sync_points=3,
                              x_length_mm=4.0, y_length_mm=4.0, center_x_mm=0.5,
                              pattern=ScanPattern.RINGS)
        segments = list(ScanPlanner(scan, self.hardware).iter_segments())
        # Ring b = b+1 arcs of A A-lines, each arc one camera frame in BM.
        self.assertEqual(len(segments), 2 * (1 + 2 + 3 + 4))
        self.assertEqual(scan.expected_alines, 8 * 2 * 10)
        self.assertEqual(scan.logical_shape_without_pixels, (20, 8))
        self.assertTrue(all(s.active_count == 8 and s.oce_trigger_count == 1 for s in segments))
        self.assertEqual([s.label for s in segments[:5]],
                         ["B1/M1/arco1", "B1/M2/arco1", "B2/M1/arco1", "B2/M1/arco2", "B2/M2/arco1"])
        for b in range(4):
            ring = [s for s in segments if s.bscan_index == b and s.repetition_index == 1]
            self.assertEqual([s.sweep_index for s in ring], list(range(b + 1)))
            xy = np.vstack([s.active_xy_mm for s in ring]) - (0.5, 0.0)
            radius = np.hypot(xy[:, 0], xy[:, 1])
            np.testing.assert_allclose(radius, 2.0 * (b + 1) / 4)
            self.assertEqual(xy.shape[0], 8 * (b + 1))
            angles = np.unwrap(np.arctan2(xy[:, 1], xy[:, 0]))
            np.testing.assert_allclose(angles[0], 0.0, atol=1e-12)  # every ring starts at +X
            # Equal angular steps over the full ring -> the same arc spacing on every ring.
            np.testing.assert_allclose(np.diff(angles) * radius[0], 2 * np.pi * 0.5 / 8)

    def test_mb_rings_store_flat_positions(self) -> None:
        scan = ScanParameters(alines=4, bscans=3, m_repetitions=5, sync_points=2,
                              x_length_mm=2.0, y_length_mm=2.0, mode=AcquisitionMode.MB,
                              pattern=ScanPattern.RINGS)
        segments = list(ScanPlanner(scan, self.hardware).iter_segments())
        self.assertEqual(len(segments), 4 * 6)
        self.assertEqual(scan.axis_order, ("position", "m_repetition", "pixel"))
        self.assertEqual(scan.logical_shape_without_pixels, (24, 5))
        self.assertEqual(scan.oce_trigger_segments, 24)
        self.assertEqual([scan.alines_in_bscan(b) for b in range(3)], [4, 8, 12])

    def test_spiral_is_one_continuous_archimedean_path_from_centre_to_edge(self) -> None:
        scan = ScanParameters(alines=16, bscans=3, x_length_mm=6.0, y_length_mm=4.0,
                              mode=AcquisitionMode.MB, pattern=ScanPattern.SPIRAL)
        planner = ScanPlanner(scan, self.hardware)
        points = np.vstack([planner._line(b) for b in range(scan.bscans)])
        normalized = points / (3.0, 2.0)  # ellipse semi-axes Lx/2, Ly/2
        radius = np.hypot(normalized[:, 0], normalized[:, 1])
        np.testing.assert_allclose(radius, np.arange(48) / 47, atol=1e-12)
        angles = np.unwrap(np.arctan2(normalized[1:, 1], normalized[1:, 0]))
        np.testing.assert_allclose(np.diff(angles), 2 * np.pi / 16)
        segments = list(planner.iter_segments())
        self.assertEqual(len(segments), 48)  # MB: one segment per position
        np.testing.assert_allclose(segments[-1].active_xy_mm[0], (3.0 * np.cos(2 * np.pi * 47 / 16),
                                                                  2.0 * np.sin(2 * np.pi * 47 / 16)))

    def test_polar_patterns_need_both_lengths_and_describe_geometry(self) -> None:
        for pattern in (ScanPattern.RINGS, ScanPattern.SPIRAL):
            with self.subTest(pattern=pattern):
                with self.assertRaises(ConfigurationError):
                    ScanParameters(x_length_mm=4.0, y_length_mm=0.0, pattern=pattern).validate()
                header = ScanParameters(pattern=pattern).to_dict()
                self.assertEqual(header["pattern"], pattern.value)
                self.assertIn("theta", header["polar_geometry"])
        self.assertNotIn("polar_geometry", ScanParameters().to_dict())

    def test_conversion_uses_confirmed_precise_calibration(self) -> None:
        scan = ScanParameters(
            alines=3,
            bscans=1,
            x_length_mm=2.0,
            y_length_mm=0.0,
            pattern=ScanPattern.LINEAR,
        )
        segment = next(ScanPlanner(scan, self.hardware).iter_segments())
        np.testing.assert_allclose(segment.active_xy_volts[:, 0], [-0.40607082, 0.0, 0.40607082])

    def test_mb_crosshair_triggers_once_per_group_of_m_alines(self) -> None:
        scan = ScanParameters(
            alines=3,
            bscans=1,
            m_repetitions=4,
            sync_points=2,
            x_length_mm=2.0,
            y_length_mm=2.0,
            mode=AcquisitionMode.MB,
            pattern=ScanPattern.CROSSHAIR,
            bframes_delay_us=1.5,
        )
        segments = list(ScanPlanner(scan, self.hardware).iter_segments())
        self.assertEqual(len(segments), 6)
        self.assertTrue(all(segment.active_count == 4 for segment in segments))
        self.assertTrue(all(segment.oce_trigger_count == 1 for segment in segments))
        self.assertTrue(all(segment.bframes_delay_us == 1.5 for segment in segments))
        self.assertEqual(scan.axis_order, ("bscan", "sweep_xy", "aline", "m_repetition", "pixel"))
        self.assertEqual(scan.logical_shape_without_pixels, (1, 2, 3, 4))

    def test_camera_rate_is_limited_to_147_klps(self) -> None:
        scan = ScanParameters(alines=64, bscans=1, sync_points=50)
        maximum = HardwareConfig(line_rate_hz=147_000.0)
        maximum.validate(scan)
        self.assertEqual(maximum.cc1_period_us, 6.8)
        self.assertAlmostEqual(maximum.effective_line_rate_hz, 1_000_000.0 / 6.8)
        self.assertEqual(maximum.camera_operational_setting, "OPR 0 - 115 to 147klps")
        with self.assertRaisesRegex(ValueError, "147 klps"):
            HardwareConfig(line_rate_hz=147_001.0).validate(scan)

    def test_oce_pulse_gets_unacquired_tail_hold_at_max_rate(self) -> None:
        scan = ScanParameters(
            alines=3,
            bscans=1,
            m_repetitions=1,
            sync_points=0,
            mode=AcquisitionMode.MB,
        )
        hardware = HardwareConfig(line_rate_hz=147_000.0, oce_pulse_width_us=10.0)
        hardware.validate(scan)
        self.assertEqual(hardware.oce_post_hold_points(scan), 1)
        segment = next(ScanPlanner(scan, hardware).iter_segments())
        self.assertEqual(segment.active_count, 1)
        self.assertEqual(segment.ticks, 2)
        np.testing.assert_allclose(segment.xy_mm[0], segment.xy_mm[1])

    def test_gvs002_manual_limits_apply_when_beam_diameter_is_known(self) -> None:
        hardware = HardwareConfig(beam_diameter_mm=5.0, galvo_v_per_degree=0.8)
        safe = ScanParameters(
            alines=32,
            bscans=2,
            x_length_mm=4.0,
            y_length_mm=4.0,
        )
        hardware.validate(safe)
        unsafe_y = ScanParameters(
            alines=32,
            bscans=2,
            x_length_mm=4.0,
            y_length_mm=30.0,
        )
        with self.assertRaisesRegex(ValueError, "recorrido Y"):
            hardware.validate(unsafe_y)
        with self.assertRaisesRegex(ValueError, "recorrido Y"):
            HardwareConfig(beam_diameter_mm=0.0).validate(unsafe_y)

    def test_half_volt_per_degree_setting_caps_input_at_6_25_v(self) -> None:
        scan = ScanParameters(alines=32, bscans=2)
        with self.assertRaisesRegex(ValueError, "±6.25 V"):
            HardwareConfig(galvo_v_per_degree=0.5, max_galvo_abs_v=9.5).validate(scan)

    def test_quintic_transition_excludes_endpoints(self) -> None:
        points = quintic_transition(np.array([0.0, 0.0]), np.array([1.0, -1.0]), 4)
        self.assertEqual(points.shape, (4, 2))
        self.assertTrue(np.all(points[:, 0] > 0.0))
        self.assertTrue(np.all(points[:, 0] < 1.0))
        self.assertTrue(np.all(np.diff(points[:, 0]) > 0.0))


if __name__ == "__main__":
    unittest.main()
