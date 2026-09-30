function [experiment, tableOutput] = runExperimentSummary( ...
        experimentRoot, varargin)
%RUNEXPERIMENTSUMMARY Summarize persisted results across sub-experiments.
%
% The maintained uniaxial-prestrain quasi-harmonic default is:
%   dimensions = strain_percent x frequency_Hz x rep_id
%   figure     = one scan axis per figure
%   curves     = strain_percent
%   x          = frequency_Hz
%   y          = paired left/right phase speed
%
% Pulse experiment summaries use the same scan-axis comparison geometry for
% full dispersion curves. Angular detail remains available through polar plots.
%
% Persisted PhaseSpeed.mat files are consumed as-is. No acquisition or
% scientific-processing stage is rerun by this summary coordinator.

    if nargin < 1
        error('MATLAB:minrhs', 'experimentRoot is required.');
    end

    parser = inputParser;
    addParameter(parser, 'SubExperiments', "all", ...
        @(x) ischar(x) || isstring(x) || iscellstr(x));
    addParameter(parser, 'GroupKeys', strings(1, 0), ...
        @(x) ischar(x) || isstring(x) || iscellstr(x));
    addParameter(parser, 'RepetitionKey', "rep_id", ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'Sheet', "Experiment", ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'MissingResultMode', "skip", ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'DuplicateMode', "error", ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'OutputDirectory', "", ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'RunPlots', true, @islogical);
    addParameter(parser, 'PlotOptions', struct(), ...
        @(x) isstruct(x) && isscalar(x));
    addParameter(parser, 'SampleFrequenciesHz', [], ...
        @(x) isempty(x) || (isnumeric(x) && isvector(x) && ...
        all(isfinite(x)) && all(x > 0)));
    addParameter(parser, 'ExportTable', true, @islogical);
    addParameter(parser, 'SaveSummary', true, @islogical);
    addParameter(parser, 'SummaryFileName', "experiment_scan_axis_summary.mat", ...
        @(x) ischar(x) || isstring(x));
    parse(parser, varargin{:});

    experimentRoot = string(experimentRoot);
    logPath = fullfile(experimentRoot, 'experimental_log.xlsx');
    acquisitionTable = oce.io.loadExperimentalLog( ...
        logPath, ...
        'Sheet', parser.Results.Sheet, ...
        'SaveAcquisitionParams', false);

    subExperiments = resolve_subexperiments( ...
        parser.Results.SubExperiments, acquisitionTable);
    selectedRows = ismember(string(acquisitionTable.sub_experiment), subExperiments);
    selectedTable = acquisitionTable(selectedRows, :);
    if isempty(selectedTable)
        error('No acquisition rows matched the selected sub-experiments.');
    end

    experimentType = require_one_text_value(selectedTable, 'experiment_type');
    excitationType = require_one_text_value(selectedTable, 'excitation_type');
    acquisitionMode = require_one_text_value(selectedTable, 'acquisition_mode');
    scanGeometry = require_one_text_value(selectedTable, 'scan_geometry');
    octSystemProfile = require_one_text_value(selectedTable, 'oct_system_profile');

    groupKeys = string(parser.Results.GroupKeys);
    groupKeys = groupKeys(strlength(strtrim(groupKeys)) > 0);
    if isempty(groupKeys)
        groupKeys = default_group_keys(experimentType, excitationType);
    end
    repetitionKey = string(parser.Results.RepetitionKey);
    validate_design_metadata(selectedTable, groupKeys, repetitionKey);
    plotOptions = resolveSummaryPlotOptions(parser.Results.PlotOptions);

    sampleFrequenciesHz = double(parser.Results.SampleFrequenciesHz(:));
    if excitationType ~= "pulse" && ~isempty(sampleFrequenciesHz)
        error('OCE:Results:PulseSamplingOnly', ...
            'SampleFrequenciesHz is only valid for pulse excitation.');
    end

    outputDirectory = string(parser.Results.OutputDirectory);
    if strlength(outputDirectory) == 0
        outputDirectory = fullfile(experimentRoot, 'Results', 'ExperimentSummary');
    end

    fprintf('\nExperiment results summary\n');
    fprintf('--------------------------\n');
    fprintf('Experiment root:  %s\n', experimentRoot);
    fprintf('Experiment type:  %s\n', experimentType);
    fprintf('Excitation type:  %s\n', excitationType);
    fprintf('Sub-experiments:  %s\n', strjoin(subExperiments, ', '));
    fprintf('Group keys:       %s\n', strjoin(groupKeys, ', '));
    fprintf('Repetition key:   %s\n', repetitionKey);
    fprintf('Output directory: %s\n', outputDirectory);

    experiment = oce.results.buildExperimentResultSet( ...
        experimentRoot, subExperiments, groupKeys, repetitionKey, ...
        'MissingResultMode', parser.Results.MissingResultMode, ...
        'DuplicateMode', parser.Results.DuplicateMode);
    experiment.metadata.experiment_type = experimentType;
    experiment.metadata.excitation_type = excitationType;
    experiment.metadata.acquisition_mode = acquisitionMode;
    experiment.metadata.scan_geometry = scanGeometry;
    experiment.metadata.oct_system_profile = octSystemProfile;
    experiment.metadata.outputDirectory = char(outputDirectory);

    if excitationType == "pulse"
        experiment = oce.results.alignDispersionFrequencies(experiment);
    end
    experiment = oce.results.summarizeRepetitions(experiment);
    if excitationType == "pulse" && ~isempty(sampleFrequenciesHz)
        experiment = oce.results.summarizeDispersionSamples( ...
            experiment, sampleFrequenciesHz);
    end
    experiment = oce.results.summarizeScanAxes(experiment);
    if excitationType == "pulse"
        experiment = oce.results.summarizeAngles(experiment);
    end

    if parser.Results.RunPlots
        if plotOptions.phase_speed_vs_frequency
            oce.plotting.summary.savePhaseSpeedVsFrequencyByScanAxis( ...
                experiment, outputDirectory);
        end

        savePolar = false;
        polarArgs = {};
        if excitationType == "pulse"
            savePolar = plotOptions.phase_speed_polar && ...
                isfield(experiment.summary, 'dispersion_sampling');
            if savePolar && any(groupKeys == "strain_percent")
                polarArgs = {'OverlayDimension', 'strain_percent'};
            end
        elseif plotOptions.phase_speed_polar && ...
                any(groupKeys == "strain_percent") && ...
                any(groupKeys == "frequency_Hz")
            savePolar = true;
            polarArgs = {'OverlayDimension', 'strain_percent'};
        end

        if savePolar
            oce.plotting.summary.savePhaseSpeedPolarSummary( ...
                experiment, outputDirectory, polarArgs{:});
        end
    end

    tableOutput = table();
    if parser.Results.ExportTable
        tableOutput = oce.io.exportScanAxisSummaryTable( ...
            experiment, outputDirectory);
    end

    if parser.Results.SaveSummary
        summaryPath = fullfile( ...
            outputDirectory, string(parser.Results.SummaryFileName));
        oce.io.saveResultsSummary( ...
            summaryPath, experiment, tableOutput, parser.Results.ExportTable);
        fprintf('Saved experiment summary:\n%s\n', summaryPath);
    end

    fprintf('Experiment results summary complete.\n');
end

function subExperiments = resolve_subexperiments(requested, acquisitionTable)
    available = unique(string(acquisitionTable.sub_experiment), 'stable');
    requested = string(requested(:));

    if isscalar(requested) && strcmpi(strtrim(requested), "all")
        subExperiments = available;
        return;
    end

    requested = unique(strtrim(requested), 'stable');
    requested = requested(strlength(requested) > 0);
    missing = setdiff(requested, available, 'stable');
    if ~isempty(missing)
        error('Unknown sub-experiment(s): %s.', strjoin(missing, ', '));
    end
    subExperiments = requested;
end

function value = require_one_text_value(T, fieldName)
    if ~ismember(fieldName, T.Properties.VariableNames)
        error('Canonical metadata column is missing: %s.', fieldName);
    end
    values = string(T.(fieldName));
    values = unique(strtrim(values(~ismissing(values) & strlength(strtrim(values)) > 0)));
    if numel(values) ~= 1
        error(['Selected sub-experiments must contain exactly one %s value; ' ...
            'found: %s.'], fieldName, strjoin(values, ', '));
    end
    value = values(1);
end

function groupKeys = default_group_keys(experimentType, excitationType)
    switch experimentType
        case "uniaxial_prestrain"
            if excitationType == "pulse"
                groupKeys = "strain_percent";
            else
                groupKeys = ["strain_percent", "frequency_Hz"];
            end
        otherwise
            error(['No default experiment-summary dimensions are defined for ' ...
                'experiment_type="%s". Supply GroupKeys explicitly.'], ...
                experimentType);
    end
end

function validate_design_metadata(T, groupKeys, repetitionKey)
    required = [groupKeys repetitionKey];
    missing = setdiff(required, string(T.Properties.VariableNames), 'stable');
    if ~isempty(missing)
        error('Selected metadata are missing design column(s): %s.', ...
            strjoin(missing, ', '));
    end

    for index = 1:numel(required)
        key = char(required(index));
        values = string(T.(key));
        if any(ismissing(values) | strlength(strtrim(values)) == 0)
            error('Selected rows contain blank values for design key: %s.', key);
        end
    end
end
