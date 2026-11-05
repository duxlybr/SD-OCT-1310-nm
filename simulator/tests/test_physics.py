"""Pruebas de la física: teoría analítica, solver FDTD y estimadores de velocidad."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from octsim import theory  # noqa: E402
from octsim.backend import GPU_AVAILABLE  # noqa: E402
from octsim.excitation import ExcitationConfig  # noqa: E402
from octsim.fdtd import FDTDSettings, FDTDSolver  # noqa: E402
from octsim.geometry import Geometry, Inclusion, Layer  # noqa: E402
from octsim.materials import Material  # noqa: E402
from octsim import speed as sp  # noqa: E402


class TheoryTests(unittest.TestCase):
    def test_rayleigh_ratio_classical_values(self) -> None:
        # nu = 0.25 -> 0.9194 (valor clásico); nu -> 0.5 -> 0.9553 [Rayleigh1885]
        self.assertAlmostEqual(theory.rayleigh_ratio_elastic(0.25), 0.9194, places=3)
        self.assertAlmostEqual(theory.rayleigh_ratio_elastic(0.4999), 0.9553, places=3)

    def test_kelvin_voigt_elastic_limit(self) -> None:
        m = Material(E_kPa=12.0, eta_Pa_s=0.0)
        self.assertAlmostEqual(float(theory.shear_phase_velocity(m, 1000.0)), m.cs, places=9)
        mv = Material(E_kPa=12.0, eta_Pa_s=0.5)
        self.assertGreater(float(theory.shear_phase_velocity(mv, 2000.0)),
                           float(theory.shear_phase_velocity(mv, 500.0)))

    def test_lamb_free_plate_low_frequency_limit(self) -> None:
        m = Material(E_kPa=12.0)
        f = np.array([20.0, 50.0])
        a0 = theory.lamb_a0_phase_velocity(theory.LambConfig(m, 0.5e-3, None), f)
        kir = theory.lamb_a0_low_frequency(m, 0.5e-3, f)
        np.testing.assert_allclose(a0, kir, rtol=0.03)

    def test_lamb_high_frequency_tends_to_rayleigh(self) -> None:
        m = Material(E_kPa=12.0)
        a0 = theory.lamb_a0_phase_velocity(theory.LambConfig(m, 0.5e-3, None), np.array([6000.0]))
        self.assertAlmostEqual(a0[0] / (theory.rayleigh_ratio_elastic(m.nu) * m.cs), 1.0, delta=0.03)

    def test_fluid_speed_reduction_is_negligible_for_a0(self) -> None:
        m = Material(E_kPa=12.0)
        w = Material("agua", is_fluid=True, rho=1000, c_acoustic=1480)
        f = np.array([500.0, 1500.0])
        real = theory.lamb_a0_phase_velocity(theory.LambConfig(m, 0.5e-3, w, 1480.0), f)
        sim = theory.lamb_a0_phase_velocity(theory.LambConfig(m, 0.5e-3, w, 10 * m.cs), f)
        np.testing.assert_allclose(sim, real, rtol=2e-3)


class FDTDTests(unittest.TestCase):
    def _solver(self, backend: str, lateral: str = "absorbente", bottom: str = "absorbente") -> FDTDSolver:
        m = Material(name="gel", E_kPa=12.0, eta_Pa_s=0.1)
        geom = Geometry(size_x_mm=3, size_y_mm=3, size_z_mm=1.5, layers=[Layer(m, 0.0)],
                        lateral=lateral, bottom=bottom,
                        inclusions=[Inclusion(Material(name="inc", E_kPa=40, eta_Pa_s=0.1), "esfera",
                                              (0.6, 0, 0.5), (0.3, 0, 0))])
        exc = ExcitationConfig(mode="arf_contacto", pressure_MPa=1.0, size_a_mm=0.4, ch2_freq_hz=2000,
                               ch2_delay_ms=0)
        st = FDTDSettings(cell_mm=0.1, backend=backend, pml_cells=6, record_stride=1)
        return FDTDSolver(geom, exc, st, (-1, 1, -1, 1))

    def test_cpu_reference_is_stable(self) -> None:
        rec = self._solver("cpu").run_transient(0.6e-3, 20e-6)
        self.assertTrue(np.isfinite(rec.uz).all())
        self.assertGreater(np.abs(rec.uz).max(), 0)

    @unittest.skipUnless(GPU_AVAILABLE, "requiere GPU con CuPy")
    def test_gpu_kernels_match_numpy_reference(self) -> None:
        for lat, bot in (("absorbente", "absorbente"), ("libre", "rigido"), ("empotrado", "libre")):
            a = self._solver("gpu", lat, bot).run_transient(0.6e-3, 20e-6).uz
            b = self._solver("cpu", lat, bot).run_transient(0.6e-3, 20e-6).uz
            self.assertLess(np.abs(a - b).max() / np.abs(b).max(), 1e-5, msg=f"{lat}/{bot}")

    @unittest.skipUnless(GPU_AVAILABLE, "requiere GPU con CuPy")
    def test_rayleigh_phase_velocity(self) -> None:
        """Velocidad de fase de superficie a 7-11 mm de una fuente lineal vs Rayleigh (< 2 %)."""
        m = Material(name="gel", E_kPa=12.0, eta_Pa_s=0.0)
        geom = Geometry(size_x_mm=16, size_y_mm=2, size_z_mm=7, layers=[Layer(m, 0.0)])
        exc = ExcitationConfig(mode="arf_contacto", shape="linea", size_a_mm=0.4, size_b_mm=20, pressure_MPa=2.0,
                               ch2_waveform="Pulso gaussiano", ch2_freq_hz=1000, ch2_delay_ms=0,
                               focal_depth_mm=1, dof_mm=4, center_x_mm=-7)
        st = FDTDSettings(cell_mm=0.08, backend="gpu", pml_cells=14, record_stride=1, record_depth_mm=0.3)
        rec = FDTDSolver(geom, exc, st, (-7.5, 8, -0.1, 0.1)).run_transient(14e-3, 20e-6)
        jy = rec.y_m.size // 2
        ks = rec.surface_k[:, jy]
        u = np.stack([rec.uz[:, i, jy, ks[i]] for i in range(rec.x_m.size)], axis=1)
        x = rec.x_m * 1e3
        v = np.gradient(u, rec.times_s, axis=0)
        F = np.fft.rfft(v, n=8192, axis=0)
        f = np.fft.rfftfreq(8192, rec.times_s[1] - rec.times_s[0])
        sel = (x >= 0) & (x <= 4)
        for fi in (1000.0, 1400.0):
            i = np.argmin(abs(f - fi))
            k = -np.polyfit(x[sel] * 1e-3, np.unwrap(np.angle(F[i, sel])), 1)[0]
            c = 2 * np.pi * fi / k
            self.assertAlmostEqual(c / theory.rayleigh_phase_velocity(m, fi)[0], 1.0, delta=0.02)


class SpeedEstimatorTests(unittest.TestCase):
    f = 2000.0
    c = 4.0
    d = 0.1e-3
    n = 100

    def _grid(self) -> tuple[np.ndarray, np.ndarray]:
        return np.meshgrid(np.arange(self.n) * self.d, np.arange(self.n) * self.d, indexing="ij")

    def test_plane_wave_phase_gradient_and_lfe(self) -> None:
        y, x = self._grid()
        k = 2 * np.pi * self.f / self.c
        P = np.exp(1j * k * (np.cos(0.5) * x + np.sin(0.5) * y))
        cfg = sp.SpeedConfig(window_mm=2.0)
        c_pg, _ = sp.phase_gradient_speed(P, self.d, self.d, self.f, cfg)
        self.assertAlmostEqual(float(np.nanmedian(c_pg)), self.c, delta=0.01)
        c_lfe = sp.lfe_speed(P, self.d, self.d, self.f, cfg)
        self.assertAlmostEqual(float(np.nanmedian(c_lfe)), self.c, delta=0.05)

    def test_time_of_flight(self) -> None:
        y, x = self._grid()
        t = np.arange(400) * 20e-6
        r = np.sqrt((x - 5e-3) ** 2 + (y + 2e-3) ** 2)
        v = np.exp(-((t[None, None, :] - 1e-3 - r[..., None] / self.c) / 2e-4) ** 2)
        T = sp.arrival_times(v, t)
        c = sp.tof_speed(T, self.d, self.d, sp.SpeedConfig(window_mm=2.0))
        self.assertAlmostEqual(float(np.nanmedian(c)), self.c, delta=0.05)

    def test_reverberant_3d_monte_carlo(self) -> None:
        """Campo reverberante de [Zvietcovich2019, Ec. (1)]; ajuste a la Ec. (2) dentro de 6 %."""
        y, x = self._grid()
        k = 2 * np.pi * self.f / self.c
        rng = np.random.default_rng(0)
        Q = 3000
        th = np.arccos(rng.uniform(-1, 1, Q))
        ph = rng.uniform(0, 2 * np.pi, Q)
        nq = np.stack([np.sin(th) * np.cos(ph), np.sin(th) * np.sin(ph), np.cos(th)], 1)
        e1 = np.cross(nq, [0, 0, 1.0])
        e1 /= np.linalg.norm(e1, axis=1, keepdims=True) + 1e-12
        e2 = np.cross(nq, e1)
        a = rng.uniform(0, 2 * np.pi, Q)
        pol = np.cos(a)[:, None] * e1 + np.sin(a)[:, None] * e2
        amp = rng.uniform(-1, 1, Q)
        phi0 = rng.uniform(0, 2 * np.pi, Q)
        X, Y = x.ravel(), y.ravel()
        Pz = ((amp * pol[:, 2])[None, :] * np.exp(1j * (k * (np.outer(X, nq[:, 0]) + np.outer(Y, nq[:, 1]))
                                                       + phi0))).sum(1).reshape(self.n, self.n)
        c, _ = sp.reverberant_speed(Pz, self.d, self.d, self.f, sp.SpeedConfig(window_mm=2.5, reverb_model="3D"),
                                    "enface")
        self.assertAlmostEqual(float(np.nanmedian(c)) / self.c, 1.0, delta=0.06)

    def test_reverberant_profiles_are_normalized(self) -> None:
        for model in ("3D_perp", "3D_par", "2D"):
            self.assertAlmostEqual(float(sp.reverb_model_profile(model, np.array([1e-6]))[0]), 1.0, places=5)


if __name__ == "__main__":
    unittest.main()
