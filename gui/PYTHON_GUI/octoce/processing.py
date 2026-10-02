from __future__ import annotations

import numpy as np
from numpy.typing import NDArray

# Spectral apodization windows offered by the preview.  "Hann" is the historical
# default.  Every window is scaled to the coherent gain of Hann, so switching the
# window changes the PSF shape/sidelobes but not the dB level of a reflector.
SPECTRAL_WINDOWS = (
    "Rectangular", "Hann", "Hamming", "Blackman", "Blackman-Harris",
    "Tukey (α=0.5)", "Kaiser (β=8)", "Gauss (σ=0.4)",
)
DEFAULT_SPECTRAL_WINDOW = "Hann"


def spectral_window(name: str, samples: int) -> NDArray[np.float64]:
    """Apodization window normalized to the coherent gain (mean) of Hann."""
    n = np.arange(samples, dtype=np.float64)
    x = n / max(samples - 1, 1)                      # 0..1
    if name == "Rectangular":
        w = np.ones(samples)
    elif name == "Hann":
        w = np.hanning(samples)
    elif name == "Hamming":
        w = np.hamming(samples)
    elif name == "Blackman":
        w = np.blackman(samples)
    elif name == "Blackman-Harris":
        a = (0.35875, 0.48829, 0.14128, 0.01168)
        w = (a[0] - a[1] * np.cos(2 * np.pi * x) + a[2] * np.cos(4 * np.pi * x)
             - a[3] * np.cos(6 * np.pi * x))
    elif name == "Tukey (α=0.5)":
        alpha = 0.5
        w = np.ones(samples)
        edge = x < alpha / 2
        w[edge] = 0.5 * (1 + np.cos(np.pi * (2 * x[edge] / alpha - 1)))
        edge = x > 1 - alpha / 2
        w[edge] = 0.5 * (1 + np.cos(np.pi * (2 * x[edge] / alpha - 2 / alpha + 1)))
    elif name == "Kaiser (β=8)":
        w = np.kaiser(samples, 8.0)
    elif name == "Gauss (σ=0.4)":
        w = np.exp(-0.5 * ((x - 0.5) / (0.4 * 0.5)) ** 2)
    else:
        raise ValueError(f"Ventana espectral desconocida: {name}. Opciones: {', '.join(SPECTRAL_WINDOWS)}")
    reference = float(np.hanning(samples).mean()) if samples > 2 else 1.0
    return w * (reference / float(w.mean()))


def reconstruct_oct_complex(
    spectra: NDArray[np.uint16],
    *,
    fft_size: int | None = None,
    background: NDArray[np.floating] | None = None,
    remove_dc: bool = True,
    reverse_spectrum: bool = False,
    wavelength_start_nm: float | None = None,
    wavelength_end_nm: float | None = None,
    dispersion_d2_rad: float = 0.0,
    dispersion_d3_rad: float = 0.0,
    window: str = DEFAULT_SPECTRAL_WINDOW,
) -> NDArray[np.complex64]:
    """Create a diagnostic complex OCT reconstruction in ``[depth, A-line]``.

    ``window`` selects the spectral apodization (see ``SPECTRAL_WINDOWS``).

    Optional endpoint-based k resampling is approximate. A non-zero dispersion
    (D2, D3 in rad over the normalized uniform-k axis q in [-1, 1]) is applied
    to the analytic signal after k resampling, with the same convention as the
    MATLAB characterization (OCT_Comun.ascan): S * exp(-1j*(D2 q^2 + D3 q^3)).
    """
    raw = np.asarray(spectra)
    if raw.ndim != 2 or raw.shape[1] < 2:
        raise ValueError("Se esperaba una matriz [A-lines, píxeles].")
    work = raw.astype(np.float32, copy=True)
    if background is not None:
        bg = np.asarray(background, dtype=np.float32)
        if bg.shape != (work.shape[1],):
            raise ValueError("El background debe tener un valor por píxel espectral.")
        work -= bg[None, :]
    elif remove_dc:
        # Standard B-scan DC/background suppression: remove the fixed spectral
        # component shared by the lateral A-lines.  Subtracting a scalar from
        # each A-line would only remove its zero-frequency offset and leaves the
        # stationary spectrometer/camera pattern dominating the preview.
        work -= work.mean(axis=0, keepdims=True)
    if reverse_spectrum:
        work = work[:, ::-1]
    if wavelength_start_nm is not None or wavelength_end_nm is not None:
        if wavelength_start_nm is None or wavelength_end_nm is None:
            raise ValueError("Se requieren ambos extremos de longitud de onda para linealizar k.")
        if wavelength_start_nm <= 0 or wavelength_end_nm <= 0 or wavelength_start_nm == wavelength_end_nm:
            raise ValueError("El rango de longitudes de onda debe ser positivo y no nulo.")
        wavelength = np.linspace(
            wavelength_start_nm,
            wavelength_end_nm,
            work.shape[1],
            dtype=np.float64,
        )
        wavenumber = 2.0 * np.pi / wavelength
        order = np.argsort(wavenumber)
        ordered_k = wavenumber[order]
        uniform_k = np.linspace(ordered_k[0], ordered_k[-1], work.shape[1], dtype=np.float64)
        mapped = np.empty_like(work)
        for row_index, row in enumerate(work):
            mapped[row_index] = np.interp(uniform_k, ordered_k, row[order])
        work = mapped
    dispersion = dispersion_d2_rad != 0.0 or dispersion_d3_rad != 0.0
    if dispersion and wavelength_start_nm is None:
        raise ValueError("La compensación de dispersión requiere la linealización en k.")
    apodization = spectral_window(window, work.shape[1]).astype(np.float32)[None, :]
    if fft_size is None:
        fft_size = 1 << int(np.ceil(np.log2(work.shape[1])))
    if dispersion:
        analytic = analytic_signal(work) * np.exp(
            -1j * dispersion_phase(work.shape[1], dispersion_d2_rad, dispersion_d3_rad))[None, :]
        spectrum = np.fft.fft(analytic * apodization, n=fft_size, axis=1)
    else:
        spectrum = np.fft.rfft(work * apodization, n=fft_size, axis=1)
    return np.asarray(spectrum[:, 1 : fft_size // 2 + 1].T, dtype=np.complex64)


def dispersion_phase(samples: int, d2_rad: float, d3_rad: float) -> NDArray[np.float64]:
    """Dispersion phase over the uniform-k axis (ascending k), q in [-1, 1]."""
    q = np.linspace(-1.0, 1.0, samples)
    return d2_rad * q ** 2 + d3_rad * q ** 3


def analytic_signal(rows: NDArray[np.floating]) -> NDArray[np.complex128]:
    """Row-wise analytic signal scaled like OCT_Comun.senalAnalitica (= hilbert/2):
    the positive-frequency magnitude equals that of the real signal."""
    n = rows.shape[-1]
    h = np.zeros(n)
    h[0] = 0.5
    if n % 2 == 0:
        h[1 : n // 2] = 1.0
        h[n // 2] = 0.5
    else:
        h[1 : (n + 1) // 2] = 1.0
    return np.fft.ifft(np.fft.fft(rows, axis=-1) * h, axis=-1)


def reconstruct_oct_db(
    spectra: NDArray[np.uint16],
    *,
    fft_size: int | None = None,
    background: NDArray[np.floating] | None = None,
    remove_dc: bool = True,
) -> NDArray[np.float32]:
    """Create a diagnostic OCT intensity preview from raw spectra."""
    spectrum = reconstruct_oct_complex(
        spectra,
        fft_size=fft_size,
        background=background,
        remove_dc=remove_dc,
    )
    magnitude = np.abs(spectrum)
    db = 20.0 * np.log10(magnitude + 1.0)
    return np.asarray(db, dtype=np.float32)


def preview_complex(
    spectra: NDArray[np.uint16],
    *,
    max_width: int = 700,
    max_height: int = 500,
    remove_dc: bool = True,
    fft_size: int = 8192,
    depth_bins: int = 2048,
    depth_start_bin: int = 1,
    depth_end_bin: int | None = None,
    selected_depth_bin: int | None = None,
    wavelength_start_nm: float = 1466.61,
    wavelength_end_nm: float = 1263.79,
    reverse_spectrum: bool = True,
    dispersion_d2_rad: float = 0.0,
    dispersion_d3_rad: float = 0.0,
    window: str = DEFAULT_SPECTRAL_WINDOW,
) -> tuple[NDArray[np.float32], ...]:
    """Return a conventional single-domain SD-OCT preview.

    Defaults use the configured 1310-nm wavelength endpoints: the
    detector row is reversed, resampled uniformly in k, Hann-windowed,
    zero-padded to 8192, and restricted to the usable near-depth domain.  Raw
    acquisition data is never altered.
    """
    raw = np.asarray(spectra)
    col_step = max(1, int(np.ceil(raw.shape[0] / max_width)))
    bounded_raw = np.ascontiguousarray(raw[::col_step])
    spectrum = reconstruct_oct_complex(
        bounded_raw,
        remove_dc=remove_dc,
        fft_size=fft_size,
        reverse_spectrum=reverse_spectrum,
        wavelength_start_nm=wavelength_start_nm,
        wavelength_end_nm=wavelength_end_nm,
        dispersion_d2_rad=dispersion_d2_rad,
        dispersion_d3_rad=dispersion_d3_rad,
        window=window,
    )
    if depth_end_bin is None:
        depth_end_bin = min(depth_bins, spectrum.shape[0])
    if not 1 <= depth_start_bin <= depth_end_bin <= spectrum.shape[0]:
        raise ValueError(
            f"Rango Z inválido: use 1 ≤ inicio ≤ fin ≤ {spectrum.shape[0]} bins FFT."
        )
    if selected_depth_bin is not None and not 1 <= selected_depth_bin <= spectrum.shape[0]:
        raise ValueError("El Z bin seleccionado debe estar entre 1 y 4096.")
    selected_phase = (
        np.asarray(np.angle(spectrum[selected_depth_bin - 1]), dtype=np.float32)
        if selected_depth_bin is not None else None
    )
    # rFFT already selects one conjugate half-space. The default visible window
    # is the near 2048 bins; the user may inspect deeper positive-depth bins.
    spectrum = spectrum[depth_start_bin - 1 : depth_end_bin]
    row_step = max(1, int(np.ceil(spectrum.shape[0] / max_height)))
    bounded = spectrum[::row_step]
    intensity_db = np.asarray(20.0 * np.log10(np.abs(bounded) + 1.0), dtype=np.float32)
    phase_rad = np.asarray(np.angle(bounded), dtype=np.float32)
    # The zero-frequency bin was discarded by reconstruct_oct_complex.
    depth_indexes = np.arange(depth_start_bin, depth_end_bin + 1, row_step, dtype=np.int64)
    aline_indexes = np.arange(bounded_raw.shape[0], dtype=np.int64) * col_step
    if selected_phase is not None:
        return intensity_db, phase_rad, depth_indexes, aline_indexes, selected_phase
    return intensity_db, phase_rad, depth_indexes, aline_indexes


def normalize_preview(
    image_db: NDArray[np.floating],
    *,
    low_percentile: float = 2.0,
    high_percentile: float = 99.5,
    max_width: int = 700,
    max_height: int = 500,
) -> NDArray[np.uint8]:
    image = np.asarray(image_db, dtype=np.float32)
    if image.ndim != 2 or image.size == 0:
        raise ValueError("La vista previa debe ser una imagen 2-D no vacía.")
    finite = image[np.isfinite(image)]
    if finite.size == 0:
        return np.zeros((1, 1), dtype=np.uint8)
    lo, hi = np.percentile(finite, (low_percentile, high_percentile))
    if hi <= lo:
        hi = lo + 1.0
    scaled = np.clip((image - lo) * (255.0 / (hi - lo)), 0.0, 255.0).astype(np.uint8)
    row_step = max(1, int(np.ceil(scaled.shape[0] / max_height)))
    col_step = max(1, int(np.ceil(scaled.shape[1] / max_width)))
    return np.ascontiguousarray(scaled[::row_step, ::col_step])


def preview_from_raw(
    spectra: NDArray[np.uint16],
    *,
    remove_dc: bool = True,
) -> NDArray[np.uint8]:
    return normalize_preview(reconstruct_oct_db(spectra, remove_dc=remove_dc))
