"""Spectrometer alignment metrics.

The processing reproduces the MATLAB characterization chain of
``SD-OCT-1310-nm/characterization/Codes`` (``OCT_Parametros.m`` +
``OCT_Comun.m``): per-A-line DC removal, linear-in-pixel wavelength axis,
not-a-knot cubic resampling to uniform k, 8192-point FFT, mean ``|FFT|`` over
A-lines, direct FWHM at half the absolute peak and a Gaussian fit in the same
window.  A reference exported by ``Exportar_Referencia_Alineacion.m`` carries
the processing parameters, so live values are directly comparable with
``Penetration_Analysis_TDMS.m``.
"""
from __future__ import annotations

import json
import math
import warnings
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

import numpy as np
from numpy.typing import NDArray

try:  # SciPy's not-a-knot spline matches MATLAB interp1(..., 'spline').
    with warnings.catch_warnings():
        # The installed SciPy warns about the newer NumPy but CubicSpline works.
        warnings.simplefilter("ignore", UserWarning)
        from scipy.interpolate import CubicSpline as _CubicSpline
except ImportError:  # pragma: no cover - exercised only without SciPy
    _CubicSpline = None

BLUE_BAND_PX = (300, 1000)
RED_BAND_PX = (1300, 2000)
RMS_BAND_PX = (200, 2000)
SHARPNESS_PERIOD_PX = (5.0, 16.0)      # spectral detail scale sensitive to the spectrometer focus
FOCUS_SENSITIVE_DEPTH_UM = 800.0       # fringe period <~ 15 camera pixels


@dataclass(frozen=True, slots=True)
class ProcessingParameters:
    lambda_start_nm: float = 1264.11
    lambda_end_nm: float = 1466.29
    n_pix: int = 2048
    n_fft: int = 8192
    um_per_px: float = 1.4836386292580375
    px_min_search: int = 25
    px_max_search: int = 4000
    fit_window: int = 100
    fit_window_auto: bool = True
    envelope_bins: int = 6
    ratio_px: tuple[int, int] = (600, 1300)

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> "ProcessingParameters":
        return cls(
            lambda_start_nm=float(data["lambda_ini_nm"]),
            lambda_end_nm=float(data["lambda_fin_nm"]),
            n_pix=int(data["n_pix"]),
            n_fft=int(data["n_fft"]),
            um_per_px=float(data["um_por_px"]),
            px_min_search=int(data["px_min_busqueda"]),
            px_max_search=int(data["px_max_busqueda"]),
            fit_window=int(data["ancho_ventana"]),
            fit_window_auto=bool(data["ventana_auto_adapt"]),
            envelope_bins=int(data["bins_envolvente"]),
            ratio_px=tuple(int(v) for v in data["px_cociente"]),  # type: ignore[arg-type]
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "lambda_ini_nm": self.lambda_start_nm,
            "lambda_fin_nm": self.lambda_end_nm,
            "metodo_interp_k": "spline",
            "n_pix": self.n_pix,
            "n_fft": self.n_fft,
            "um_por_px": self.um_per_px,
            "px_min_busqueda": self.px_min_search,
            "px_max_busqueda": self.px_max_search,
            "modelo_ajuste": "gauss",
            "ancho_ventana": self.fit_window,
            "ventana_auto_adapt": self.fit_window_auto,
            "bins_envolvente": self.envelope_bins,
            "px_cociente": list(self.ratio_px),
        }


@dataclass(slots=True)
class SpectrumMetrics:
    mean_spectrum: NDArray[np.float64]
    envelope: NDArray[np.float64]
    envelope_norm: NDArray[np.float64]
    ratio: float
    edges50_px: tuple[int, int]
    width50_px: int
    fwhm_spectrum_um: float
    max_counts: float
    saturated_fraction: float
    sharpness: float = float("nan")    # fine spectral detail / mean level (x1000), see spectral_sharpness


@dataclass(slots=True)
class FringeMetrics:
    """Fringe contrast of the mirror interference (spectrometer focus indicator).

    ``contrast`` = AC amplitude / DC level, averaged over the bright part of the
    spectrum.  It equals V*2*sqrt(rho)/(1+rho) with rho = Is/Ir; ``visibility``
    is the absolute V when rho is known (both arms captured).  ``blue_red`` is the
    contrast of the blue third of the camera over the red third: a value that
    drifts away from ~0.9 as the mirror moves deeper reveals a tilted focal plane.
    """
    contrast: float
    visibility: float
    blue_red: float
    depth_um: float
    focus_sensitive: bool
    valid: bool
    pixel: NDArray[np.float64]
    profile: NDArray[np.float64]


@dataclass(slots=True)
class PsfMetrics:
    depth_um: float
    peak_px: float
    peak_db: float
    fwhm_fit_um: float
    fwhm_direct_um: float
    r2: float
    window_px: NDArray[np.float64]
    window_amp: NDArray[np.float64]
    fit_params: NDArray[np.float64]
    shallow_warning: bool
    ascan: NDArray[np.float64] = field(default_factory=lambda: np.empty(0))
    search_px: tuple[int, int] = (0, 0)
    manual_window: bool = False
    snr_db: float = float("nan")   # peak over the median A-scan level (noise floor)


@dataclass(slots=True)
class AlignmentResult:
    spectrum: SpectrumMetrics
    psf: PsfMetrics | None
    n_alines: int
    rms_diff_pct: float | None = None
    blue_change_pct: float | None = None
    red_change_pct: float | None = None
    timestamp: float = 0.0
    warnings: list[str] = field(default_factory=list)
    fringe: FringeMetrics | None = None
    frame_mean: NDArray[np.float64] | None = None   # mean raw spectrum of this frame only
    sharpness_rel: float | None = None              # sharpness / reference sharpness


@dataclass(slots=True)
class AlignmentReference:
    name: str
    path: Path | None
    params: ProcessingParameters
    metrics: SpectrumMetrics
    psf: PsfMetrics | None
    created: str
    source: str

    @classmethod
    def load(cls, path: str | Path) -> "AlignmentReference":
        path = Path(path)
        data = json.loads(path.read_text(encoding="utf-8"))
        params = ProcessingParameters.from_json(data["procesamiento"])
        processor = AlignmentProcessor(params)
        spectrum = np.asarray(data["espectro_medio"], dtype=np.float64)
        if spectrum.shape != (params.n_pix,):
            raise ValueError(f"La referencia tiene {spectrum.size} píxeles; se esperaban {params.n_pix}.")
        metrics = processor.spectrum_metrics(spectrum, max_counts=float(
            data.get("indicadores_matlab", {}).get("max_cuentas", spectrum.max())))
        psf = None
        ind = data.get("indicadores_matlab", {})
        depth = float(ind.get("profundidad_um", float("nan")))
        fringe_f0 = depth / params.um_per_px / params.n_fft if math.isfinite(depth) else None
        metrics.sharpness = spectral_sharpness(spectrum, metrics.envelope, fringe_f0)
        if "fwhm_ajuste_um" in ind:
            psf = PsfMetrics(
                depth_um=float(ind["profundidad_um"]), peak_px=float("nan"), peak_db=float("nan"),
                fwhm_fit_um=float(ind["fwhm_ajuste_um"]), fwhm_direct_um=float(ind["fwhm_datos_um"]),
                r2=float("nan"), window_px=np.empty(0), window_amp=np.empty(0),
                fit_params=np.empty(0), shallow_warning=False,
            )
        source = str(data.get("archivo_tdms", ""))
        name = path.stem
        if source and source != "live":
            source_path = Path(source.replace("\\", "/"))
            name = f"{source_path.parent.name}/{source_path.name}"
        return cls(name=name, path=path, params=params, metrics=metrics, psf=psf,
                   created=str(data.get("creado", "")), source=source)

    @classmethod
    def from_result(cls, result: AlignmentResult, params: ProcessingParameters, name: str) -> "AlignmentReference":
        return cls(name=name, path=None, params=params, metrics=result.spectrum, psf=result.psf,
                   created=datetime.now().strftime("%Y-%m-%d %H:%M:%S"), source="live")

    def save(self, path: str | Path) -> Path:
        path = Path(path)
        payload: dict[str, Any] = {
            "version": 1,
            "descripcion": "Referencia espectral para Alineacion del espectrometro (OCT_GUI)",
            "creado": self.created,
            "archivo_tdms": self.source,
            "procesamiento": self.params.to_json(),
            "espectro_medio": [float(v) for v in self.metrics.mean_spectrum],
            "indicadores_matlab": {
                "cociente": self.metrics.ratio,
                "borde50_px": list(self.metrics.edges50_px),
                "fwhm_espectro_um": self.metrics.fwhm_spectrum_um,
                "max_cuentas": self.metrics.max_counts,
            },
        }
        if self.psf is not None:
            payload["indicadores_matlab"].update(
                profundidad_um=self.psf.depth_um,
                fwhm_ajuste_um=self.psf.fwhm_fit_um,
                fwhm_datos_um=self.psf.fwhm_direct_um,
            )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        self.path = path
        return path


class AlignmentProcessor:
    """Stateless per-frame computation with precomputed k-grids."""

    def __init__(self, params: ProcessingParameters, *, sensor_max: float = 4095.0):
        self.params = params
        self.sensor_max = float(sensor_max)
        wavelength = np.linspace(params.lambda_start_nm, params.lambda_end_nm, params.n_pix)
        self._k_ascending = (2.0 * np.pi / wavelength)[::-1]
        self._k_uniform = np.linspace(self._k_ascending[0], self._k_ascending[-1], params.n_pix)
        self.spline_exact = _CubicSpline is not None
        pixels = np.arange(params.n_pix, dtype=np.float64)
        # camera pixel (0-based) sampled by each uniform-k point (OCT_Comun / pixelFuenteK)
        self.pixel_of_k = np.interp(self._k_uniform, self._k_ascending, pixels[::-1])
        # rFFT of the k-resampled A-lines of the last psf_metrics call (reused by fringe_metrics)
        self.last_rfft: NDArray[np.complex128] | None = None

    # -- k-linearization ---------------------------------------------------
    def _to_uniform_k(self, rows: NDArray[np.float64]) -> NDArray[np.float64]:
        """Resample [..., pixel] camera-order spectra onto uniform k."""
        flipped = rows[..., ::-1]
        if _CubicSpline is not None:
            return _CubicSpline(self._k_ascending, flipped, axis=-1)(self._k_uniform)
        flat = flipped.reshape(-1, flipped.shape[-1])
        out = np.vstack([np.interp(self._k_uniform, self._k_ascending, r) for r in flat])
        return out.reshape(flipped.shape)

    # -- spectrum shape ----------------------------------------------------
    def spectrum_metrics(self, mean_spectrum: NDArray[np.floating], *, max_counts: float,
                         saturated_fraction: float = 0.0) -> SpectrumMetrics:
        p = self.params
        spectrum = np.asarray(mean_spectrum, dtype=np.float64)
        envelope = lowpass_envelope(spectrum, p.envelope_bins)
        peak = float(envelope.max())
        envelope_norm = envelope / peak if peak > 0 else np.zeros_like(envelope)
        a, b = p.ratio_px
        ratio = float(envelope[a] / envelope[b]) if envelope[b] != 0 else float("nan")
        above = np.flatnonzero(envelope_norm >= 0.5)
        edges = (int(above[0]), int(above[-1])) if above.size else (0, 0)

        shifted = np.maximum(envelope - envelope.min(), 0.0)
        envelope_k = self._to_uniform_k(shifted)
        coherence = np.fft.fftshift(np.abs(np.fft.fft(envelope_k, p.n_fft)))
        x = np.arange(-p.n_fft // 2, p.n_fft // 2, dtype=np.float64)
        fwhm_px = fwhm_direct(x, coherence, p.n_fft // 2)
        return SpectrumMetrics(
            mean_spectrum=spectrum, envelope=envelope, envelope_norm=envelope_norm, ratio=ratio,
            edges50_px=edges, width50_px=edges[1] - edges[0],
            fwhm_spectrum_um=fwhm_px * p.um_per_px, max_counts=float(max_counts),
            saturated_fraction=float(saturated_fraction),
        )

    # -- mirror PSF (as Penetration_Analysis_TDMS.m) ------------------------
    def psf_metrics(self, spectra: NDArray[np.integer],
                    search_um: tuple[float, float] | None = None) -> PsfMetrics | None:
        """Mirror PSF.  ``search_um`` restricts the peak search, the direct FWHM and
        the fit window to a manual depth range; ``None`` uses the full range of
        Penetration_Analysis_TDMS.m."""
        p = self.params
        work = np.asarray(spectra, dtype=np.float64)
        work = work - work.mean(axis=1, keepdims=True)          # DC per A-line
        work = self._to_uniform_k(work)
        self.last_rfft = np.fft.rfft(work, n=p.n_fft, axis=1)
        amp = np.abs(self.last_rfft).mean(axis=0)[: p.n_fft // 2]
        x = np.arange(p.n_fft // 2, dtype=np.float64)
        px_min = max(1, p.px_min_search)
        px_max = min(p.n_fft // 2 - 2, p.px_max_search)
        if search_um is not None:
            lo_um, hi_um = sorted(float(v) for v in search_um)
            lo = max(px_min, int(math.ceil(lo_um / p.um_per_px)))
            hi = min(px_max, int(math.floor(hi_um / p.um_per_px)))
            if hi - lo < 4:
                raise ValueError(
                    f"La ventana PSF {lo_um:.0f}–{hi_um:.0f} µm es demasiado estrecha o está fuera "
                    f"del rango útil ({px_min * p.um_per_px:.0f}–{px_max * p.um_per_px:.0f} µm).")
            i_min, i_max = lo, hi
        else:
            lo, hi = px_min, px_max
            # 0-based port of OCT_Comun.medirFWHMDirecto: iMin = pxMin+1 (1-based).
            i_min, i_max = px_min, amp.size - 2
        peak_px, peak_idx, _ = find_peak(x, amp, np.arange(lo, hi + 1))
        # Relocalize +-5 bins on the unwindowed A-scan (identical here: no Hann).
        local = np.arange(max(i_min, peak_idx - 5), min(i_max, peak_idx + 5) + 1)
        peak_px, peak_idx, peak_amp = find_peak(x, amp, local)
        if search_um is None:
            fwhm_px = fwhm_direct(x, amp, peak_idx)
        else:   # half-maximum crossings must lie inside the manual window
            fwhm_px = fwhm_direct(x[lo:hi + 1], amp[lo:hi + 1], peak_idx - lo)
        n = p.fit_window
        if p.fit_window_auto and math.isfinite(fwhm_px):
            n = max(n, math.ceil(3 * fwhm_px))
        xw, yw = peak_window(x, amp, peak_idx, n, i_min, None if search_um is None else i_max)
        seed = fwhm_px if math.isfinite(fwhm_px) else max(2.0, p.fit_window / 10)
        params = fit_gauss(xw, yw, np.array([peak_amp, peak_px, seed, 0.0]))
        model = gauss_model(params, xw)
        sst = float(np.sum((yw - yw.mean()) ** 2))
        r2 = 1.0 - float(np.sum((yw - model) ** 2)) / sst if sst > 0 else float("nan")
        native_bin = peak_px * p.n_pix / p.n_fft
        noise_floor = float(np.median(amp[px_min:px_max + 1]))
        snr_db = 20.0 * math.log10(peak_amp / noise_floor) if noise_floor > 0 else float("inf")
        return PsfMetrics(
            depth_um=peak_px * p.um_per_px, peak_px=peak_px,
            peak_db=10.0 * math.log10(max(peak_amp, 1e-12)),
            fwhm_fit_um=abs(params[2]) * p.um_per_px, fwhm_direct_um=fwhm_px * p.um_per_px,
            r2=r2, window_px=xw, window_amp=yw, fit_params=params,
            shallow_warning=native_bin < 1.7 * p.envelope_bins,
            ascan=amp, search_px=(lo, hi), manual_window=search_um is not None, snr_db=snr_db,
        )

    # -- spectrometer focus --------------------------------------------------
    def fringe_metrics(self, spectra: NDArray[np.integer], psf: PsfMetrics,
                       dark: NDArray[np.floating] | None = None,
                       rho: NDArray[np.floating] | None = None,
                       max_lines: int = 100) -> FringeMetrics:
        """Local fringe contrast along the camera by k-domain demodulation of the
        mirror term (band-pass around the PSF, analytic signal, |.| per A-line).

        Reuses the rFFT left by :meth:`psf_metrics` for the same ``spectra``."""
        p = self.params
        data = np.asarray(spectra, dtype=np.float64)
        mean = data.mean(axis=0)
        if dark is not None:
            mean = mean - np.asarray(dark, dtype=np.float64)
        dc_k = self._to_uniform_k(np.maximum(mean, 0.0))
        rfft = self.last_rfft
        if rfft is None or rfft.shape[0] != data.shape[0]:
            work = self._to_uniform_k(data - data.mean(axis=1, keepdims=True))
            rfft = np.fft.rfft(work, n=p.n_fft, axis=1)
        rfft = rfft[:max_lines]
        center = int(round(psf.peak_px))
        fwhm_px = psf.fwhm_fit_um / p.um_per_px if math.isfinite(psf.fwhm_fit_um) else 10.0
        half = max(30, int(4 * fwhm_px))
        lo, hi = center - half, min(p.n_fft // 2 - 1, center + half)
        valid = lo > p.px_min_search + 5 and psf.snr_db >= 15.0
        lo = max(lo, p.px_min_search)
        band = np.zeros((rfft.shape[0], p.n_fft), dtype=np.complex128)
        band[:, lo:hi + 1] = 2.0 * rfft[:, lo:hi + 1]   # one-sided band -> analytic signal
        analytic = np.fft.ifft(band, axis=1)[:, : p.n_pix]
        ac_k = np.abs(analytic).mean(axis=0)      # cosine amplitude 2*sqrt(Ir*Is)*V per k sample
        bright = dc_k > 0.3 * dc_k.max() if dc_k.max() > 0 else np.zeros(p.n_pix, dtype=bool)
        if np.count_nonzero(bright) < 30:
            valid = False
            bright = np.ones(p.n_pix, dtype=bool)
        contrast = float(ac_k[bright].sum() / max(dc_k[bright].sum(), 1e-12))
        profile = np.full(p.n_pix, np.nan)
        profile[bright] = ac_k[bright] / dc_k[bright]
        thirds = np.array_split(np.flatnonzero(bright), 3)

        def band(idx: NDArray[np.int64]) -> float:
            return float(ac_k[idx].sum() / max(dc_k[idx].sum(), 1e-12))

        # uniform-k samples run from long to short wavelength: blue (low camera
        # pixel) is the high-k end, i.e. the last third.
        blue_red = band(thirds[2]) / band(thirds[0]) if band(thirds[0]) > 0 else float("nan")
        visibility = float("nan")
        if rho is not None:
            rho_k = np.interp(self.pixel_of_k, np.arange(p.n_pix), np.asarray(rho, dtype=np.float64))
            rho_k = np.clip(rho_k, 1e-6, None)
            scale = (1.0 + rho_k) / (2.0 * np.sqrt(rho_k))
            visibility = float((ac_k[bright] * scale[bright]).sum() / max(dc_k[bright].sum(), 1e-12))
        return FringeMetrics(
            contrast=contrast, visibility=visibility, blue_red=blue_red, depth_um=psf.depth_um,
            focus_sensitive=psf.depth_um >= FOCUS_SENSITIVE_DEPTH_UM, valid=bool(valid),
            pixel=self.pixel_of_k.copy(), profile=profile,
        )

    def process(self, spectra: NDArray[np.integer], reference: AlignmentReference | None = None,
                *, with_psf: bool = True,
                search_um: tuple[float, float] | None = None,
                dark: NDArray[np.floating] | None = None,
                rho: NDArray[np.floating] | None = None) -> AlignmentResult:
        raw = np.asarray(spectra)
        if raw.ndim != 2 or raw.shape[1] != self.params.n_pix:
            raise ValueError(f"Se esperaba [A-lines, {self.params.n_pix}] y llegó {raw.shape}.")
        mean_spectrum = raw.mean(axis=0, dtype=np.float64)
        max_counts = float(raw.max())
        saturated = float(np.mean(raw >= self.sensor_max))
        spectrum = self.spectrum_metrics(mean_spectrum, max_counts=max_counts,
                                         saturated_fraction=saturated)
        psf = self.psf_metrics(raw, search_um) if with_psf else None
        f0 = psf.peak_px / self.params.n_fft if psf is not None else None
        spectrum.sharpness = spectral_sharpness(mean_spectrum, spectrum.envelope, f0)
        result = AlignmentResult(spectrum=spectrum, psf=psf, n_alines=int(raw.shape[0]),
                                 frame_mean=mean_spectrum)
        if psf is not None:
            result.fringe = self.fringe_metrics(raw, psf, dark, rho)
        if reference is not None:
            compare(result, reference)
        if psf is not None and psf.shallow_warning:
            result.warnings.append("Espejo muy cerca del retardo cero: las franjas contaminan la envolvente.")
        if max_counts >= self.sensor_max:
            result.warnings.append("Saturación del sensor: reduzca la potencia.")
        return result


def lowpass_envelope(spectrum: NDArray[np.floating], bins: int = 6) -> NDArray[np.float64]:
    """Spectral envelope: keeps the lowest ``bins`` FFT bins (removes the mirror fringes)."""
    spectrum = np.asarray(spectrum, dtype=np.float64)
    mask = np.zeros(spectrum.size)
    mask[: bins + 1] = 1.0
    mask[-bins:] = 1.0
    return np.real(np.fft.ifft(np.fft.fft(spectrum) * mask))


def spectral_sharpness(mean_spectrum: NDArray[np.floating], envelope: NDArray[np.floating],
                       fringe_cycles_per_px: float | None = None) -> float:
    """Fine spectral detail (periods of 5-16 camera pixels) relative to the mean level.

    A defocused spectrometer blurs the fine structure of the source/fiber spectrum,
    so this index drops even when the mirror is close to zero delay, where the
    fringe contrast cannot see the focus.  The band around the mirror fringe
    frequency (and its 2nd harmonic) is excluded.  Indicative only: the camera's
    fixed-pattern noise also contributes.
    """
    spectrum = np.asarray(mean_spectrum, dtype=np.float64)
    env = np.asarray(envelope, dtype=np.float64)
    bright = np.flatnonzero(env > 0.3 * env.max()) if env.max() > 0 else np.empty(0, dtype=int)
    if bright.size < 200:
        return float("nan")
    core = slice(int(bright[0]), int(bright[-1]) + 1)
    detail = (spectrum - env)[core]
    coeffs = np.abs(np.fft.rfft(detail * np.hanning(detail.size)))
    freq = np.fft.rfftfreq(detail.size)
    band = (freq >= 1.0 / SHARPNESS_PERIOD_PX[1]) & (freq <= 1.0 / SHARPNESS_PERIOD_PX[0])
    total = np.count_nonzero(band)
    if fringe_cycles_per_px is not None and fringe_cycles_per_px > 0:
        f0 = fringe_cycles_per_px
        band &= ~((freq > 0.75 * f0) & (freq < 1.33 * f0))
        band &= ~((freq > 1.5 * f0) & (freq < 2.66 * f0))
    if np.count_nonzero(band) < 0.3 * total:
        return float("nan")
    level = float(env[core].mean())
    return float(np.sqrt(np.mean(coeffs[band] ** 2)) / level * 1e3) if level > 0 else float("nan")


def compare(result: AlignmentResult, reference: AlignmentReference) -> None:
    if math.isfinite(result.spectrum.sharpness) and math.isfinite(reference.metrics.sharpness) \
            and reference.metrics.sharpness > 0:
        result.sharpness_rel = result.spectrum.sharpness / reference.metrics.sharpness
    cur, ref = result.spectrum.envelope_norm, reference.metrics.envelope_norm
    a, b = RMS_BAND_PX
    result.rms_diff_pct = float(100.0 * np.sqrt(np.mean((cur[a:b + 1] - ref[a:b + 1]) ** 2)))
    for attr, (lo, hi) in (("blue_change_pct", BLUE_BAND_PX), ("red_change_pct", RED_BAND_PX)):
        ref_mean = float(ref[lo:hi + 1].mean())
        setattr(result, attr, 100.0 * (float(cur[lo:hi + 1].mean()) / ref_mean - 1.0)
                if ref_mean > 0 else None)


# -- numerical helpers shared with OCT_Comun.m -----------------------------
def find_peak(x: NDArray[np.float64], y: NDArray[np.float64],
              index_range: NDArray[np.int64]) -> tuple[float, int, float]:
    """Max inside ``index_range`` with parabolic refinement in dB (OCT_Comun.buscarPico)."""
    i = int(index_range[int(np.argmax(y[index_range]))])
    amp = float(y[i])
    v = 10.0 * np.log10(np.maximum(y[i - 1:i + 2], np.finfo(float).eps))
    den = v[0] - 2.0 * v[1] + v[2]
    px = float(x[i]) if den == 0 else float(x[i] + 0.5 * (v[0] - v[2]) / den)
    return px, i, amp


def fwhm_direct(x: NDArray[np.float64], y: NDArray[np.float64], i: int) -> float:
    """FWHM at half the absolute peak with linear interpolation (OCT_Comun.fwhmDirecto)."""
    h = y[i] / 2.0
    left = i
    while left > 0 and y[left] > h:
        left -= 1
    right = i
    while right < y.size - 1 and y[right] > h:
        right += 1
    if left == i or right == i or left == 0 or right == y.size - 1:
        return float("nan")
    x_left = x[left] + (h - y[left]) * (x[left + 1] - x[left]) / (y[left + 1] - y[left])
    x_right = x[right - 1] + (h - y[right - 1]) * (x[right] - x[right - 1]) / (y[right] - y[right - 1])
    return float(x_right - x_left)


def peak_window(x: NDArray[np.float64], y: NDArray[np.float64], i: int, n: int,
                i_min: int, i_max: int | None = None) -> tuple[NDArray[np.float64], NDArray[np.float64]]:
    """0-based port of OCT_Comun.ventanaPico; ``i_max`` optionally caps the window."""
    last = x.size - 1 if i_max is None else min(x.size - 1, i_max)
    i0 = max(i_min, i - n // 2)
    i1 = min(last, i0 + n - 1)
    i0 = max(i_min, i1 - n + 1)
    return x[i0:i1 + 1].copy(), y[i0:i1 + 1].copy()


def gauss_model(p: NDArray[np.float64], x: NDArray[np.float64]) -> NDArray[np.float64]:
    u = (x - p[1]) / abs(p[2])
    return p[0] * np.exp(-4.0 * np.log(2.0) * u * u) + p[3]


def fit_gauss(x: NDArray[np.float64], y: NDArray[np.float64],
              p0: NDArray[np.float64], iterations: int = 200) -> NDArray[np.float64]:
    """Bounded Levenberg-Marquardt fit of A*exp(-4ln2((x-x0)/FWHM)^2)+C.

    Same bounds as OCT_Comun.ajustarPico: A>=0, x0 inside the window,
    1 <= FWHM <= 3*window, 0 <= C <= max(y).
    """
    width = float(x[-1] - x[0])
    lo = np.array([0.0, x[0], 1.0, 0.0])
    hi = np.array([2.0 * y.max(), x[-1], 3.0 * width, y.max()])
    p = np.clip(np.asarray(p0, dtype=np.float64), lo, hi)
    lam = 1e-3
    c = 4.0 * np.log(2.0)

    def residual(q: NDArray[np.float64]) -> NDArray[np.float64]:
        return gauss_model(q, x) - y

    r = residual(p)
    cost = float(r @ r)
    for _ in range(iterations):
        u = (x - p[1]) / p[2]
        g = np.exp(-c * u * u)
        jac = np.column_stack((
            g,
            p[0] * g * 2.0 * c * u / p[2],
            p[0] * g * 2.0 * c * u * u / p[2],
            np.ones_like(x),
        ))
        jtj = jac.T @ jac
        grad = jac.T @ r
        improved = False
        step = np.zeros_like(p)
        for _ in range(12):
            try:
                step = np.linalg.solve(jtj + lam * np.diag(np.diag(jtj) + 1e-12), -grad)
            except np.linalg.LinAlgError:
                lam *= 10.0
                continue
            trial = np.clip(p + step, lo, hi)
            r_trial = residual(trial)
            cost_trial = float(r_trial @ r_trial)
            if cost_trial < cost:
                p, r, cost = trial, r_trial, cost_trial
                lam = max(lam / 3.0, 1e-9)
                improved = True
                break
            lam *= 4.0
        if not improved or np.max(np.abs(step)) < 1e-7 * max(1.0, float(np.max(np.abs(p)))):
            break
    return p
