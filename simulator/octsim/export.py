"""Guardado de resultados en la carpeta de la simulación (una carpeta por simulación)."""
from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
from matplotlib.figure import Figure

from . import figures, references
from .video import bmode_overlay_frames, close, enface_frames, write_video


def _save_fig(draw: Any, path: Path, *args: Any, size: tuple[float, float] = (11, 5)) -> str:
    fig = Figure(figsize=size, dpi=110)
    draw(fig, *args)
    fig.savefig(path, bbox_inches="tight")
    return str(path)


def _subsample(n: int, maxn: int) -> np.ndarray:
    return np.unique(np.linspace(0, n - 1, min(n, maxn)).astype(int))


def truth_slice_frames(res: Any, bm: dict[str, Any]) -> tuple[np.ndarray, np.ndarray, np.ndarray] | None:
    """Corte xz central del FDTD como verdad para el video B-mode (si la línea es horizontal)."""
    f = res.field
    pos = bm["positions"]
    exc = res.cfg.excitation
    if np.ptp(pos[:, 1]) > 1e-6 or abs(pos[0, 1] - exc.center_y_mm) > 0.25 or f.slice_x_m is None:
        return None
    x = f.slice_x_m * 1e3
    z = f.slice_z_m * 1e3
    sx = (x >= pos[:, 0].min()) & (x <= pos[:, 0].max())
    sz = (z >= -0.05) & (z <= bm["z_mm"][-1])
    t = bm["times_ms"] * 1e-3
    if f.regime == "transitorio":
        dt = f.times_s[1] - f.times_s[0]
        u = f.slice_uz[:, sx][:, :, sz]                      # [T, X, Z]
        v = np.diff(u, axis=0) / dt
        tv = 0.5 * (f.times_s[1:] + f.times_s[:-1])
        idx = np.clip(np.round((t - tv[0]) / dt).astype(int), 0, v.shape[0] - 1)
        frames = np.where(((t >= tv[0]) & (t <= tv[-1]))[:, None, None], v[idx], 0.0)
    else:
        w = 2 * np.pi * f.freq_hz
        frames = 0.0
        for h, U in f.slice_U.items():
            Us = U[sx][:, sz]
            frames = frames + np.real(1j * h * w * Us[None] * np.exp(1j * h * w * t)[:, None, None])
    frames = np.moveaxis(np.asarray(frames), 1, 2)          # [T, Z, X]
    return x[sx], z[sz], frames                              # x físico, como el eje del B-mode


def save_all(res: Any) -> None:
    out: Path = res.outdir
    cfg = res.cfg
    files: dict[str, str] = {}
    cfg.save_json(out / "config.json")
    files["config"] = str(out / "config.json")
    (out / "supuestos.md").write_text(
        "# Supuestos explícitos del simulador\n\n" + "\n".join(f"- {a}" for a in res.assumptions)
        + "\n\n# Advertencias de esta corrida\n\n" + ("\n".join(f"- {w}" for w in res.warnings) or "- ninguna")
        + "\n", encoding="utf-8")
    (out / "referencias.md").write_text(references.bibliography_markdown(), encoding="utf-8")
    files["supuestos"] = str(out / "supuestos.md")

    fps = cfg.output.fps
    maxf = cfg.output.max_video_frames
    # --- videos B-mode
    for bm in res.bmode:
        T = bm["velocity"].shape[-1]
        idx = _subsample(T, maxf)
        truth = truth_slice_frames(res, bm)
        tr = None if truth is None else (truth[0], truth[1], truth[2][idx])
        frame = bmode_overlay_frames(bm["structural_db"], bm["struct_z_mm"], bm["velocity"][..., idx],
                                     bm["z_mm"], bm["x_mm"], bm["times_ms"][idx], bm["mask"],
                                     f"B-mode OCE (B{bm['b'] + 1})", truth=tr)
        p = write_video(frame, idx.size, out / f"video_bmode_B{bm['b'] + 1}", fps)
        close(frame)
        files[f"video_bmode_B{bm['b'] + 1}"] = str(p)
    # --- video en-face
    if res.enface is not None:
        e = res.enface
        idx = _subsample(e["frames"].shape[-1], maxf)
        frame = enface_frames(e["frames"][..., idx], e["x_mm"], e["y_mm"], e["times_ms"][idx],
                              f"En-face superficie ({cfg.processing.enface_method})", points=e["points"])
        p = write_video(frame, idx.size, out / "video_enface_superficie", fps)
        close(frame)
        files["video_enface"] = str(p)
        for d, ed in res.enface_depths.items():
            idx = _subsample(ed["frames"].shape[-1], maxf)
            frame = enface_frames(ed["frames"][..., idx], ed["x_mm"], ed["y_mm"], ed["times_ms"][idx],
                                  f"En-face a {d:g} mm bajo la superficie")
            p = write_video(frame, idx.size, out / f"video_enface_{d:g}mm".replace(".", "p"), fps)
            close(frame)
            files[f"video_enface_{d:g}mm"] = str(p)
    # --- figuras
    files["fig_geometria"] = _save_fig(figures.draw_geometry, out / "geometria.png", cfg)
    files["fig_teoria"] = _save_fig(figures.draw_theory, out / "teoria.png", cfg, size=(7, 5))
    files["fig_estructural"] = _save_fig(figures.draw_structural, out / "estructural.png", res)
    files["fig_instantaneas"] = _save_fig(figures.draw_snapshots, out / "instantaneas.png", res, size=(12, 6))
    for plane in ("enface", "bmode"):
        if any(m.plane == plane for m in res.speed_maps):
            files[f"fig_velocidad_{plane}"] = _save_fig(figures.draw_speed_maps, out / f"velocidad_{plane}.png",
                                                        res, plane, size=(12, 7))
    if res.kf is not None:
        files["fig_dispersion"] = _save_fig(figures.draw_kf, out / "dispersion_kf.png", res)
    files["fig_validacion"] = _save_fig(figures.draw_validation, out / "validacion.png", res, size=(11, 4))
    if res.truth_check is not None:
        files["fig_cadena_oct"] = _save_fig(figures.draw_truth, out / "cadena_oct.png", res)
    # --- datos
    if cfg.output.save_npz:
        data: dict[str, Any] = {
            "structural_db": res.structural_db, "surface_idx": res.surface_idx,
            "positions_mm": res.plan.positions, "f_analysis_hz": res.f_analysis_hz,
        }
        if res.surface_v is not None:
            data["surface_velocity_m_s"] = res.surface_v.astype(np.float32)
        if res.tau_s is not None:
            data["tau_s"] = res.tau_s
        if res.enface is not None:
            data["enface_frames_m_s"] = res.enface["frames"]
            data["enface_x_mm"] = res.enface["x_mm"]
            data["enface_y_mm"] = res.enface["y_mm"]
            data["enface_times_ms"] = res.enface["times_ms"]
            data["enface_phasor"] = res.enface["phasor"]
        for bm in res.bmode:
            key = f"bmode_B{bm['b'] + 1}"
            data[key + "_velocity_m_s"] = bm["velocity"]
            data[key + "_x_mm"] = bm["x_mm"]
            data[key + "_z_mm"] = bm["z_mm"]
            data[key + "_times_ms"] = bm["times_ms"]
        for m in res.speed_maps:
            data[f"speed_{m.plane}_{m.method}_m_s"] = m.c
            data[f"speed_{m.plane}_{m.method}_axis1_mm"] = m.axis1_mm
            data[f"speed_{m.plane}_{m.method}_axis2_mm"] = m.axis2_mm
        if res.kf is not None:
            data["kf_f_hz"] = res.kf["f_hz"]
            data["kf_c_m_s"] = res.kf["c_mean"]
        np.savez_compressed(out / "datos.npz", **data)
        files["datos"] = str(out / "datos.npz")
    res.files = files
