# Summary statistics

## Assembly and ordering

`oce.results.buildSubexperimentResultSet` loads each persisted
[scientific result](scientific_result_schema.md) once into `experiment.data`.
`buildExperimentResultSet` uses that assembly boundary across subexperiments.
Downstream reductions never reopen `source_result_file`; it is provenance only.
Operational scripts, selection and output controls belong to the
[workflow guide](processing_workflow.md#summaries).

The last dimension of `experiment.data(d1,...,dn,repetition)` represents repeated
acquisitions of one experimental condition. Run identity, filename and source file
remain associated with each cell. Design dimensions are independent of scan-axis identity.

The common `angular.source_direction_indices` permutation applies to angles,
scan-axis indices, direction names, k-f curves/diagnostics/target speeds and
phase-gradient scalar speeds. It prevents pairing values with the wrong direction.

| Assembled quantity | Field |
| --- | --- |
| Full-circle angles | `full_circle_angles_deg` |
| k-f target speed | `angular_phase_speed_m_per_s`, `direction_target_phase_speed_m_per_s` |
| Phase-gradient speed | `angular_phase_gradient_speed_m_per_s`, `direction_phase_gradient_speed_m_per_s` |
| Thickness | `angular_mean_thickness_mm` |
| Direction identity | `direction_scan_axis_indices`, `direction_names` |
| k-f curves/diagnostics | `direction_frequency_axes_hz`, `direction_smoothed_phase_speed_m_per_s`, `direction_temporal_diagnostic_magnitude` |
| Filter provenance | `filter_effective_passband_hz` |

Disabled or invalid phase-gradient directions become NaN. Both estimators are
summarized independently: no estimator average, difference, agreement score or
preferred-estimator selection is calculated.

## Statistical convention

Reductions retain mean, sample SD, SEM, CI95 and valid count `n` for each quantity.
Missing values do not count as valid observations. The uncertainty convention is:

```text
SEM = SD / sqrt(nValid)
CI95 = t(0.975, nValid - 1) * SEM
```

CI95 is the **half-width** of the Student-t interval around the mean.
SEM and CI95 are NaN for fewer than two valid repetitions. For technical repetitions,
these fields describe repeatability, not biological-population uncertainty.
Angular SD is descriptive directional variability and must not be presented as CI95.

## Repetition and angle reductions

Subexperiment summary order is:

```text
assemble -> alignDispersionFrequencies -> summarizeRepetitions
         -> optional summarizeDispersionSamples -> summarizeAngles
```

`summarizeRepetitions` operates across repetitions at each angle/frequency or
scalar position. It writes `experiment.summary.repetition_mean_data`,
`repetition_std_data`, `repetition_sem_data`, `repetition_ci95_data` and
`repetition_n_data`.

`summarizeAngles` requires that repetition summary. Its outputs have distinct meanings:

| Output under `experiment.summary` | Interpretation |
| --- | --- |
| `angle_mean_data` | Mean across angles of the repetition-averaged values |
| `angle_std_data` | SD across those angles: descriptive angular variability |
| `angle_sem_data` | SEM across repetitions after averaging angles within each repetition |
| `angle_ci95_data` | Corresponding CI95 half-width across repetitions |
| `angle_n_data` | Valid repetition count for that uncertainty calculation |

Angles are not substituted for independent repetitions in uncertainty estimates.
The same infrastructure handles k-f and phase-gradient without a second statistics system.

## Scan-axis reductions

`summarizeScanAxes` uses assembled direction identity. Each scan axis must contain
exactly one left and one right direction in a repetition. For scalar target speeds it
calculates independently for each estimator:

```text
c_axis,r = (c_left,r + c_right,r) / 2
```

When dispersion frequencies have already been aligned, the same operation is
performed independently at every aligned frequency bin:

```text
c_axis,r(f) = (c_left,r(f) + c_right,r(f)) / 2
```

The left/right pair is formed **within each repetition before** mean, SD, SEM, CI95
and valid count are calculated across repetitions. A missing side makes that paired
value NaN; a lone direction is not substituted. The existing k-f diagnostic
`Delta c_r = c_left,r - c_right,r` remains a scalar target diagnostic.

`experiment.summary.scan_axis` retains paired repetition values, statistics,
identity and pairing provenance. For aligned dispersion it additionally retains
`dispersion_frequency_axis_hz` and `dispersion_phase_speed_m_per_s` in the scan-axis
repetition/statistical structs. Human scan-axis tables continue to use the scalar
target fields and are not expanded with broadband curves.

## Frequency alignment

`alignDispersionFrequencies` forms a global axis from bins in assembled k-f results.
Bins match by exact numeric Hz value; there is no rounding, interpolation or
tolerance-merging. Missing bins become NaN. True resampling needs a separately
validated policy. Phase-gradient is a scalar at the physical excitation frequency,
not another dispersion curve to interpolate onto this axis.

## Pulse dispersion sampling

`oce.results.summarizeDispersionSamples` is an optional pulse-summary operation.
Requested frequencies are explicit summary configuration and are mapped to the
nearest bins of the already aligned k-f frequency axis. It performs no interpolation
and does not recompute repetition statistics. Instead it samples the existing
repetition mean, SD, SEM, CI95 and valid-count arrays at the same selected bins.

The derived product is stored under `experiment.summary.dispersion_sampling` with
requested frequency, selected frequency, frequency error and selected-bin provenance.
It is summary-only: it does not alter `oce_phase_speed_result`, `PhaseSpeed.mat`,
experimental design dimensions or human summary tables. Phase-gradient is not
sampled for pulse excitation.

## Human tables

`buildConditionSummaryTable` and `buildScanAxisSummaryTable` own table construction;
`oce.io.exportConditionSummaryTable` and `exportScanAxisSummaryTable` own CSV/XLSX output.
Historical `phase_speed_*` columns continue to mean k-f.

Phase-gradient columns are:

| Column | Meaning |
| --- | --- |
| `phase_gradient_speed_mean_mps` | Mean speed |
| `phase_gradient_speed_angular_std_mps` | Angular SD in condition summaries |
| `phase_gradient_speed_repetition_std_mps` | Repetition SD in scan-axis summaries |
| `phase_gradient_speed_sem_mps` | Repetition-based SEM |
| `phase_gradient_speed_ci95_mps` | CI95 half-width |
| `phase_gradient_speed_n` | Valid repetition count |

Estimator columns remain separate. Unavailable phase-gradient results propagate
naturally as NaN; they are not zero-filled or replaced by k-f.

## Plotting interpretation

Subexperiment plots own detailed diagnostics. `RepetitionDispersion` shows the full
repetition-averaged `c(f)` and temporal FFT for each direction/condition, while
`AngleDispersion` shows the corresponding angle-reduced curves. For pulse excitation,
these products replace separate by-angle and angle-averaged phase-speed-versus-frequency
views because those would repeat the same `c(f)` data without the FFT diagnostic.
Thickness and angular phase-speed polars also remain subexperiment products.

Experiment plots are intentionally comparative. Phase-speed-versus-frequency uses
scan-axis geometry for both quasi-harmonic targets and pulse broadband dispersion,
pairing opposite propagation directions while preserving differences between physical
scan axes. The polar remains the angular comparison across experimental conditions.
Detailed dispersion and thickness figures are not regenerated at experiment level.

The quasi-harmonic polar renders k-f and phase-gradient in parallel panels; sampled
pulse polars use k-f only. The optional quasi-harmonic angle-averaged
phase-speed-versus-frequency view remains off by default because angular averaging may
obscure directional differences in anisotropic designs.

Polar phase/thickness, repetition- and angle-averaged dispersion, and
speed-versus-frequency views live under `oce.plotting.summary`; each `save*` reuses
its corresponding `plot*`. The phase-gradient spatial-fit preview consumes runtime
diagnostics and is described in [analysis](dispersion_analysis_options.md#plotting).

Phase-speed summary plots use zero-based robust display scales. The upper envelope
uses `speed + CI95` when CI95 exists. A median absolute deviation (MAD) modified-Z
criterion excludes isolated highs from scale estimation, followed by a margin and
upward rounding. By-angle, angle-averaged and scan-axis scale populations are separate.
For dispersion plots, only the persisted effective filter passband contributes to
speed-axis scale estimation; full validated curves remain plotted.

This is display scaling only: it neither removes scientific values nor changes
uncertainty, persisted results or the statistics described above.
