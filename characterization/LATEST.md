# Current reference values

**Source campaign:** [2026-09_final-alignment](2026-09_final-alignment/)
**Last updated:** 2026-09

These are the values that should be used to scale and interpret images
acquired with the system in its current configuration. All values are in
air. Update this file whenever a new campaign supersedes them (see
[`README.md`](README.md)).

## Calibration constants

| Constant | Value | Notes |
|---|---|---|
| Spectrometer wavelength axis | 1262.34 nm (pixel 1) → 1471.08 nm (pixel 2048), linear | Used in the thesis characterization; the processing profile `spectral_domain_1310` currently uses 1261.36 → 1472.76 nm (to be reconciled) |
| Axial calibration (8192-pt FFT) | p = 0.6744·d + 43.24 | p: peak pixel, d: micrometer reading (µm); max residual 0.72 px |
| Axial pixel size | 1.483 µm/px (8192-pt) · 2.966 µm/px (4096-pt) · 5.931 µm/native sample | Processing profile uses 1.48 µm/bin at 8192 → 5.92 µm/bin unpadded |
| Depth from zero delay | z = p / 0.6744 µm | |
| Galvanometer factor, X | 0.4053 V/mm (RMSE 1.3 mV) | Proportional fit through origin |
| Galvanometer factor, Y | 0.4071 V/mm (RMSE 2.1 mV) | Proportional fit through origin |
| Voltage for full LSM04 field (14.1 mm) | ±2.86 V (X) · ±2.87 V (Y) | Do not exceed; outside the lens design field |

## Performance

| Parameter | Expected | Measured | Method |
|---|---|---|---|
| Central wavelength | 1310 nm (nominal) | 1317.97 nm | Source certificate |
| Bandwidth (FWHM) | — | 90.29 nm | Source certificate |
| Source power | — | 10.14 mW | Source certificate |
| Axial resolution, near zero delay | 8.49 µm | 9.65 µm | Gaussian fit to unwindowed PSF, 80 A-lines, 8192-pt FFT |
| Axial resolution at 4.08 mm | — | 11.46 µm | Same (mean over 9 positions: 10.52 µm) |
| Lateral resolution | — | 11.04 µm | USAF 1951, G5E4 (45.3 lp/mm), half period |
| Nyquist axial range | — | 6.07 mm | 1024 × 5.931 µm |
| Imaging depth (−10 dB) | 3.57 mm (roll-off model) | 3.45 mm (≈ 2.6 mm in water) | Signal roll-off |
| Signal roll-off | — | −3.32 dB/mm | Linear fit, 0.08–4.08 mm |
| Roll-off model fit | — | ω = 1.81, p₁ = −0.57 dB | Hu–Pan–Rollins model, z_max = 6.07 mm |
| Sensitivity (direct) | — | 79.6 dB at 0.07 mm → 66.2 dB at 4.32 mm (−2.71 dB/mm) | Mirror + NENIR506A-C (OD 1.02, 20.4 dB round trip) |
| Sensitivity (equivalent, calibration series) | — | 81.1 dB at 0.08 mm, max 82.8 dB | Derived, not directly measured |
| Phase stability | — | 0.636 mrad | Common path, 1000 A-lines at 50 kHz |
| Displacement sensitivity | — | 66.7 pm (air), ≈ 50 pm (water) | σφ·λ₀ / (4πn) |
| Line rate | ≤ 147 kHz | 50 kHz (operating) | |

## Known limitations of the current configuration

- Noise is dominated by excess noise that depends on the sample-arm light,
  not by reference-arm shot noise; the system is not shot-noise limited.
- No enclosure or vibration isolation beyond the breadboard; alignment is
  sensitive to mechanical perturbations.
- Values do not include the extra loss of glass windows or water columns in
  the sample path.
