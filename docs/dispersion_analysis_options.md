# Dispersion analysis options

## Responsibility

Dispersion analysis consumes resolved directional windows and produces directional phase-speed results. The required k-f analysis has no `enabled`/passthrough contract; the complementary phase-gradient estimator has its own opt-in toggle. `RunOptions.stop_after` determines whether execution reaches this required domain.

Maintained method:

```text
windowed_fft_ridge
```

Editable contract includes:

```matlab
options.spectrum.fft.time_bin_count
options.spectrum.fft.spatial_bin_count
options.spectrum.crop.maximum_frequency_hz
options.spectrum.crop.maximum_wavenumber_per_m
options.spectrum.window.time.enabled
options.spectrum.window.time.method
options.spectrum.window.space.enabled
options.spectrum.window.space.method
options.ridge.maximum_wavenumber_jump_per_m
options.ridge.minimum_relative_magnitude
options.ridge.interpolation.method
options.ridge.interpolation.extrapolate
options.phase_speed.smoothing.method
options.phase_speed.smoothing.span_fraction
options.target_frequency.source
options.phase_gradient.enabled
```

Maintained target-frequency sources are:

```text
resolved_filter_center
not_available
```

`resolved_filter_center` preserves the quasi-harmonic behavior: `oce.config.resolveDispersionAnalysisOptions` resolves `target_frequency.requested_hz` from the already-resolved filter center. `not_available` sets `requested_hz=NaN` and is used for broadband pulse excitation, where no single physical excitation frequency exists.

The target-frequency choice affects only the selected scalar/bin provenance. The complete k-f spectrum, ridge, and phase-speed dispersion curve are still calculated when the target frequency is unavailable. The center of a manually selected pulse filter passband remains filter-design metadata and is not promoted to an excitation or target frequency.

`spectrum.window` is an explicit required part of the maintained configuration contract. Canonical defaults set both temporal and spatial tapers to `enabled=false` with method `hann_symmetric`. Missing `spectrum.window` is rejected rather than filled at runtime.

## Frozen scientific behavior

`oce.dispersion.computeDispersionSpectrum` preserves the established FFT, axes, crop, peak/ridge selection, thresholding, tie-breaking, interpolation, extrapolation, and LOWESS phase-speed smoothing arithmetic.

`maximum_wavenumber_jump_per_m` retains its established narrow role in peak selection.

After left-direction normalization, optional temporal/spatial Hann vectors are applied as separable tapers over acquired samples before configured FFT zero padding. No coherent-gain/RMS/energy correction is applied.

The taper belongs only to dispersion spectral analysis. It does not modify extracted `window_result.bmodes`, filtering, phase, borders, or reconstruction.

The 1-D temporal diagnostic uses the temporal Hann intent when enabled and never uses the spatial taper.

Wavenumber is stored in cycles/m, so phase speed remains:

```text
frequency [Hz] / wavenumber [cycles/m]
```

## Direction contract

Acquisition order remains:

```text
left_1, right_1, left_2, right_2, ...
```

Runtime k-f directions carry identity, spectrum, ridge, phase-speed curve,
target selection and mean thickness. Phase-gradient directions align with that same order.

For `target_frequency.source="not_available"`, every target-selection scalar is `NaN`; the full `phase_speed_curve` remains available.

Circular angular ordering remains downstream in `oce.dispersion.orderBidirectionalAngles`.

## Phase gradient

`phase_gradient.enabled` defaults to `false`. The second output of `resolveDispersionAnalysisOptions` carries its resolved intent into `analyzeWindows` alongside `SurfacePhase` and `PhaseTimeStartIndex`. Its physical frequency comes only from `acquisition_row.frequency_Hz` for `quasi_harmonic`, accepting canonical numeric, text and scalar-cell representations. It must equal the k-f target. Pulse cannot enable phase-gradient.

`computePhaseGradientSpeed` projects the pre-filter `phase.surface` increments at that frequency, unwraps the spatial phase and fits phase in radians against x in metres, with an intercept and a slope in rad/m. It reports `k = abs(slope)/(2*pi)` in cycles/m and `c = f0/k` in m/s. Both estimators use the same resolved window geometry, but phase-gradient keeps natural lateral order and uses the pre-FIR, pre-mean-removal, pre-median signal. That signal is not raw: motion estimation, axial aggregation and optional LOWESS have already occurred.

The result is one dominant-wavenumber estimate, not a dispersion curve. Spatial sampling must resolve phase wraps. R^2 and phase RMSE describe the spatial fit; neither establishes monomodal propagation. k-f and phase-gradient remain independent, with no averaging or automatic selection.

## Plotting

`oce.plotting.plotDispersionKfPreview` consumes existing cropped k-f magnitude, axes, ridge, and target metadata. It does not recalculate FFT/taper/ridge. When no target frequency exists, the complete k-f map and ridge remain visible while the target-specific k profile is reported as unavailable.

`oce.plotting.plotSpeedDispersionPreview` consumes existing smoothed phase-speed curves and temporal diagnostics. Its y-axis scaling is display-only. For pulse excitation the complete curves remain visible without target markers.

The phase-speed polar result is unavailable when there is no target frequency. Thickness remains independent and may still be rendered when available.

`oce.plotting.plotPhaseGradientPreview(analysis, scanAxisIndex)` renders existing runtime `diagnostic.x_axis_mm`, `unwrapped_phase_rad` and `fitted_phase_rad`, without recomputing science. One figure separates left/right panels with x in mm, phase in rad, speed, R^2, RMSE and status. Invalid directions retain their status and only display available vectors; disabled estimation creates no figure.

Set `show_phase_gradient_preview=true` in stepwise section 9, or `show_representative_phase_gradient_preview=true` in batch preparation, together with the estimator toggle. Both preview controls default to `false`. Batch previews apply only to representative-window review, not each automatic acquisition. There is no automatic image saver, persisted diagnostic vector, or phase-gradient summary-plot family.

## Persistence boundary

`buildScientificResult` compacts both estimators into the
[scientific result](scientific_result_schema.md). Curves and target selection remain
k-f-specific; phase-gradient stores scalar estimates/provenance and excludes its
runtime diagnostic vectors. Pulse uses the same persisted contract with no target speed.
