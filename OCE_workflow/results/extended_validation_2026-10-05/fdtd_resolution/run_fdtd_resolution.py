"""Mesh/time-step sensitivity of the unchanged Claude noncontact FDTD solver.

Run with the simulator .venv Python. Outputs stay beside this script. The
continuum Rayleigh reference is not exact finite-domain/discretized truth.
"""
from pathlib import Path
import argparse
import json
import os
import sys
import time

for variable in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ[variable] = "1"

import numpy as np
from scipy.io import savemat


def main():
    here = Path(__file__).resolve().parent
    workflow = here.parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--simulator", type=Path, default=workflow.parent / ".claude/worktrees/oct-simulator-gui-python-9d18ef/simulator")
    args = parser.parse_args()
    sys.path[:0] = [str(args.simulator), str(workflow / "workflows")]
    from export_simulator_wave_cases import independent_rayleigh_ratio, attach_original_estimators
    from octsim.excitation import ExcitationConfig
    from octsim.fdtd import FDTDSettings, FDTDSolver, MODEL_VERSION
    from octsim.geometry import Geometry, Layer
    from octsim.materials import Material

    material = Material(name="benchmark_gel", E_kPa=12.0, eta_Pa_s=0.0)
    geometry = Geometry(size_x_mm=9.0, size_y_mm=3.4, size_z_mm=4.0,
                        layers=[Layer(material, 0.0)], lateral="absorbente", bottom="absorbente")
    excitation = ExcitationConfig(mode="arf_sin_contacto", pressure_MPa=0.007,
                                 shape="linea", size_a_mm=0.8, size_b_mm=10,
                                 center_x_mm=-3, ch2_waveform="Pulso gaussiano",
                                 ch2_freq_hz=1000.0, ch2_delay_ms=0, rise_time_us=50)
    frequency = 1000.0
    reference = independent_rayleigh_ratio(material.nu) * np.sqrt(material.E / (2 * (1 + material.nu) * material.rho))
    cases, settings_records = [], []
    # Constant physical PML thickness; CFL time step follows mesh refinement.
    for cell_mm, courant in [(0.2, 0.85), (0.15, 0.85), (0.1, 0.85), (0.15, 0.5)]:
        label = f"fdtd_cell_{cell_mm:.2f}mm_courant_{courant:.2f}"
        settings = FDTDSettings(cell_mm=cell_mm, courant=courant, backend="cpu",
                                pml_cells=round(1.2 / cell_mm), record_stride=1,
                                record_margin_mm=0.0, record_depth_mm=0.4)
        start = time.perf_counter()
        last_progress = [-1.0]
        def progress(fraction, message):
            if fraction - last_progress[0] >= 0.15:
                print(label, message, flush=True)
                last_progress[0] = fraction
        solver = FDTDSolver(geometry, excitation, settings, (-0.5, 4.0, -1.4, 1.4), progress=progress)
        description = solver.describe()
        print(label, description, flush=True)
        rec = solver.run_transient(8e-3, 40e-6)
        surface = np.stack([rec.uz[:, ix, iy, rec.surface_k[ix, iy]]
                            for iy in range(rec.y_m.size) for ix in range(rec.x_m.size)])
        motion = surface.reshape(rec.y_m.size, rec.x_m.size, rec.times_s.size)
        motion = np.gradient(motion, rec.times_s, axis=-1)
        t = rec.times_s
        basis = np.column_stack((np.cos(2 * np.pi * frequency * t), np.sin(2 * np.pi * frequency * t), np.ones(t.size)))
        coefficients = np.linalg.lstsq(basis, motion.reshape(-1, t.size).T, rcond=None)[0]
        phasor = (coefficients[0] - 1j * coefficients[1]).reshape(motion.shape[:2])
        truth = np.full(motion.shape[:2], reference)
        truth[(rec.x_m[None, :] < 0) | (rec.x_m[None, :] > 3.3e-3) | (np.abs(rec.y_m[:, None]) > 1.0e-3)] = np.nan
        cases.append(dict(label=label, model="rayleigh", f_hz=frequency,
                          truth_speed=truth, truth_young=np.where(np.isfinite(truth), material.E, np.nan),
                          density_kg_m3=material.rho, poisson_ratio=material.nu,
                          thickness_m=0.0, window_m=1.5e-3, snr_db=np.inf,
                          reverb_model="scalar2d", direction_deg=0.0,
                          data=dict(motion=motion.astype(np.float32), x_m=rec.x_m, row_m=rec.y_m,
                                    t_s=t, valid_mask=np.ones(truth.shape, dtype=bool), plane_type="enface",
                                    metadata=dict(source="claude_fdtd_resolution_sensitivity", frequency_hz=frequency,
                                                  fdtd_cell_m=cell_mm * 1e-3, courant=courant,
                                                  displacement_unit="m/s", phase_coherent=True,
                                                  description="Continuum Rayleigh reference; finite domain, no extrapolated converged truth.")),
                          measured_phasor=phasor))
        settings_records.append(dict(label=label, settings=settings.to_dict(), solver_description=description,
                                     record_info=rec.info, elapsed_s=time.perf_counter()-start,
                                     samples=list(motion.shape), continuum_reference_m_s=reference))
        print(label, "FINISHED", settings_records[-1]["elapsed_s"], flush=True)
    attach_original_estimators(cases)
    savemat(here / "fdtd_cases.mat", {"cases": np.array(cases, dtype=object)}, do_compression=True)
    def serialise(value):
        if isinstance(value, np.generic):
            return value.item()
        if isinstance(value, np.ndarray):
            return value.tolist()
        return str(value)
    (here / "fdtd_settings.json").write_text(json.dumps(dict(model_version=MODEL_VERSION,
        material=material.to_dict(), geometry=geometry.to_dict(), excitation=excitation.to_dict(),
        cases=settings_records, comparison_note="Mesh sensitivity only; no Richardson extrapolation or proven convergence order."),
        indent=2, default=serialise), encoding="utf-8")
    print("FDTD_RESOLUTION_EXPORT_PASS", flush=True)


if __name__ == "__main__":
    main()
