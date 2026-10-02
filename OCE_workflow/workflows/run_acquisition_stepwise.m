%#ok<*UNRCH>
% Intentional: editable false-by-default section toggles appear unreachable to Code Analyzer.
%% 0. INITIALIZATION
% Run sections in order. After changing an upstream setting, rerun that
% section and every downstream section whose result you still need.
%
% --- USER OPTIONS ---
manual_show_progress = true;       % true | false
manual_parallel_enabled = true;    % true | false
manual_parallel_worker_count = 4;  % positive integer

% --- EXECUTION ---
% Resolve this script from the active MATLAB Editor file so Run Section works
% regardless of the current MATLAB folder.
workflow_file = matlab.desktop.editor.getActiveFilename;
if isempty(workflow_file)
    error('OCE:Workflow:CannotLocateDriver', ...
        ['Could not determine the active workflow file. Open ' ...
         'run_acquisition_stepwise.m in the MATLAB Editor.']);
end
repository_root = fileparts(fileparts(workflow_file));
startup_file = fullfile(repository_root, 'startup.m');
assert(isfile(startup_file), ...
    'Could not locate repository startup.m: %s', startup_file);
run(startup_file);

% Maintained owners control calculation/output progress. Parallel execution
% uses the same maintained hotspots as the automatic single-acquisition path.
parallel_options = oce.config.resolveRunOptions(struct( ...
    'parallel', struct( ...
        'enabled', manual_parallel_enabled, ...
        'worker_count', manual_parallel_worker_count))).parallel;
parallel_state = oce.pipeline.prepareParallelExecution(parallel_options);
manual_use_parallel = parallel_state.active;

%% 1. ACQUISITION SELECTION
% Select one standalone .bin acquisition. It may live outside the batch
% experiment/subexperiment hierarchy.
%
% --- EXECUTION ---
[selected_file, selected_path] = uigetfile( ...
    {'*.bin', 'OCE binary acquisitions (*.bin)'}, ...
    'Select OCE acquisition');
if isequal(selected_file, 0)
    error('OCE:Workflow:AcquisitionSelectionCancelled', ...
        'No acquisition file was selected.');
end
bin_file = string(fullfile(selected_path, selected_file));
bin_directory = string(selected_path);
filename = string(selected_file);

%% 2. ACQUISITION PARAMETER PREPARATION
% The OCT system, acquisition mode, scan geometry, and crop are acquisition
% decisions. Physical OCT profile values remain config-owned.
%
% --- USER OPTIONS ---
% oct_system_profile: "swept_source_1300" | "spectral_domain_1040" | "spectral_domain_1310"
oct_system_profile = "spectral_domain_1310";
% acquisition_mode: currently maintained processing supports "mb_mode".
acquisition_mode = "mb_mode";
% scan_geometry: "angular_bmodes" | "raster".
% Raster is recognized metadata but is not a maintained processing path yet.
scan_geometry = "angular_bmodes";

% Crop selection: "interactive" | "manual_indices".
% With manual_indices, fill inclusive start/end indices below.
% B-mode limits: [] = automatic | [low high] = explicit dB limits.
crop_options = struct();
crop_options.depth = struct( ...
    'selection', "interactive", ...
    'start_index_inclusive', [], ...
    'end_index_inclusive', [], ...
    'bmode_intensity_limits_db', []);
crop_options.time = struct( ...
    'selection', "interactive", ...
    'start_index_inclusive', [], ...
    'end_index_inclusive', []);

% --- EXECUTION ---
oct_system_options = oce.config.getOCTSystemOptions(oct_system_profile);
[acquisition_parameters, ~, measurement] = ...
    oce.acquisition.prepareAcquisitionParameters( ...
        filename, bin_directory, ...
        'AcquisitionMode', acquisition_mode, ...
        'ScanGeometry', scan_geometry, ...
        'OCTSystemOptions', oct_system_options, ...
        'CropOptions', crop_options, ...
        'SaveParameters', false, ...
        'CloseFigures', false);

%% 3. PROCESSING CONFIGURATION
% Metadata and shared defaults for this standalone acquisition.
%
% --- USER OPTIONS ---
% sample_type: "phantom" | "in_vivo_eye" | "ex_vivo_eye"
sample_type = "phantom";
% excitation_type: "quasi_harmonic" | "pulse".
% quasi_harmonic uses a positive physical excitation frequency.
% pulse has no single target frequency; set frequency_Hz = NaN.
excitation_type = "quasi_harmonic";
frequency_Hz = 500;

% --- EXECUTION ---
acquisition_metadata = struct( ...
    'sample_type', sample_type, ...
    'excitation_type', excitation_type, ...
    'frequency_Hz', frequency_Hz);

processing_config = oce.config.getDefaultProcessingConfig(sample_type);
processing_config.OCTSystemOptions = oct_system_options;

% Optional material-specific refractive-index override for quantitative work:
% processing_config.SampleOpticalOptions.refractive_index.value = 1.41;
% processing_config.SampleOpticalOptions.refractive_index.source = ...
%     "material_specific_override";

processing_config.AcquisitionOptions = struct( ...
    'acquisition_mode', acquisition_mode, ...
    'scan_geometry_selection', "manual", ...
    'scan_geometry', scan_geometry);

processing_inputs = oce.acquisition.prepareSingleFileInputs( ...
    bin_file, acquisition_parameters, acquisition_metadata, ...
    processing_config, 'ResultsDirectory', fullfile(bin_directory, "Results"));
config_for_run = oce.config.buildProcessingConfigForAcquisition( ...
    processing_inputs);
% Every output of this acquisition goes to Results/<acquisition name>/,
% the same per-file folder the automatic pipeline uses.
results_directory = string(oce.pipeline.resolveOutputDirectory( ...
    processing_inputs));
run_id = string(processing_inputs.acquisition_row.run_id);

%% 4. RECONSTRUCTION
% Raw I/O is geometry-neutral. Reuse the measurement already read in section 2;
% buildAcquisitionState interprets geometry and owns scientific reconstruction.
%
% --- USER OPTIONS ---
show_reconstruction_preview = false;  % true | false

% --- EXECUTION ---
acquisition_state = oce.acquisition.buildAcquisitionState( ...
    measurement, config_for_run, 'ShowProgress', manual_show_progress);
reconstruction_result = acquisition_state.reconstruction;

if show_reconstruction_preview
    oce.plotting.plotReconstructionPreview( ...
        reconstruction_result, ...
        acquisition_parameters.preview_display.bmode_intensity_limits_db);
end

%% 5. BORDER DETECTION
% Automatic border selection maps sample_type to the maintained detector:
% phantom -> phantom; in_vivo_eye -> in_vivo_corneal;
% ex_vivo_eye -> adaptive_corneal.
%
% --- USER OPTIONS ---
% border_tuning: "interactive" | "headless"
border_tuning = "interactive";
% border_selection: "automatic" | "manual"
border_selection = "automatic";
% Manual methods: "phantom" | "adaptive_corneal" | "in_vivo_corneal".
% Leave "" when border_selection="automatic".
border_method_override = "";
% Phantom surface mode: "anterior_posterior" | "anterior_only".
phantom_surface_mode = "anterior_only";
processing_config.BorderOptions.mask_threshold = 42;  % finite intensity threshold

% Detector-specific parameters remain directly editable when needed, e.g.:
% processing_config.BorderOptions.corneal_preprocessing.adaptive_threshold_k = 0.12;
% processing_config.BorderOptions.methods.in_vivo_corneal.smooth_span_px = 21;

% --- EXECUTION ---
processing_config.BorderOptions.selection = border_selection;
processing_config.BorderOptions.method = border_method_override;
processing_config.BorderOptions.methods.phantom.surface_mode = ...
    phantom_surface_mode;
initial_border_options = oce.config.resolveBorderOptions( ...
    processing_config.BorderOptions, processing_inputs.acquisition_row, ...
    config_for_run.resolved_crop);

switch border_tuning
    case "interactive"
        [processing_config.BorderOptions, border_result] = ...
            oce.interaction.tuneBorderDetection( ...
                acquisition_state, processing_config.BorderOptions, ...
                processing_inputs.acquisition_row, ...
                config_for_run.resolved_crop, ...
                acquisition_parameters.preview_display. ...
                    bmode_intensity_limits_db);
        config_for_run.BorderOptions = oce.config.resolveBorderOptions( ...
            processing_config.BorderOptions, ...
            processing_inputs.acquisition_row, config_for_run.resolved_crop);

    case "headless"
        config_for_run.BorderOptions = initial_border_options;
        border_result = oce.borders.detectAndMask( ...
            acquisition_state, config_for_run.BorderOptions);

    otherwise
        error('OCE:Workflow:InvalidBorderTuning', ...
            'border_tuning must be "interactive" or "headless".');
end

%% 6. PHASE ESTIMATION
% Phase calculation remains headless. phase_clim_* controls 2-D phase maps;
% video_clim_* controls depth-motion displays. CLim mode options are
% "auto" | "robust" | "manual". A scalar manual CLim means +/-value.
%
% --- USER OPTIONS ---
show_phase_preview = false;  % true | false
phase_clim_mode = "robust";
phase_clim = [];            % [] unless phase_clim_mode="manual"
video_clim_mode = "robust";
video_clim = [];            % [] unless video_clim_mode="manual"

% Surface-motion estimator parameters.
processing_config.MotionOptions.surface.depth_offset_samples = 0;
processing_config.MotionOptions.surface.aggregation_band_samples = 6;
processing_config.MotionOptions.surface.loupas.axial_window_samples = 20;
processing_config.MotionOptions.surface.smoothing.span_fraction = 0.05;

% --- EXECUTION ---
processing_config.MotionOptions.show_progress = manual_show_progress;
config_for_run.MotionOptions = oce.config.resolvePhaseEstimationOptions( ...
    processing_config.MotionOptions);
complex_values = reconstruction_result.complex_volume.values;
depth_phase_result = oce.motion.computeDepthResolvedPhase( ...
    complex_values, config_for_run.MotionOptions, ...
    'UseParallel', manual_use_parallel);
surface_phase_result = oce.motion.computeSurfacePhase( ...
    complex_values, border_result.indices.anterior, ...
    config_for_run.MotionOptions, 'UseParallel', manual_use_parallel);
phase_result = struct( ...
    'depth_resolved', depth_phase_result, ...
    'surface', surface_phase_result, ...
    'options', config_for_run.MotionOptions);

if show_phase_preview
    oce.plotting.plotPhasePreview( ...
        phase_result, reconstruction_result, acquisition_state.geometry, ...
        'CLimMode', phase_clim_mode, ...
        'CLim', phase_clim);
end

%% 6A. OPTIONAL RAW DEPTH-MOTION ANIMATION
% Reuses phase_result, reconstruction_result, and border_result. It performs no
% phase estimation and writes no file.
%
% --- USER OPTIONS ---
show_raw_depth_motion_animation = false;  % true | false

% --- EXECUTION ---
if show_raw_depth_motion_animation
    oce.plotting.showDepthMotionAnimation( ...
        phase_result, reconstruction_result, border_result, ...
        acquisition_state.geometry, ...
        'BmodeDisplayLimitsDb', ...
            acquisition_parameters.preview_display.bmode_intensity_limits_db, ...
        'CLimMode', video_clim_mode, ...
        'CLim', video_clim);
end

%% 7. TEMPORAL FILTERING
% automatic -> center frequency comes from acquisition metadata.
% manual    -> use manual_passband_hz or select limits on the FFT display.
% Pulse excitation uses manual because it has no single excitation frequency.
%
% --- USER OPTIONS ---
filter_frequency_selection = "automatic";  % "automatic" | "manual"
manual_passband_hz = [];                    % [] | [low high] Hz
show_filter_preview = true;                 % true | false
processing_config.FilterOptions.enabled = true;  % true | false
processing_config.FilterOptions.order = 100;
processing_config.FilterOptions.diagnostic.fft_length = 2^12;
processing_config.FilterOptions.diagnostic.line_index = [];  % [] = maintained default
processing_config.FilterOptions.frequency.bandwidth.fraction = 0.65;

% --- EXECUTION ---
if excitation_type == "pulse" && string(filter_frequency_selection) ~= "manual"
    error('OCE:Workflow:PulseFilterSelection', ...
        ['Pulse excitation has no automatic center frequency. Use ' ...
         'filter_frequency_selection="manual" and select the useful passband.']);
end
switch string(filter_frequency_selection)
    case "automatic"
        processing_config.FilterOptions.frequency.selection_source = ...
            "acquisition_row";
        processing_config.FilterOptions.frequency.center_hz = [];
        processing_config.FilterOptions.frequency.bandwidth.mode = ...
            "fraction_of_center";
        processing_config.FilterOptions.frequency.bandwidth.hz = [];

    case "manual"
        if isempty(manual_passband_hz)
            processing_config.FilterOptions = ...
                oce.interaction.selectTemporalFilterPassband( ...
                    phase_result.surface.values, config_for_run, ...
                    acquisition_state.system.oct, ...
                    acquisition_state.geometry, ...
                    processing_config.FilterOptions);
        else
            if ~isnumeric(manual_passband_hz) || ...
                    ~isequal(size(manual_passband_hz), [1 2]) || ...
                    any(~isfinite(manual_passband_hz)) || ...
                    manual_passband_hz(1) <= 0 || ...
                    manual_passband_hz(1) >= manual_passband_hz(2)
                error('OCE:Workflow:InvalidManualPassband', ...
                    'manual_passband_hz must be [] or [low high] in Hz.');
            end
            processing_config.FilterOptions.frequency.selection_source = ...
                "manual_configuration";
            processing_config.FilterOptions.frequency.center_hz = ...
                mean(manual_passband_hz);
            processing_config.FilterOptions.frequency.bandwidth.mode = ...
                "absolute_hz";
            processing_config.FilterOptions.frequency.bandwidth.fraction = [];
            processing_config.FilterOptions.frequency.bandwidth.hz = ...
                diff(manual_passband_hz);
        end

    otherwise
        error('OCE:Workflow:InvalidFilterSelection', ...
            ['filter_frequency_selection must be "automatic" or ' ...
             '"manual".']);
end

config_for_run.FilterOptions = processing_config.FilterOptions;
[filter_result, resolved_filter_options] = ...
    oce.filtering.filterPhaseResults( ...
        phase_result, config_for_run, acquisition_state.system.oct, ...
        acquisition_state.geometry);
config_for_run.FilterOptions = resolved_filter_options;

if show_filter_preview
    oce.plotting.plotFilterPreviews( ...
        phase_result, filter_result, reconstruction_result, ...
        acquisition_state.geometry, ...
        'CLimMode', phase_clim_mode, ...
        'CLim', phase_clim);
end

%% 7A. OPTIONAL COMPLETE SPACE-TIME
% Uses filtered data when section 7 has been run; otherwise it can display the
% phase-only product.
%
% --- USER OPTIONS ---
show_complete_space_time = false;  % true | false

% --- EXECUTION ---
complete_space_time_filter_result = [];
if exist('filter_result', 'var') == 1
    complete_space_time_filter_result = filter_result;
end
if show_complete_space_time
    oce.plotting.plotCompleteSpaceTime( ...
        phase_result, complete_space_time_filter_result, ...
        reconstruction_result, acquisition_state.geometry, ...
        'CLimMode', phase_clim_mode, ...
        'CLim', phase_clim);
end

%% 7B. OPTIONAL FILTERED MOTION VIDEO
% Independent file-generating stage. Requires an applied filter from section 7.
%
% --- USER OPTIONS ---
generate_filtered_motion_video = true;  % true | false
processing_config.VideoOptions.time_start_idx = 1;   % first frame index
processing_config.VideoOptions.max_frames = 350;     % maximum frames written
processing_config.VideoOptions.frame_rate = 30;      % frames/s
processing_config.VideoOptions.filename = "Video_2D_Filtered.mp4";

% --- EXECUTION ---
filtered_motion_video_path = "";
if generate_filtered_motion_video
    video_filter_result = [];
    if exist('filter_result', 'var') == 1
        video_filter_result = filter_result;
    end
    filtered_motion_video_path = oce.video.createFilteredMotionVideo( ...
        video_filter_result, phase_result, reconstruction_result, border_result, ...
        acquisition_state.geometry, processing_config.VideoOptions, ...
        results_directory, ...
        'BmodeDisplayLimitsDb', ...
            acquisition_parameters.preview_display.bmode_intensity_limits_db, ...
        'CLimMode', video_clim_mode, ...
        'CLim', video_clim, ...
        'ShowProgress', manual_show_progress);
end

%% 8. DISPERSION WINDOWS
% Window extraction is configured here; buildWindows consumes only the resolved
% policy and the already filtered surface phase.
%
% --- USER OPTIONS ---
show_dispersion_window_context = true;  % true | false

% center.method:
% "middle" | "manual_local_index" | "max_rms_phase_increment" |
% "max_mirrored_correlation"
processing_config.DispersionWindowOptions.center.method = ...
    "max_mirrored_correlation";
% Required only for center.method="manual_local_index":
% processing_config.DispersionWindowOptions.center.manual_local_index = [200 200];

% spatial.method: "fraction_of_bmode" | "manual_interval_count"
processing_config.DispersionWindowOptions.spatial.method = ...
    "fraction_of_bmode";
processing_config.DispersionWindowOptions.spatial.interval_fraction = 0.30;
% Required only for spatial.method="manual_interval_count":
% processing_config.DispersionWindowOptions.spatial.manual_interval_count = 150;

processing_config.DispersionWindowOptions.directional_offsets.left_samples = -3;
processing_config.DispersionWindowOptions.directional_offsets.right_samples = 3;
crop_time_start_index = double( ...
    reconstruction_result.crop.time.start_index_inclusive);
processing_config.DispersionWindowOptions.temporal.start_index_inclusive = ...
    crop_time_start_index + 74;  % absolute acquisition sample

% temporal.method: "cycle_count" | "manual_interval_count" | "to_end"
% Pulse excitation may use to_end to retain the packet through the crop end.
processing_config.DispersionWindowOptions.temporal.method = "cycle_count";
processing_config.DispersionWindowOptions.temporal.cycle_count = 3;
% Required only for temporal.method="manual_interval_count":
% processing_config.DispersionWindowOptions.temporal.manual_interval_count = 300;

% --- EXECUTION ---
if excitation_type == "pulse" && ...
        string(processing_config.DispersionWindowOptions.temporal.method) == ...
        "cycle_count"
    error('OCE:Workflow:PulseTemporalWindow', ...
        ['Pulse excitation requires temporal.method="to_end" or ' ...
         '"manual_interval_count" rather than an excitation-cycle duration.']);
end
processing_config.DispersionWindowOptions.show_progress = manual_show_progress;
config_for_run.DispersionWindowOptions = ...
    oce.config.resolveDispersionWindowOptions( ...
        processing_config.DispersionWindowOptions);
window_result = oce.dispersion.buildWindows( ...
    config_for_run, filter_result, ...
    acquisition_state.geometry.bmode_lateral_axis_mm, ...
    config_for_run.FilterOptions, acquisition_state.geometry);

if show_dispersion_window_context
    local_lateral_axis_mm = acquisition_state.geometry.bmode_lateral_axis_mm;
    for bmode_index = 1:numel(window_result.bmodes)
        oce.plotting.plotDispersionWindowContext( ...
            window_result, filter_result, local_lateral_axis_mm, ...
            bmode_index, ...
            'CLimMode', phase_clim_mode, ...
            'CLim', phase_clim, ...
            'TimeSampleStartIndex', crop_time_start_index);
    end
end

%% 9. DISPERSION ANALYSIS
% Configure the pre-FFT taper, FFT grid, crop, ridge threshold, and curve
% smoothing. Diagnostics consume the already-computed analysis result.
%
% --- USER OPTIONS ---
show_kf_preview = true;      % true | false
show_speed_preview = true;   % true | false
show_phase_gradient_preview = false; % requires phase_gradient.enabled
% Persist scalar phase-gradient estimates alongside k-f when enabled.
processing_config.DispersionAnalysisOptions.phase_gradient.enabled = false;
dispersion_time_window_enabled = true;    % Hann taper: true | false
dispersion_space_window_enabled = false;  % Hann taper: true | false

processing_config.DispersionAnalysisOptions.spectrum.window.time.enabled = ...
    dispersion_time_window_enabled;
processing_config.DispersionAnalysisOptions.spectrum.window.space.enabled = ...
    dispersion_space_window_enabled;
processing_config.DispersionAnalysisOptions.spectrum.fft.time_bin_count = ...
    (2^13) + 1;
processing_config.DispersionAnalysisOptions.spectrum.fft.spatial_bin_count = ...
    (2^13) + 1;
processing_config.DispersionAnalysisOptions.spectrum.crop.maximum_frequency_hz = ...
    8000;
processing_config.DispersionAnalysisOptions.ridge.minimum_relative_magnitude = ...
    0.01;
processing_config.DispersionAnalysisOptions.phase_speed.smoothing.span_fraction = ...
    0.10;

% --- EXECUTION ---
if excitation_type == "pulse"
    processing_config.DispersionAnalysisOptions.target_frequency.source = ...
        "not_available";
end
[config_for_run.DispersionAnalysisOptions, phase_gradient_options] = ...
    oce.config.resolveDispersionAnalysisOptions( ...
        processing_config.DispersionAnalysisOptions, ...
        config_for_run.FilterOptions, processing_inputs.acquisition_row);
dispersion_analysis_result = oce.dispersion.analyzeWindows( ...
    window_result, border_result.thickness, ...
    config_for_run.DispersionAnalysisOptions, ...
    'UseParallel', manual_use_parallel, ...
    'PhaseGradientOptions', phase_gradient_options, ...
    'SurfacePhase', phase_result.surface, ...
    'PhaseTimeStartIndex', crop_time_start_index);

if show_kf_preview || show_speed_preview || ...
        (show_phase_gradient_preview && dispersion_analysis_result.phase_gradient.enabled)
    for scan_axis_index = 1:dispersion_analysis_result.scan_axis_count
        if show_kf_preview
            oce.plotting.plotDispersionKfPreview( ...
                dispersion_analysis_result, scan_axis_index);
        end
        if show_speed_preview
            oce.plotting.plotSpeedDispersionPreview( ...
                dispersion_analysis_result, scan_axis_index);
        end
        if show_phase_gradient_preview && dispersion_analysis_result.phase_gradient.enabled
            oce.plotting.plotPhaseGradientPreview( ...
                dispersion_analysis_result, scan_axis_index);
        end
    end
end

%% 10. SCIENTIFIC RESULT
% Assemble the canonical persisted scientific schema from the already-computed
% products. This remains an explicit debugging boundary.
%
% --- EXECUTION ---
oce_result = oce.results.buildScientificResult( ...
    processing_inputs, config_for_run, window_result, ...
    dispersion_analysis_result);
oce.results.validateScientificResult(oce_result);

%% 10A. POLAR RESULTS
% Display-only angular summaries. No dispersion or thickness calculation occurs.
%
% --- USER OPTIONS ---
show_polar_results = true;  % true | false

% --- EXECUTION ---
if show_polar_results
    oce.plotting.plotPolarPhaseResults(oce_result);
end

%% 11. OPTIONAL PERSISTENCE
% Select which already-computed products should be persisted. Saving remains
% explicit here; the save owners below consume existing scientific products.
%
% --- USER OPTIONS ---
manual_output = struct();
manual_output.save_reconstruction_preview = false;  % true | false
manual_output.save_border_preview = false;          % true | false
manual_output.save_filter_preview = false;          % true | false
manual_output.save_complete_space_time = false;     % true | false
manual_output.save_dispersion_window_context = false; % true | false
manual_output.save_kf_preview = false;               % true | false
manual_output.save_dispersion_preview = false;      % true | false
manual_output.save_polar_results = false;           % true | false
manual_output.save_scientific_result = false;       % true | false
manual_output.close_generated_figures = false;      % true | false

% --- EXECUTION ---
persistence_filter_result = [];
if exist('filter_result', 'var') == 1
    persistence_filter_result = filter_result;
end

generated_artifacts = strings(0, 1);
write_any_output = manual_output.save_reconstruction_preview || ...
    manual_output.save_border_preview || ...
    manual_output.save_filter_preview || ...
    manual_output.save_complete_space_time || ...
    manual_output.save_dispersion_window_context || ...
    manual_output.save_kf_preview || ...
    manual_output.save_dispersion_preview || ...
    manual_output.save_polar_results || ...
    manual_output.save_scientific_result;

if write_any_output
    if ~isfolder(results_directory)
        mkdir(results_directory);
    end
    figures_before = findall(groot, 'Type', 'figure');

    if manual_output.save_reconstruction_preview
        generated_artifacts = [generated_artifacts; ...
            oce.plotting.saveReconstructionPreview( ...
                reconstruction_result, ...
                acquisition_parameters.preview_display. ...
                    bmode_intensity_limits_db, ...
                results_directory)];
    end

    if manual_output.save_border_preview
        generated_artifacts = [generated_artifacts; ...
            oce.plotting.saveBorderPreview( ...
                reconstruction_result, border_result, ...
                acquisition_state.system.oct, ...
                acquisition_parameters.preview_display. ...
                    bmode_intensity_limits_db, ...
                results_directory)];
    end

    if manual_output.save_filter_preview
        generated_artifacts = [generated_artifacts; ...
            oce.plotting.saveFilterPreviews( ...
                phase_result, persistence_filter_result, ...
                reconstruction_result, acquisition_state.geometry, ...
                results_directory, ...
                'CLimMode', phase_clim_mode, ...
                'CLim', phase_clim, ...
                'BmodeMode', "representative")];
    end

    if manual_output.save_complete_space_time
        generated_artifacts = [generated_artifacts; ...
            oce.plotting.saveCompleteSpaceTime( ...
                phase_result, persistence_filter_result, ...
                reconstruction_result, acquisition_state.geometry, ...
                results_directory, ...
                'CLimMode', phase_clim_mode, ...
                'CLim', phase_clim)];
    end

    if manual_output.save_dispersion_window_context
        local_lateral_axis_mm = acquisition_state.geometry.bmode_lateral_axis_mm;
        for bmode_index = 1:numel(window_result.bmodes)
            generated_artifacts = [generated_artifacts; ...
                oce.plotting.saveDispersionWindowContext( ...
                    window_result, persistence_filter_result, ...
                    local_lateral_axis_mm, bmode_index, results_directory, ...
                    'CLimMode', phase_clim_mode, 'CLim', phase_clim, ...
                    'TimeSampleStartIndex', crop_time_start_index)];
        end
    end

    if manual_output.save_kf_preview
        kf_artifacts = strings( ...
            2 * dispersion_analysis_result.scan_axis_count, 1);
        for scan_axis_index = 1:dispersion_analysis_result.scan_axis_count
            artifact_indices = ...
                (2 * scan_axis_index - 1):(2 * scan_axis_index);
            kf_artifacts(artifact_indices) = ...
                oce.plotting.saveDispersionKfPreview( ...
                    dispersion_analysis_result, scan_axis_index, ...
                    results_directory);
        end
        generated_artifacts = [generated_artifacts; kf_artifacts];
    end

    if manual_output.save_dispersion_preview
        dispersion_artifacts = strings( ...
            2 * dispersion_analysis_result.scan_axis_count, 1);
        for scan_axis_index = 1:dispersion_analysis_result.scan_axis_count
            artifact_indices = ...
                (2 * scan_axis_index - 1):(2 * scan_axis_index);
            dispersion_artifacts(artifact_indices) = ...
                oce.plotting.saveSpeedDispersionPreview( ...
                    dispersion_analysis_result, scan_axis_index, ...
                    results_directory);
        end
        generated_artifacts = [generated_artifacts; dispersion_artifacts];
    end

    if manual_output.save_polar_results
        polar_artifacts = oce.plotting.savePolarPhaseResults( ...
            oce_result, results_directory, ...
            'CloseFigures', manual_output.close_generated_figures);
        generated_artifacts = [generated_artifacts; polar_artifacts];
    end

    if manual_output.save_scientific_result
        generated_artifacts(end + 1, 1) = string( ...
            oce.io.saveScientificResult(results_directory, oce_result));
    end

    oce.plotting.closeGeneratedFigures( ...
        figures_before, manual_output.close_generated_figures);
end
