from __future__ import annotations

import json
import math
import tempfile
import unittest
from pathlib import Path

import numpy as np

from octoce.alignment_metrics import AlignmentProcessor, ProcessingParameters, lowpass_envelope
from octoce.alignment_pipeline import STEPS, AlignmentPipeline, PipelineTargets

PARAMS = ProcessingParameters()
PIXELS = np.arange(2048, dtype=float)
WAVELENGTH = np.linspace(PARAMS.lambda_start_nm, PARAMS.lambda_end_nm, 2048)
K = 2 * np.pi / WAVELENGTH
ENVELOPE = np.exp(-0.5 * ((PIXELS - 1150.0) / 380.0) ** 2)


def _frame(ir_peak: float, is_peak: float, depth_nm: float | None, visibility: float = 1.0,
           blue_visibility: float | None = None, lines: int = 48, seed: int = 0) -> np.ndarray:
    """Ir + Is + 2*sqrt(Ir*Is)*V*cos(2kz) with random phase per A-line (phase drift)."""
    rng = np.random.default_rng(seed)
    ir, is_ = ir_peak * ENVELOPE, is_peak * ENVELOPE
    v = np.full(2048, visibility)
    if blue_visibility is not None:   # visibility falls linearly towards the blue end (low pixels)
        v = blue_visibility + (visibility - blue_visibility) * PIXELS / 2047
    out = np.empty((lines, 2048))
    for i in range(lines):
        fringe = 0.0 if depth_nm is None else \
            2 * np.sqrt(ir * is_) * v * np.cos(2 * K * depth_nm + rng.uniform(0, 2 * np.pi))
        out[i] = 20.0 + ir + is_ + fringe + rng.normal(0, 3, 2048)
    return np.clip(out, 0, 4095)


class FringeMetricsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.processor = AlignmentProcessor(PARAMS)

    def _fringe(self, frame: np.ndarray, rho: np.ndarray | None = None, dark: float = 20.0):
        psf = self.processor.psf_metrics(frame)
        return self.processor.fringe_metrics(frame, psf, dark=np.full(2048, dark), rho=rho)

    def test_contrast_and_visibility_recover_the_synthetic_values(self) -> None:
        ir, is_, vis = 2000.0, 200.0, 0.8
        f = self._fringe(_frame(ir, is_, 1.4e6, vis), rho=np.full(2048, is_ / ir))
        self.assertTrue(f.valid and f.focus_sensitive)
        expected_contrast = vis * 2 * math.sqrt(is_ / ir) / (1 + is_ / ir)
        self.assertAlmostEqual(f.contrast, expected_contrast, delta=0.03)
        self.assertAlmostEqual(f.visibility, vis, delta=0.04)
        self.assertAlmostEqual(f.blue_red, 1.0, delta=0.06)

    def test_blue_red_detects_a_defocused_blue_end(self) -> None:
        f = self._fringe(_frame(2000.0, 200.0, 1.4e6, 0.9, blue_visibility=0.4))
        self.assertLess(f.blue_red, 0.85)

    def test_covered_arm_has_no_fringe_contrast(self) -> None:
        f = self._fringe(_frame(2000.0, 0.0, None))
        self.assertLess(f.contrast if f.valid else 0.0, 0.03)


class PipelineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.processor = AlignmentProcessor(PARAMS)
        self.pipe = AlignmentPipeline(PipelineTargets())

    def _results(self, frame_args: dict, n: int = 3) -> list:
        return [self.processor.process(_frame(seed=i, **frame_args), dark=self.pipe.dark, rho=self.pipe.rho)
                for i in range(n)]

    def test_full_protocol_with_covered_arms(self) -> None:
        pipe = self.pipe
        self.assertEqual(pipe.step.key, "oscuro")
        dark = self._results(dict(ir_peak=0.0, is_peak=0.0, depth_nm=None))
        self.assertTrue(pipe.evaluate(dark[0], None).ready)
        pipe.capture(dark)
        pipe.next()

        ref = self._results(dict(ir_peak=2300.0, is_peak=0.0, depth_nm=None))
        view = pipe.evaluate(ref[0], None)
        self.assertTrue(view.ready, view.criteria)
        pipe.capture(ref)
        pipe.goto(3)   # "muestra"
        self.assertEqual(pipe.step.key, "muestra")
        limit = pipe.sample_limit_counts()
        # (sqrt(Ir)+sqrt(Is))^2 <= 0.9*4095 - dark  ->  analytic limit at the envelope peak
        expected = (math.sqrt(0.9 * 4095 - 20.0) - math.sqrt(2300.0)) ** 2
        self.assertAlmostEqual(limit, expected, delta=0.03 * expected)
        too_strong = self._results(dict(ir_peak=0.0, is_peak=1.5 * limit, depth_nm=None))
        self.assertIn("Cierre", pipe.evaluate(too_strong[0], None).hint)
        sample = self._results(dict(ir_peak=0.0, is_peak=0.6 * limit, depth_nm=None))
        self.assertTrue(pipe.evaluate(sample[0], None).ready)
        pipe.capture(sample)
        self.assertAlmostEqual(pipe.mean_rho(), 0.6 * limit / 2300.0, delta=0.01)

        pipe.goto(4)
        shallow = self._results(dict(ir_peak=2300.0, is_peak=0.6 * limit, depth_nm=4.0e5, visibility=0.9))
        pipe.capture(shallow)
        self.assertAlmostEqual(pipe.shallow["visibility"], 0.9, delta=0.06)
        pipe.goto(5)
        deep = self._results(dict(ir_peak=2300.0, is_peak=0.6 * limit, depth_nm=2.0e6, visibility=0.5))
        view = pipe.evaluate(deep[0], None)
        self.assertEqual(view.criteria[0].status, "good")      # depth inside the focus range
        pipe.capture(deep)
        drop, p3_drop = pipe.contrast_drop_db()
        self.assertAlmostEqual(drop, 10 * math.log10(0.5 / 0.9), delta=0.5)
        self.assertLess(p3_drop, 0)
        pipe.goto(6)
        pipe.capture(shallow)
        self.assertIsNotNone(pipe.sharpness_baseline)
        with tempfile.TemporaryDirectory() as folder:
            report = json.loads(pipe.save_report(Path(folder)).read_text(encoding="utf-8"))
        self.assertEqual(len(report["ir"]), 2048)
        self.assertIn("caida_contraste_db", report)

    def test_targets_round_trip_and_p3_expectation(self) -> None:
        targets = PipelineTargets()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "objetivos.json"
            targets.save(path)
            self.assertEqual(PipelineTargets.load(path), targets)
        self.assertAlmostEqual(targets.expected_relative_contrast(579.0, 2080.0), 0.497 / 0.815, places=3)
        self.assertEqual([s.key for s in STEPS], ["oscuro", "referencia", "forma", "muestra",
                                                  "interferencia", "enfoque", "verificacion"])

    def test_envelope_helper_removes_fringes(self) -> None:
        frame = _frame(2000.0, 200.0, 1.0e6).mean(axis=0)
        env = lowpass_envelope(frame)
        bright = ENVELOPE > 0.3
        error = np.abs(env - (20 + 2200 * ENVELOPE))[bright]
        self.assertLess(np.max(error), 0.03 * 2200)   # 6-bin low-pass, as in MATLAB


if __name__ == "__main__":
    unittest.main()
