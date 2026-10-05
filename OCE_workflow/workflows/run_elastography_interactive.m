%% 0. INITIALIZATION
% Open this script in MATLAB and execute sections in order.
% New local maps are opt-in; the established acquisition workflow is unchanged.
workflow_file = matlab.desktop.editor.getActiveFilename;
assert(~isempty(workflow_file),'Open this workflow in the MATLAB Editor.');
repository_root = fileparts(fileparts(workflow_file));
startup_file = fullfile(repository_root, 'startup.m');
assert(isfile(startup_file),'Cannot locate the OCE workflow repository.');
current_paths = string(strsplit(path,pathsep));
foreign_paths = current_paths(contains(current_paths,filesep+"OCE_workflow"+filesep) & ...
    ~startsWith(current_paths,string(repository_root),'IgnoreCase',true));
if ~isempty(foreign_paths), rmpath(foreign_paths{:}); clear functions; end
run(startup_file);

%% 1. INPUT MODE AND MATERIAL ASSUMPTIONS
% "bin": file selector / streaming BIN, or a MAT containing data.
% "stepwise": reuse acquisition_state + phase_result + border_result from
% run_acquisition_stepwise; no BIN reread, FFT or phase calculation here.
input_mode = "bin";  % "bin" | "stepwise"
source_file = [];
% Legacy Luis3: frequency_hz=1000. Legacy raster: frequency_hz=2000.
% New metadata overrides this initial frequency when it is available.
initial_options = struct('frequency_hz', 1000, 'young_model', "none");
% Young starts disabled; choose the physical wave model explicitly in the UI.

% Used only in stepwise mode; rerun section 2 to change plane/depth/B-mode.
plane_options = struct('plane_type', "auto", 'bmode_index', 1, ...
    'depth_offset_mm', 0, 'depth_band_mm', .04, ...
    'phase_registration_status', "unverified");

%% 2. BUILD THE PLANE AND OPEN INTERACTIVE EXPLORATION
switch input_mode
    case "bin"
        wave_source = source_file;
    case "stepwise"
        assert(exist('acquisition_state','var')==1 && exist('phase_result','var')==1 && ...
            exist('border_result','var')==1, ...
            'Run reconstruction, border detection and depth phase in the stepwise workflow first.');
        wave_source = oce.acquisition.buildWaveMotionPlane( ...
            acquisition_state, phase_result, border_result, plane_options);
    otherwise
        error('OCE:Workflow:InvalidWaveInput','input_mode must be bin or stepwise.');
end
wave_map_ui = oce.interaction.tuneWaveSpeedMaps(wave_source, initial_options);
% For a memory plane, acquisition controls are locked: rebuild it here after
% revising borders/geometry/depth in stepwise. Estimator controls stay live.

%% 3. INSPECT THE LAST ACCEPTED NUMERICAL PRODUCT
% Execute this section after pressing Recalcular in the application.
wave_map_session = wave_map_ui.UserData;
% wave_map_session.speed_result.speed_m_s is the unsmoothed measurement.
% wave_map_session.young_result.young_pa carries the selected model's limits.
