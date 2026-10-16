"""Pruebas de la adquisición (equivalencia con octoce), la señal OCT y el procesamiento."""
from __future__ import annotations

import sys
import unittest
from math import pi
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT.parent / "gui" / "PYTHON_GUI_DG4162"))

from octsim.acquisition import AcquisitionConfig, build_plan, sweep_positions  # noqa: E402
from octsim.excitation import ExcitationConfig  # noqa: E402
from octsim.fdtd import FieldRecord  # noqa: E402
from octsim.geometry import Geometry, Layer  # noqa: E402
from octsim.materials import Material  # noqa: E402
from octsim.oct_signal import OCTSimulator, OCTSystem  # noqa: E402
from octsim.processing import (detect_surface, loupas_phase_increment, phase_to_displacement,  # noqa: E402
                               surface_window_start)

try:
    from octoce.config import (AcquisitionMode, HardwareConfig, Orientation, ScanParameters,  # noqa: E402
                               ScanPattern, optimized_scan_period_ticks)
    from octoce.scan import ScanPlanner  # noqa: E402
    OCTOCE = True
except Exception:  # noqa: BLE001
    OCTOCE = False

PATTERN_MAP = {"raster": "RASTER", "crosshair": "CROSSHAIR", "meridianos": "MERIDIANS", "lineal": "LINEAR"}


@unittest.skipUnless(OCTOCE, "octoce no disponible")
class OctoceEquivalenceTests(unittest.TestCase):
    """El plan simulado reproduce posiciones y temporización de la GUI de adquisición real."""

    CASES = [("MB", "raster", 32, 8, 200, 50, 0.0), ("MB", "lineal", 64, 3, 400, 200, 120.0),
             ("BM", "crosshair", 100, 2, 4, 50, 0.0), ("BM", "meridianos", 50, 6, 3, 30, 30.0),
             ("MB", "crosshair", 20, 1, 100, 0, 0.0)]

    def _pair(self, case: tuple) -> tuple[AcquisitionConfig, ScanParameters, HardwareConfig]:
        mode, pat, A, B, M, sync, delay = case
        ours = AcquisitionConfig(mode=mode, pattern=pat, alines=A, bscans=B, m_reps=M, sync_points=sync,
                                 x_length_mm=4.0, y_length_mm=3.0, bframes_delay_us=delay)
        sp = ScanParameters(alines=A, bscans=B, m_repetitions=M, sync_points=sync, x_length_mm=4.0,
                            y_length_mm=3.0, mode=AcquisitionMode[mode], pattern=ScanPattern[PATTERN_MAP[pat]],
                            orientation=Orientation.HORIZONTAL, bframes_delay_us=delay)
        return ours, sp, HardwareConfig()

    def test_segment_period_and_hold(self) -> None:
        for case in self.CASES:
            ours, sp, hw = self._pair(case)
            nominal = sp.sync_points + sp.lines_per_segment + hw.oce_post_hold_points(sp)
            ref = optimized_scan_period_ticks(hw, active_start=sp.sync_points, active_count=sp.lines_per_segment,
                                              nominal_ticks=nominal, bframes_delay_us=sp.bframes_delay_us)
            self.assertEqual(ours.hold_points(), hw.oce_post_hold_points(sp), msg=str(case))
            self.assertEqual(ours.segment_ticks(), ref, msg=str(case))
            self.assertAlmostEqual(ours.cc1_period_us, hw.cc1_period_us)
            self.assertEqual(ours.n_segments, sp.total_segments)

    def test_positions_match_planner_lines(self) -> None:
        for case in self.CASES:
            ours, sp, hw = self._pair(case)
            planner = ScanPlanner(sp, hw)
            for b in range(sp.bscans):
                for s, (_label, line) in enumerate(planner._sweeps(b)):
                    np.testing.assert_allclose(sweep_positions(ours, b)[s], line, atol=1e-12, err_msg=str(case))

    def test_trigger_count(self) -> None:
        for case in self.CASES:
            ours, sp, _hw = self._pair(case)
            self.assertEqual(build_plan(ours).trigger_times.size, sp.oce_trigger_segments, msg=str(case))


class ProcessingTests(unittest.TestCase):
    def test_loupas_constant_phase_ramp(self) -> None:
        """Rampa de fase pura: Loupas devuelve phi_actual - phi_siguiente = -delta [Loupas1995]."""
        rng = np.random.default_rng(1)
        A0 = rng.uniform(0.5, 1.5, 64) * np.exp(0.7j)       # fase axial constante: término axial = 0
        delta = 0.3
        iq = A0[:, None] * np.exp(1j * delta * np.arange(20))[None, :]
        out = loupas_phase_increment(iq, 4)
        self.assertEqual(out.shape, (61, 19))
        np.testing.assert_allclose(out, -delta, atol=1e-12)

    def test_surface_correction_song2013(self) -> None:
        """Superficie en aire: du_sup = dOPL_sup; subsuperficie: (dOPL + (n-1) dOPL_sup)/n."""
        lam = 1.3e-6
        n = 1.4
        u_s = 2e-9
        u_in = 3e-9
        dopl = np.zeros((1, 10, 1))
        dopl[0, 3:, 0] = n * u_in - (n - 1) * u_s
        dopl[0, 3, 0] = u_s
        dphi = -dopl * 4 * pi / lam
        du, du_s = phase_to_displacement(dphi, lam, n, np.array([3]), True, 1)
        self.assertAlmostEqual(du_s[0, 0], u_s, delta=1e-15)
        self.assertAlmostEqual(du[0, 6, 0], u_in, delta=1e-15)


class OCTChainTests(unittest.TestCase):
    def test_uniform_motion_is_recovered(self) -> None:
        """Traslación rígida conocida: la cadena OCT simulada (Loupas + Song) recupera du."""
        geom = Geometry(size_x_mm=2, size_y_mm=2, size_z_mm=1.0, layers=[Layer(Material(E_kPa=10, n=1.38), 0.0)])
        acq = AcquisitionConfig(mode="MB", pattern="lineal", alines=8, bscans=1, m_reps=120, sync_points=10,
                                x_length_mm=1.0, y_length_mm=0.0)
        exc = ExcitationConfig(ch2_delay_ms=0.0)
        plan = build_plan(acq)
        x = np.linspace(-1, 1, 5) * 1e-3
        y = np.array([-0.1e-3, 0.1e-3])
        z = np.linspace(-0.05e-3, 1.0e-3, 30)
        t = np.arange(400) * 20e-6
        # pulso que se extingue antes del siguiente disparo (T_seg ~ 2.7 ms): solo cuenta el disparo actual
        u_t = 80e-9 * np.sin(2 * pi * 800 * t) * np.exp(-(((t - 1.0e-3) / 0.35e-3) ** 2))
        uz = np.zeros((t.size, x.size, y.size, z.size), np.float32)
        ks = int(np.searchsorted(z, 0.0))
        uz[:, :, :, ks:] = u_t[:, None, None, None]
        rec = FieldRecord("transitorio", x, y, z, times_s=t, uz=uz,
                          surface_k=np.full((x.size, y.size), ks), info={})
        sim = OCTSimulator(OCTSystem(depth_window_mm=0.6), geom, rec, plan, exc)
        out = sim.bscan(0, 0, np.random.default_rng(0))
        I = 10 * np.log10(np.mean(np.abs(out["data"]) ** 2, axis=2))
        s = detect_surface(I, 10)
        dphi = loupas_phase_increment(out["data"], 4)
        _du, du_s = phase_to_displacement(dphi, 1317.97e-9, 1.38, surface_window_start(I, s, 4), True, 3)
        times = out["times"]
        onsets = plan.trigger_times
        trel = times - onsets[np.clip(np.searchsorted(onsets, times, side="right") - 1, 0, None)]
        truth = np.diff(np.interp(trel, t, u_t), axis=1)
        gain = float(np.sum(du_s * truth) / np.sum(truth * truth))
        r = float(np.corrcoef(du_s.ravel(), truth.ravel())[0, 1])
        self.assertGreater(r, 0.98)
        self.assertAlmostEqual(gain, 1.0, delta=0.05)


if __name__ == "__main__":
    unittest.main()
