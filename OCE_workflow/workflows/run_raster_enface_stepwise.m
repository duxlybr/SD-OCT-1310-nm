%#ok<*UNRCH>
% Intentional: editable false-by-default section toggles appear unreachable to Code Analyzer.
%% 0. INITIALIZATION
% Stepwise processing of one raster acquisition up to filtered surface motion
% and its en-face (XY) wave-propagation video. Run sections in order. After
% changing an upstream setting, rerun that section and every downstream one.
%
% Raster positions are acquired in MB mode with one excitation trigger per
% position, so equal time samples across positions form one en-face frame.
% k-f dispersion analysis is not available for raster geometry: its directional
% windows assume angular B-modes centered on the excitation.
%
% --- USER OPTIONS ---
manual_show_progress = true;  % true | false

% --- EXECUTION ---
workflow_file = matlab.desktop.editor.getActiveFilename;
if isempty(workflow_file)
    error('OCE:Workflow:CannotLocateDriver', ...
        ['Could not determine the active workflow file. Open ' ...
         'run_raster_enface_stepwise.m in the MATLAB Editor.']);
end
repository_root = fileparts(fileparts(workflow_file));
startup_file = fullfile(repository_root, 'startup.m');
assert(isfile(startup_file), ...
    'Could not locate repository startup.m: %s', startup_file);
% Another OCE_workflow checkout already on the path (e.g. main next to a
% worktree) would shadow this repository's packages; keep only this one.
current_paths = string(strsplit(path, pathsep));
foreign_paths = current_paths(contains(current_paths, ...
    filesep + "OCE_workflow" + filesep) & ...
    ~startsWith(current_paths, string(repository_root), 'IgnoreCase', true));
if ~isempty(foreign_paths)
    rmpath(foreign_paths{:});
    clear functions
end
run(startup_file);
assert(startsWith(string(which('oce.acquisition.buildAcquisitionGeometry')), ...
    string(repository_root), 'IgnoreCase', true), ...
    'The oce package resolves outside %s. Run restoredefaultpath and retry.', ...
    repository_root);

%% 1. ACQUISITION SELECTION
% Select one standalone raster .bin acquisition.
%
% --- EXECUTION ---
[selected_file, selected_path] = uigetfile( ...
    {'*.bin', 'OCE binary acquisitions (*.bin)'}, ...
    'Select raster OCE acquisition');
if isequal(selected_file, 0)
    error('OCE:Workflow:AcquisitionSelectionCancelled', ...
        'No acquisition file was selected.');
end
bin_file = string(fullfile(selected_path, selected_file));
bin_directory = string(selected_path);
filename = string(selected_file);

%% 2. ACQUISITION PARAMETER PREPARATION
% The raw file is read once (uint16 digitizer counts) and reused below.
% The depth preview concatenates every B-scan of the raster.
%
% --- USER OPTIONS ---
% oct_system_profile: "swept_source_1300" | "spectral_domain_1040" | "spectral_domain_1310"
oct_system_profile = "spectral_domain_1310";
acquisition_mode = "mb_mode";
scan_geometry = "raster";

% Crop selection: "interactive" | "manual_indices".
% The complex reconstruction holds lateral x depth x time complex doubles;
% keep the depth crop tight around the sample surface for large rasters.
crop_options = struct();
crop_options.depth = struct( ...
    'selection', "interactive", ...
    'start_index_inclusive', [], ...
    'end_index_inclusive', [], ...
    'bmode_intensity_limits_db', []);
crop_options.time = struct( ...
    'selection', "manual_indices", ...
    'start_index_inclusive', 1, ...
    'end_index_inclusive', []);  % [] = last M-repetition

% --- EXECUTION ---
if crop_options.time.selection == "manual_indices" && ...
        isempty(crop_options.time.end_index_inclusive)
    header = oce.io.readAcquisitionHeader(filename, bin_directory);
    crop_options.time.end_index_inclusive = header.Alines_in_Bframe;
end
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
% --- USER OPTIONS ---
% sample_type: "phantom" | "in_vivo_eye" | "ex_vivo_eye"
sample_type = "phantom";
% excitation_type: "quasi_harmonic" | "pulse" (pulse uses frequency_Hz = NaN).
excitation_type = "quasi_harmonic";
frequency_Hz = 500;

% --- EXECUTION ---
acquisition_metadata = struct( ...
    'sample_type', sample_type, ...
    'excitation_type', excitation_type, ...
    'frequency_Hz', frequency_Hz);

processing_config = oce.config.getDefaultProcessingConfig(sample_type);
processing_config.OCTSystemOptions = oct_system_options;
processing_config.AcquisitionOptions = struct( ...
    'acquisition_mode', acquisition_mode, ...
    'scan_geometry_selection', "manual", ...
    'scan_geometry', scan_geometry);

results_directory = fullfile(bin_directory, "Results");
processing_inputs = oce.acquisition.prepareSingleFileInputs( ...
    bin_file, acquisition_parameters, acquisition_metadata, ...
    processing_config, 'ResultsDirectory', results_directory);
config_for_run = oce.config.buildProcessingConfigForAcquisition( ...
    processing_inputs);

%% 4. RECONSTRUCTION
% Raster geometry: one B-mode is one B-scan along x; B-modes step along y
% (acquisition_state.geometry.raster).
%
% --- USER OPTIONS ---
release_raw_spectra = true;  % free raw memory once reconstruction exists

% --- EXECUTION ---
acquisition_state = oce.acquisition.buildAcquisitionState( ...
    measurement, config_for_run, 'ShowProgress', manual_show_progress);
reconstruction_result = acquisition_state.reconstruction;
if release_raw_spectra
    % Downstream stages consume the reconstruction only.
    acquisition_state.raw.spectra = [];
    clear measurement
end

%% 4A. OPTIONAL STRUCTURAL EN-FACE
% Depth-averaged structural map. Each position first averages the OCT
% amplitude of N M-repetitions (A-scan averaging), then averages linearly
% over the selected depth range of the reconstructed crop.
%
% --- USER OPTIONS ---
export_structural_enface = true;       % true | false
structural_average_count = 50;         % N M-repetitions per A-scan
structural_first_m_repetition = [];    % [] = first retained repetition
structural_depth_range = [];           % [] = whole depth crop | [first last]
structural_display_limits_db = [];     % [] = automatic | [low high]

% --- EXECUTION ---
structural_enface_artifacts = strings(0, 1);
if export_structural_enface
    structural_enface = oce.acquisition.computeStructuralEnface( ...
        reconstruction_result, acquisition_state.geometry, ...
        'AScanAverageCount', structural_average_count, ...
        'FirstMRepetition', structural_first_m_repetition, ...
        'DepthRangeIndices', structural_depth_range);
    structural_enface_artifacts = oce.plotting.saveStructuralEnface( ...
        structural_enface, results_directory, ...
        'DisplayLimitsDb', structural_display_limits_db);
    fprintf('Structural en-face written to:\n%s\n', ...
        structural_enface_artifacts(end));
end

%% 5. BORDER DETECTION
% Borders remain independent per B-scan.
%
% --- USER OPTIONS ---
border_tuning = "interactive";  % "interactive" | "headless"
phantom_surface_mode = "anterior_only";
processing_config.BorderOptions.mask_threshold = 42;

% --- EXECUTION ---
processing_config.BorderOptions.methods.phantom.surface_mode = ...
    phantom_surface_mode;
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
        config_for_run.BorderOptions = oce.config.resolveBorderOptions( ...
            processing_config.BorderOptions, ...
            processing_inputs.acquisition_row, config_for_run.resolved_crop);
        border_result = oce.borders.detectAndMask( ...
            acquisition_state, config_for_run.BorderOptions);
    otherwise
        error('OCE:Workflow:InvalidBorderTuning', ...
            'border_tuning must be "interactive" or "headless".');
end

%% 6. SURFACE PHASE ESTIMATION
% The en-face video uses the anterior-surface phase. Depth-resolved phase is
% not computed here: it is not needed for XY propagation and is large for rasters.
%
% --- USER OPTIONS ---
processing_config.MotionOptions.surface.depth_offset_samples = 0;
processing_config.MotionOptions.surface.aggregation_band_samples = 6;
processing_config.MotionOptions.surface.loupas.axial_window_samples = 20;
processing_config.MotionOptions.surface.smoothing.span_fraction = 0.05;

% --- EXECUTION ---
processing_config.MotionOptions.show_progress = manual_show_progress;
config_for_run.MotionOptions = oce.config.resolvePhaseEstimationOptions( ...
    processing_config.MotionOptions);
surface_phase_result = oce.motion.computeSurfacePhase( ...
    reconstruction_result.complex_volume.values, ...
    border_result.indices.anterior, config_for_run.MotionOptions);

%% 7. SURFACE TEMPORAL FILTERING
% automatic -> center frequency comes from acquisition metadata.
% manual    -> use manual_passband_hz or select limits on the FFT display.
%
% --- USER OPTIONS ---
filter_frequency_selection = "manual";  % "automatic" | "manual"
manual_passband_hz = [];                    % [] | [low high] Hz
processing_config.FilterOptions.enabled = true;
processing_config.FilterOptions.order = 100;
processing_config.FilterOptions.frequency.bandwidth.fraction = 0.65;

% --- EXECUTION ---
if excitation_type == "pulse" && filter_frequency_selection ~= "manual"
    error('OCE:Workflow:PulseFilterSelection', ...
        ['Pulse excitation has no automatic center frequency. Use ' ...
         'filter_frequency_selection="manual".']);
end
switch filter_frequency_selection
    case "automatic"
        processing_config.FilterOptions.frequency.selection_source = ...
            "acquisition_row";
    case "manual"
        if isempty(manual_passband_hz)
            processing_config.FilterOptions = ...
                oce.interaction.selectTemporalFilterPassband( ...
                    surface_phase_result.values, config_for_run, ...
                    acquisition_state.system.oct, ...
                    acquisition_state.geometry, ...
                    processing_config.FilterOptions);
        else
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
            'filter_frequency_selection must be "automatic" or "manual".');
end
config_for_run.FilterOptions = processing_config.FilterOptions;
[filter_result, config_for_run.FilterOptions] = ...
    oce.filtering.filterSurfacePhase( ...
        surface_phase_result, config_for_run, ...
        acquisition_state.system.oct, acquisition_state.geometry);

%% 7A. OPTIONAL EN-FACE SNAPSHOTS
% Display-only: temporal mean removed per position, spatial median per frame.
%
% --- USER OPTIONS ---
show_enface_snapshots = true;  % true | false
enface_clim_mode = "robust";   % "auto" | "robust" | "manual"
enface_clim = [];              % [] unless enface_clim_mode="manual"
enface_median_window = [3 3];  % [] disables the display median

% --- EXECUTION ---
if show_enface_snapshots
    oce.plotting.plotEnfaceMotionSnapshots( ...
        filter_result, reconstruction_result, acquisition_state.geometry, ...
        'SnapshotCount', 8, ...
        'CLimMode', enface_clim_mode, 'CLim', enface_clim, ...
        'MedianWindow', enface_median_window);
end

%% 8. EN-FACE MOTION VIDEO
% Independent file-generating stage. Requires the applied filter of section 7.
%
% --- USER OPTIONS ---
generate_enface_motion_video = true;  % true | false
enface_video_options = struct( ...
    'time_start_idx', 1, ...    % first displayed frame index
    'max_frames', 1000, ...     % maximum frames written
    'frame_rate', 30, ...       % frames/s
    'filename', "Video_Enface_Filtered.mp4");

% --- EXECUTION ---
enface_video_path = "";
if generate_enface_motion_video
    enface_video_path = oce.video.createEnfaceMotionVideo( ...
        filter_result, reconstruction_result, acquisition_state.geometry, ...
        enface_video_options, results_directory, ...
        'CLimMode', enface_clim_mode, 'CLim', enface_clim, ...
        'MedianWindow', enface_median_window, ...
        'ShowProgress', manual_show_progress);
    fprintf('En-face video written to:\n%s\n', enface_video_path);
end
