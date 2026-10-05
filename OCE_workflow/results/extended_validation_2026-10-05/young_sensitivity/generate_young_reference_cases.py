"""Independent elastic forward references for observational Young validation.

This generator imports only the independent scalar forward equations from
export_simulator_wave_cases.py. It never calls invertYoungModulus or the
simulator's matrix inversion to generate truth. Re-run with NumPy/SciPy.
"""
from __future__ import annotations

import csv
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import sys

import numpy as np
import scipy


def main() -> None:
    destination = Path(__file__).resolve().parent
    workflow = destination.parents[2]
    reference_file = workflow / "workflows" / "export_simulator_wave_cases.py"
    spec = importlib.util.spec_from_file_location("independent_oce_forward", reference_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    rows = []
    failures = []
    rho = 1000.0
    E_values = (3000.0, 12000.0, 30000.0)
    h_values = (0.1e-3, 0.3e-3, 1.0e-3)
    frequencies = (300.0, 1000.0, 2000.0)
    nu_values = (0.45, 0.495)
    for E, h, f, nu in itertools.product(E_values, h_values, frequencies, nu_values):
        name = f"A0_E{E/1000:g}k_h{h*1000:g}mm_f{f:g}_nu{nu:g}"
        try:
            velocity = module.independent_lamb_a0(E, nu, rho, h, f)
            assert np.isfinite(velocity) and velocity > 0
            rows.append({"case_id": name, "reference_model": "lamb_a0_free",
                         "true_E_pa": E, "true_density_kg_m3": rho,
                         "true_poisson_ratio": nu, "true_thickness_m": h,
                         "frequency_hz": f, "truth_phase_speed_m_s": velocity,
                         "truth_kh": 2 * np.pi * f * h / velocity})
        except Exception as error:
            failures.append({"case_id": name, "error": str(error)})
    for model, E, f, nu in itertools.product(("rayleigh", "bulk_shear"), E_values,
                                            frequencies, nu_values):
        cs = np.sqrt(E / (2 * (1 + nu) * rho))
        velocity = cs * (module.independent_rayleigh_ratio(nu) if model == "rayleigh" else 1)
        rows.append({"case_id": f"{model}_E{E/1000:g}k_f{f:g}_nu{nu:g}",
                     "reference_model": model, "true_E_pa": E,
                     "true_density_kg_m3": rho, "true_poisson_ratio": nu,
                     "true_thickness_m": 0.0, "frequency_hz": f,
                     "truth_phase_speed_m_s": velocity, "truth_kh": np.nan})
    with (destination / "forward_reference_cases.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    metadata = {
        "description": "Independent scalar Rayleigh-Lamb A0 and Rayleigh secular forward references; homogeneous isotropic elastic unstressed unfluidloaded media.",
        "E_pa": E_values, "thickness_m": h_values, "frequency_hz": frequencies,
        "poisson_ratio": nu_values, "density_kg_m3": rho,
        "a0_reference_count": sum(r["reference_model"] == "lamb_a0_free" for r in rows),
        "total_reference_count": len(rows), "reference_failures": failures,
        "python_version": sys.version, "numpy_version": np.__version__, "scipy_version": scipy.__version__,
        "forward_source": str(reference_file),
        "forward_source_sha256": hashlib.sha256(reference_file.read_bytes()).hexdigest(),
        "truth_generation_uses_production_inversion": False,
        "experimental_ground_truth": False,
    }
    (destination / "reference_metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(json.dumps({"reference_rows": len(rows), "A0_rows": metadata["a0_reference_count"],
                      "failures": failures}, indent=2))
    if failures:
        raise SystemExit("Independent forward roots failed; inspect reference_metadata.json.")


if __name__ == "__main__":
    main()
