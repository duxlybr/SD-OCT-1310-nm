"""Validación cuantitativa de cada simulación contra la teoría y contra la verdad del FDTD.

1. Dispersión k-f medida en la superficie frente a la curva teórica del modelo
   (Rayleigh viscoelástico [Rayleigh1885; Christensen1982], Lamb A0 libre
   [Lamb1917] o con fluido (mRLFE) [Han2017], o corte Kelvin-Voigt [Chen2004]).
2. Medianas de los mapas de velocidad en regiones de interés frente al valor
   esperado (teoría a la frecuencia de análisis o propiedades de la inclusión).
3. Cadena OCT: incrementos de desplazamiento superficial medidos con OCT
   (Loupas + conversión de fase) frente a los del campo FDTD en las mismas
   posiciones e instantes (correlación de Pearson y ganancia).
"""
from __future__ import annotations

from typing import Any

import numpy as np

from . import theory
from .materials import Material


def auto_model(cfg: Any, f_hz: float) -> tuple[str, dict[str, Any]]:
    """Elige el modelo teórico para la superficie de la capa superior."""
    spec = cfg.validation
    g = cfg.geometry
    layer = g.layers[min(spec.layer, len(g.layers) - 1)]
    mat = layer.material
    model = spec.model
    lam_R = theory.rayleigh_speed_approx(mat) / max(f_hz, 1.0) * 1e3      # mm
    if model == "auto":
        if len(g.layers) >= 2 and g.layers[0].thickness_mm > 0 and g.layers[1].material.is_fluid:
            model = "lamb_fluido"
        elif len(g.layers) == 1 and g.bottom == "libre" and g.size_z_mm < 2 * lam_R:
            model = "lamb_libre"
        else:
            model = "rayleigh"
    kw: dict[str, Any] = {"material": mat}
    if model == "lamb_fluido":
        kw["thickness_m"] = g.layers[0].thickness_mm * 1e-3
        kw["fluid"] = g.layers[1].material
        from .fdtd import auto_fluid_speed  # noqa: PLC0415
        kw["c_fluid"] = auto_fluid_speed(g.materials())
    elif model == "lamb_libre":
        kw["thickness_m"] = (g.layers[0].thickness_mm or g.size_z_mm) * 1e-3
    return model, kw


THEORY_NAMES = {"rayleigh": "rayleigh", "lamb_libre": "lamb_free", "lamb_fluido": "lamb_fluid",
                "corte": "shear"}


def theory_curve(model: str, kw: dict[str, Any], f: np.ndarray) -> np.ndarray:
    if model not in THEORY_NAMES:
        return np.full_like(np.asarray(f, float), np.nan)
    return theory.reference_curve(THEORY_NAMES[model], f, **kw)


def _expected_value(expr: Any, cfg: Any, f: float, model: str, kw: dict[str, Any]) -> tuple[float, str]:
    g = cfg.geometry
    if isinstance(expr, (int, float)):
        return float(expr), "valor fijo"
    if expr == "teoria":
        return float(theory_curve(model, kw, np.array([f]))[0]), f"{model} @ {f:.0f} Hz"
    kind, _, idx = str(expr).partition(":")
    mats = g.materials()
    m: Material = mats[int(idx)] if idx else g.layers[0].material
    if kind == "corte":
        return float(theory.shear_phase_velocity(m, f)), f"corte KV de {m.name} @ {f:.0f} Hz [Chen2004]"
    if kind == "rayleigh":
        return float(theory.rayleigh_phase_velocity(m, f)[0]), f"Rayleigh de {m.name} @ {f:.0f} Hz"
    raise ValueError(f"Valor esperado desconocido: {expr}")


def _region_mask(sm: Any, region: Any, cfg: Any) -> np.ndarray:
    A1, A2 = np.meshgrid(sm.axis1_mm, sm.axis2_mm, indexing="ij")
    g = cfg.geometry
    exc = cfg.excitation
    if isinstance(region, (list, tuple)):
        x0, x1, a0, a1 = region
        return (A2 >= x0) & (A2 <= x1) & (A1 >= a0) & (A1 <= a1)
    incl_mask = np.zeros_like(A1, dtype=bool)
    for k, inc in enumerate(g.inclusions):
        cx, cy, cz = inc.center_mm
        r = max(inc.size_mm[0], inc.size_mm[1] if inc.shape != "cilindro" else inc.size_mm[0])
        if sm.plane.startswith("enface"):
            d = np.hypot(A2 - cx, A1 - cy) if inc.shape != "cilindro" or inc.axis == "z" else (
                np.abs(A2 - cx) if inc.axis == "y" else np.abs(A1 - cy))
        else:
            d = np.hypot(A2 - cx, A1 - cz)
        if str(region) == f"inclusion:{k}":
            return d <= 0.7 * r
        incl_mask |= d <= r + cfg.speed.window_mm / 2
    if str(region) == "fondo":
        src = np.zeros_like(incl_mask)
        if sm.plane.startswith("enface"):
            src = np.hypot(A2 - exc.center_x_mm, A1 - exc.center_y_mm) < max(exc.size_a_mm, 0.3) * 1.5
        return ~incl_mask & ~src
    raise ValueError(f"Región desconocida: {region}")


def run_validation(res: Any) -> dict[str, Any]:
    cfg = res.cfg
    spec = cfg.validation
    f_an = res.f_analysis_hz
    model, kw = auto_model(cfg, f_an)
    checks: list[dict[str, Any]] = []
    out: dict[str, Any] = {"modelo": model, "frecuencia_hz": f_an}
    if model != "ninguno":
        out["velocidad_teorica_m_s"] = float(theory_curve(model, kw, np.array([f_an]))[0])

    # 1) dispersión k-f
    if res.kf is not None and model in THEORY_NAMES:
        f = res.kf["f_hz"]
        c = res.kf["c_mean"]
        mag = res.kf["magnitude"]
        lo, hi = spec.band_hz if spec.band_hz[1] > 0 else (cfg.processing.filter_low_hz,
                                                           cfg.processing.filter_high_hz)
        band = (f >= lo) & (f <= hi) & np.isfinite(c) & (mag >= 0.3 * np.nanmax(mag))
        if band.sum() >= 3:
            fb = f[band]
            # submuestreo para no evaluar la teoría en miles de frecuencias
            idx = np.unique(np.linspace(0, fb.size - 1, min(25, fb.size)).astype(int))
            cm = c[band][idx]
            detail = f"{model}, banda {fb.min():.0f}-{fb.max():.0f} Hz, mediana |error|"
            if model in ("lamb_libre", "lamb_fluido"):
                # identificación de modo: raíz de la mRLFE más cercana [Han2017]
                modes = theory.lamb_all_modes(theory.LambConfig(kw["material"], kw["thickness_m"],
                                                                kw.get("fluid"), kw.get("c_fluid")), fb[idx])
                nearest = np.nanargmin(np.abs(modes - cm[:, None]), axis=1)
                th = modes[np.arange(cm.size), nearest]
                detail += "; modo de la mRLFE más cercano a cada punto"
                out["kf_modos_teoricos"] = modes.tolist()
            else:
                th = theory_curve(model, kw, fb[idx])
            err = 100 * (cm / th - 1)
            med = float(np.nanmedian(np.abs(err)))
            checks.append({"nombre": "Dispersión k-f vs teoría", "valor": float(np.nanmedian(cm)),
                           "esperado": float(np.nanmedian(th)), "error_pct": med,
                           "tol_pct": spec.tolerance_pct, "ok": bool(med <= spec.tolerance_pct),
                           "detalle": detail})
            out["kf_curva"] = {"f_hz": fb[idx].tolist(), "c_medida": cm.tolist(), "c_teoria": th.tolist()}
    # 2) regiones de interés en los mapas
    for chk in spec.checks:
        maps = [m for m in res.speed_maps if m.plane == chk.get("plano", "enface")
                and m.method == chk.get("metodo")]
        if not maps:
            continue
        sm = maps[0]
        try:
            mask = _region_mask(sm, chk.get("region", "fondo"), cfg) & np.isfinite(sm.c)
        except ValueError as exc:
            checks.append({"nombre": chk.get("nombre", "?"), "ok": False, "detalle": str(exc)})
            continue
        if mask.sum() < 4:
            checks.append({"nombre": chk.get("nombre", "?"), "ok": False,
                           "detalle": "sin píxeles válidos en la región"})
            continue
        val = float(np.median(sm.c[mask]))
        exp, why = _expected_value(chk.get("esperado", "teoria"), cfg, f_an, model, kw)
        err = 100 * (val / exp - 1)
        tol = float(chk.get("tol_pct", 15.0))
        checks.append({"nombre": chk.get("nombre", f"{sm.method} {sm.plane}"), "valor": val, "esperado": exp,
                       "error_pct": err, "tol_pct": tol, "ok": bool(abs(err) <= tol),
                       "detalle": f"{sm.method} ({sm.plane}), región {chk.get('region')}, {why}"})
    # 3) cadena OCT
    tc = res.truth_check
    if tc is not None and np.isfinite(tc.get("r", np.nan)):
        ok = tc["r"] >= spec.oct_chain_min_r and abs(tc["ganancia"] - 1) <= 0.15
        checks.append({"nombre": "Cadena OCT vs verdad FDTD", "valor": tc["r"], "esperado": 1.0,
                       "error_pct": 100 * (tc["ganancia"] - 1), "tol_pct": 15.0, "ok": bool(ok),
                       "detalle": f"r = {tc['r']:.3f}, ganancia = {tc['ganancia']:.3f}, ruido "
                                  f"{tc.get('ruido_nm', 0):.2f} nm/A-line, {tc.get('muestras', 0)} muestras > 3 sigma "
                                  "(Loupas + corrección [Song2013])"})
    out["checks"] = checks
    out["aprobado"] = bool(checks) and all(c.get("ok", False) for c in checks)
    return out


def truth_comparison(res: Any, sim: Any) -> dict[str, Any] | None:
    """Compara los incrementos de desplazamiento superficial OCT con la verdad FDTD."""
    if not res.bmode or res.surface_du is None:
        return None
    bm = res.bmode[0]
    b, s = bm["b"], bm["s"]
    pos = res.plan.positions[b, s]
    times = res.plan.aline_times(b, s)
    f = res.field
    dopl = sim.delta_opl_columns(pos, times) * 1e-3                # [A, M, nz] mm -> m
    ix = np.array([np.argmin(np.abs(f.x_m * 1e3 - p)) for p in pos[:, 0]])
    iy = np.array([np.argmin(np.abs(f.y_m * 1e3 - p)) for p in pos[:, 1]])
    ks = np.clip(f.surface_k[ix, iy] + 1, 0, f.z_m.size - 1)
    u_true = dopl[np.arange(pos.shape[0]), :, ks]                  # [A, M] (en la superficie dOPL = u)
    du_true = np.diff(u_true, axis=1)
    du_oct = res.surface_du[b, s].astype(float)
    # ruido de la medición OCT estimado donde el campo verdadero no se mueve; la
    # comparación usa las muestras con señal > 3 sigma (fidelidad, no SNR)
    still = np.abs(du_true) < 0.01 * np.abs(du_true).max()
    sigma = float(np.std(du_oct[still])) if still.sum() > 20 else 0.0
    sig = np.abs(du_true) > max(0.05 * np.abs(du_true).max(), 3 * sigma)
    if sig.sum() < 10:
        return {"r": np.nan, "ganancia": np.nan}
    a, t = du_oct[sig], du_true[sig]
    r = float(np.corrcoef(a, t)[0, 1])
    gain = float(np.dot(a, t) / np.dot(t, t))
    return {"r": r, "ganancia": gain, "ruido_nm": sigma * 1e9, "muestras": int(sig.sum()),
            "b": b, "s": s, "du_true": du_true.astype(np.float32),
            "du_oct": du_oct.astype(np.float32)}
