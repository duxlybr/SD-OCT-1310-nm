# 5. Operation and acquisition

## Timing model

The fast-axis galvanometer follows a **bidirectional triangular waveform**:
one B-scan is formed on every linear ramp (up and down). Each B-scan has
N_A useful A-lines followed by N_w = 15 samples discarded at the
turnaround.

```
T_B = (N_A + N_w) · T_A        f_B = 1 / T_B
```

Reverse-ramp B-scans must be flipped along the fast axis before assembling
volumes.

## Standard settings

| N_A | T_B (ms) | f_B (Hz) | Duty cycle | Δx at 6 mm field | Raw data per 5000 B-scans |
|---|---|---|---|---|---|
| 250 | 5.30 | 188.7 | 94.3 % | 24 µm | 5.1 GB (26.5 s) |
| 500 (nominal) | 10.30 | 97.1 | 97.1 % | 12 µm | 10.2 GB (51.5 s) |
| 1000 | 20.30 | 49.3 | 98.5 % | 6 µm | 20.5 GB (101.5 s) |

Line rate 50 kHz (T_A = 20 µs), integration time as long as the line rate
allows. The camera supports up to 147 kHz, but the lower rate favors signal.
Sustained data rate ≈ 205 MB/s (2048 px × 16 bit × 50 kHz).

## Field of view

`V_pp = κ · L`, with κ_x = 0.4053 V/mm and κ_y = 0.4071 V/mm. The full LSM04
field (14.1 mm) needs only ≈ 5.7 V peak to peak; do not exceed it. The spot
size is ≈ 31 µm (center) to ≈ 35 µm (corners) per the manufacturer at
1315 nm.

## Typical session

1. Power the SLD, camera, and galvanometer drivers; let the source stabilize.
2. Check the spectrum and fringes; set the reference arm so the sample lies
   in the first ≈ 3.45 mm (sensitivity drops ≈ 2.6–2.7 dB/mm).
3. Set line rate, N_A, field of view and number of B-scans in LabVIEW.
4. Acquire to TDMS; verify there are no dropped frames.
5. Reconstruct in MATLAB using the current calibration constants.

## Imaging through windows and water

- Tilt glass windows ≈ 10° to push the specular reflection out of the
  detection path.
- Keep the water column short (strong absorption at 1310 nm, double pass).
- Physical depth in water ≈ optical depth / 1.33.
- Optical dispersion compensation is matched to the lens, not to the window;
  add numerical compensation if the axial PSF degrades.
