from __future__ import annotations

import tempfile
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

from diagnostics.camera_serial_timing import sequence
from octoce.camera_icd import icd_timeout_warning, raise_timeouts, serial_timeouts
from octoce.backends.ni_hardware import NIHardwareBackend
from octoce.backends.ni_imaq import IMG_ERR_SERIAL_READ_TIMEOUT, ImaqError
from octoce.config import ConfigurationError, HardwareConfig, ScanParameters

ICD_EXCERPT = b"""      FrameTimeout (3000)
   Attribute (Operational Setting) {
            Action (Serial) {
               Command (OPR 2\\r)
               Response (OPR 2\\rOK\\r>)
               Timeout (3000)
               Delay (0)
            }
            Action (Serial) {
               Command (RESET\\r)
               Timeout (12000)
            }
            Units (\xb5S)
"""


class CameraSerialTests(unittest.TestCase):
    def test_serial_timeout_error_explains_the_fix(self) -> None:
        error = ImaqError("imgRingSetup", IMG_ERR_SERIAL_READ_TIMEOUT, "The serial read did not complete")
        self.assertIn("diagnostics.camera_serial_timing --fix", str(error))
        self.assertNotIn("camera_serial_timing", str(ImaqError("imgRingSetup", -1, "other")))

    def test_icd_serial_timeouts_are_raised_with_backup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            icd = Path(directory) / "camera.icd"
            icd.write_bytes(ICD_EXCERPT)
            self.assertEqual(serial_timeouts(icd), [3000, 12000])  # FrameTimeout excluded
            changed, backup = raise_timeouts(icd, 10_000)
            self.assertEqual(changed, 1)
            self.assertEqual(backup.read_bytes(), ICD_EXCERPT)
            self.assertEqual(serial_timeouts(icd), [10000, 12000])
            self.assertIn(b"FrameTimeout (3000)", icd.read_bytes())
            self.assertIn(b"\xb5S", icd.read_bytes())  # non-UTF-8 bytes untouched
            self.assertEqual(raise_timeouts(icd, 10_000), (0, None))

    def test_gui_warns_when_the_icd_has_no_margin(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            icd = Path(directory) / "camera.icd"
            icd.write_bytes(ICD_EXCERPT)
            with patch("octoce.camera_icd.camera_file", return_value=icd):
                self.assertIn("--fix", icd_timeout_warning())
                raise_timeouts(icd)
                self.assertIsNone(icd_timeout_warning())
        with patch("octoce.camera_icd.camera_file", side_effect=OSError("no NI-IMAQ")):
            self.assertIsNone(icd_timeout_warning())  # simulation PCs stay silent

    def test_timing_tool_replays_the_application_settings(self) -> None:
        commands = sequence(HardwareConfig())
        self.assertIn("CORR:GAIN OFF", commands)  # never re-enables the uniformity correction
        self.assertNotIn("CORR:GAIN ON", commands)
        self.assertEqual(commands[-1], "RESET")

    def test_camera_corrections_are_sent_at_every_open(self) -> None:
        opened: dict = {}

        class Camera:
            bits_per_pixel = 12

            def open(self, **kwargs) -> None:
                opened.update(kwargs)

            def close(self, *, abort: bool = False) -> None:
                pass

        class Daq:
            def __init__(self, _config) -> None:
                pass

            def __getattr__(self, _name):  # park/abort/close: nothing to do here
                return lambda *args, **kwargs: None

        scan = ScanParameters(alines=10, bscans=1, m_repetitions=10, x_length_mm=0.0, y_length_mm=0.0)
        with patch("octoce.backends.ni_hardware.NIIMAQCamera", Camera), \
                patch("octoce.backends.ni_hardware.NIDaqGalvoController", Daq):
            backend = NIHardwareBackend()
            backend.open(scan, HardwareConfig())
            backend.close()
        # CORR:GAIN stays off; offset (dark frame) and pixel replace on; global offset 0.
        self.assertEqual(
            (opened["offset_correction"], opened["uniformity_correction"],
             opened["pixel_replace"], opened["dark_level"]),
            (True, False, True, 0),
        )

    def test_dark_level_must_be_a_valid_camera_step(self) -> None:
        for level in (-50, 75, 2100):
            with self.subTest(level=level), self.assertRaises(ConfigurationError):
                replace(HardwareConfig(), camera_dark_level=level).validate()
        replace(HardwareConfig(), camera_dark_level=100).validate()


if __name__ == "__main__":
    unittest.main()
