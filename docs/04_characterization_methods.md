# 4. Characterization methods

Results of each campaign are recorded in
[`../characterization/`](../characterization/). Always state FFT length,
window, number of averaged A-lines and ND filter.

## 4.1 Axial resolution

- Use the mirror series of the axial calibration.
- Reconstruct **without** spectral window (a window broadens the PSF).
- Fit a Gaussian + offset to the linear magnitude within ±100 points of the
  peak; convert the FWHM to µm with the axial pixel size. Use the
  interpolated half-maximum crossings as a model-free check.
- Theoretical value: Δz = (2 ln2/π)·λ₀²/Δλ.
- Report the value closest to zero delay as the system resolution, and the
  FWHM vs. depth curve.

## 4.2 Lateral resolution

- Acquire a volume of a USAF 1951 target (Thorlabs R1DS1P) and build an en
  face projection by averaging over a depth interval.
- Use a small field (e.g. 2 × 2 mm, 1000 × 1000 px) to find the smallest
  resolved group/element.
- `f = 2^(G + (E−1)/6)` lp/mm; resolution = 1000 / (2f) µm (half period).

## 4.3 Sensitivity

- Mirror in the sample arm attenuated by a calibrated absorptive ND filter
  (NENIR506A-C: OD 1.02 at 1310 nm), diaphragms open.
- Acquire 80 A-lines at several depths (e.g. 18 positions, 250 µm steps).
- SNR = peak of the averaged magnitude − noise at the same depth, where the
  noise is the temporal standard deviation over the 80 A-lines within ±25
  bins, taken from acquisitions with the mirror > 200 bins away.
- Sensitivity Σ = SNR + 2 × 10·OD (double pass).

## 4.4 Roll-off and imaging depth

- Peak signal relative to the first position vs. depth.
- Report the linear slope (dB/mm) and the −10 dB crossing (imaging depth).
- Fit the Hu–Pan–Rollins spectrometer model with z_max fixed to the Nyquist
  depth:
  `R(z) = p₁ + 10·log₁₀[sinc²(ζ)·exp(−ω²ζ²/(2 ln2))]`, `ζ = (π/2)·z/z_max`.

## 4.5 Phase stability

- Common-path setup: front/back reflections of a coverslip in the sample arm,
  reference arm blocked, galvanometers held at 0 V.
- Acquire 1000 consecutive A-lines at the operating line rate.
- Extract the phase at the common-path peak, remove a linear trend,
  σφ = standard deviation.
- Displacement sensitivity: δz = σφ·λ₀ / (4πn).

## 4.6 Noise diagnostics

- Change the sample-arm power and observe the noise: if the noise follows
  the sample light, it is excess noise, not reference shot noise.
