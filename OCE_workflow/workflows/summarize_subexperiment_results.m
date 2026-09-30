%% SUMMARIZE_SUBEXPERIMENT_RESULTS
% Human-facing summary of one or more processed sub-experiments.
%
% Edit the options below and run the sections in order. Scientific summary
% calculation remains owned by oce.pipeline.runSubexperimentSummary.

%% 1. USER CONFIGURATION

experiment_root = "E:\OCE_Experiments\<experiment>";

% Use "all", one name, or an explicit string vector.
subexperiments_to_summarize = "all";

% Experimental design used to group processed acquisitions.
% Quasi-harmonic example: group_keys = "frequency_Hz";
% Pulse example: group_keys = "strain_percent";
group_keys = "frequency_Hz";
repetition_key = "rep_id";
experimental_log_sheet = "Experiment";

% Pulse-only dispersion samples used for polar summaries. Leave empty to disable.
pulse_sample_frequencies_hz = [];
% pulse_sample_frequencies_hz = [1000 1500 2000 2500 3000];

% Summary plot controls. run_plots=false disables all plot output.
% The phase-speed-vs-frequency controls are quasi-harmonic only; pulse c(f)
% is already represented by the repetition/angle dispersion summaries.
run_plots = true;
plot_options = struct( ...
    'phase_speed_vs_frequency', true, ...
    'phase_speed_polar', true, ...
    'thickness_polar', true, ...
    'repetition_averaged_dispersion', true, ...
    'angle_averaged_dispersion', true, ...
    'angle_averaged_phase_speed_vs_frequency', false);
export_table = true;
save_summary = true;

%% 2. INITIALIZE REPOSITORY

% Resolve this script from the active MATLAB Editor file so Run Section works
% regardless of the current MATLAB folder.
workflow_file = matlab.desktop.editor.getActiveFilename;
if isempty(workflow_file)
    error('OCE:Workflow:CannotLocateDriver', ...
        ['Could not determine the active workflow file. Open ' ...
         'summarize_subexperiment_results.m in the MATLAB Editor.']);
end
repository_root = fileparts(fileparts(workflow_file));
startup_file = fullfile(repository_root, 'startup.m');
assert(isfile(startup_file), ...
    'Could not locate repository startup.m: %s', startup_file);
run(startup_file);

%% 3. RESOLVE SUB-EXPERIMENTS

log_path = fullfile(experiment_root, "experimental_log.xlsx");
acquisition_table = oce.io.loadExperimentalLog( ...
    log_path, ...
    'Sheet', experimental_log_sheet, ...
    'SaveAcquisitionParams', false);

available_subexperiments = unique( ...
    string(acquisition_table.sub_experiment), 'stable');

requested_subexperiments = string(subexperiments_to_summarize(:));
if isscalar(requested_subexperiments) && ...
        strcmpi(strtrim(requested_subexperiments), "all")
    subexperiments = available_subexperiments;
else
    subexperiments = unique(strtrim(requested_subexperiments), 'stable');
    subexperiments = subexperiments(strlength(subexperiments) > 0);

    missing_subexperiments = setdiff( ...
        subexperiments, available_subexperiments, 'stable');
    if ~isempty(missing_subexperiments)
        error('OCE:Workflow:UnknownSubexperiment', ...
            'Unknown sub-experiment(s): %s.', ...
            strjoin(missing_subexperiments, ', '));
    end
end

if isempty(subexperiments)
    error('OCE:Workflow:NoSubexperiments', ...
        'No sub-experiments were selected for summary.');
end

%% 4. RUN SUB-EXPERIMENT SUMMARIES

summary_results = repmat(struct( ...
    'sub_experiment', "", ...
    'experiment', [], ...
    'table', table()), numel(subexperiments), 1);

for sub_index = 1:numel(subexperiments)
    sub_experiment = subexperiments(sub_index);

    fprintf('\n============================================================\n');
    fprintf('Summarizing sub-experiment %d/%d: %s\n', ...
        sub_index, numel(subexperiments), sub_experiment);
    fprintf('============================================================\n');

    [experiment, table_output] = oce.pipeline.runSubexperimentSummary( ...
        experiment_root, sub_experiment, ...
        'GroupKeys', group_keys, ...
        'RepetitionKey', repetition_key, ...
        'RunPlots', run_plots, ...
        'PlotOptions', plot_options, ...
        'SampleFrequenciesHz', pulse_sample_frequencies_hz, ...
        'ExportTable', export_table, ...
        'SaveSummary', save_summary);

    summary_results(sub_index).sub_experiment = sub_experiment;
    summary_results(sub_index).experiment = experiment;
    summary_results(sub_index).table = table_output;
end
