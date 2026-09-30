%% SUMMARIZE_EXPERIMENT_RESULTS
% Human-facing summary across processed sub-experiments.
%
% Edit the options below and run the sections in order. Scientific summary
% calculation remains owned by oce.pipeline.runExperimentSummary.

%% 1. USER CONFIGURATION

experiment_root = "E:\OCE_Experiments\<experiment>";

% Use "all" or an explicit string vector of sub-experiment names.
subexperiments_to_include = "all";

% Leave empty to use the maintained default for experiment_type/excitation_type.
% Uniaxial quasi-harmonic default:
% group_keys = ["strain_percent", "frequency_Hz"];
% Uniaxial pulse default:
% group_keys = "strain_percent";
group_keys = strings(1, 0);
repetition_key = "rep_id";

% Pulse-only dispersion samples used for polar summaries. Leave empty to disable.
pulse_sample_frequencies_hz = [];
% pulse_sample_frequencies_hz = [1000 1500 2000 2500 3000];

% Comparative experiment plots. run_plots=false disables all plot output.
plot_options = struct( ...
    'phase_speed_vs_frequency', true, ...
    'phase_speed_polar', true);
run_plots = true;

% Experimental log and persistence controls.
experimental_log_sheet = "Experiment";
export_table = true;
save_summary = true;

%% 2. INITIALIZE REPOSITORY

% Resolve this script from the active MATLAB Editor file so Run Section works
% regardless of the current MATLAB folder.
workflow_file = matlab.desktop.editor.getActiveFilename;
if isempty(workflow_file)
    error('OCE:Workflow:CannotLocateDriver', ...
        ['Could not determine the active workflow file. Open ' ...
         'summarize_experiment_results.m in the MATLAB Editor.']);
end
repository_root = fileparts(fileparts(workflow_file));
startup_file = fullfile(repository_root, 'startup.m');
assert(isfile(startup_file), ...
    'Could not locate repository startup.m: %s', startup_file);
run(startup_file);

%% 3. RUN EXPERIMENT SUMMARY

[experiment, table_output] = oce.pipeline.runExperimentSummary( ...
    experiment_root, ...
    'SubExperiments', subexperiments_to_include, ...
    'GroupKeys', group_keys, ...
    'RepetitionKey', repetition_key, ...
    'Sheet', experimental_log_sheet, ...
    'RunPlots', run_plots, ...
    'PlotOptions', plot_options, ...
    'SampleFrequenciesHz', pulse_sample_frequencies_hz, ...
    'ExportTable', export_table, ...
    'SaveSummary', save_summary);
