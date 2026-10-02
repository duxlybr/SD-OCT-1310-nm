# Processing workflow

## Choose an entrypoint

Start MATLAB in the repository root and run `startup`. Keep experimental data,
parameter files and generated results outside the repository.

| Need | Human entrypoint | Programmatic owner |
| --- | --- | --- |
| Inspect one acquisition by stages | `workflows/run_acquisition_stepwise.m` | Explicit domain calls |
| Process one raster acquisition to an en-face video | `workflows/run_raster_enface_stepwise.m` | Explicit domain calls |
| Prepare interactively, then process a batch | `workflows/run_experiment_batch.m` | Preparation and batch owners |
| Process one prepared acquisition | `workflows/process_single_acquisition.m` | `oce.pipeline.runSingleAcquisition` |
| Process a prepared batch | `workflows/process_acquisition_batch.m` | `oce.pipeline.runBatchProcessing` |
| Summarize a subexperiment | `workflows/summarize_subexperiment_results.m` | `oce.pipeline.runSubexperimentSummary` |
| Summarize an experiment | `workflows/summarize_experiment_results.m` | `oce.pipeline.runExperimentSummary` |

Edit the user-configuration section of the selected script. Stepwise sections
preserve explicit scientific products for inspection; batch execution applies the
same maintained owners to each acquisition. There is no alternate pulse pipeline.

## Prepare metadata and configuration

1. Set the experiment root and select a subexperiment/acquisition from its
   `experimental_log.xlsx`. Follow the [metadata contract](experimental_metadata.md).
2. Use the interactive preparation workflow to inspect a representative acquisition,
   select depth/time crops, and validate the intended acquisition organization.
3. Build/edit `processing_config` through the owning configuration domains, including
   OCT system, sample optics, borders, motion, filtering, windows and analysis.
4. Save the accepted configuration, then process the selected acquisitions.

`oce.pipeline.prepareAcquisitionRun` returns `processing_inputs` and `config_for_run`.
`oce.config.buildProcessingConfigForAcquisition` resolves the editable configuration
and canonical acquisition row; downstream stages consume this effective configuration.

The per-subexperiment parameter artifacts live under `Params/<subExperiment>/`:

| File | Responsibility |
| --- | --- |
| `AcquisitionParams_<subExperiment>.mat` | Canonical acquisition table from the Experimental Log |
| `Params_<subExperiment>.mat` | Representative acquisition parameters, crop and preview intent |
| `ProcessingConfig_<subExperiment>.mat` | Editable scientific processing configuration |

These files have separate owners; a header snapshot does not replace experimental
metadata or OCT/sample configuration. See [reconstruction](reconstruction_result_contract.md)
for optical and calibration ownership.

The manual preparation stage reads raw data once; its `measurement` is reused by
reconstruction. Crop-selection preview FFTs remain separate from scientific reconstruction.

For quasi-harmonic acquisitions, the filter policy uses physical `frequency_Hz`.
For pulse acquisitions, select the useful passband on the representative spectrum;
that manual passband is processing intent, not a new physical excitation frequency.

Batch preparation may seed the next compatible subexperiment with accepted window
intent. Automatic centers are still resolved per acquisition. Quasi-harmonic and
pulse temporal policies are not inherited across excitation families.

## Calculation and stopping

`oce.pipeline.processPreparedAcquisition` calculates the fixed prefix ending at
`RunOptions.stop_after`. Product ownership is mapped in
[architecture](repository/final_architecture.md).

| `stop_after` | Product boundary |
| --- | --- |
| `reconstruction` | Raw acquisition, geometry, calibrated/cropped reconstruction |
| `borders` | Anterior/posterior surface information and thickness |
| `phase_estimation` | Depth-resolved and surface phase products |
| `filtering` | Filtered phase and surface postprocessing |
| `dispersion_windows` | One resolved left/right window geometry per B-mode |
| `dispersion_analysis` | k-f results and optional phase-gradient estimates |
| `scientific_result` | Validated compact result ready for persistence |

For example:

```matlab
RunOptions.stop_after = "scientific_result";
RunOptions.return_intermediate_products = "required";
RunOptions.parallel.enabled = true;
RunOptions.parallel.worker_count = 4;
```

Intermediate-product return modes are `none`, `required` and `all`. Optional
outputs operate on these calculated products; they are not additional scientific stages.

Borders remain isolated per B-mode. The phantom `surface_mode` can be
`anterior_posterior` (default) or `anterior_only`; the latter deliberately returns
NaN posterior geometry/thickness while surface phase and dispersion continue.

Phase products have explicit quantities, units and layouts. Filtering/postprocessing
remain scientific transforms. [Window options](dispersion_window_options.md) define
alignment and clipping; [analysis options](dispersion_analysis_options.md) define
k-f and phase-gradient inputs, physical target constraints and method limitations.

Parallelism is runtime state, not ProcessingConfig. `runSingleAcquisition` owns
process-pool setup/reuse through `prepareParallelExecution`. Domain execution receives
resolved state and does not discover pools. Serial and parallel branches preserve
the same independent scientific calculations and geometry.

## Outputs and persistence

`OutputOptions` controls side effects, independently from the calculation boundary.
Requesting an output whose product is unavailable fails before processing.

| Output option | Required product |
| --- | --- |
| `save_reconstruction_preview` | reconstruction |
| `save_border_preview` | borders |
| `save_filter_preview`, `save_filtered_motion_video` | filtering |
| `save_dispersion_window_context` | dispersion_windows |
| `save_kf_plots`, `save_dispersion_plots` | dispersion_analysis |
| `save_polar_plots`, `save_scientific_result` | scientific_result |

The result directory is created only when an output is requested. `close_figures`
controls cleanup of generated figures. Renderers consume existing products;
savers reuse renderers. Video/plot generation never writes display processing
back into scientific arrays.

A completed scientific run can save:

```text
Results/<subExperiment>/<filename-without-.bin>/PhaseSpeed.mat
```

Every output of one acquisition goes to a folder named after the processed file,
resolved by `oce.pipeline.resolveOutputDirectory`. The standalone stepwise
workflows (`run_acquisition_stepwise.m`, `run_raster_enface_stepwise.m`) use the
same owner, writing to `<.bin folder>/Results/<filename-without-.bin>/`.

`oce.io.saveScientificResult` writes the validated `oce_result` through a temporary
file and verifies its round-trip. `loadScientificResult` is the strict read boundary;
see the [scientific schema](scientific_result_schema.md) for supported data and provenance.

The returned pipeline result distinguishes completion, available products,
scientific-result availability, persistence and generated artifacts. Batch execution
calls the same single-run contract for each acquisition.

## Runtime inspection

Preview controls affect display, not the saved scientific configuration.
B-mode mosaics retain independent panels and local axes. Representative previews
may select scan axes nearest 0 and 90 degrees without reducing scientific processing.

Phase/space-time/window-context renderers share `phase_clim_mode` and `phase_clim`;
motion/video use `video_clim_mode` and `video_clim`. Modes are `auto`, `robust`, or
`manual`. Manual limits accept a positive scalar (symmetric limits) or an increasing pair.
The automatic runner exposes these presentation values through OutputOptions.

- **Phase:** optional depth-motion animation uses the calculated phase product,
  is disabled by default, and writes no file.
- **Filter:** `FilterOptions.diagnostic.line_index=[]` selects the center lateral
  pixel of the first B-mode; an explicit positive index overrides it. Time-profile
  plots compensate FIR delay visually, without shifting stored arrays.
  `FilteredSpaceTime` uses representative B-modes; `CompleteSpaceTime` shows all.
- **Windows:** the tuner edits configuration methods/values; ROI graphics are
  display-only. `plotDispersionWindowContext` overlays already resolved geometry.
- **Analysis:** k-f and speed previews reuse spectrum/ridge/curve outputs.
  Phase-gradient's spatial-fit preview is opt-in and runtime-only; see its
  [controls and interpretation](dispersion_analysis_options.md#plotting).
  Batch preview controls act during representative review, not every automatic run.
- **Polar:** rendering follows scientific-result construction and uses its existing
  angular values. It does not recalculate dispersion or thickness.

## Raster en-face motion

`run_raster_enface_stepwise.m` processes a `raster` acquisition through
reconstruction, per-B-scan borders, anterior-surface phase and
`oce.filtering.filterSurfacePhase`. Depth-resolved phase is not needed for the
en-face product and is skipped. Every raster position has its own excitation
trigger, so one time sample across positions forms one XY frame.
`oce.plotting.prepareEnfaceMotionVisualization` arranges the filtered surface
phase as `y_x_time` frames with FIR delay compensated visually, each position's
temporal mean removed and an optional display-only spatial median.
`plotEnfaceMotionSnapshots` previews selected frames and
`oce.video.createEnfaceMotionVideo` writes the MP4. The automatic pipeline accepts
raster up to `stop_after="filtering"`; dispersion windows reject raster geometry.

The optional structural en-face (section 4A) uses
`oce.acquisition.computeStructuralEnface`: each position averages the OCT
amplitude `|A|` of `N` M-repetitions starting at `FirstMRepetition` (incoherent
A-scan averaging, insensitive to motion-induced phase), then takes the linear mean
over `DepthRangeIndices` of the reconstructed depth crop. The map keeps linear
amplitude and its `20*log10` value with the averaging provenance.
`oce.plotting.saveStructuralEnface` writes `StructuralEnface.fig/.png`.
For a static sample, repeated A-scans share the same speckle, so A-scan averaging
reduces detector noise rather than speckle.

Raw acquisitions are held as `uint16` digitizer counts and converted to double
during spectral preparation. The complex reconstruction still stores
lateral x depth x time complex doubles, so large rasters need a tight depth crop.

Filtered-motion video subtracts the temporal mean per spatial pixel and applies
`medfilt2(frame,[5 3],'Symmetric')` only to temporary display frames. This does not
change the separate scientific surface postprocessing or its dispersion inputs.

## Summaries

The two summary scripts expose experiment/subexperiment selection, group keys,
repetition key and output controls. Selection may be `all`, one subexperiment or
an explicit list. Automatic processing is not rerun during summary work.

`run_plots` is the master summary-plot switch. Subexperiment summaries expose the
full diagnostic plot set:

```matlab
plot_options = struct( ...
    'phase_speed_vs_frequency', true, ...
    'phase_speed_polar', true, ...
    'thickness_polar', true, ...
    'repetition_averaged_dispersion', true, ...
    'angle_averaged_dispersion', true, ...
    'angle_averaged_phase_speed_vs_frequency', false);
```

The two phase-speed-versus-frequency controls above are quasi-harmonic products.
For pulse subexperiments, `RepetitionDispersion` already provides the full directional
`c(f)` curves and FFT diagnostics, while `AngleDispersion` provides the corresponding
angle-averaged dispersion. Separate pulse by-angle/angle-averaged frequency views are
therefore not generated.

Experiment summaries are intentionally comparative and expose only:

```matlab
plot_options = struct( ...
    'phase_speed_vs_frequency', true, ...
    'phase_speed_polar', true);
```

Plot controls affect only saved summary figures; summary calculations and persisted
summary data remain available.

Assembly loads each scientific result once into `experiment.data`. Subexperiment
summaries reduce repetitions then angles; experiment scan-axis summaries pair
left/right within each repetition before reducing repetitions. Both estimators
remain separate. [Summary statistics](results_summary_statistics.md) defines valid
counts, uncertainty, ordering and the human table columns.

For quasi-harmonic uniaxial-prestrain experiments, a common design is
`strain_percent x frequency_Hz x rep_id`. For pulse experiments with unavailable
frequency, group by the actual experimental conditions rather than frequency.
At experiment level, both excitation families use one phase-speed-versus-frequency
figure per physical scan axis. Quasi-harmonic curves use discrete target frequencies;
pulse curves use the complete aligned k-f dispersion after left/right pairing within
each repetition. The experimental angular comparison is represented by the polar.
Thickness and detailed dispersion diagnostics remain subexperiment products instead
of being regenerated at experiment level.

`pulse_sample_frequencies_hz` is an optional pulse-only summary control. An explicit
vector maps each requested frequency to the nearest bin of the aligned dispersion
axis and enables sampled k-f polar summaries. Leaving it empty disables only the
sampled polar; it does not disable the full pulse phase-speed-versus-frequency plot.
The sample frequencies remain summary intent and are never promoted to physical
`frequency_Hz` acquisition metadata.

Tables use existing CSV/XLSX exporters. Experiment scan-axis summary persistence
defaults to `Results/ExperimentSummary/experiment_scan_axis_summary.mat`.
See [validation](repository/validation_status.md) before delivering workflow changes.
