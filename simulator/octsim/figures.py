"""Figuras (matplotlib) compartidas por la GUI y la exportación de resultados."""
from __future__ import annotations

from typing import Any

import numpy as np
from matplotlib.colors import ListedColormap
from matplotlib.figure import Figure

from . import theory
from .acquisition import sweep_positions
from .excitation import lateral_shape, source_centers_mm
from .video import WAVE_CMAP, robust_limit

SPEED_CMAP = "jet"   # como repo:OCE_workflow/inherited/Codes/Elastogram.m


def _tight(fig: Any, **kw: Any) -> None:
    """tight_layout solo en figuras completas (las subfiguras no lo tienen)."""
    if hasattr(fig, "tight_layout"):
        fig.tight_layout(**kw)


def _material_cmap(cfg: Any) -> tuple[ListedColormap, list[str]]:
    mats = cfg.geometry.materials()
    colors = ["#ffffff"] + [m.color for m in mats]
    names = ["aire"] + [m.name for m in mats]
    return ListedColormap(colors), names


def draw_geometry(fig: Figure, cfg: Any) -> None:
    """Corte XZ (en y de la fuente) y vista XY con patrón de barrido y excitación."""
    fig.clear()
    g, e, a = cfg.geometry, cfg.excitation, cfg.acquisition
    ax1 = fig.add_subplot(1, 2, 1)
    ax2 = fig.add_subplot(1, 2, 2)
    cmap, names = _material_cmap(cfg)
    nx, nz = 320, 160
    x = np.linspace(-g.size_x_mm / 2, g.size_x_mm / 2, nx)
    z = np.linspace(-0.2, g.size_z_mm, nz)
    X, Z = np.meshgrid(x, z)
    ids = g.material_id_map(X, np.full_like(X, e.center_y_mm), Z).astype(float)
    ax1.imshow(ids, cmap=cmap, vmin=-0.5, vmax=len(names) - 0.5, extent=[x[0], x[-1], z[-1], z[0]],
               aspect="auto", interpolation="nearest")
    for cx, cy in source_centers_mm(e):
        if abs(cy - e.center_y_mm) < 1e-6 or e.regime == "transitorio":
            zs = float(g.surface_z(cx, cy))
            if e.mode == "arf_contacto":
                ax1.plot([cx, cx], [zs, zs + e.focal_depth_mm + e.dof_mm / 2], color="orange", lw=2, alpha=0.7)
                ax1.plot(cx, zs + e.focal_depth_mm, "o", color="orange")
            ax1.annotate("", xy=(cx, zs), xytext=(cx, zs - 0.15),
                         arrowprops=dict(arrowstyle="->", color="red", lw=1.5))
    ax1.set_title(f"Corte XZ (y = {e.center_y_mm:g} mm)")
    ax1.set_xlabel("x (mm)")
    ax1.set_ylabel("z (mm)")
    # vista superior
    ny = 200
    y = np.linspace(-g.size_y_mm / 2, g.size_y_mm / 2, ny)
    Xs, Ys = np.meshgrid(x, y)
    zs = g.surface_z(Xs, Ys)
    top = g.material_id_map(Xs, Ys, zs + 0.02).astype(float)
    ax2.imshow(top, cmap=cmap, vmin=-0.5, vmax=len(names) - 0.5, extent=[x[0], x[-1], y[-1], y[0]],
               aspect="equal", interpolation="nearest", alpha=0.6)
    for inc in g.inclusions:
        cx, cy, _ = inc.center_mm
        ax2.add_patch(_ellipse((cx, cy), 2 * inc.size_mm[0],
                               2 * (inc.size_mm[1] if inc.shape in ("elipsoide", "caja") else inc.size_mm[0])))
    hm = max(g.size_x_mm / nx, 0.01)
    S = np.zeros_like(Xs)
    for cx, cy in source_centers_mm(e):
        S = np.maximum(S, lateral_shape(e, Xs, Ys, cx, cy, hm))
    ax2.contour(Xs, Ys, S, levels=[0.5], colors="red", linewidths=1.2)
    for b in range(0, a.bscans, max(1, a.bscans // 24)):
        for line in sweep_positions(a, b):
            if a.alines > 1:
                ax2.plot(line[:, 0], line[:, 1], "-", color="k", lw=0.6, alpha=0.6)
            else:
                ax2.plot(line[:, 0], line[:, 1], ".", color="k")
    ax2.set_title("Vista superior: barrido (negro), excitación (rojo, FWHM)")
    ax2.set_xlabel("x (mm)")
    ax2.set_ylabel("y (mm)")
    ax2.set_xlim(x[0], x[-1])
    ax2.set_ylim(y[-1], y[0])
    handles = [_patch(cmap(i), n) for i, n in enumerate(names)]
    fig.legend(handles=handles, loc="lower center", ncol=min(6, len(handles)), fontsize=8, frameon=False)
    _tight(fig, rect=(0, 0.08, 1, 1))


def _ellipse(c: tuple[float, float], w: float, h: float) -> Any:
    from matplotlib.patches import Ellipse  # noqa: PLC0415
    return Ellipse(c, w, h, fill=False, ec="k", ls="--", lw=1)


def _patch(color: Any, label: str) -> Any:
    from matplotlib.patches import Patch  # noqa: PLC0415
    return Patch(facecolor=color, edgecolor="k", label=label)


def draw_theory(fig: Figure, cfg: Any) -> None:
    """Curvas teóricas de velocidad de fase de cada material."""
    fig.clear()
    ax = fig.add_subplot(1, 1, 1)
    f = np.linspace(100, 4000, 40)
    g = cfg.geometry
    for m in [mm for mm in g.materials() if not mm.is_fluid]:
        ax.plot(f, theory.shear_phase_velocity(m, f), "--", color=m.color, label=f"corte KV {m.name} [Chen2004]")
        ax.plot(f, theory.rayleigh_phase_velocity(m, f), "-", color=m.color, label=f"Rayleigh {m.name}")
    if len(g.layers) >= 2 and g.layers[0].thickness_mm > 0 and g.layers[1].material.is_fluid:
        from .fdtd import auto_fluid_speed  # noqa: PLC0415
        fA = np.linspace(100, 4000, 14)
        cA = theory.lamb_a0_phase_velocity(theory.LambConfig(
            g.layers[0].material, g.layers[0].thickness_mm * 1e-3, g.layers[1].material,
            auto_fluid_speed(g.materials())), fA)
        ax.plot(fA, cA, "k-o", ms=3, label="Lamb A0 con fluido (mRLFE) [Han2017]")
    e = cfg.excitation
    if e.regime == "armonico":
        ax.axvline(e.harmonic_hz, color="gray", ls=":")
    ax.set_xlabel("frecuencia (Hz)")
    ax.set_ylabel("velocidad de fase (m/s)")
    ax.set_title("Predicción teórica")
    ax.grid(alpha=0.3)
    ax.legend(fontsize=7, loc="best")
    _tight(fig)


def draw_structural(fig: Figure, res: Any) -> None:
    fig.clear()
    n = 1 + (res.enface is not None and "structural" in res.enface)
    if res.bmode:
        bm = res.bmode[0]
        ax = fig.add_subplot(1, n, 1)
        I = bm["structural_db"]
        lo, hi = np.percentile(I, [5, 99.5])
        ax.imshow(I, cmap="gray", vmin=lo, vmax=hi, aspect="auto",
                  extent=[bm["x_mm"][0], bm["x_mm"][-1], bm["struct_z_mm"][-1], bm["struct_z_mm"][0]])
        ax.set_title(f"B-mode estructural (B{bm['b'] + 1})")
        ax.set_xlabel("x (mm)")
        ax.set_ylabel("z = OPL/n (mm)")
    if n == 2:
        e = res.enface
        ax = fig.add_subplot(1, 2, 2)
        ax.imshow(e["structural"], cmap="gray", extent=[e["x_mm"][0], e["x_mm"][-1], e["y_mm"][-1], e["y_mm"][0]],
                  aspect="equal")
        ax.set_title("En-face estructural (bajo la superficie)")
        ax.set_xlabel("x (mm)")
        ax.set_ylabel("y (mm)")
    _tight(fig)


def draw_snapshots(fig: Figure, res: Any, n: int = 6) -> None:
    fig.clear()
    if res.enface is not None:
        e = res.enface
        fr, t = e["frames"], e["times_ms"]
        ext = [e["x_mm"][0], e["x_mm"][-1], e["y_mm"][-1], e["y_mm"][0]]
    elif res.bmode:
        bm = res.bmode[0]
        fr, t = bm["velocity"], bm["times_ms"]
        ext = [bm["x_mm"][0], bm["x_mm"][-1], bm["z_mm"][-1], bm["z_mm"][0]]
    else:
        return
    valid = np.nanmax(np.abs(fr.reshape(-1, fr.shape[-1])), axis=0)
    start = int(np.argmax(valid > 0.05 * np.nanmax(valid))) if np.nanmax(valid) > 0 else 0
    idx = np.linspace(start, fr.shape[-1] - 1, n).astype(int)
    lim = robust_limit(fr) * 1e3
    for k, i in enumerate(idx):
        ax = fig.add_subplot(2, (n + 1) // 2, k + 1)
        im = ax.imshow(fr[..., i] * 1e3, cmap=WAVE_CMAP, vmin=-lim, vmax=lim, extent=ext,
                       aspect="equal" if res.enface is not None else "auto")
        ax.set_title(f"t = {t[i]:.2f} ms", fontsize=9)
        ax.tick_params(labelsize=7)
    fig.colorbar(im, ax=fig.axes, fraction=0.025).set_label("v_z (mm/s)")


def draw_speed_maps(fig: Figure, res: Any, plane: str) -> None:
    fig.clear()
    maps = [m for m in res.speed_maps if m.plane == plane]
    if not maps:
        ax = fig.add_subplot(1, 1, 1)
        ax.text(0.5, 0.5, "Sin mapas para este plano", ha="center", va="center")
        ax.axis("off")
        return
    vals = np.concatenate([m.c[np.isfinite(m.c)] for m in maps]) if maps else np.array([1.0])
    lo, hi = (np.percentile(vals, [2, 98]) if vals.size else (0, 1))
    n = len(maps)
    cols = min(n, 3)
    rows = int(np.ceil(n / cols))
    g = res.cfg.geometry
    for k, m in enumerate(maps):
        ax = fig.add_subplot(rows, cols, k + 1)
        ext = [m.axis2_mm[0], m.axis2_mm[-1], m.axis1_mm[-1], m.axis1_mm[0]]
        im = ax.imshow(m.c, cmap=SPEED_CMAP, vmin=lo, vmax=hi, extent=ext,
                       aspect="equal" if plane.startswith("enface") else "auto")
        for inc in g.inclusions:
            cx, cy, cz = inc.center_mm
            r = inc.size_mm[0]
            if plane.startswith("enface"):
                ax.add_patch(_ellipse((cx, cy), 2 * r, 2 * (inc.size_mm[1] if inc.shape in ("elipsoide", "caja") else r)))
            else:
                ax.add_patch(_ellipse((cx, cz), 2 * r, 2 * (inc.size_mm[2] if inc.shape in ("elipsoide", "caja") else r)))
        med = np.nanmedian(m.c) if np.isfinite(m.c).any() else np.nan
        ax.set_title(f"{m.method}  (mediana {med:.2f} m/s)", fontsize=9)
        ax.set_xlabel("x (mm)", fontsize=8)
        ax.set_ylabel("y (mm)" if plane.startswith("enface") else "z (mm)", fontsize=8)
        ax.tick_params(labelsize=7)
    fig.colorbar(im, ax=fig.axes, fraction=0.025).set_label("velocidad (m/s)")
    fig.suptitle(f"Mapas de velocidad ({plane}), f = {res.f_analysis_hz:.0f} Hz", fontsize=10)


def draw_kf(fig: Figure, res: Any) -> None:
    fig.clear()
    if res.kf is None:
        ax = fig.add_subplot(1, 1, 1)
        ax.text(0.5, 0.5, "Dispersión k-f no disponible (régimen armónico o sin línea)", ha="center")
        ax.axis("off")
        return
    from .validation import auto_model, theory_curve  # noqa: PLC0415
    cur = res.kf["curves"][0]
    ax1 = fig.add_subplot(1, 2, 1)
    A = cur["kf_map"]
    k = cur["k_cyc_m"]
    f = cur["f_hz"]
    fmax = res.cfg.processing.filter_high_hz
    sel_f = f <= fmax
    order = np.argsort(k)
    kk = k[order]
    ksel = (np.abs(kk) <= np.nanmax(f[sel_f]) / max(res.cfg.speed.c_min, 0.3))
    img = A[order][ksel][:, sel_f]
    ax1.imshow(20 * np.log10(img / img.max() + 1e-6).T, origin="lower", aspect="auto", vmin=-40, vmax=0,
               extent=[kk[ksel][0] * 1e-3, kk[ksel][-1] * 1e-3, f[sel_f][0], f[sel_f][-1]], cmap="magma")
    ax1.set_xlabel("k (ciclos/mm)")
    ax1.set_ylabel("f (Hz)")
    ax1.set_title("Espectro k-f |U| (dB) [Singh2022, Ec. (19)]", fontsize=9)
    ax2 = fig.add_subplot(1, 2, 2)
    band = (f >= res.cfg.processing.filter_low_hz) & (f <= fmax) & (res.kf["magnitude"] > 0.2 * res.kf["magnitude"].max())
    ax2.plot(f[band], res.kf["c_mean"][band], ".", ms=3, label="medida (OCT simulado)")
    model, kw = auto_model(res.cfg, res.f_analysis_hz)
    if np.any(band):
        ft = np.linspace(f[band].min(), f[band].max(), 25)
        if model in ("lamb_libre", "lamb_fluido"):
            modes = theory.lamb_all_modes(theory.LambConfig(kw["material"], kw["thickness_m"], kw.get("fluid"),
                                                            kw.get("c_fluid")), ft)
            for m in range(modes.shape[1]):
                ax2.plot(ft, modes[:, m], "ko", ms=3, mfc="none",
                         label="raíces mRLFE [Han2017]" if m == 0 else None)
        else:
            ax2.plot(ft, theory_curve(model, kw, ft), "k-", label=f"teoría: {model}")
    ax2.set_xlabel("f (Hz)")
    ax2.set_ylabel("c (m/s)")
    ax2.grid(alpha=0.3)
    ax2.legend(fontsize=8)
    ax2.set_title("Velocidad de fase c = w/k [Singh2022, Ec. (20)]", fontsize=9)
    _tight(fig)


def draw_validation(fig: Figure, res: Any) -> None:
    fig.clear()
    ax = fig.add_subplot(1, 1, 1)
    ax.axis("off")
    v = res.validation
    rows = []
    for c in v.get("checks", []):
        rows.append([c["nombre"], f"{c.get('valor', np.nan):.3f}", f"{c.get('esperado', np.nan):.3f}",
                     f"{c.get('error_pct', np.nan):+.1f} %", f"±{c.get('tol_pct', np.nan):.0f} %",
                     "OK" if c.get("ok") else "FALLA"])
    if rows:
        tab = ax.table(cellText=rows, colLabels=["Prueba", "Medido", "Esperado", "Error", "Tol.", "Estado"],
                       loc="center", cellLoc="center", colWidths=[0.42, 0.11, 0.11, 0.11, 0.1, 0.1])
        tab.auto_set_font_size(False)
        tab.set_fontsize(8)
        tab.scale(1, 1.4)
        for (r, c), cell in tab.get_celld().items():
            if r > 0 and c == 5:
                cell.set_facecolor("#c7e9c0" if rows[r - 1][5] == "OK" else "#fcbba1")
    status = "APROBADA" if v.get("aprobado") else "CON FALLAS"
    ax.set_title(f"Validación {status} - modelo {v.get('modelo')}, f = {v.get('frecuencia_hz', 0):.0f} Hz",
                 fontsize=10)


def draw_truth(fig: Figure, res: Any) -> None:
    fig.clear()
    tc = res.truth_check
    ax = fig.add_subplot(1, 2, 1)
    ax2 = fig.add_subplot(1, 2, 2)
    if tc is None or "du_true" not in tc:
        ax.text(0.5, 0.5, "Sin comparación", ha="center")
        return
    dt = res.cfg.acquisition.line_period_s
    a = int(np.argmax(np.abs(tc["du_true"]).max(axis=1)))
    t = res.tau_s * 1e3 if res.tau_s is not None else np.arange(tc["du_true"].shape[1])
    ax.plot(t, tc["du_true"][a] / dt * 1e3, "k-", lw=1.5, label="FDTD (verdad)")
    ax.plot(t, tc["du_oct"][a] / dt * 1e3, "r-", lw=0.8, alpha=0.8, label="OCT simulado (Loupas)")
    ax.set_xlabel("t desde la excitación (ms)")
    ax.set_ylabel("v_z superficie (mm/s)")
    ax.legend(fontsize=8)
    ax.set_title(f"A-line {a + 1}", fontsize=9)
    sel = np.abs(tc["du_true"]) > 0.05 * np.abs(tc["du_true"]).max()
    ax2.plot(tc["du_true"][sel] * 1e9, tc["du_oct"][sel] * 1e9, ",", alpha=0.4)
    lim = np.abs(tc["du_true"][sel]).max() * 1e9
    ax2.plot([-lim, lim], [-lim, lim], "k--", lw=0.8)
    ax2.set_xlabel("du FDTD (nm)")
    ax2.set_ylabel("du OCT (nm)")
    ax2.set_title(f"r = {tc['r']:.3f}, ganancia = {tc['ganancia']:.3f}", fontsize=9)
    _tight(fig)
