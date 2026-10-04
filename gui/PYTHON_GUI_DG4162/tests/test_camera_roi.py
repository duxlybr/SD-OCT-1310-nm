import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

import numpy as np
from PIL import Image

from octoce.camera_roi import CameraROI, OUTLINE_RENDERERS, pattern_outline, render_pattern
from octoce.config import Orientation, ScanParameters, ScanPattern


class CameraROITests(unittest.TestCase):
    def setUp(self):
        self.roi = CameraROI(0, 640, 480, 20, 320, 240)

    def test_round_trip_and_exact_square_crop(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "roi.json"
            self.assertIsNone(CameraROI.load(path))
            self.roi.save(path)
            self.assertEqual(CameraROI.load(path), self.roi)
        frame = np.arange(480 * 640 * 3).reshape(480, 640, 3)
        self.assertEqual(self.roi.bounds(640, 480), (170, 90, 470, 390))
        np.testing.assert_array_equal(self.roi.crop(frame), frame[90:390, 170:470])

    def test_rejects_invalid_scale_off_image_center_and_resolution_change(self):
        for roi in (replace(self.roi, pixels_per_mm=0), replace(self.roi, pixels_per_mm=float("nan")),
                    replace(self.roi, center_x=50), replace(self.roi, center_y=450)):
            with self.assertRaises(ValueError):
                roi.bounds(640, 480)
        with self.assertRaises(ValueError):
            self.roi.bounds(1280, 960)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "roi.json"
            path.write_text(json.dumps({"version": 99}))
            with self.assertRaises(ValueError):
                CameraROI.load(path)

    def test_all_existing_outlines_and_center_offsets(self):
        scan = ScanParameters(x_length_mm=6, y_length_mm=4, center_x_mm=1, center_y_mm=2)
        self.assertEqual(pattern_outline(scan), [("rectangle", (-2, 0, 4, 4))])
        self.assertEqual(pattern_outline(replace(scan, pattern=ScanPattern.MERIDIANS)), [("oval", (-2, 0, 4, 4))])
        for pattern in (ScanPattern.RINGS, ScanPattern.SPIRAL):
            self.assertEqual(pattern_outline(replace(scan, pattern=pattern)), [("oval", (-2, 0, 4, 4))])
        self.assertEqual(pattern_outline(replace(scan, pattern=ScanPattern.CROSSHAIR)),
                         [("line", (-2, 2, 4, 2)), ("line", (1, 0, 1, 4))])
        self.assertEqual(pattern_outline(replace(scan, pattern=ScanPattern.LINEAR, orientation=Orientation.VERTICAL)), [("line", (1, 0, 1, 4))])
        self.assertEqual(pattern_outline(replace(scan, x_length_mm=0, y_length_mm=0)), [("point", (1, 2))])

    def test_metric_projection_flips_and_clipping(self):
        image = Image.new("RGB", (300, 300))
        scan = ScanParameters(pattern=ScanPattern.LINEAR, x_length_mm=4, y_length_mm=0, center_x_mm=1)
        rendered = render_pattern(image, scan, self.roi, 1, cropped=True)
        self.assertEqual(rendered.getpixel((130, 150)), (255, 0, 0))
        self.assertEqual(rendered.getpixel((210, 150)), (255, 0, 0))
        flipped = render_pattern(image, scan, replace(self.roi, flip_x=True), 1, cropped=True)
        self.assertEqual(flipped.getpixel((90, 150)), (255, 0, 0))
        full = render_pattern(Image.new("RGB", (640, 480)), scan, self.roi, 1, cropped=False)
        self.assertEqual(full.getpixel((300, 240)), (255, 0, 0))
        large = render_pattern(image, replace(scan, x_length_mm=50), self.roi, 1, cropped=True)
        self.assertEqual(large.size, (300, 300))
        self.assertEqual(image.getpixel((150, 150)), (0, 0, 0))

    def test_renderer_registry_supports_extensions(self):
        OUTLINE_RENDERERS[ScanPattern.LINEAR] = lambda scan: [("point", (2, 3))]
        try:
            self.assertEqual(pattern_outline(ScanParameters(pattern=ScanPattern.LINEAR)), [("point", (2, 3))])
        finally:
            OUTLINE_RENDERERS.pop(ScanPattern.LINEAR)


if __name__ == "__main__":
    unittest.main()
