"""Renderizado de videos (MP4 con ffmpeg de imageio, o GIF) y figuras."""
from __future__ import annotations

from pathlib import Path
from typing import Callable, Sequence

import numpy as np

from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.figure import Figure

# Mapa divergente para velocidad de partícula (azul = hacia la sonda, rojo = hacia +z)
WAVE_CMAP = LinearSegmentedColormap.from_list(
    "onda", ["#08306b", "#2171b5", "#9ecae1", "#f7f7f7", "#fcae91", "#cb181d", "#67000d"])


def robust_limit(values: np.ndarray, pct: float = 99.0) -> float:
    v = np.abs(values[np.isfinite(values)])
    if v.size == 0:
        return 1.0
    lim = float(np.percentile(v, pct))
    return lim if lim > 0 else float(v.max() or 1.0)


def _new_figure(figsize: tuple[float, float], ncols: int = 1) -> tuple[Figure, np.ndarray]:
    """Figura sin pyplot (segura en hilos de trabajo)."""
    fig = Figure(figsize=figsize, dpi=100)
    FigureCanvasAgg(fig)
    axes = np.atleast_2d(fig.subplots(1, ncols, squeeze=False))
    return fig, axes


def figure_to_array(fig: Figure) -> np.ndarray:
    fig.canvas.draw()
    buf = np.asarray(fig.canvas.buffer_rgba())
    return buf[..., :3].copy()


def write_video(frames: Sequence[np.ndarray] | Callable[[int], np.ndarray], n_frames: int,
                path: Path, fps: float = 15.0) -> Path:
    """Escribe MP4 (H.264 vía imageio-ffmpeg); si falla, GIF."""
    import imageio.v2 as imageio  # noqa: PLC0415

    get = frames if callable(frames) else (lambda i: frames[i])
    path = Path(path)
    try:
        with imageio.get_writer(path.with_suffix(".mp4"), fps=fps, codec="libx264",
                                quality=8, macro_block_size=16) as w:
            for i in range(n_frames):
                w.append_data(_pad16(get(i)))
        return path.with_suffix(".mp4")
    except Exception:  # noqa: BLE001 - sin ffmpeg: GIF
        imgs = [get(i) for i in range(n_frames)]
        imageio.mimsave(path.with_suffix(".gif"), imgs, duration=1.0 / fps)
        return path.with_suffix(".gif")


def _pad16(img: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    H, W = -(-h // 16) * 16, -(-w // 16) * 16
    if (H, W) == (h, w):
        return img
    out = np.full((H, W, 3), 255, dtype=np.uint8)
    out[:h, :w] = img
    return out


def bmode_overlay_frames(structural_db: np.ndarray, struct_z_mm: np.ndarray, velocity: np.ndarray,
                         vel_z_mm: np.ndarray, x_mm: np.ndarray, times_ms: np.ndarray,
                         mask: np.ndarray, title: str, vlim: float | None = None,
                         truth: tuple[np.ndarray, np.ndarray, np.ndarray] | None = None,
                         ) -> Callable[[int], np.ndarray]:
    """Fábrica de cuadros: velocidad [Zv, X, T] sobre B-mode estructural [Z, X].

    truth (opcional): (x_mm, z_mm, campo [T, Z, X]) del FDTD para comparar.
    """
    vlim = vlim or robust_limit(velocity)
    lo, hi = np.percentile(structural_db[np.isfinite(structural_db)], [5, 99.5])
    ncols = 2 if truth is not None else 1
    fig, axes = _new_figure((6.4 * ncols, 4.2), ncols)
    ext_s = [x_mm[0], x_mm[-1], struct_z_mm[-1], struct_z_mm[0]]
    ext = [x_mm[0], x_mm[-1], vel_z_mm[-1], vel_z_mm[0]]
    ax = axes[0, 0]
    ax.imshow(structural_db, cmap="gray", vmin=lo, vmax=hi, extent=ext_s, aspect="auto")
    first = np.where(mask, velocity[..., 0], np.nan) * 1e3
    im = ax.imshow(first, cmap=WAVE_CMAP, vmin=-vlim * 1e3, vmax=vlim * 1e3, extent=ext, aspect="auto",
                   alpha=0.9)
    ax.set_xlim(x_mm[0], x_mm[-1])
    ax.set_ylim(min(vel_z_mm[-1], struct_z_mm[-1]), struct_z_mm[0])
    ax.set_xlabel("x (mm)")
    ax.set_ylabel("profundidad z (mm)")
    cb = fig.colorbar(im, ax=ax, fraction=0.046)
    cb.set_label("v_z (mm/s), + hacia +z")
    ttl = ax.set_title(title)
    im2 = None
    if truth is not None:
        tx, tz, tf = truth
        ax2 = axes[0, 1]
        tl = robust_limit(tf)
        im2 = ax2.imshow(tf[0] * 1e3, cmap=WAVE_CMAP, vmin=-tl * 1e3, vmax=tl * 1e3,
                         extent=[tx[0], tx[-1], tz[-1], tz[0]], aspect="auto")
        ax2.set_title("Verdad FDTD (corte central)")
        ax2.set_xlabel("x (mm)")
        ax2.set_ylabel("z (mm)")
        fig.colorbar(im2, ax=ax2, fraction=0.046).set_label("v_z (mm/s)")
    fig.tight_layout()

    def frame(i: int) -> np.ndarray:
        im.set_data(np.where(mask, velocity[..., i], np.nan) * 1e3)
        ttl.set_text(f"{title} - t = {times_ms[i]:.2f} ms")
        if im2 is not None:
            im2.set_data(truth[2][min(i, truth[2].shape[0] - 1)] * 1e3)
        return figure_to_array(fig)

    frame.figure = fig  # type: ignore[attr-defined]
    return frame


def enface_frames(frames: np.ndarray, x_mm: np.ndarray, y_mm: np.ndarray, times_ms: np.ndarray,
                  title: str, vlim: float | None = None, points: np.ndarray | None = None,
                  ) -> Callable[[int], np.ndarray]:
    """Fábrica de cuadros en-face [Y, X, T]."""
    vlim = vlim or robust_limit(frames)
    fig, axes = _new_figure((5.6, 5.0))
    ax = axes[0, 0]
    im = ax.imshow(frames[..., 0] * 1e3, cmap=WAVE_CMAP, vmin=-vlim * 1e3, vmax=vlim * 1e3,
                   extent=[x_mm[0], x_mm[-1], y_mm[-1], y_mm[0]], aspect="equal")
    if points is not None and points.shape[0] < 4000:
        ax.plot(points[:, 0], points[:, 1], ",", color="k", alpha=0.35)
    ax.set_xlabel("x (mm)")
    ax.set_ylabel("y (mm)")
    fig.colorbar(im, ax=ax, fraction=0.046).set_label("v_z (mm/s)")
    ttl = ax.set_title(title)
    fig.tight_layout()

    def frame(i: int) -> np.ndarray:
        im.set_data(frames[..., i] * 1e3)
        ttl.set_text(f"{title} - t = {times_ms[i]:.2f} ms")
        return figure_to_array(fig)

    frame.figure = fig  # type: ignore[attr-defined]
    return frame


def close(frame_fn: Callable[[int], np.ndarray]) -> None:
    fig = getattr(frame_fn, "figure", None)
    if fig is not None:
        fig.clear()
