"""Export independent wave fields and Claude simulator baselines to MATLAB.

Run using the simulator's Python environment (NumPy/SciPy), for example::

    python export_simulator_wave_cases.py --output C:/Temp/simulator_cases.mat

Add --with-fdtd for one CPU elastodynamic non-contact surface-wave case.
The analytic fields test estimators, rather than the full OCT reconstruction.
No simulator source or experimental acquisition is modified. Young truth is
material Young modulus in Pa; speed truth is phase velocity at f_hz.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
from scipy.io import savemat
from scipy.optimize import brentq


def independent_rayleigh_ratio(nu: float) -> float:
    """Solve the nonzero Rayleigh secular root, independent of octsim.theory."""
    gamma2 = (1.0 - 2.0 * nu) / (2.0 * (1.0 - nu))
    return brentq(lambda s: (2.0 - s * s) ** 2
                  - 4.0 * np.sqrt(1.0 - s * s)
                  * np.sqrt(1.0 - gamma2 * s * s), 0.5, 0.999999)


def independent_lamb_a0(E: float, nu: float, rho: float,
                        h: float, f: float) -> float:
    """Free isotropic plate A0 using the scalar Rayleigh-Lamb equation.

    p=i*alpha, q=i*beta for the sub-shear A0 branch; h is full thickness.
    (k^2+beta^2)^2*tanh(alpha*h/2)
        -4*k^2*alpha*beta*tanh(beta*h/2)=0.
    Dimensionless form avoids large k powers and is distinct from the
    simulator's 5x5 SVD implementation. This is lossless, unloaded, unstressed.
    """
    cs = np.sqrt(E / (2.0 * (1.0 + nu) * rho))
    cp = np.sqrt(E * (1.0 - nu) / ((1.0 + nu) * (1.0 - 2.0 * nu) * rho))
    omega = 2.0 * np.pi * f
    beta_r = independent_rayleigh_ratio(nu)

    def determinant(xi: float) -> float:
        alpha = np.sqrt(1.0 - xi * xi * cs * cs / (cp * cp))
        beta = np.sqrt(1.0 - xi * xi)
        kh2 = omega * h / (2.0 * cs * xi)
        return ((1.0 + beta * beta) ** 2 * np.tanh(alpha * kh2)
                - 4.0 * alpha * beta * np.tanh(beta * kh2))

    thin = np.sqrt(omega) * (E * h * h / (12 * rho * (1 - nu * nu))) ** 0.25
    xi_grid = np.linspace(max(0.04, 0.35 * thin / cs),
                          min(beta_r * 1.000001, max(0.99 * beta_r, 1.8 * thin / cs)), 500)
    residual = np.asarray([determinant(s) for s in xi_grid])
    crossings = np.flatnonzero(residual[:-1] * residual[1:] < 0)
    if crossings.size == 0:
        raise RuntimeError(f"A0 root not bracketed: f={f}, h={h}, E={E}")
    i = crossings[0]
    return cs * brentq(determinant, xi_grid[i], xi_grid[i + 1], xtol=1e-13)


def field_case(label: str, model: str, phasor: np.ndarray, x: np.ndarray,
               y: np.ndarray, f: float, speed: float, young: float,
               rng: np.random.Generator, *, snr_db: float = np.inf,
               duration_s: float = 0.02, dt_s: float = 50e-6,
               h: float = 0.0, note: str = "", nu: float = 0.495,
               rho: float = 1000.0, reference_level: float | None = None) -> dict:
    t = np.arange(int(round(duration_s / dt_s))) * dt_s
    # OCT observes an axial real displacement, not the complex phasor itself.
    phasor = phasor / np.sqrt(np.mean(np.abs(phasor) ** 2)) * 10e-9
    u = np.real(phasor[..., None] * np.exp(-2j * np.pi * f * t))
    if np.isfinite(snr_db):
        signal_rms = np.sqrt(np.mean(u * u))
        noise_rms = (reference_level if reference_level is not None else signal_rms)
        noise_rms *= 10 ** (-snr_db / 20.0)
        u += noise_rms * rng.normal(size=u.shape)
    # Extract the observed phasor exactly as the MATLAB harmonic regression
    # (cos, sin, constant); old and new estimators receive the same noisy data.
    basis = np.column_stack((np.cos(2 * np.pi * f * t),
                             np.sin(2 * np.pi * f * t), np.ones(t.size)))
    coeff = np.linalg.lstsq(basis, u.reshape(-1, t.size).T, rcond=None)[0]
    measured_phasor = (coeff[0] - 1j * coeff[1]).reshape(phasor.shape)
    return {
        "label": label, "model": model, "f_hz": f,
        "truth_speed": np.full(phasor.shape, speed),
        "truth_young": np.full(phasor.shape, young),
        "density_kg_m3": rho, "poisson_ratio": nu, "thickness_m": h,
        "window_m": 2.5e-3, "snr_db": snr_db,
        "reverb_model": "shear3d" if model == "bulk_shear" else "scalar2d",
        "data": {"motion": u.astype(np.float32), "x_m": x,
                 "row_m": y, "t_s": t,
                 "valid_mask": np.ones(phasor.shape, dtype=bool),
                 "plane_type": "enface",
                 "metadata": {"source": "analytic_independent_wavefield",
                              "frequency_hz": f, "description": note,
                              "displacement_unit": "m", "phase_coherent": True}},
        "measured_phasor": measured_phasor,
    }


def analytic_cases(seed: int) -> list[dict]:
    rng = np.random.default_rng(seed)
    n = 81
    x = np.arange(n) * 0.125e-3
    y = np.arange(n) * 0.125e-3
    X, Y = np.meshgrid(x, y)
    nu, rho, E = 0.495, 1000.0, 12000.0
    cs = np.sqrt(E / (2 * (1 + nu) * rho))
    cR = independent_rayleigh_ratio(nu) * cs
    f = 1000.0
    k = 2 * np.pi * f / cR
    phi = k * (0.8660254 * X + 0.5 * Y)
    plane = np.exp(1j * phi)
    common = {"note": "Lossless homogeneous half-space Rayleigh field; no OCT noise model."}
    cases = [
        field_case("rayleigh_plane_clean", "rayleigh", plane, x, y, f, cR, E,
                   rng, **common),
        field_case("rayleigh_plane_snr5", "rayleigh", plane, x, y, f, cR, E,
                   rng, snr_db=5, **common),
        field_case("rayleigh_reflected_snr10", "rayleigh",
                   plane + 0.85 * np.exp(-1j * phi + 0.3j), x, y, f, cR, E,
                   rng, snr_db=10,
                   note="Two opposite Rayleigh waves; phase-gradient cancellation at nodes."),
    ]
    scalar = np.zeros_like(plane)
    for theta, phase in zip(rng.uniform(0, 2 * np.pi, 96), rng.uniform(0, 2 * np.pi, 96)):
        scalar += np.exp(1j * (k * (np.cos(theta) * X + np.sin(theta) * Y) + phase))
    cases.append(field_case("rayleigh_2d_diffuse_snr10", "rayleigh", scalar,
                            x, y, f, cR, E, rng, snr_db=10,
                            note="96 random planar directions at one Rayleigh k; J0 AIA model."))
    # True 3D isotropic shear field viewed through its axial z component.
    # Polarization is sampled transverse to each random propagation vector.
    volumetric = np.zeros_like(plane)
    ks = 2 * np.pi * f / cs
    for _ in range(1500):
        qz = rng.uniform(-1.0, 1.0)
        theta = rng.uniform(0.0, 2 * np.pi)
        radial = np.sqrt(1.0 - qz * qz)
        q = np.asarray([radial * np.cos(theta), radial * np.sin(theta), qz])
        e1 = np.cross(q, [0, 0, 1])
        e1 /= np.linalg.norm(e1)
        e2 = np.cross(q, e1)
        angle = rng.uniform(0, 2 * np.pi)
        polarization_z = np.cos(angle) * e1[2] + np.sin(angle) * e2[2]
        phase = rng.uniform(0, 2 * np.pi)
        volumetric += polarization_z * np.exp(1j * (ks * (q[0] * X + q[1] * Y) + phase))
    cases.append(field_case("bulk_shear_3d_diffuse_snr10", "bulk_shear", volumetric,
                            x, y, f, cs, E, rng, snr_db=10,
                            note="1500 random 3D transverse waves observed in XY through u_z; spherical Bessel XY model."))
    for fL, hL, name in ((60.0, 0.4e-3, "lamb_a0_thin_snr10"),
                         (1000.0, 0.8e-3, "lamb_a0_outside_thin_gate_snr10")):
        cL = independent_lamb_a0(E, nu, rho, hL, fL)
        kL = 2 * np.pi * fL / cL
        lamb = np.exp(1j * kL * (0.8660254 * X + 0.5 * Y))
        cases.append(field_case(name, "lamb_a0", lamb, x, y, fL, cL, E, rng,
                                snr_db=10, h=hL, duration_s=12.0 / fL,
                                dt_s=1.0 / (40.0 * fL),
                                note=f"Free unstressed elastic plate A0, scalar Rayleigh-Lamb root; kh={kL*hL:.5f}."))
    attenuation = np.exp(-450 * X)
    cases.append(field_case("rayleigh_attenuation_snr0", "rayleigh", plane * attenuation,
                            x, y, f, cR, E, rng, snr_db=0,
                            note="Amplitude decays by exp(-450*x); fixed white displacement noise, rapid distal SNR loss."))
    for case in cases:
        # Physical propagation direction: with the regression convention
        # u=Re[Pfit*exp(+i*w*t)], the phasor gradient has the opposite sign.
        case["direction_deg"] = 30.0 if "diffuse" not in case["label"] else 0.0
    return cases


def fdtd_case() -> dict:
    """Independent forward-model field from the unchanged Claude simulator."""
    from octsim.excitation import ExcitationConfig
    from octsim.fdtd import FDTDSettings, FDTDSolver
    from octsim.geometry import Geometry, Layer
    from octsim.materials import Material

    m = Material(name="benchmark_gel", E_kPa=12.0, eta_Pa_s=0.0)
    geom = Geometry(size_x_mm=9.0, size_y_mm=3.4, size_z_mm=4.0,
                    layers=[Layer(m, 0.0)], lateral="absorbente", bottom="absorbente")
    exc = ExcitationConfig(mode="arf_sin_contacto", pressure_MPa=0.007,
                           shape="linea", size_a_mm=0.8, size_b_mm=10,
                           center_x_mm=-3, ch2_waveform="Pulso gaussiano",
                           ch2_freq_hz=1000.0, ch2_delay_ms=0,
                           rise_time_us=50)
    st = FDTDSettings(cell_mm=0.15, backend="cpu", pml_cells=8,
                      record_stride=1, record_margin_mm=0.0, record_depth_mm=0.4)
    last_progress = [-100.0]

    def progress(fraction: float, message: str) -> None:
        if fraction - last_progress[0] >= 0.06:
            print(message, flush=True)
            last_progress[0] = fraction

    solver = FDTDSolver(geom, exc, st, (-0.5, 4.0, -1.4, 1.4), progress=progress)
    print("FDTD grid:", solver.describe(), flush=True)
    rec = solver.run_transient(8e-3, 40e-6)
    # Every lateral location is sampled at its own first-solid axial cell.
    surface = np.stack([rec.uz[:, ix, iy, rec.surface_k[ix, iy]]
                        for iy in range(rec.y_m.size)
                        for ix in range(rec.x_m.size)])
    u = surface.reshape(rec.y_m.size, rec.x_m.size, rec.times_s.size)
    # Compare harmonic velocity and displacement consistently: temporal
    # derivative removes the DC/static residual from the finite impulse.
    u = np.gradient(u, rec.times_s, axis=-1)
    f = 1000.0
    t = rec.times_s
    basis = np.column_stack((np.cos(2 * np.pi * f * t),
                             np.sin(2 * np.pi * f * t), np.ones(t.size)))
    coeff = np.linalg.lstsq(basis, u.reshape(-1, t.size).T, rcond=None)[0]
    P = (coeff[0] - 1j * coeff[1]).reshape(u.shape[:2])
    shape = P.shape
    c = independent_rayleigh_ratio(m.nu) * np.sqrt(m.E / (2 * (1 + m.nu) * m.rho))
    truth = np.full(shape, c)
    # Exclude the source near field and numerical absorbing boundaries. The
    # remaining truth is still a continuum expectation, not a fitted answer.
    truth[(rec.x_m[None, :] < 0) | (rec.x_m[None, :] > 3.3e-3)
          | (np.abs(rec.y_m[:, None]) > 1.0e-3)] = np.nan
    return {
        "label": "fdtd_noncontact_rayleigh_cpu", "model": "rayleigh", "f_hz": f,
        "truth_speed": truth, "truth_young": np.where(np.isfinite(truth), m.E, np.nan),
        "density_kg_m3": m.rho, "poisson_ratio": m.nu, "thickness_m": 0.0,
        "window_m": 1.5e-3, "snr_db": np.inf, "reverb_model": "scalar2d",
        "direction_deg": 0.0,
        "data": {"motion": u.astype(np.float32), "x_m": rec.x_m,
                 "row_m": rec.y_m, "t_s": t, "valid_mask": np.ones(shape, dtype=bool),
                 "plane_type": "enface",
                 "metadata": {"source": "claude_fdtd_cpu_elastodynamics",
                              "frequency_hz": f, "displacement_unit": "m/s",
                              "phase_coherent": True,
                              "description": "Noncontact Gaussian air-coupled push; free surface with absorbing lateral/bottom boundaries. Wave speed truth is homogeneous lossless half-space Rayleigh asymptote, not exact finite-domain speed.",
                              "fdtd_cell_m": st.cell_mm * 1e-3,
                              "fdtd_elapsed_s": rec.info.get("tiempo_s", np.nan)}},
        "measured_phasor": P,
    }


def attach_original_estimators(cases: list[dict]) -> list[dict]:
    from octsim import speed as sp
    summary = []
    for case in cases:
        P = case["measured_phasor"]
        d = case["data"]
        dy, dx = np.median(np.diff(d["row_m"])), np.median(np.diff(d["x_m"]))
        cfg = sp.SpeedConfig(window_mm=case["window_m"] * 1e3,
                             c_min=0.2, c_max=6.0)
        normalized_phasor = P / max(np.sqrt(np.mean(np.abs(P) ** 2)), np.finfo(float).tiny)
        methods = {
            "old_phase_gradient": lambda: sp.phase_gradient_speed(P, dy, dx, case["f_hz"], cfg)[0],
            "old_lfe": lambda: sp.lfe_speed(P, dy, dx, case["f_hz"], cfg),
            "old_reverberant": lambda: sp.reverberant_speed(P, dy, dx, case["f_hz"], cfg, "enface")[0],
            "old_reverberant_3d": lambda: sp.reverberant_speed(
                P, dy, dx, case["f_hz"],
                sp.SpeedConfig(window_mm=case["window_m"] * 1e3,
                               c_min=0.2, c_max=6.0, reverb_model="3D"), "enface")[0],
            # Normalization only changes signal units; separate this numerical
            # conditioning benefit from changes in wave physics or estimator.
            "old_reverberant_normalized": lambda: sp.reverberant_speed(
                normalized_phasor, dy, dx, case["f_hz"], cfg, "enface")[0],
            "old_reverberant_3d_normalized": lambda: sp.reverberant_speed(
                normalized_phasor, dy, dx, case["f_hz"],
                sp.SpeedConfig(window_mm=case["window_m"] * 1e3,
                               c_min=0.2, c_max=6.0, reverb_model="3D"), "enface")[0],
        }
        truth = case["truth_speed"]
        # Shared support for observations: a complete local window and a
        # physically sufficient lateral aperture. No imputation of NaN holes.
        half_window = case["window_m"] / 2
        x, y = d["x_m"], d["row_m"]
        support = (np.isfinite(truth)
                   & (x[None, :] >= x[0] + half_window)
                   & (x[None, :] <= x[-1] - half_window)
                   & (y[:, None] >= y[0] + half_window)
                   & (y[:, None] <= y[-1] - half_window))
        case["evaluation_mask"] = support
        for method, compute in methods.items():
            start = time.perf_counter()
            estimate = compute()
            case[method] = estimate
            valid = support & np.isfinite(estimate)
            error = (estimate[valid] - truth[valid]) / truth[valid] * 100
            row = {"case": case["label"], "method": method,
                   "median_speed_m_s": float(np.median(estimate[valid])) if valid.any() else None,
                   "median_bias_pct": float(np.median(error)) if valid.any() else None,
                   "median_abs_error_pct": float(np.median(np.abs(error))) if valid.any() else None,
                   "rmse_relative_pct": float(np.sqrt(np.mean(error ** 2))) if valid.any() else None,
                   "coverage_pct": float(100 * valid.sum() / max(support.sum(), 1)),
                   "elapsed_s": time.perf_counter() - start}
            summary.append(row)
            print(f"{case['label']} {method}: {row['median_bias_pct']}% bias, "
                  f"{row['coverage_pct']:.1f}% coverage", flush=True)
        # Existing simulator formula uses Rayleigh conversion for every field.
        # Persist this baseline to demonstrate inversion bias independently of
        # the speed estimator, especially for Lamb waves and volumetric shear.
        case["old_young_from_truth_speed"] = sp.youngs_modulus_kpa(truth, case["density_kg_m3"], True) * 1000
        case["original_settings"] = cfg.to_dict()
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", type=Path, help="Directory containing octsim/")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=20261004)
    parser.add_argument("--with-fdtd", action="store_true")
    args = parser.parse_args()
    if args.simulator is None:
        repo = Path(__file__).resolve().parents[2]
        matches = list((repo / ".claude" / "worktrees").glob("*/simulator/octsim/speed.py"))
        if len(matches) != 1:
            parser.error("Specify --simulator; cannot identify one Claude simulator checkout.")
        args.simulator = matches[0].parents[1]
    if not (args.simulator / "octsim" / "speed.py").is_file():
        parser.error("--simulator must contain octsim/speed.py")
    sys.path.insert(0, str(args.simulator.resolve()))
    cases = analytic_cases(args.seed)
    if args.with_fdtd:
        cases.append(fdtd_case())
    summary = attach_original_estimators(cases)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Cell arrays retain the MATLAB contract when cases have different sizes.
    cell = np.empty((1, len(cases)), dtype=object)
    for i, case in enumerate(cases):
        cell[0, i] = case
    temporary = args.output.with_suffix(".writing.mat")
    savemat(temporary, {"cases": cell, "seed": args.seed,
                       "simulator_source": str(args.simulator.resolve()),
                       "schema_version": "oce_wave_benchmark_v1"}, do_compression=True,
            long_field_names=True)
    temporary.replace(args.output)
    summary_path = args.output.with_suffix(".baseline.json")
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")
    demo_path = args.output.parent / "demo_plane.mat"
    demo_data = cases[2]["data"]
    savemat(demo_path, {"data": demo_data}, do_compression=True, long_field_names=True)
    print(f"Wrote {len(cases)} cases to {args.output}", flush=True)
    print(f"Original-estimator observations: {summary_path}", flush=True)
    print(f"Interactive reflected-wave demonstration: {demo_path}", flush=True)


if __name__ == "__main__":
    main()
