from __future__ import annotations

import os
import tempfile
import tkinter as tk
import unittest
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace

import numpy as np

from octoce.phase_peak import (
    PeakHistory,
    PeakReading,
    PhasePeakSettings,
    find_peak,
    settings_from_text,
    value_at,
)

RATE_HZ = 50_000.0  # 1000 samples = 20 ms block
TIME_MS = np.arange(1000) / RATE_HZ * 1000.0


def two_bumps() -> np.ndarray:
    """+2.5 rad at 2 ms (outside the ROI) and -1.5 rad at 8 ms (inside 6–10 ms)."""
    return (2.5 * np.exp(-((TIME_MS - 2.0) / 0.3) ** 2)
            - 1.5 * np.exp(-((TIME_MS - 8.0) / 0.3) ** 2))


class PhasePeakLogicTests(unittest.TestCase):
    def test_auto_peak_is_largest_magnitude_inside_the_roi(self) -> None:
        phase = two_bumps()
        whole = find_peak(TIME_MS, phase, None)
        self.assertAlmostEqual(whole.time_ms, 2.0)
        self.assertAlmostEqual(whole.value_rad, 2.5, places=6)
        roi = find_peak(TIME_MS, phase, (6.0, 10.0))
        self.assertAlmostEqual(roi.time_ms, 8.0)
        self.assertAlmostEqual(roi.value_rad, -1.5, places=6)  # sign kept, |phase| ranked
        self.assertIsNone(find_peak(TIME_MS, phase, (30.0, 40.0)))
        with_nan = phase.copy()
        with_nan[50] = np.nan  # NaN samples are skipped
        self.assertAlmostEqual(find_peak(TIME_MS, with_nan, None).value_rad, 2.5, places=6)

    def test_manual_cursor_reads_the_nearest_sample(self) -> None:
        reading = value_at(TIME_MS, two_bumps(), 8.01)
        self.assertEqual(reading.index, 400)
        self.assertAlmostEqual(reading.value_rad, -1.5, places=6)

    def test_history_keeps_the_window_and_the_maximum(self) -> None:
        history = PeakHistory(seconds=10.0)
        for second, value in ((0.0, 1.0), (5.0, -3.0), (12.0, 2.0)):
            history.add(PeakReading(0, 4.0 + second, value), now=second)
        ages, values = history.as_arrays(now=12.0)
        self.assertEqual(values.tolist(), [3.0, 2.0])  # 0 s dropped, magnitudes
        self.assertEqual(ages.tolist(), [-7.0, 0.0])
        self.assertEqual(history.best, (3.0, 9.0))
        history.reset()
        self.assertIsNone(history.best)

    def test_settings_round_trip_and_validation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "phase_peak.json"
            self.assertEqual(PhasePeakSettings.load(path), PhasePeakSettings())  # no file
            settings = PhasePeakSettings(mode="auto", roi_ms=(6.0, 10.0), view_ms=(1.0, 15.0), history_s=30.0)
            settings.save(path)
            self.assertEqual(PhasePeakSettings.load(path), settings)
            path.write_text("{ broken", encoding="utf-8")
            self.assertEqual(PhasePeakSettings.load(path), PhasePeakSettings())
        fields = {"mode": "auto", "roi_start": "6", "roi_end": "10", "view_start": "", "view_end": "",
                  "history_enabled": True, "history_s": "20", "max_hold": True}
        self.assertEqual(settings_from_text(PhasePeakSettings(), fields).roi_ms, (6.0, 10.0))
        for key, value in (("roi_end", "5"), ("roi_start", "abc"), ("history_s", "0.5")):
            with self.subTest(key=key), self.assertRaises(ValueError):
                settings_from_text(PhasePeakSettings(), {**fields, key: value})


@unittest.skipUnless(os.name == "nt", "Smoke visual de Tkinter para Windows")
class PhasePeakGuiTests(unittest.TestCase):
    def setUp(self) -> None:
        from octoce.config import ScanParameters
        from octoce.gui import OCTOCEApp

        self.tmp = tempfile.TemporaryDirectory()
        self.root = tk.Tk()
        self.root.geometry("1200x800")
        self.app = OCTOCEApp(self.root)
        app = self.app
        app._phase_peak_path = Path(self.tmp.name) / "phase_peak.json"
        app._active_scan = ScanParameters(alines=1, bscans=1, m_repetitions=1000, x_length_mm=0.0,
                                          y_length_mm=0.0)
        app.phase_auto_var.set(True)

    def tearDown(self) -> None:
        self.root.destroy()
        self.tmp.cleanup()

    def show_alignment_frame(self) -> None:
        app = self.app
        phase = np.tile(two_bumps().astype(np.float32), (8, 1))
        app._preview_alignment_rate_hz = RATE_HZ  # what the preview event sets during alignment
        app._show_preview(np.full((8, 1000), 50.0, np.float32), phase, np.arange(8), np.arange(1000), None)
        app.lateral_cursor_var.set(0)  # reference at t = 0 (baseline)
        self.root.update_idletasks()
        app._draw_phase_profile()

    def x_at(self, time_ms: float) -> SimpleNamespace:
        left, width, t0, t1 = self.app._phase_axes
        return SimpleNamespace(x=left + (time_ms - t0) / (t1 - t0) * width)

    def test_auto_peak_manual_cursor_roi_drag_and_persistence(self) -> None:
        app = self.app
        app.phase_peak = PhasePeakSettings(mode="auto", roi_ms=(6.0, 10.0))
        self.show_alignment_frame()
        self.assertIn("Pico |fase| 1.500 rad (-1.500) @ 8.00 ms", app.phase_peak_var.get())
        self.assertIn("máx. retenido 1.500", app.phase_peak_var.get())
        app._draw_phase_profile()  # a redraw is not a new block
        self.assertEqual(len(app._peak_history.samples), 1)
        self.assertTrue(app.phase_history_canvas.winfo_manager())

        app._set_phase_peak(replace(app.phase_peak, mode="manual", manual_ms=2.0))
        self.assertIn("Cursor 2.500 rad", app.phase_peak_var.get())
        app._phase_press(self.x_at(8.0))
        app._phase_release(self.x_at(8.0))
        self.assertAlmostEqual(app.phase_peak.manual_ms, 8.0, delta=0.05)

        app._arm_roi_selection()
        app._phase_press(self.x_at(1.0))
        app._phase_drag(self.x_at(2.0))
        app._phase_release(self.x_at(3.0))
        self.assertFalse(app._roi_select_armed)
        start, end = app.phase_peak.roi_ms
        self.assertAlmostEqual(start, 1.0, delta=0.05)
        self.assertAlmostEqual(end, 3.0, delta=0.05)
        app._set_phase_peak(replace(app.phase_peak, mode="auto"))
        self.assertIn("Pico |fase| 2.500 rad (+2.500) @ 2.00 ms", app.phase_peak_var.get())
        # Remembered for the next session.
        self.assertEqual(PhasePeakSettings.load(app._phase_peak_path), app.phase_peak)

    def test_settings_window_view_window_and_non_alignment_frames(self) -> None:
        app = self.app
        app.phase_peak = PhasePeakSettings(mode="auto")
        self.show_alignment_frame()
        app._open_phase_settings()
        window = app._phase_settings_window
        window.view_start_var.set("5")
        window.view_end_var.set("12")
        self.assertTrue(window.apply())
        self.assertEqual(app._phase_axes[2:], (5.0, 12.0))
        # The auto peak still searches the whole block (no ROI) but is drawn only if visible.
        self.assertIn("@ 2.00 ms", app.phase_peak_var.get())
        window.roi_start_var.set("9")
        window.roi_end_var.set("4")
        self.assertFalse(window.apply())
        self.assertIn("ROI", window.status_var.get())
        window.reset_history()
        self.assertEqual(len(app._peak_history.samples), 0)
        window.window.destroy()
        app._set_phase_peak(replace(app.phase_peak, mode="manual"))  # closed window: no error
        # Frames that are not continuous alignment keep the plain plot.
        app._preview_alignment_rate_hz = None
        app._draw_phase_profile()
        self.assertEqual(app.phase_peak_var.get(), "")
        self.assertFalse(app.phase_history_canvas.winfo_manager())


if __name__ == "__main__":
    unittest.main()
