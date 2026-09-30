%#ok<*UNRCH>
%% RUN_EXPERIMENT_BATCH
% Human-facing experiment workflow.
%
% Phase A prepares every selected sub-experiment interactively and persists one
% validated ProcessingConfig per sub-experiment. Phase B then runs all prepared
% batches without further interaction. Scientific calculation remains owned by
% maintained oce.* APIs.

%% 1. USER CONFIGURATION

experiment_root = "E:\OCE_Experiments\<experiment>";
experimental_log_sheet = "Experiment";

% Use "all" or an explicit string vector.
subexperiments_to_process = "all";
overwrite_parameters = true;

% Prepare every sub-experiment first. Set false to stop after parameter setup.
run_batches_after_preparation = true;
stop_on_batch_error = false;
keep_full_output = false;

% Optional experiment-wide sample refractive-index override. Leave [] to use
% the maintained sample-type default in each ProcessingConfig.
sample_refractive_index_override = [];

% Shared phantom border geometry: "anterior_posterior" | "anterior_only".
phantom_surface_mode = "anterior_posterior";

% Shared temporal-filter policy. Quasi-harmonic acquisitions use frequency_Hz.
% Pulse acquisitions select the useful passband interactively on the
% representative spectrum and persist that manual passband for the batch.
filter_enabled = true;
filter_order = 100;
filter_bandwidth_fraction = 0.65;

% Shared dispersion-analysis policy.
dispersion_time_hann_enabled = true;
dispersion_space_hann_enabled = false;
phase_gradient_enabled = false;
show_representative_kf_preview = true;
show_representative_speed_preview = true;
show_representative_phase_gradient_preview = false; % requires phase_gradient_enabled

% Initial dispersion-window policy. The tuner opens with these methods and may
% change them before acceptance. Accepted center/spatial values seed the next
% compatible sub-experiment; temporal placement starts from the current crop.
% Pulse acquisitions use to_end so the selected start extends to the crop end.
dispersion_center_method = "max_mirrored_correlation";
dispersion_manual_center_indices = [];
dispersion_center_search_range_fraction = [0.30 0.70];
dispersion_rms_smoothing_span_fraction = 0.07;
dispersion_mirrored_half_width_fraction = 0.25;
dispersion_mirrored_score_smoothing_fraction = 0.03;

dispersion_spatial_method = "fraction_of_bmode";
dispersion_spatial_fraction = 0.30;
dispersion_spatial_interval_count = [];
dispersion_left_offset_samples = -3;
dispersion_right_offset_samples = 3;

dispersion_temporal_method = "cycle_count";
dispersion_temporal_start_offset_samples = 74;
dispersion_cycle_count = 3;
dispersion_temporal_interval_count = [];

% Shared output policy for every final batch acquisition.
% phase_clim_* controls saved phase/space-time figures.
% video_clim_* controls filtered-motion MP4 rendering.
% For a fixed scale use mode="manual" and, e.g., clim=0.5.
output_options = struct( ...
    'save_scientific_result', true, ...
    'save_reconstruction_preview', false, ...
    'save_border_preview', true, ...
    'save_filter_preview', true, ...
    'save_dispersion_window_context', true, ...
    'save_kf_plots', true, ...
    'save_dispersion_plots', true, ...
    'save_polar_plots', true, ...
    'save_filtered_motion_video', true, ...
    'phase_clim_mode', "robust", ...
    'phase_clim', [], ...
    'video_clim_mode', "robust", ...
    'video_clim', [], ...
    'close_figures', true);

batch_run_options = struct( ...
    'stop_after', "scientific_result", ...
    'return_intermediate_products', "required");

%% 2. INITIALIZE AND LOAD EXPERIMENT

% Run Section evaluates script code in the base workspace, where helpers in
% workflows/private are not reliably resolved. Resolve this script from the
% active MATLAB Editor file, matching the maintained stepwise driver.
workflow_file = matlab.desktop.editor.getActiveFilename;
if isempty(workflow_file)
    error('OCE:Workflow:CannotLocateDriver', ...
        ['Could not determine the active workflow file. Open ' ...
         'run_experiment_batch.m in the MATLAB Editor.']);
end
repository_root = fileparts(fileparts(workflow_file));
startup_file = fullfile(repository_root, 'startup.m');
assert(isfile(startup_file), ...
    'Could not locate repository startup.m: %s', startup_file);
run(startup_file);

log_path = fullfile(experiment_root, "experimental_log.xlsx");

[acquisition_table, ~, acquisition_params_paths] = oce.io.loadExperimentalLog( ...
    log_path, 'Sheet', experimental_log_sheet, ...
    'SaveAcquisitionParams', true, ...
    'Overwrite', overwrite_parameters);

available_subexperiments = unique( ...
    string(acquisition_table.sub_experiment), 'stable');
subexperiments = resolve_subexperiments( ...
    subexperiments_to_process, available_subexperiments);

experiment_output = struct( ...
    'status', "preparing", ...
    'started_at', string(datetime('now')), ...
    'experiment_root', experiment_root, ...
    'acquisition_params_paths', acquisition_params_paths, ...
    'sub_experiments', repmat(empty_subexperiment_result(), ...
        numel(subexperiments), 1));

previous_border_options = struct();
previous_border_method = "";
previous_border_surface_mode = "";
previous_window_options = struct();
previous_window_excitation_type = "";

%% 3. INTERACTIVE PREPARATION OF ALL SUB-EXPERIMENTS

for sub_index = 1:numel(subexperiments)
    sub_experiment = subexperiments(sub_index);
    fprintf('\n============================================================\n');
    fprintf('Preparing sub-experiment %d/%d: %s\n', ...
        sub_index, numel(subexperiments), sub_experiment);
    fprintf('============================================================\n');

    rows = acquisition_table( ...
        string(acquisition_table.sub_experiment) == sub_experiment, :);
    result = empty_subexperiment_result();
    result.sub_experiment = sub_experiment;
    result.output_options = output_options;

    acquisition_mode = require_one_text_value(rows, 'acquisition_mode');
    scan_geometry = require_one_text_value(rows, 'scan_geometry');
    oct_system_profile = require_one_text_value(rows, 'oct_system_profile');
    excitation_type = require_one_text_value(rows, 'excitation_type');
    oct_system_options = oce.config.getOCTSystemOptions(oct_system_profile);
    result.acquisition_mode = acquisition_mode;
    result.scan_geometry = scan_geometry;
    result.oct_system_profile = oct_system_profile;

    %% 3A. Representative acquisition and acquisition parameters
    representative_index = select_representative_row(rows);
    representative_row = rows(representative_index, :);
    representative_run_id = string(representative_row.run_id);
    representative_file = string(representative_row.filename);
    result.representative_run_id = representative_run_id;
    result.representative_filename = representative_file;

    sample_type = require_one_sample_type(rows);
    data_directory = fullfile(experiment_root, "Data", sub_experiment);
    [~, params_path] = oce.acquisition.prepareAcquisitionParameters( ...
        representative_file, data_directory, ...
        'AcquisitionMode', acquisition_mode, ...
        'ScanGeometry', scan_geometry, ...
        'OCTSystemOptions', oct_system_options, ...
        'SaveParameters', true, ...
        'Overwrite', overwrite_parameters, ...
        'CloseFigures', false);
    result.params_path = string(params_path);

    %% 3B. Build experiment-shared processing intent in memory
    processing_config = oce.config.getDefaultProcessingConfig(sample_type);
    processing_config.AcquisitionOptions.acquisition_mode = acquisition_mode;
    processing_config.OCTSystemOptions = oct_system_options;
    if sample_type == "phantom"
        processing_config.BorderOptions.methods.phantom.surface_mode = ...
            phantom_surface_mode;
    end

    if ~isempty(sample_refractive_index_override)
        validate_positive_scalar(sample_refractive_index_override, ...
            'sample_refractive_index_override');
        processing_config.SampleOpticalOptions.refractive_index.value = ...
            sample_refractive_index_override;
        processing_config.SampleOpticalOptions.refractive_index.source = ...
            "experiment_configuration_override";
    end

    processing_config.FilterOptions.enabled = logical(filter_enabled);
    processing_config.FilterOptions.order = filter_order;
    processing_config.FilterOptions.frequency.selection_source = ...
        "acquisition_row";
    processing_config.FilterOptions.frequency.center_hz = [];
    processing_config.FilterOptions.frequency.bandwidth.mode = ...
        "fraction_of_center";
    processing_config.FilterOptions.frequency.bandwidth.fraction = ...
        filter_bandwidth_fraction;
    processing_config.FilterOptions.frequency.bandwidth.hz = [];

    processing_config.DispersionAnalysisOptions.spectrum.window.time.enabled = ...
        logical(dispersion_time_hann_enabled);
    processing_config.DispersionAnalysisOptions.spectrum.window.space.enabled = ...
        logical(dispersion_space_hann_enabled);
    processing_config.DispersionAnalysisOptions.phase_gradient.enabled = ...
        logical(phase_gradient_enabled);
    if excitation_type == "pulse"
        if phase_gradient_enabled
            error('OCE:Workflow:PhaseGradientPulse', ...
                'Phase gradient requires quasi-harmonic excitation with a physical frequency.');
        end
        processing_config.DispersionAnalysisOptions.target_frequency.source = ...
            "not_available";
    end

    reusePreviousWindows = ~isempty(fieldnames(previous_window_options)) && ...
        previous_window_excitation_type == excitation_type;
    if ~reusePreviousWindows
        processing_config.DispersionWindowOptions.center.method = ...
            string(dispersion_center_method);
        processing_config.DispersionWindowOptions.center.manual_local_index = ...
            dispersion_manual_center_indices;
        processing_config.DispersionWindowOptions.center.search_range_fraction = ...
            dispersion_center_search_range_fraction;
        processing_config.DispersionWindowOptions.center. ...
            max_rms_phase_increment.smoothing_span_fraction = ...
            dispersion_rms_smoothing_span_fraction;
        processing_config.DispersionWindowOptions.center. ...
            max_mirrored_correlation.half_width_fraction = ...
            dispersion_mirrored_half_width_fraction;
        processing_config.DispersionWindowOptions.center. ...
            max_mirrored_correlation.score_smoothing_span_fraction = ...
            dispersion_mirrored_score_smoothing_fraction;

        processing_config.DispersionWindowOptions.spatial.method = ...
            string(dispersion_spatial_method);
        processing_config.DispersionWindowOptions.spatial.interval_fraction = ...
            dispersion_spatial_fraction;
        processing_config.DispersionWindowOptions.spatial.manual_interval_count = ...
            dispersion_spatial_interval_count;
        processing_config.DispersionWindowOptions.directional_offsets.left_samples = ...
            dispersion_left_offset_samples;
        processing_config.DispersionWindowOptions.directional_offsets.right_samples = ...
            dispersion_right_offset_samples;

        processing_config.DispersionWindowOptions.temporal.cycle_count = ...
            dispersion_cycle_count;
        processing_config.DispersionWindowOptions.temporal.manual_interval_count = ...
            dispersion_temporal_interval_count;
        if excitation_type == "pulse"
            processing_config.DispersionWindowOptions.temporal.method = ...
                "to_end";
        else
            processing_config.DispersionWindowOptions.temporal.method = ...
                string(dispersion_temporal_method);
        end
    else
        processing_config.DispersionWindowOptions = previous_window_options;
        fprintf(['Starting dispersion tuning from the previous accepted policy; ' ...
            'temporal start will follow the current crop.\n']);
    end

    [processing_inputs, config_for_run, acquisition_state] = ...
        prepare_representative_context( ...
            experiment_root, sub_experiment, representative_run_id, ...
            processing_config);
    display_limits = processing_inputs.acquisition_parameters. ...
        preview_display.bmode_intensity_limits_db;
    crop_time_start_index = double( ...
        config_for_run.resolved_crop.time.start_index_inclusive);
    crop_time_end_index = double( ...
        config_for_run.resolved_crop.time.end_index_inclusive);
    processing_config.DispersionWindowOptions.temporal. ...
        start_index_inclusive = crop_time_start_index + ...
        dispersion_temporal_start_offset_samples;

    %% 3C. Tune borders; inherit the previous accepted method when compatible
    effective_border_method = string(config_for_run.BorderOptions.method);
    effective_border_surface_mode = string( ...
        config_for_run.BorderOptions.surface_mode);
    border_seed = processing_config.BorderOptions;
    if ~isempty(fieldnames(previous_border_options)) && ...
            previous_border_method == effective_border_method && ...
            previous_border_surface_mode == effective_border_surface_mode
        border_seed = previous_border_options;
        fprintf('Starting borders from previous %s parameters.\n', ...
            effective_border_method);
    end

    [accepted_borders, border_result] = oce.interaction.tuneBorderDetection( ...
        acquisition_state, border_seed, processing_inputs.acquisition_row, ...
        config_for_run.resolved_crop, display_limits);
    processing_config.BorderOptions = accepted_borders;
    previous_border_options = accepted_borders;
    previous_border_method = effective_border_method;
    previous_border_surface_mode = effective_border_surface_mode;

    %% 3D. Fast representative surface-only motion and filtering
    surface_phase_result = oce.motion.computeSurfacePhase( ...
        acquisition_state.reconstruction.complex_volume.values, ...
        border_result.indices.anterior, config_for_run.MotionOptions);
    if excitation_type == "pulse"
        processing_config.FilterOptions = ...
            oce.interaction.selectTemporalFilterPassband( ...
                surface_phase_result.values, config_for_run, ...
                acquisition_state.system.oct, acquisition_state.geometry, ...
                processing_config.FilterOptions);
        config_for_run.FilterOptions = processing_config.FilterOptions;
    end
    [filter_result, resolved_filter] = oce.filtering.filterSurfacePhase( ...
        surface_phase_result, config_for_run, acquisition_state.system.oct, ...
        acquisition_state.geometry);
    %% 3E. Tune maintained dispersion-window methods and numeric values
    windows_accepted = false;
    while ~windows_accepted
        [accepted_windows, window_result] = ...
            oce.interaction.tuneDispersionWindows( ...
                filter_result, processing_config.DispersionWindowOptions, ...
                resolved_filter, acquisition_state.geometry, ...
                acquisition_state.geometry.bmode_lateral_axis_mm, ...
                'TimeSampleStartIndex', crop_time_start_index, ...
                'TimeSampleEndIndex', crop_time_end_index);
        processing_config.DispersionWindowOptions = accepted_windows;

        figures_before = findall(groot, 'Type', 'figure');
        if show_representative_kf_preview || show_representative_speed_preview || ...
                (show_representative_phase_gradient_preview && phase_gradient_enabled)
            [analysis_options, phase_gradient_options] = ...
                oce.config.resolveDispersionAnalysisOptions( ...
                    processing_config.DispersionAnalysisOptions, ...
                    resolved_filter, processing_inputs.acquisition_row);
            dispersion_result = oce.dispersion.analyzeWindows( ...
                window_result, border_result.thickness, analysis_options, ...
                'PhaseGradientOptions', phase_gradient_options, ...
                'SurfacePhase', surface_phase_result, ...
                'PhaseTimeStartIndex', crop_time_start_index);
            show_representative_dispersion( ...
                dispersion_result, show_representative_kf_preview, ...
                show_representative_speed_preview, ...
                show_representative_phase_gradient_preview);
            review_accepted = ask_yes_no( ...
                'Accept these dispersion windows for the sub-experiment?', ...
                true);
        else
            review_accepted = true;
        end

        if review_accepted
            try
                validate_window_policy_for_subexperiment( ...
                    rows, processing_config, config_for_run, ...
                    surface_phase_result, filter_result, acquisition_state);
                windows_accepted = true;
            catch ME
                warning('OCE:Workflow:DispersionWindowReview', ...
                    ['Accepted ROI does not fit every acquisition in this ' ...
                     'sub-experiment. Adjust the tuner configuration.\n%s'], ...
                    ME.message);
            end
        end
        oce.plotting.closeGeneratedFigures(figures_before, true);
    end
    previous_window_options = accepted_windows;
    previous_window_excitation_type = excitation_type;

    %% 3F. Validate and persist only the final accepted configuration
    validation_inputs = processing_inputs;
    validation_inputs.processing_config = processing_config;
    validation_inputs.processingConfigFile = '';
    oce.config.buildProcessingConfigForAcquisition(validation_inputs);

    config_path = oce.config.saveProcessingConfig( ...
        experiment_root, sub_experiment, processing_config, ...
        'Overwrite', true);
    result.processing_config_path = string(config_path);
    result.status = "prepared";
    experiment_output.sub_experiments(sub_index) = result;

    fprintf('\nPrepared %s.\nProcessingConfig:\n%s\n', ...
        sub_experiment, config_path);
end

%% 4. AUTOMATIC BATCH EXECUTION AFTER ALL CONFIGURATIONS ARE READY

if run_batches_after_preparation
    experiment_output.status = "processing";
    fprintf('\nAll selected sub-experiments are prepared. Starting batches.\n');

    for sub_index = 1:numel(subexperiments)
        sub_experiment = subexperiments(sub_index);
        rows = acquisition_table( ...
            string(acquisition_table.sub_experiment) == sub_experiment, :);
        run_ids = string(rows.run_id);

        fprintf('\n------------------------------------------------------------\n');
        fprintf('Batch %d/%d: %s (%d acquisitions)\n', ...
            sub_index, numel(subexperiments), sub_experiment, height(rows));
        fprintf('------------------------------------------------------------\n');

        batch_output = oce.pipeline.runBatchProcessing( ...
            experiment_root, sub_experiment, run_ids, ...
            'Key', 'run_id', ...
            'RunOptions', batch_run_options, ...
            'OutputOptions', output_options, ...
            'StopOnError', stop_on_batch_error, ...
            'KeepFullOutput', keep_full_output);

        experiment_output.sub_experiments(sub_index).batch_output = batch_output;
        if isempty(batch_output.failed_keys)
            experiment_output.sub_experiments(sub_index).status = "completed";
        else
            experiment_output.sub_experiments(sub_index).status = ...
                "completed_with_failures";
        end
    end
end

%% 5. FINAL SUMMARY

statuses = string({experiment_output.sub_experiments.status});
if ~run_batches_after_preparation
    experiment_output.status = "prepared";
elseif any(statuses == "completed_with_failures")
    experiment_output.status = "completed_with_failures";
else
    experiment_output.status = "completed";
end
experiment_output.completed_at = string(datetime('now'));

fprintf('\nExperiment workflow finished: %s\n', experiment_output.status);
for sub_index = 1:numel(experiment_output.sub_experiments)
    item = experiment_output.sub_experiments(sub_index);
    fprintf('  %-30s : %s\n', item.sub_experiment, item.status);
end

%% Local helpers

function subexperiments = resolve_subexperiments(requested, available)
    requested = string(requested);
    if isscalar(requested) && lower(strtrim(requested)) == "all"
        subexperiments = available;
        return;
    end
    subexperiments = requested(:);
    subexperiments = subexperiments(strlength(strtrim(subexperiments)) > 0);
    missing = setdiff(subexperiments, available, 'stable');
    if ~isempty(missing)
        error('OCE:Workflow:UnknownSubExperiment', ...
            'Unknown sub-experiment(s): %s.', strjoin(missing, ', '));
    end
end

function index = select_representative_row(rows)
    fprintf('\nAvailable acquisitions:\n');
    frequency = numeric_or_text_column(rows, 'frequency_Hz');
    repetition = numeric_or_text_column(rows, 'rep_id');
    for rowIndex = 1:height(rows)
        fprintf('  %2d) %-8s | %-35s | f=%s Hz | rep=%s\n', ...
            rowIndex, string(rows.run_id(rowIndex)), ...
            string(rows.filename(rowIndex)), frequency(rowIndex), ...
            repetition(rowIndex));
    end
    while true
        raw = input(sprintf('Representative acquisition [1-%d]: ', ...
            height(rows)), 's');
        value = str2double(raw);
        if isfinite(value) && value == round(value) && ...
                value >= 1 && value <= height(rows)
            index = value;
            return;
        end
        fprintf('Enter one listed row number.\n');
    end
end

function values = numeric_or_text_column(rows, name)
    if ~ismember(name, rows.Properties.VariableNames)
        values = repmat("-", height(rows), 1);
        return;
    end
    values = string(rows.(name));
end

function sampleType = require_one_sample_type(rows)
    sampleType = require_one_text_value(rows, 'sample_type');
end

function value = require_one_text_value(rows, name)
    if ~ismember(name, rows.Properties.VariableNames)
        error('OCE:Workflow:MissingAcquisitionMetadata', ...
            'Sub-experiment rows are missing required column %s.', name);
    end
    values = strtrim(string(rows.(name)));
    values = unique(values(~ismissing(values) & strlength(values) > 0), 'stable');
    if numel(values) ~= 1
        error('OCE:Workflow:AmbiguousAcquisitionMetadata', ...
            'Each sub-experiment must contain exactly one %s.', name);
    end
    value = values(1);
end

function [inputs, configForRun, acquisitionState] = ...
        prepare_representative_context(root, subExperiment, runId, processingConfig)
    inputs = oce.acquisition.prepareProcessingInputs( ...
        root, subExperiment, runId, ...
        'Key', 'run_id', 'RequireProcessingConfig', false);
    contextConfig = make_window_options_resolvable_for_context(processingConfig);
    inputs.processing_config = contextConfig;
    inputs.processingConfigFile = '';
    configForRun = oce.config.buildProcessingConfigForAcquisition(inputs);
    measurement = oce.io.readRawAcquisition(inputs.filename, inputs.filepath);
    acquisitionState = oce.acquisition.buildAcquisitionState( ...
        measurement, configForRun);
end

function config = make_window_options_resolvable_for_context(config)
    options = config.DispersionWindowOptions;
    if string(options.center.method) == "manual_local_index" && ...
            isempty(options.center.manual_local_index)
        options.center.method = "middle";
    end
    if string(options.spatial.method) == "manual_interval_count" && ...
            isempty(options.spatial.manual_interval_count)
        options.spatial.method = "fraction_of_bmode";
    end
    if string(options.temporal.method) == "manual_interval_count" && ...
            isempty(options.temporal.manual_interval_count)
        options.temporal.method = "cycle_count";
    end
    config.DispersionWindowOptions = options;
end

function validate_window_policy_for_subexperiment(rows, processingConfig, ...
        representativeConfig, surfacePhase, filterResult, acquisitionState)
    excitationType = require_one_text_value(rows, 'excitation_type');
    if excitationType == "pulse"
        candidateConfig = representativeConfig;
        candidateConfig.FilterOptions = processingConfig.FilterOptions;
        candidateConfig.DispersionWindowOptions = ...
            processingConfig.DispersionWindowOptions;
        resolvedFilter = oce.config.resolveFilterOptions( ...
            candidateConfig, surfacePhase.values, acquisitionState.system.oct);
        oce.config.resolveDispersionAnalysisOptions( ...
            processingConfig.DispersionAnalysisOptions, resolvedFilter);
        oce.dispersion.buildWindows( ...
            candidateConfig, filterResult, ...
            acquisitionState.geometry.bmode_lateral_axis_mm, ...
            resolvedFilter, acquisitionState.geometry);
        fprintf('Validated pulse dispersion-window policy.\n');
        return;
    end

    sourceFrequencies = numeric_frequency_column(rows);
    frequencies = unique(sourceFrequencies, 'stable');
    for index = 1:numel(frequencies)
        frequencyHz = frequencies(index);
        rowIndex = find(sourceFrequencies == frequencyHz, 1);
        candidateConfig = representativeConfig;
        candidateConfig.acquisition_row = rows(rowIndex, :);
        candidateConfig.FilterOptions = processingConfig.FilterOptions;
        candidateConfig.DispersionWindowOptions = ...
            processingConfig.DispersionWindowOptions;
        try
            resolvedFilter = oce.config.resolveFilterOptions( ...
                candidateConfig, surfacePhase.values, ...
                acquisitionState.system.oct);
            [~, ~] = oce.config.resolveDispersionAnalysisOptions( ...
                processingConfig.DispersionAnalysisOptions, resolvedFilter, ...
                rows(rowIndex, :));
            oce.dispersion.buildWindows( ...
                candidateConfig, filterResult, ...
                acquisitionState.geometry.bmode_lateral_axis_mm, ...
                resolvedFilter, acquisitionState.geometry);
        catch ME
            error('OCE:Workflow:DispersionWindowFrequencyValidation', ...
                'Window policy is invalid at %.6g Hz: %s', ...
                frequencyHz, ME.message);
        end
    end
    fprintf('Validated dispersion-window policy for frequencies: %s Hz.\n', ...
        strjoin(string(frequencies), ', '));
end

function values = numeric_frequency_column(rows)
    if ~ismember('frequency_Hz', rows.Properties.VariableNames)
        error('OCE:Workflow:MissingFrequency', ...
            'experimental_log must contain frequency_Hz.');
    end
    raw = rows.frequency_Hz;
    if isnumeric(raw)
        values = double(raw(:));
    else
        values = str2double(string(raw(:)));
    end
    if any(~isfinite(values)) || any(values <= 0)
        error('OCE:Workflow:InvalidFrequency', ...
            'Every quasi-harmonic frequency_Hz value must be positive and finite.');
    end
end

function show_representative_dispersion(result, showKf, showSpeed, showPhaseGradient)
    for scanAxisIndex = 1:result.scan_axis_count
        if showKf
            oce.plotting.plotDispersionKfPreview(result, scanAxisIndex);
        end
        if showSpeed
            oce.plotting.plotSpeedDispersionPreview(result, scanAxisIndex);
        end
        if showPhaseGradient && result.phase_gradient.enabled
            oce.plotting.plotPhaseGradientPreview(result, scanAxisIndex);
        end
    end
end

function tf = ask_yes_no(prompt, defaultValue)
    if defaultValue
        suffix = ' [Y/n]: ';
    else
        suffix = ' [y/N]: ';
    end
    while true
        raw = lower(strtrim(string(input([prompt suffix], 's'))));
        if strlength(raw) == 0
            tf = defaultValue;
            return;
        end
        if any(raw == ["y", "yes", "s", "si", "sí"])
            tf = true;
            return;
        end
        if any(raw == ["n", "no"])
            tf = false;
            return;
        end
        fprintf('Answer yes/no.\n');
    end
end

function validate_positive_scalar(value, name)
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
        error('OCE:Workflow:InvalidConfiguration', ...
            '%s must be a positive finite scalar.', name);
    end
end

function result = empty_subexperiment_result()
    result = struct( ...
        'sub_experiment', "", ...
        'status', "not_started", ...
        'acquisition_mode', "", ...
        'scan_geometry', "", ...
        'oct_system_profile', "", ...
        'representative_run_id', "", ...
        'representative_filename', "", ...
        'params_path', "", ...
        'processing_config_path', "", ...
        'output_options', struct(), ...
        'batch_output', struct());
end
