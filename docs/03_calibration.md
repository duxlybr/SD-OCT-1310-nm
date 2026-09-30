# 3. Calibration

Current calibration constants are in
[`../characterization/LATEST.md`](../characterization/LATEST.md) and must be
mirrored in `processing/matlab/config/`.

## 3.1 Spectral (pixel → wavelength)

The reconstruction assumes a linear wavelength axis from **1262.34 nm at
pixel 1** to **1471.08 nm at pixel 2048** (≈ 0.102 nm/pixel). The spectrum
is then resampled to a uniform wavenumber grid with spline interpolation.

After any realignment of the grating, focusing mirror or camera, this axis
must be re-verified, e.g. by comparing the detected SLD spectrum with the
certificate spectrum or with a reference source.

## 3.2 Axial (pixel → depth)

1. Place a mirror in the sample arm on a micrometer translation stage.
2. Partially close the diaphragms so the camera does not saturate (no ND
   filter).
3. Step the mirror through 9 positions (15 µm → 4015 µm, 500 µm steps) and
   acquire 80 A-lines at each.
4. Reconstruct with Hann window and 8192-point FFT; average the magnitudes.
5. Fit peak pixel vs. micrometer reading: `p = a·d + b`.
6. Axial pixel size = 1/a. Scale for other FFT lengths by 8192/N_FFT.

Depths are measured from zero delay as `z = p / a`.

## 3.3 Lateral (galvanometer voltage → distance)

1. Image a target with three marks 3 mm apart in the focal plane.
2. Acquire volumes at several nominal fields of view (3 × 3 mm to
   9 × 9 mm, 1 mm steps), each from a known drive voltage.
3. Build en face projections; detect the marks automatically (blob
   detection) and convert the pixel distance to mm with the known spacing.
4. Fit voltage vs. measured scan length with a line through the origin, per
   axis → κ_x, κ_y (V/mm).
5. Field of view for a given drive: `L = V_pp / κ`.

**Sanity check.** From component specifications (0.8 V/° driver scale,
optical angle = 2 × mechanical, f–θ lens with f = 54 mm):
κ_th = S / (2 f π/180) ≈ 0.424 V/mm. Measured factors should agree within
≈ 5 %. Never drive beyond the 14.1 mm LSM04 field (≈ ±2.9 V).
