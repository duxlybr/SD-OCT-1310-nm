# MATLAB processing

## Layout

| Folder | Content |
|---|---|
| `config/` | System and calibration parameters (λ axis, axial slope, κ factors, N_w, FFT lengths) |
| `io/` | Readers for `.tdms` acquisitions and headers |
| `reconstruction/` | A-line pipeline: DC subtraction, k-linearization, windowing, FFT, log scale |
| `imaging/` | B-scan assembly (bidirectional flip, turnaround removal), volumes, en face projections |
| `calibration/` | Axial calibration fit and three-dot galvanometer calibration |
| `characterization/` | PSF/FWHM, sensitivity, roll-off model fit, phase stability |
| `utils/` | Helper and plotting functions |

## A-line pipeline

| Step | Operation | Parameters |
|---|---|---|
| 1 | DC subtraction | Background spectrum (mean over A-lines or reference-only acquisition) |
| 2 | λ → k resampling | Linear λ axis 1262.34 → 1471.08 nm over 2048 px; spline interpolation to uniform k |
| 3 | Window | Hann (no window when measuring PSF width) |
| 4 | Zero-padded FFT | 4096 (imaging) or 8192 (characterization); keep non-conjugate half |
| 5 | Magnitude in dB | 20·log₁₀\|FFT\| |

No numerical dispersion compensation is applied (dispersion is compensated
optically).

## B-scan / volume assembly

- Split the A-line stream into blocks of N_A + N_w; drop the N_w turnaround
  samples.
- Flip every reverse-ramp B-scan along the fast axis.
- Scale axes: Δz = 2.966 µm/px (4096-pt FFT), L_x = V_pp / κ_x,
  Δx = L_x / N_A.

## Calibration constants (current)

See [`../../characterization/LATEST.md`](../../characterization/LATEST.md).
