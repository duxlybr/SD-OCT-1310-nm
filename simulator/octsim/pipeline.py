"""Flujo completo: FDTD -> adquisición OCT simulada -> procesamiento -> mapas -> validación."""
from __future__ import annotations

import json
import time
from dataclasses import dataclass, field
from datetime import datetime
from math import pi
from pathlib import Path
from threading import Event
from typing import Any, Callable

import numpy as np

from . import references
from .acquisition import AcquisitionPlan, bscan_axis_mm, build_plan, scan_extent_mm
from .config import SimulationConfig, explicit_assumptions
from .excitation import burst_duration_s
from .fdtd import FDTDSolver, FieldRecord
from .oct_signal import OCTSimulator
from .processing import (cone_filter, detect_surface, donut_filter_phasor, surface_window_start, enface_grid,
                         harmonic_phasor, interpolate_enface, loupas_phase_increment,
                         phase_to_displacement, temporal_filter)
from .speed import (SpeedMap, arrival_times, kf_dispersion, lfe_speed, phase_gradient_speed,
                    reverberant_speed, tof_speed)

ProgressFn = Callable[[float, str], None]
SIM_ROOT = Path(__file__).resolve().parents[1]


@dataclass
class SimulationResult:
    cfg: SimulationConfig
    outdir: Path
    plan: AcquisitionPlan
    field: FieldRecord
    fdtd_info: dict[str, Any]
    regime: str
    f_analysis_hz: float
    structural_db: np.ndarray                  # [B, S, A, Z]
    surface_idx: np.ndarray                    # [B, S, A]
    bmode: list[dict[str, Any]] = field(default_factory=list)
    enface: dict[str, Any] | None = None
    enface_depths: dict[float, dict[str, Any]] = field(default_factory=dict)
    speed_maps: list[SpeedMap] = field(default_factory=list)
    kf: dict[str, Any] | None = None
    truth_check: dict[str, Any] | None = None
    validation: dict[str, Any] = field(default_factory=dict)
    files: dict[str, str] = field(default_factory=dict)
    warnings: list[str] = field(default_factory=list)
    timings: dict[str, float] = field(default_factory=dict)
    assumptions: list[str] = field(default_factory=list)
    surface_du: np.ndarray | None = None
    surface_v: np.ndarray | None = None
    tau_s: np.ndarray | None = None


def default_outdir(cfg: SimulationConfig) -> Path:
    root = Path(cfg.output.root)
    if not root.is_absolute():
        root = SIM_ROOT / root
    safe = "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in cfg.name).strip("_") or "simulacion"
    return root / safe


def _main_bscans(cfg: SimulationConfig, plan: AcquisitionPlan) -> list[tuple[int, int]]:
    """B-scans con video en profundidad: los indicados o el más cercano a la fuente."""
    acq = cfg.acquisition
    if cfg.processing.bmode_bscans:
        return [(int(b) % acq.bscans, 0) for b in cfg.processing.bmode_bscans]
    cx, cy = cfg.excitation.center_x_mm, cfg.excitation.center_y_mm
    best, best_d = (0, 0), np.inf
    for b in range(acq.bscans):
        for s in range(acq.sweeps):
            pos = plan.positions[b, s]
            d = np.min(np.hypot(pos[:, 0] - cx, pos[:, 1] - cy))
            # preferir el barrido X del crosshair y líneas a lo largo de x
            d += 1e-3 * s
            if d < best_d - 1e-9:
                best, best_d = (b, s), d
    return [best]


def phase_wrap_warning(field: FieldRecord, cfg: SimulationConfig) -> str | None:
    """Riesgo de envolvimiento de fase entre A-lines consecutivas.

    El estimador de Loupas (atan2) es ambiguo si |dphi| > pi entre muestras, es decir si
    |du| > lambda0 / (4 n) por intervalo [Nguyen2014, Ec. (1)]. Se avisa desde la mitad.
    """
    T = cfg.acquisition.line_period_s
    n = max(m.n for m in cfg.geometry.materials())
    lim = cfg.oct.lambda0_nm * 1e-9 / (4 * n)
    if field.regime == "transitorio":
        step = max(1, int(round(T / (field.times_s[1] - field.times_s[0]))))
        du = float(np.abs(np.diff(field.uz[::step], axis=0)).max())
    else:
        w = 2 * pi * field.freq_hz
        du = max(float(np.abs(U).max()) * h * w * T for h, U in field.U.items())
    if du > 0.5 * lim:
        return (f"Riesgo de envolvimiento de fase: |du| máximo por A-line = {du * 1e9:.1f} nm frente al límite "
                f"lambda0/(4n) = {lim * 1e9:.0f} nm. Reduzca la presión de excitación (el modelo es lineal).")
    return None


def _transient_duration(cfg: SimulationConfig) -> float:
    if cfg.fdtd.duration_ms > 0:
        return cfg.fdtd.duration_ms * 1e-3
    acq, exc = cfg.acquisition, cfg.excitation
    delay = exc.ch2_delay_ms * 1e-3 + acq.bframes_delay_us * 1e-6
    end_rel = acq.active_count * acq.line_period_s - delay
    return max(end_rel, burst_duration_s(exc)) + 1.0e-3     # 0.5 ms de margen + 0.5 ms de desvanecimiento


def fdtd_cache_key(cfg: SimulationConfig, box: list[float]) -> str:
    """Huella de todo lo que determina el campo FDTD (geometría, excitación, malla, registro)."""
    import hashlib  # noqa: PLC0415
    acq = cfg.acquisition
    from .fdtd import MODEL_VERSION  # noqa: PLC0415
    payload = {"v": MODEL_VERSION, "g": cfg.geometry.to_dict(), "e": cfg.excitation.to_dict(), "f": cfg.fdtd.to_dict(),
               "box": [round(v, 6) for v in box], "T": acq.line_period_s,
               "dur": _transient_duration(cfg) if cfg.excitation.regime == "transitorio" else 0}
    return hashlib.sha256(json.dumps(payload, sort_keys=True, default=str).encode()).hexdigest()


def run_simulation(cfg: SimulationConfig, progress: ProgressFn | None = None,
                   cancel: Event | None = None, outdir: Path | None = None,
                   use_cache: bool = True) -> SimulationResult:
    progress = progress or (lambda f, m: None)
    cancel = cancel or Event()
    errors = cfg.validate()
    if errors:
        raise ValueError("Configuración inválida:\n- " + "\n- ".join(errors))
    t_start = time.perf_counter()
    timings: dict[str, float] = {}
    outdir = Path(outdir) if outdir else default_outdir(cfg)
    outdir.mkdir(parents=True, exist_ok=True)
    acq, exc, geom = cfg.acquisition, cfg.excitation, cfg.geometry
    plan = build_plan(acq)
    box = list(scan_extent_mm(acq))
    centers = np.array([[exc.center_x_mm, exc.center_y_mm]])
    box = [min(box[0], centers[:, 0].min()), max(box[1], centers[:, 0].max()),
           min(box[2], centers[:, 1].min()), max(box[3], centers[:, 1].max())]

    # ------------------------------------------------------------------ 1. FDTD
    t0 = time.perf_counter()
    key = fdtd_cache_key(cfg, box)
    cache = outdir / "campo_fdtd_cache.npz"
    field = FieldRecord.load(cache, key) if use_cache and cache.exists() else None
    if field is None:
        progress(0.01, "Preparando la malla FDTD")
        solver = FDTDSolver(geom, exc, cfg.fdtd, tuple(box), progress, cancel)
        if exc.regime == "transitorio":
            field = solver.run_transient(_transient_duration(cfg), acq.line_period_s)
        else:
            field = solver.run_harmonic()
        solver.release()
        if use_cache:
            progress(0.65, "Guardando el campo FDTD en caché")
            field.save(cache, key)
    else:
        progress(0.65, "Campo FDTD reutilizado desde la caché (misma física y temporización)")
    timings["fdtd_s"] = time.perf_counter() - t0
    warnings = list(field.info.get("advertencias", []))
    msg = phase_wrap_warning(field, cfg)
    if msg:
        warnings.append(msg)

    # ------------------------------------------------------- 2. adquisición OCT
    sim = OCTSimulator(cfg.oct, geom, field, plan, exc)
    proc = cfg.processing
    n_proc = proc.n_processing or geom.layers[0].material.n
    lam0 = cfg.oct.lambda0_nm * 1e-9
    B, S, A, M = acq.bscans, acq.sweeps, acq.alines, acq.m_reps
    nZ = sim.d_mm.size
    W = proc.loupas_window
    structural = np.zeros((B, S, A, nZ), np.float32)
    surf_idx = np.zeros((B, S, A), np.int32)
    surf_du = np.zeros((B, S, A, M - 1), np.float32)
    times_mid = np.zeros((B, S, A, M - 1))
    main = _main_bscans(cfg, plan)
    bmode_raw: dict[tuple[int, int], dict[str, Any]] = {}
    depth_bins = {d: int(round(d * n_proc / cfg.oct.dz_mm)) for d in proc.enface_depths_mm}
    depth_du = {d: np.zeros((B, S, A, M - 1), np.float32) for d in depth_bins}
    rng = np.random.default_rng(cfg.oct.seed)
    t0 = time.perf_counter()
    total = B * S
    for b in range(B):
        for s in range(S):
            if cancel.is_set():
                from .fdtd import SimulationCancelled  # noqa: PLC0415
                raise SimulationCancelled("Simulación cancelada por el usuario.")
            out = sim.bscan(b, s, rng)
            data = out["data"]                                           # [A, Z, M]
            I_db = 10 * np.log10(np.mean(np.abs(data) ** 2, axis=2) + 1e-30)
            structural[b, s] = I_db
            sidx = detect_surface(I_db, proc.surface_threshold_db)
            surf_idx[b, s] = sidx
            dphi = loupas_phase_increment(data, W)                       # [A, Zl, M-1]
            s_start = surface_window_start(I_db, sidx, W)
            du, du_s = phase_to_displacement(dphi, lam0, n_proc, s_start, proc.surface_correction,
                                             proc.surface_samples)
            surf_du[b, s] = du_s
            t = out["times"]
            times_mid[b, s] = 0.5 * (t[:, :-1] + t[:, 1:])
            rows = np.arange(A)
            for d, nb in depth_bins.items():
                depth_du[d][b, s] = du[rows, np.clip(sidx + 1 + nb, 0, du.shape[1] - 1)]
            if (b, s) in main:
                bmode_raw[(b, s)] = {"du": du.astype(np.float32), "I_db": I_db, "sidx": sidx,
                                     "times_mid": times_mid[b, s].copy(), "positions": out["positions"]}
            k = b * S + s + 1
            if k % max(1, total // 50) == 0 or k == total:
                el = time.perf_counter() - t0
                progress(0.66 + 0.18 * k / total,
                         f"Adquisición OCT: B-scan {k}/{total} ({el:.0f} s, quedan ~{el / k * (total - k):.0f} s)")
    timings["oct_s"] = time.perf_counter() - t0
    msg = sim.check_shift()
    if msg:
        warnings.append(msg)

    # ----------------------------------------------------- 3. procesamiento
    t0 = time.perf_counter()
    progress(0.85, "Procesando fase, filtros y en-face")
    if acq.mode == "MB":
        dt_inc = acq.line_period_s
    else:
        dt_inc = acq.sweeps * acq.segment_period_s
    harmonic = exc.regime == "armonico"
    f_an = exc.harmonic_hz if harmonic else 0.0
    w_an = 2 * pi * f_an
    delay = exc.ch2_delay_ms * 1e-3 + acq.bframes_delay_us * 1e-6
    tau = -delay + (np.arange(M - 1) + 0.5) * acq.line_period_s   # tiempo relativo a la excitación (MB)
    surf_v = surf_du / dt_inc                                           # m/s

    if not harmonic:
        fs = 1.0 / dt_inc
        surf_v_f = temporal_filter(surf_v, fs, proc, axis=-1)
        spec = np.abs(np.fft.rfft(surf_v_f.reshape(-1, M - 1), axis=1)).mean(axis=0)
        freqs = np.fft.rfftfreq(M - 1, dt_inc)
        band = (freqs >= proc.filter_low_hz) & (freqs <= proc.filter_high_hz)
        f_an = float(freqs[band][np.argmax(spec[band])]) if band.any() else 1000.0
        if cfg.speed.frequencies_hz:
            f_an = float(cfg.speed.frequencies_hz[0])
        w_an = 2 * pi * f_an
    else:
        surf_v_f = surf_v

    result = SimulationResult(cfg=cfg, outdir=outdir, plan=plan, field=field, fdtd_info=field.info,
                              regime=exc.regime, f_analysis_hz=f_an, structural_db=structural,
                              surface_idx=surf_idx, warnings=warnings, timings=timings)
    result.surface_du = surf_du            # incrementos de desplazamiento superficial (m) [B,S,A,M-1]
    result.surface_v = surf_v_f            # velocidad superficial filtrada (m/s)
    result.tau_s = tau
    result.assumptions = explicit_assumptions(cfg)

    # -------- en-face (superficie)
    pts = plan.positions.reshape(-1, 2)
    pixel = proc.enface_pixel_mm
    raster = acq.pattern == "raster" and acq.bscans > 1 and acq.alines > 1
    spread = np.ptp(pts, axis=0)
    can_enface = (spread > 0).all() and acq.bscans * acq.sweeps > 1
    if can_enface:
        result.enface = _build_enface(pts, surf_v_f.reshape(-1, M - 1), surf_du.reshape(-1, M - 1),
                                      times_mid.reshape(-1, M - 1), tau, harmonic, w_an, f_an, pixel,
                                      raster, acq, cfg, structural, surf_idx)
        for d, arr in depth_du.items():
            v = arr / dt_inc
            vf = temporal_filter(v, 1.0 / dt_inc, proc, axis=-1) if not harmonic else v
            result.enface_depths[d] = _build_enface(pts, vf.reshape(-1, M - 1), arr.reshape(-1, M - 1),
                                                    times_mid.reshape(-1, M - 1), tau, harmonic, w_an,
                                                    f_an, pixel, raster, acq, cfg, None, None)
    else:
        warnings.append("El patrón no cubre un área (línea o punto): no hay en-face; se usa el B-mode.")

    # -------- B-mode con profundidad
    for (b, s), raw in bmode_raw.items():
        result.bmode.append(_build_bmode(raw, b, s, cfg, sim, n_proc, dt_inc, tau, harmonic, w_an, f_an,
                                         field))
    timings["procesamiento_s"] = time.perf_counter() - t0

    # ----------------------------------------------------- 4. velocidades
    t0 = time.perf_counter()
    progress(0.9, "Estimando mapas de velocidad")
    result.speed_maps = _speed_maps(result, harmonic, f_an)
    if not harmonic:
        result.kf = _kf_analysis(result, surf_v_f, tau)
    timings["velocidad_s"] = time.perf_counter() - t0

    # ----------------------------------------------------- 5. validación
    from .validation import run_validation, truth_comparison  # noqa: PLC0415
    progress(0.94, "Validando contra la teoría")
    if result.bmode:
        result.truth_check = truth_comparison(result, sim)
    result.validation = run_validation(result)

    # ----------------------------------------------------- 6. guardar
    progress(0.96, "Guardando videos, figuras y datos")
    t0 = time.perf_counter()
    from .export import save_all  # noqa: PLC0415
    save_all(result)
    timings["guardado_s"] = time.perf_counter() - t0
    timings["total_s"] = time.perf_counter() - t_start
    (outdir / "resumen.json").write_text(json.dumps(_summary(result), indent=2, ensure_ascii=False,
                                                    default=_json_default), encoding="utf-8")
    progress(1.0, f"Listo en {timings['total_s']:.0f} s -> {outdir}")
    return result


# --------------------------------------------------------------------------------------
def _build_enface(pts: np.ndarray, v: np.ndarray, du: np.ndarray, times: np.ndarray, tau: np.ndarray,
                  harmonic: bool, w: float, f: float, pixel: float, raster: bool, acq: Any,
                  cfg: SimulationConfig, structural: np.ndarray | None,
                  surf_idx: np.ndarray | None) -> dict[str, Any]:
    proc = cfg.processing
    x, y = enface_grid(pts, pixel)
    if harmonic:
        # fasor de desplazamiento con tiempos reales [Zvietcovich2019, Ec. (7)] -> velocidad i w U
        u = np.cumsum(du, axis=1)
        Pv = 1j * w * harmonic_phasor(u, times, f)
        Pgrid = interpolate_enface(pts, Pv, x, y, proc.enface_method)
        if proc.speed_filter:
            dx, dy = (x[1] - x[0]) * 1e-3, (y[1] - y[0]) * 1e-3
            nanm = ~np.isfinite(Pgrid)
            Pgrid = donut_filter_phasor(Pgrid, dx, dy, f, proc.speed_min_m_s, proc.speed_max_m_s)
            Pgrid[nanm] = np.nan
        nfr = 48
        ph = np.arange(nfr) / 24 * (2 * pi)          # dos periodos
        frames = np.real(Pgrid[..., None] * np.exp(1j * ph)[None, None, :])
        tframes = ph / w * 1e3
        out = {"x_mm": x, "y_mm": y, "frames": frames.astype(np.float32), "times_ms": tframes,
               "phasor": Pgrid, "points": pts}
    else:
        frames = interpolate_enface(pts, v, x, y, proc.enface_method)   # [Y, X, T]
        if proc.speed_filter and frames.shape[0] > 3 and frames.shape[1] > 3:
            nanm = ~np.isfinite(frames[..., 0])
            dx, dy = (x[1] - x[0]) * 1e-3, (y[1] - y[0]) * 1e-3
            frames = cone_filter(frames, (dy, dx), cfg.acquisition.line_period_s,
                                 proc.speed_min_m_s, proc.speed_max_m_s)
            frames[nanm] = np.nan
        out = {"x_mm": x, "y_mm": y, "frames": frames.astype(np.float32), "times_ms": tau * 1e3,
               "points": pts}
        out["phasor"] = _phasor_from_frames(frames, tau, f)
    if structural is not None and surf_idx is not None:
        flat = structural.reshape(-1, structural.shape[-1])
        sid = surf_idx.reshape(-1)
        lo = np.clip(sid + 2, 0, flat.shape[1] - 1)
        hi = np.clip(sid + 30, 1, flat.shape[1])
        mean_db = np.array([flat[i, lo[i]:hi[i]].mean() if hi[i] > lo[i] else np.nan for i in range(flat.shape[0])])
        out["structural"] = interpolate_enface(pts, mean_db, x, y, proc.enface_method)
    return out


def _phasor_from_frames(frames: np.ndarray, tau: np.ndarray, f: float) -> np.ndarray:
    """Fasor complejo de velocidad a f (DFT con ventana de Hann, amplitud de pico)."""
    win = np.hanning(tau.size)
    vv = np.nan_to_num(frames) * win
    P = 2 * np.sum(vv * np.exp(-2j * pi * f * tau), axis=-1) / win.sum()
    P[~np.isfinite(frames[..., 0])] = np.nan
    return P


def _build_bmode(raw: dict[str, Any], b: int, s: int, cfg: SimulationConfig, sim: OCTSimulator,
                 n_proc: float, dt_inc: float, tau: np.ndarray, harmonic: bool, w: float, f: float,
                 field: FieldRecord) -> dict[str, Any]:
    proc = cfg.processing
    acq = cfg.acquisition
    W = proc.loupas_window
    du = raw["du"]                                       # [A, Zl, T]
    A, Zl, T = du.shape
    x_mm = bscan_axis_mm(acq, b, s)
    pos = raw["positions"]
    dz = cfg.oct.dz_mm
    d_center = sim.d_mm[: Zl] + (W - 1) / 2 * dz           # OPL del centro de la ventana de Loupas
    z_mm = (d_center - cfg.oct.zero_delay_gap_mm) / n_proc  # profundidad aproximada (OPL / n)
    I_db = raw["I_db"]
    floor = np.median(I_db[:, :5])
    I_c = np.stack([np.convolve(I_db[a], np.ones(W) / W, mode="valid") for a in range(A)])   # [A, Zl]
    below = np.arange(Zl)[None, :] >= raw["sidx"][:, None]
    mask = (I_c > floor + proc.intensity_mask_db) & below
    v = du / dt_inc
    if harmonic:
        u = np.cumsum(du, axis=2)
        tt = np.repeat(raw["times_mid"][:, None, :], Zl, axis=1)
        P = 1j * w * harmonic_phasor(u, tt, f)              # [A, Zl]
        P = P.T                                              # [Z, X]
        nfr = 48
        ph = np.arange(nfr) / 24 * (2 * pi)
        vel = np.real(P[..., None] * np.exp(1j * ph)[None, None, :])
        times_ms = ph / w * 1e3
    else:
        vf = temporal_filter(v, 1.0 / dt_inc, proc, axis=-1)
        vel = np.moveaxis(vf, 0, 1)                          # [Z, X, T]
        if proc.speed_filter:
            dzm = dz / n_proc * 1e-3
            dxm = abs(np.median(np.diff(x_mm))) * 1e-3
            vel = cone_filter(vel, (dzm, dxm), cfg.acquisition.line_period_s,
                              proc.speed_min_m_s, proc.speed_max_m_s)
        times_ms = tau * 1e3
        P = _phasor_from_frames(vel, tau, f)
    vel = np.where(mask.T[..., None], vel, np.nan).astype(np.float32)
    P = np.where(mask.T, P, np.nan)
    exc = cfg.excitation
    x_src = float(x_mm[np.argmin(np.hypot(pos[:, 0] - exc.center_x_mm, pos[:, 1] - exc.center_y_mm))])
    return {"b": b, "s": s, "x_mm": x_mm, "x_src_mm": x_src, "z_mm": z_mm, "structural_db": I_db.T,
            "struct_z_mm":
            (sim.d_mm - cfg.oct.zero_delay_gap_mm) / n_proc, "velocity": vel, "times_ms": times_ms,
            "mask": mask.T, "phasor": P, "surface_idx": raw["sidx"], "positions": pos,
            "surface_du": None}


def _speed_maps(res: SimulationResult, harmonic: bool, f: float) -> list[SpeedMap]:
    cfg = res.cfg
    sc = cfg.speed
    methods = set(sc.methods)
    if harmonic:
        methods.add("reverberante")
    maps: list[SpeedMap] = []
    exc = cfg.excitation
    planes = []
    if res.enface is not None:
        e = res.enface
        planes.append(("enface", e["phasor"], e["frames"], e["times_ms"] * 1e-3, e["y_mm"], e["x_mm"]))
    for d, ed in res.enface_depths.items():
        planes.append((f"enface_{d:g}", ed["phasor"], ed["frames"], ed["times_ms"] * 1e-3, ed["y_mm"],
                       ed["x_mm"]))
    for bm in res.bmode:
        planes.append(("bmode", bm["phasor"], bm["velocity"], bm["times_ms"] * 1e-3, bm["z_mm"], bm["x_mm"]))
    for plane, P, frames, times, a1, a2 in planes:
        d1 = abs(np.median(np.diff(a1))) * 1e-3 if a1.size > 1 else 1e-3
        d2 = abs(np.median(np.diff(a2))) * 1e-3
        win1 = sc.window_z_mm if plane == "bmode" else sc.window_mm
        if "gradiente_fase" in methods:
            c, _ = phase_gradient_speed(P, d1, d2, f, sc, win1)
            maps.append(SpeedMap("gradiente_fase", c, a1, a2, plane, f"f = {f:.0f} Hz [repo:PhaseDeriv]"))
        if "lfe" in methods:
            maps.append(SpeedMap("lfe", lfe_speed(P, d1, d2, f, sc), a1, a2, plane,
                                 f"f = {f:.0f} Hz [Knutsson1994]"))
        if "tiempo_vuelo" in methods and not harmonic:
            T = arrival_times(frames, times)
            T[~np.isfinite(frames[..., 0])] = np.nan
            valid = np.isfinite(T)
            if plane.startswith("enface"):
                X, Y = np.meshgrid(a2, a1)
                r = np.hypot(X - exc.center_x_mm, Y - exc.center_y_mm)
                excl = sc.exclude_radius_mm or max(exc.size_a_mm, 0.3)
                valid &= r > excl
            else:
                excl = sc.exclude_radius_mm or max(exc.size_a_mm, 0.3)
                xsrc = next((bm["x_src_mm"] for bm in res.bmode if bm["x_mm"] is a2), 0.0)
                valid &= np.abs(a2[None, :] - xsrc) > excl
            maps.append(SpeedMap("tiempo_vuelo", tof_speed(T, d1, d2, sc, valid, win1), a1, a2, plane,
                                 "eikonal |grad T| = 1/c [McLaughlin2006]"))
        if "reverberante" in methods:
            c, info = reverberant_speed(P, d1, d2, f, sc, plane)
            maps.append(SpeedMap("reverberante", c, a1, a2, plane,
                                 f"modelo {info['modelo']} [Zvietcovich2019; Aki1957]"))
    return maps


def _kf_analysis(res: SimulationResult, surf_v: np.ndarray, tau: np.ndarray) -> dict[str, Any] | None:
    """Dispersión k-f a lo largo del B-scan principal, a ambos lados de la fuente."""
    if not res.bmode:
        return None
    cfg = res.cfg
    bm = res.bmode[0]
    b, s = bm["b"], bm["s"]
    v = surf_v[b, s]                                  # [A, T]
    pos = res.plan.positions[b, s]
    exc = cfg.excitation
    # coordenada a lo largo de la línea medida desde la proyección de la fuente
    direction = pos[-1] - pos[0]
    L = np.linalg.norm(direction)
    if L == 0:
        return None
    u = direction / L
    xl = (pos - np.array([exc.center_x_mm, exc.center_y_mm])) @ u
    excl = max(exc.size_a_mm, 0.4)
    out: dict[str, Any] = {"curves": []}
    for side in (+1, -1):
        sel = side * xl > excl
        if sel.sum() < 8:
            continue
        order = np.argsort(xl[sel])
        xs = xl[sel][order] * 1e-3
        vs = v[sel][order]
        lo, hi = cfg.processing.filter_low_hz, cfg.processing.filter_high_hz
        res_kf = kf_dispersion(vs, xs, cfg.acquisition.line_period_s, cfg.speed, direction=side,
                               start_band_hz=(lo, hi))
        res_kf["side"] = side
        out["curves"].append(res_kf)
    if not out["curves"]:
        return None
    f = out["curves"][0]["f_hz"]
    cs = np.vstack([c["c_m_s"] for c in out["curves"]])
    mags = np.vstack([c["magnitude"] for c in out["curves"]])
    with np.errstate(invalid="ignore"):
        out["c_mean"] = np.nanmean(np.where(mags > 0, cs, np.nan), axis=0)
    out["f_hz"] = f
    out["magnitude"] = mags.max(axis=0)
    return out


def _json_default(o: Any) -> Any:
    if isinstance(o, (np.floating, np.integer)):
        return o.item()
    if isinstance(o, np.ndarray):
        return o.tolist()
    if isinstance(o, Path):
        return str(o)
    return str(o)


def _summary(res: SimulationResult) -> dict[str, Any]:
    return {
        "nombre": res.cfg.name,
        "fecha": datetime.now().isoformat(timespec="seconds"),
        "regimen": res.regime,
        "frecuencia_analisis_hz": res.f_analysis_hz,
        "fdtd": res.fdtd_info,
        "adquisicion": res.plan.info,
        "tiempos_s": res.timings,
        "advertencias": res.warnings,
        "validacion": res.validation,
        "comprobacion_cadena_oct": ({k: v for k, v in res.truth_check.items() if np.isscalar(v)}
                                    if res.truth_check else None),
        "archivos": res.files,
        "supuestos": res.assumptions,
        "referencias_preset": {k: references.REFERENCES.get(k, k) for k in res.cfg.sources},
    }
