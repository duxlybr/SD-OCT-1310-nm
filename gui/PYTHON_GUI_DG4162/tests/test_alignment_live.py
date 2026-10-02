from __future__ import annotations

import json
import os
import tempfile
import time
import tkinter as tk
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

from octoce.alignment_metrics import (
    AlignmentProcessor,
    AlignmentReference,
    ProcessingParameters,
    fit_gauss,
    fwhm_direct,
    gauss_model,
)
from octoce.alignment_live import DEFAULT_REFERENCE, AlignmentLiveApp


def _synthetic_frame(blue_scale: float = 1.0, lines: int = 64, seed: int = 0) -> np.ndarray:
    """Gaussian spectrum on the camera with a mirror fringe; blue side scalable."""
    rng = np.random.default_rng(seed)
    px = np.arange(2048, dtype=float)
    envelope = 2000.0 * np.exp(-0.5 * ((px - 1150.0) / 380.0) ** 2)
    envelope[px < 1150] *= 1.0 - (1.0 - blue_scale) * (1150 - px[px < 1150]) / 1150
    params = ProcessingParameters()
    wavelength = np.linspace(params.lambda_start_nm, params.lambda_end_nm, 2048)
    k = 2 * np.pi / wavelength
    fringe = 0.6 * np.cos(2.0 * k * 3.0e5)   # mirror 300 µm (3e5 nm) from zero delay
    frame = envelope * (1.0 + fringe)
    return np.clip(frame[None, :] + rng.normal(0, 4, (lines, 2048)), 0, 4095).astype(np.uint16)


class AlignmentMetricsTests(unittest.TestCase):
    def test_direct_fwhm_and_gauss_fit_recover_known_width(self) -> None:
        x = np.arange(400, dtype=float)
        truth = np.array([5.0, 200.3, 17.5, 0.2])
        y = gauss_model(truth, x)
        self.assertAlmostEqual(fwhm_direct(x, y - truth[3], 200), 17.5, delta=0.1)
        fitted = fit_gauss(x[150:250], y[150:250], np.array([4.0, 199.0, 12.0, 0.0]))
        np.testing.assert_allclose(fitted, truth, rtol=1e-4, atol=1e-4)

    def test_default_reference_matches_matlab_export(self) -> None:
        if not DEFAULT_REFERENCE.exists():
            self.skipTest("config/alineacion_referencia.json no existe")
        reference = AlignmentReference.load(DEFAULT_REFERENCE)
        matlab = json.loads(DEFAULT_REFERENCE.read_text(encoding="utf-8"))["indicadores_matlab"]
        self.assertAlmostEqual(reference.metrics.ratio, matlab["cociente"], places=6)
        self.assertEqual(list(reference.metrics.edges50_px), list(matlab["borde50_px"]))
        self.assertAlmostEqual(reference.metrics.fwhm_spectrum_um, matlab["fwhm_espectro_um"], places=4)

    def test_blue_loss_is_detected_and_reference_round_trips(self) -> None:
        processor = AlignmentProcessor(ProcessingParameters())
        good = processor.process(_synthetic_frame(1.0))
        reference = AlignmentReference.from_result(good, processor.params, "sintetica")
        with tempfile.TemporaryDirectory() as folder:
            path = reference.save(Path(folder) / "ref.json")
            loaded = AlignmentReference.load(path)
        same = processor.process(_synthetic_frame(1.0, seed=1), loaded)
        self.assertLess(same.rms_diff_pct, 1.0)
        weak_blue = processor.process(_synthetic_frame(0.5, seed=2), loaded)
        self.assertLess(weak_blue.blue_change_pct, -10.0)
        self.assertGreater(weak_blue.red_change_pct, -3.0)
        self.assertLess(weak_blue.spectrum.ratio, good.spectrum.ratio)
        self.assertGreater(weak_blue.spectrum.fwhm_spectrum_um, good.spectrum.fwhm_spectrum_um)
        self.assertTrue(np.isfinite(weak_blue.psf.fwhm_fit_um))


class ManualPsfWindowTests(unittest.TestCase):
    def test_manual_window_measures_the_selected_reflector_only(self) -> None:
        params = ProcessingParameters()
        processor = AlignmentProcessor(params)
        wavelength = np.linspace(params.lambda_start_nm, params.lambda_end_nm, 2048)
        k = 2 * np.pi / wavelength
        px = np.arange(2048, dtype=float)
        envelope = 2000.0 * np.exp(-0.5 * ((px - 1150.0) / 380.0) ** 2)
        strong, weak = 0.6 * np.cos(2.0 * k * 3.0e5), 0.15 * np.cos(2.0 * k * 9.0e5)   # 300 and 900 µm
        rng = np.random.default_rng(3)
        frame = np.clip(envelope * (1.0 + strong + weak) + rng.normal(0, 4, (32, 2048)), 0, 4095)

        auto = processor.psf_metrics(frame)   # strongest reflector
        self.assertFalse(auto.manual_window)
        # The weak reflector sits at three times the depth of the strong one.
        manual = processor.psf_metrics(frame, (2.6 * auto.depth_um, 3.4 * auto.depth_um))
        self.assertTrue(manual.manual_window)
        self.assertLess(abs(manual.depth_um - 3 * auto.depth_um), 15.0)   # the 900 µm reflector
        lo, hi = manual.search_px
        self.assertTrue(lo <= manual.window_px.min() and manual.window_px.max() <= hi)
        self.assertTrue(np.isfinite(manual.fwhm_fit_um) and np.isfinite(manual.fwhm_direct_um))
        self.assertEqual(manual.ascan.size, params.n_fft // 2)
        with self.assertRaises(ValueError):
            processor.psf_metrics(frame, (500.0, 503.0))


@unittest.skipUnless(os.name == "nt", "Smoke visual de Tkinter para Windows")
class AlignmentLiveSmokeTests(unittest.TestCase):
    def test_simulated_session_renders_results_and_stops(self) -> None:
        root = tk.Tk()
        try:
            app = AlignmentLiveApp(root)
            if app.processor is None:
                self.skipTest("Sin referencia por defecto")
            app.backend_var.set("Simulación")
            with patch("octoce.alignment_live.messagebox.showerror") as error:
                app._start()
                deadline = time.monotonic() + 20.0
                while app.frames < 2 and time.monotonic() < deadline:
                    root.update()
                    time.sleep(0.02)
                error.assert_not_called()
            self.assertGreaterEqual(app.frames, 2)
            self.assertNotEqual(app.tiles["ratio"].value.cget("text"), "—")
            app._stop()
            app.engine.join(timeout=10.0)
            self.assertFalse(app.engine.is_active)
        finally:
            app._closing = True
            app.analyzer.close()
            root.update_idletasks()
            root.destroy()


if __name__ == "__main__":
    unittest.main()
