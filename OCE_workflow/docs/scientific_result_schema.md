# Scientific result schema

`PhaseSpeed.mat` contains exactly one top-level scalar struct, `oce_result`.
The maintained loader accepts only `schema.name="oce_phase_speed_result"`,
`schema.version=3`. Historical flat files and v1/v2 results are rejected, not migrated.

## Root and provenance

| Field | Meaning |
| --- | --- |
| `schema` | Contract identity and version |
| `acquisition` | Experiment, subexperiment, run, sample type, protocol and source row |
| `processing.config` | Compact resolved scientific configuration |
| `borders` | Directional mean physical thickness |
| `windows` | Shared compact window geometry/provenance |
| `dispersion` | Shared identity/target and separate estimators |
| `angular` | Full-circle permutation and existing k-f/thickness values |
| `statistics` | Existing k-f speed and thickness descriptive statistics |

`acquisition.protocol` is `angular_bmodes`; a stored `source_row.scan_geometry`
must agree. Temporal acquisition mode remains separate in processing configuration.
See [metadata](experimental_metadata.md) for input semantics.

`processing.config` preserves reproducibility without volatile runtime state.
Sample optics remain explicit in `SampleOpticalOptions.refractive_index`.
Resolved k-f options live once in `DispersionAnalysisOptions`; their target is
`dispersion.target_frequency`, not a duplicated configuration block.

## Borders

`borders.directional_mean_thickness_mm` records one mean physical thickness per
directional dispersion window. Its contract is:

```text
quantity = mean_physical_thickness_per_directional_dispersion_window
units = mm; layout = direction; ordering = acquisition_direction_order
```

Unavailable thickness remains NaN independently of the phase-speed estimates.

## Windows

`windows.bmodes` has one entry per independent B-mode. Each retains center and
left/right window metadata, local physical x axes, time axes, indices, sample/interval
counts, boundary adjustments and filter provenance. Directional signal `values`
are excluded. Local `x_axis_mm` never implies continuity across storage seams.
The [window contract](dispersion_window_options.md) owns geometry and alignment semantics.

## Shared dispersion identity

`dispersion.scan_axis_count`, `scan_axis_angles_deg` and `directions` are common
to both estimators. Each identity contains only `scan_axis_index` and
`direction="left"|"right"`; arrays use acquisition order:

```text
left_1, right_1, left_2, right_2, ...
```

`dispersion.target_frequency` has `source` and `requested_hz`:

- `resolved_filter_center`: finite positive k-f target; enabling phase-gradient
  additionally requires equality with the physical acquisition frequency.
- `not_available`: NaN target for broadband pulse. Every k-f target-selection
  scalar is NaN, while the complete frequency axis, ridge and curve remain available.
  A manual pulse filter center is never promoted to an excitation frequency.

Identity, angles, thickness, window geometry and target are not copied into each estimator.

## k-f estimator

`dispersion.estimators.kf_ridge` contains `method="windowed_fft_ridge"`, the shared
increasing `frequency_axis_hz` (`temporal_frequency`, `Hz`, `frequency` layout),
and aligned `directions`. Each k-f direction retains:

| Field | Persisted meaning |
| --- | --- |
| `spectrum` | Reduced temporal FFT diagnostic, wavenumber axis and input/window metadata |
| `ridge` | Selected wavenumbers, magnitudes, validity/interpolation/extrapolation masks and parameters |
| `phase_speed_curve` | Raw and smoothed speeds in m/s, frequency layout, smoothing metadata |
| `target_selection` | Selected bin, frequency, frequency error, wavenumber and phase speed |

The common target supplies `requested_frequency_hz`; it is not repeated per selection.
The reduced spectrum input also omits repeated direction identity. Frequency axes
are shared rather than copied into each curve. Full k-f magnitude maps, FFT/crop
working arrays, tapers and signal windows are not persisted.

## Phase-gradient estimator

`dispersion.estimators.phase_gradient` contains:

```text
enabled
frequency_source = "acquisition_row.frequency_Hz"
target_frequency_reference = "dispersion.target_frequency.requested_hz"
input
directions
```

Enabled estimation requires a positive physical frequency from a quasi-harmonic
acquisition, equal to the common k-f target. Numeric, convertible text and canonical
scalar-cell representations are accepted; pulse cannot enable this estimator.

`input` records `source="phase.surface"`, `quantity="phase_increment"`, `units="rad"`,
`layout="lateral_time"`, `estimator` and `difference_axis="time"`. This is the pre-filter
scientific phase product, not raw acquisition. Loupas/unwrap-difference, axial
sampling/aggregation and smoothing remain in `processing.config.MotionOptions`;
the builder checks agreement before compacting metadata.

Each direction contains only `status`, `phase_slope_rad_per_m`,
`wavenumber_cycles_per_m`, `phase_speed_m_per_s`, `r_squared`, `phase_rmse_rad`,
`spatial_sample_count`, and `spatial_span_mm`. The [analysis contract](dispersion_analysis_options.md)
defines their physical interpretation and limitations.

- **Disabled:** `enabled=false`, empty scalar `input` struct, empty `directions`.
- **Enabled/valid:** one scalar estimate per common direction slot.
- **Enabled/invalid:** status `nonfinite_signal`, `undefined_projection` or
  `degenerate_slope`, with NaN estimates and retained spatial count/span.

All states use v3. `diagnostic` is runtime-only: no complex projection, unwrapped
phase, fitted phase, residual vector, duplicate x vector or signal array is saved.
Consequently the spatial-fit preview cannot be reconstructed from this MAT alone.

## Angular values and statistics

`angular.source_direction_indices` permutes acquisition-direction order into
`counterclockwise_full_circle` order. `full_circle_angles_deg` uses degrees;
`phase_speed_m_per_s` retains k-f target speed and `mean_thickness_mm` retains
thickness. Without a target, angular phase speed is NaN; thickness is independent.

`statistics.phase_speed` stores mean, sample SD and range in m/s from these angular
k-f speeds. `statistics.thickness` stores the corresponding values in um, with
source units mm and conversion factor `1e3`. Validation recomputes both.
These per-acquisition descriptive values are distinct from repetition uncertainty.
The [summary layer](results_summary_statistics.md) projects phase-gradient scalars
separately, using the same permutation; the persisted angular block is not duplicated.

## Creation and I/O boundary

`oce.results.buildScientificResult` assembles completed pipeline products;
`validateScientificResult` owns validation. `oce.io.saveScientificResult` saves a
same-directory temporary file, reloads/validates, then replaces the target and
verifies the result. `loadScientificResult` accepts only the strict current contract,
without aliasing, default insertion, recalibration or historical conversion.
