# Dispersion-window contract

`oce.dispersion.buildWindows` receives the postprocessed surface phase-increment signal and produces one resolved `window_result`. Both estimators reuse this resolved geometry; no second window geometry is resolved for phase-gradient.

## Editable options

```matlab
DispersionWindowOptions.center.method
DispersionWindowOptions.center.manual_local_index
DispersionWindowOptions.center.search_range_fraction
DispersionWindowOptions.center.max_rms_phase_increment
DispersionWindowOptions.center.max_mirrored_correlation

DispersionWindowOptions.spatial.method
DispersionWindowOptions.spatial.interval_fraction
DispersionWindowOptions.spatial.manual_interval_count

DispersionWindowOptions.directional_offsets.left_samples
DispersionWindowOptions.directional_offsets.right_samples

DispersionWindowOptions.temporal.start_index_inclusive
DispersionWindowOptions.temporal.method
DispersionWindowOptions.temporal.manual_interval_count
DispersionWindowOptions.temporal.cycle_count

DispersionWindowOptions.boundary_policy
DispersionWindowOptions.show_progress
```

`oce.config.resolveDispersionWindowOptions` validates the editable schema after per-acquisition overrides. Derived geometry, centers, ranges, axes, and signal sizes do not belong to editable configuration.

## Maintained methods

| Domain | Identifier | Implementation |
| --- | --- | --- |
| center | `middle` | `oce.dispersion.centers.middle` |
| center | `manual_local_index` | `oce.dispersion.centers.manualLocalIndex` |
| center | `max_rms_phase_increment` | `oce.dispersion.centers.maxRmsPhaseIncrement` |
| center | `max_mirrored_correlation` | `oce.dispersion.centers.maxMirroredCorrelation` |
| spatial | `fraction_of_bmode` | `oce.dispersion.spatialextents.fractionOfBmode` |
| spatial | `manual_interval_count` | `oce.dispersion.spatialextents.manualIntervalCount` |
| temporal | `cycle_count` | `oce.dispersion.windowdurations.cycleCount` |
| temporal | `manual_interval_count` | `oce.dispersion.windowdurations.manualIntervalCount` |
| temporal | `to_end` | `oce.dispersion.windowdurations.toEnd` |

`max_mirrored_correlation` is the canonical automatic center default. The center method remains explicitly editable and all maintained strategies continue to resolve through the same window contract.

`cycle_count` is the default automatic temporal-duration method for quasi-harmonic excitation. It requests a duration of `cycle_count / frequency_hz`, then rounds that duration to a temporal interval count. If fewer FIR-aligned intervals remain from the configured start, the effective count is clipped to the available duration with a warning; requested and effective duration/cycle provenance remain distinct.

Broadband pulse excitation defaults to `to_end` because there is no single physical excitation period. The requested temporal range starts at `start_index_inclusive` and ends at `resolved_crop.time.end_index_inclusive`. If FIR alignment leaves fewer valid samples, the effective scientific window ends at the last aligned sample while the requested crop end remains recorded in boundary provenance. `manual_interval_count` remains available when a shorter explicit packet window is preferred.

## Interactive tuning

`oce.interaction.tuneDispersionWindows` is the maintained desktop tuner for reproducible window intent. Method selectors and numeric controls are authoritative; ROI graphics are display-only.

Every candidate is resolved through `oce.dispersion.buildWindows` and rendered by `oce.plotting.plotDispersionWindowContext`.

Automatic center methods are resolved separately for each acquisition from that acquisition's signal. `manual_local_index` is the only center strategy that stores fixed local B-mode center indices.

The experiment-level workflow may copy an accepted complete window policy as an initial guess for the next compatible subexperiment. Quasi-harmonic and pulse temporal policies are not inherited across excitation families. Each persisted `ProcessingConfig` remains self-contained.

## Indices, intervals, and samples

All effective ranges are inclusive. Temporal start indices use absolute
acquisition samples; the retained crop defines the valid temporal domain.
FIR group delay is converted internally to the corresponding filtered-array
indices and does not change the configured physical start sample.

```text
sample_count = numel(indices)
interval_count = sample_count - 1
```

Fixed-length windows use the maintained `shift_to_fit` boundary policy when the requested interval count fits the available domain. `cycle_count` first clips an overlong duration to the FIR-aligned intervals available from its configured start; it does not pad or extrapolate. For `to_end`, the start sample is preserved, the requested end is the temporal crop end, and the effective end is clipped only when the aligned filtered signal ends earlier.

## Resolved result

`window_result` records:

```text
source quantity / units / layout / signal size
filter provenance
center frequency and sample interval
resolved center/spatial/temporal/offset/boundary options
window_result.bmodes
```

For pulse excitation, `window_result.frequency.center_hz` remains the center of the manually selected filter passband for provenance. It is not an excitation or target frequency.

Each `window_result.bmodes(i)` contains:

```text
center
left
right
```

Left/right windows retain natural lateral order, local/global indices, physical x/time axes, interval/sample counts, direction, reversal requirement, and boundary-adjustment metadata.

Left values remain in natural lateral order. The k-f solver performs the required spatial reversal exactly once for the left direction. Phase-gradient keeps natural lateral order and samples pre-filter `phase.surface` using these same spatial indices and absolute increment midpoint times.

`oce.dispersion.analyzeWindows(window_result, thickness, DispersionAnalysisOptions)` consumes the extracted values/axes directly.

## Persistence and previews

The pipeline exposes this product as `products.windows`. The scientific result
retains window geometry/provenance without directional signal `values`; see the
[scientific schema](scientific_result_schema.md#windows).

`plotDispersionWindowContext` renders an already resolved B-mode; it performs no
window detection. Its `saveDispersionWindowContext` partner persists the same view.
Operational preview controls belong to the [workflow guide](processing_workflow.md#runtime-inspection).
