# Campaign: 2026-09_final-alignment

- **Date(s):** September 2026 (galvanometer calibration: 2026-09-15; exact
  dates of the other series to be recorded)
- **Operator(s):** L. E. Barreto Espinosa
- **Previous campaign:** — (first recorded campaign)
- **Raw data location:** institutional storage (`.tdms`, not versioned)

## System configuration

Final alignment of the spectrometer and interferometer, used for all
measurements reported in the MSc thesis.

| Item | Setting |
|---|---|
| Line rate / integration time | 50 kHz / maximum compatible with the line rate |
| Scan lens | Thorlabs LSM04 (f = 54 mm) |
| Dispersion compensation | Optical, LSM04-matched compensator; no numerical coefficients |
| Diaphragms | Partially closed (calibration series) / fully open (direct sensitivity series) |
| ND filter | Thorlabs NENIR506A-C, nominal OD 0.6, OD 1.02 at 1310 nm (20.4 dB round trip) |
| FFT length / window / A-lines averaged | 8192 points / Hann (unwindowed for PSF width) / 80 |

## Results

### Axial calibration

Mirror on a micrometer stage, 9 positions from 15 µm to 4015 µm in 500 µm
steps, 80 A-lines each, no ND filter.

| Quantity | Value |
|---|---|
| Linear fit | p = 0.6744·d + 43.24 (p in px, d in µm) |
| Max residual | 0.72 px (≈ 1 µm) |
| Axial pixel size | 1.483 µm/px (8192-pt), 2.966 µm/px (4096-pt), 5.931 µm/native sample |
| Depth of first / last position | 78.7 µm / 4079.2 µm |

### Axial resolution

| Quantity | Value |
|---|---|
| Theoretical (λ₀ = 1317.97 nm, Δλ = 90.29 nm) | 8.49 µm |
| Measured at z = 78.7 µm (Gaussian fit) | **9.65 µm** (+14 %) |
| Measured at z = 4.08 mm | 11.46 µm |
| Mean over the 9 positions | 10.52 µm |
| Direct half-maximum crossings | 0.25–0.8 µm larger than the Gaussian fit |

### Lateral resolution

USAF 1951 target (Thorlabs R1DS1P), en face projections at 5 × 5 mm and
2 × 2 mm (1000 × 1000 px). Smallest resolved element: group 5, element 4
(45.3 lp/mm) → **11.04 µm** (half period).

### Galvanometer calibration (2026-09-15)

Three-dot target (3 mm spacing), 7 nominal fields of view from 3 × 3 mm to
9 × 9 mm.

| Axis | Measured factor | RMSE | Expected (0.8 V/°, f = 54 mm) | Deviation |
|---|---|---|---|---|
| X | **0.4053 V/mm** | 1.3 mV | 0.424 V/mm | −4.5 % |
| Y | **0.4071 V/mm** | 2.1 mV | 0.424 V/mm | −4.1 % |

Per-file factors: 0.4047–0.4078 V/mm, no trend with field of view.

### Sensitivity and roll-off

| Series | Quantity | Value |
|---|---|---|
| Direct (ND filter, diaphragms open, 18 positions, 0.07–4.32 mm) | Sensitivity | **79.6 dB** → 66.2 dB (−2.71 dB/mm) |
| Direct | Peak-signal slope | −4.48 dB/mm |
| Calibration (9 positions, derived) | Equivalent sensitivity | 81.1 dB at 0.08 mm, max 82.8 dB at 0.58 mm, 70.5 dB at 4.08 mm (−2.64 dB/mm) |
| Calibration | Signal roll-off | −3.32 dB/mm; −10 dB at **3.45 mm** |
| Calibration | Hu–Pan–Rollins fit | ω = 1.81, p₁ = −0.57 dB; −6 dB at 2.77 mm, −10 dB at 3.57 mm |
| Direct | Hu–Pan–Rollins fit | ω = 2.05 |

The equivalence transformation between series reproduced the direct
sensitivity with 0.53 dB RMSE.

### Phase stability

Common-path configuration (front/back reflections of a coverslip, peak at
≈ 200 µm), reference arm blocked, galvanometers at 0 V, 1000 A-lines at
50 kHz, linear trend removed.

| Quantity | Value |
|---|---|
| σφ | **0.636 mrad** |
| Displacement sensitivity | 66.7 pm (air), ≈ 50 pm (water) |

## Files

- `tables/`: processed characterization tables (to be added)
- `figures/`: exported figures (to be added)

## Notes

- Noise is dominated by excess noise: reducing sample-arm power by ≈ 4 dB
  lowered the noise by ≈ 3 dB, and the noise decreases with depth.
- The roll-off parameter ω differs between the two series (1.81 vs 2.05),
  which indicates that the effective roll-off depends on the illumination of
  the spectrometer, not only on its alignment.
- These values are the current reference values (see
  [`../LATEST.md`](../LATEST.md)).
