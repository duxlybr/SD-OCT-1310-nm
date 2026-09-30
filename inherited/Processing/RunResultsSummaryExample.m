%% RunResultsSummaryExample
% Minimal example for running the modern results-summary workflow.
%
% Before running this script:
%   1. Process the desired acquisitions with run_full_processing_single or run_batch_processing.
%   2. Confirm that PhaseSpeed.mat exists in Results/<subExperiment>/<run_id>/.
%   3. Confirm that AcquisitionParams_<subExperiment>.mat exists in Params/<subExperiment>/.

clc; clear; close all;

%% User settings
experimentRoot = "F:\OCE_Experiments\<experiment>";
subExperiment  = "<subExperiment>";

% Define the experimental condition dimensions and repetition dimension.
% Common examples:
%   GroupKeys     = "frequency_Hz";
%   GroupKeys     = ["frequency_Hz", "voltage_mVpp"];
%   RepetitionKey = "rep_id";
GroupKeys     = "frequency_Hz";
RepetitionKey = "rep_id";

%% Run summary workflow
experiment = run_results_summary( ...
    experimentRoot, ...
    subExperiment, ...
    "GroupKeys", GroupKeys, ...
    "RepetitionKey", RepetitionKey, ...
    "MissingResultMode", "skip", ...
    "RunPlots", true, ...
    "RunFrequencyPlots", true, ...
    "SaveSummary", true, ...
    "AssignToBase", true);

%% Quick checks
disp(experiment.design);
disp(experiment.summary);

summaryPath = fullfile(experimentRoot, "Results", subExperiment, "summary.mat");
figuresPath = fullfile(experimentRoot, "Results", subExperiment, "Summary Figures");

fprintf('\nSummary file:\n%s\n', summaryPath);
fprintf('Summary figures folder:\n%s\n', figuresPath);
