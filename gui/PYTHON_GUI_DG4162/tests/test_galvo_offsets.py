import unittest
from dataclasses import replace
import numpy as np
from octoce.config import AcquisitionMode, ConfigurationError, HardwareConfig, Orientation, ScanParameters, ScanPattern
from octoce.scan import ScanPlanner

class OffsetTests(unittest.TestCase):
    def setUp(self):
        self.hardware = HardwareConfig(spectral_samples=64, oce_enabled=False)

    def test_offset_translates_all_patterns_and_modes_without_extra_alines(self) -> None:
        for mode in AcquisitionMode:
            for pattern in ScanPattern:
                for orientation in Orientation:
                    with self.subTest(mode=mode, pattern=pattern, orientation=orientation):
                        original = ScanParameters(alines=5, bscans=3, m_repetitions=2,
                                                  x_length_mm=2, y_length_mm=2,
                                                  mode=mode, pattern=pattern, orientation=orientation)
                        shifted = replace(original, center_x_mm=3.25, center_y_mm=1.75)
                        base_segments = list(ScanPlanner(original, self.hardware).iter_segments())
                        shifted_segments = list(ScanPlanner(shifted, self.hardware).iter_segments())
                        self.assertEqual(original.expected_alines, shifted.expected_alines)
                        for base, actual in zip(base_segments, shifted_segments):
                            np.testing.assert_allclose(actual.active_xy_mm, base.active_xy_mm + [3.25, 1.75])
                            np.testing.assert_allclose(actual.active_xy_volts,
                                actual.active_xy_mm * [self.hardware.x_v_per_mm, self.hardware.y_v_per_mm])
                            self.assertEqual(actual.oce_trigger_count, base.oce_trigger_count)
                            self.assertEqual(actual.logical_reverse, base.logical_reverse)
                            self.assertLessEqual(np.max(np.abs(actual.xy_mm)), 7.05)

    def test_fov_rejects_full_trajectory_but_ignores_unused_linear_axis(self) -> None:
        hardware = replace(self.hardware, beam_diameter_mm=1)
        scan = ScanParameters(alines=5, bscans=2, x_length_mm=2, y_length_mm=2,
                              center_x_mm=6.05, center_y_mm=0)
        hardware.validate(scan)  # Exactly +7.05 mm is allowed.
        with self.assertRaisesRegex(ConfigurationError, "FOV LSM04"):
            hardware.validate(replace(scan, center_x_mm=6.051))
        linear = replace(scan, pattern=ScanPattern.LINEAR, x_length_mm=1,
                         center_x_mm=6.5, center_y_mm=7, y_length_mm=30)
        hardware.validate(linear)  # Y is held at 7 mm, not swept over 30 mm.
        with self.assertRaisesRegex(ConfigurationError, "FOV LSM04"):
            hardware.validate(replace(linear, orientation=Orientation.VERTICAL))
        with self.assertRaisesRegex(ConfigurationError, "park.*FOV LSM04"):
            replace(hardware, park_x_mm=8).validate()

    def test_sync_rejects_initial_position_outside_lens(self) -> None:
        planner = ScanPlanner(ScanParameters(alines=3, sync_points=50), self.hardware)
        with self.assertRaisesRegex(ValueError, "FOV LSM04"):
            next(planner.iter_segments(initial_xy_mm=np.asarray([8.0, 0.0])))
