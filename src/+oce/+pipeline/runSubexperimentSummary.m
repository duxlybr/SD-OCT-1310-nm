function [experiment, tableOutput] = runSubexperimentSummary( ...
        experimentRoot, subExperiment, varargin)
%RUNSUBEXPERIMENTSUMMARY Run the complete sub-experiment result summary.

    if nargin < 2
        error('MATLAB:minrhs', 'Not enough input arguments.');
    end

    parser = inputParser;
    addParameter(parser, 'GroupKeys', "frequency_Hz", ...
        @(x) ischar(x) || isstring(x) || iscellstr(x));
    addParameter(parser, 'RepetitionKey', "rep_id", ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'RootDir', "", @(x) ischar(x) || isstring(x));
    addParameter(parser, 'MissingResultMode', "skip", ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'DuplicateMode', "error", ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'RunPlots', true, @islogical);
    addParameter(parser, 'RunFrequencyPlots', true, @islogical);
    addParameter(parser, 'PlotOptions', struct(), ...
        @(x) isstruct(x) && isscalar(x));
    addParameter(parser, 'SampleFrequenciesHz', [], ...
        @(x) isempty(x) || (isnumeric(x) && isvector(x) && ...
        all(isfinite(x)) && all(x > 0)));
    addParameter(parser, 'ExportTable', true, @islogical);
    addParameter(parser, 'SaveSummary', true, @islogical);
    addParameter(parser, 'SummaryFileName', "summary.mat", ...
        @(x) ischar(x) || isstring(x));
    parse(parser, varargin{:});

    experimentRoot = string(experimentRoot);
    subExperiment = string(subExperiment);
    rootDir = string(parser.Results.RootDir);
    if strlength(rootDir) == 0
        rootDir = fullfile(experimentRoot, "Results", subExperiment);
    end

    groupKeys = string(parser.Results.GroupKeys);
    repetitionKey = string(parser.Results.RepetitionKey);
    plotOptions = resolveSummaryPlotOptions(parser.Results.PlotOptions);
    fprintf('\nSub-experiment results summary\n');
    fprintf('------------------------------\n');
    fprintf('Experiment root: %s\n', experimentRoot);
    fprintf('Sub-experiment:  %s\n', subExperiment);
    fprintf('Root dir:        %s\n', rootDir);
    fprintf('Group keys:      %s\n', strjoin(groupKeys, ', '));
    fprintf('Repetition key:  %s\n', repetitionKey);

    experiment = oce.results.buildSubexperimentResultSet( ...
        experimentRoot, subExperiment, groupKeys, repetitionKey, ...
        "MissingResultMode", parser.Results.MissingResultMode, ...
        "DuplicateMode", parser.Results.DuplicateMode);
    excitationType = get_excitation_type(experiment);
    experiment.metadata.excitation_type = excitationType;
    sampleFrequenciesHz = double(parser.Results.SampleFrequenciesHz(:));
    if excitationType ~= "pulse" && ~isempty(sampleFrequenciesHz)
        error('OCE:Results:PulseSamplingOnly', ...
            'SampleFrequenciesHz is only valid for pulse excitation.');
    end

    experiment = oce.results.alignDispersionFrequencies(experiment);
    experiment = oce.results.summarizeRepetitions(experiment);
    if excitationType == "pulse" && ~isempty(sampleFrequenciesHz)
        experiment = oce.results.summarizeDispersionSamples( ...
            experiment, sampleFrequenciesHz);
    end
    experiment = oce.results.summarizeAngles(experiment);

    if parser.Results.RunPlots
        if plotOptions.phase_speed_polar && ...
                (excitationType ~= "pulse" || ...
                isfield(experiment.summary, 'dispersion_sampling'))
            oce.plotting.summary.savePhaseSpeedPolarSummary(experiment, rootDir);
        end
        if plotOptions.thickness_polar
            oce.plotting.summary.saveThicknessPolarSummary(experiment, rootDir);
        end
        if plotOptions.repetition_averaged_dispersion
            oce.plotting.summary.saveRepetitionAveragedDispersionSummary( ...
                experiment, rootDir);
        end
        if plotOptions.angle_averaged_dispersion
            oce.plotting.summary.saveAngleAveragedDispersionSummary( ...
                experiment, rootDir);
        end

        frequencyPlotsRequested = parser.Results.RunFrequencyPlots && ...
            excitationType ~= "pulse" && ...
            (plotOptions.phase_speed_vs_frequency || ...
            plotOptions.angle_averaged_phase_speed_vs_frequency);
        if frequencyPlotsRequested
            if has_frequency_dimension(experiment)
                if plotOptions.phase_speed_vs_frequency
                    oce.plotting.summary.savePhaseSpeedVsFrequencyByAngle( ...
                        experiment, rootDir);
                end
                if plotOptions.angle_averaged_phase_speed_vs_frequency
                    oce.plotting.summary.savePhaseSpeedVsFrequencyAngleAveraged( ...
                        experiment, rootDir);
                end
            else
                warning(['Skipping frequency plots because frequency_Hz ' ...
                    'is not a design dimension.']);
            end
        end
    end

    tableOutput = table();
    if parser.Results.ExportTable
        tableOutput = oce.io.exportConditionSummaryTable(experiment, rootDir);
    end
    if parser.Results.SaveSummary
        summaryPath = fullfile(rootDir, string(parser.Results.SummaryFileName));
        oce.io.saveResultsSummary(summaryPath, experiment, tableOutput, ...
            parser.Results.ExportTable);
        fprintf('Saved summary file:\n%s\n', summaryPath);
    end
    fprintf('Sub-experiment results summary complete.\n');
end

function value = get_excitation_type(experiment)
    sourceTable = experiment.source.acquisition_table;
    if ~ismember('excitation_type', sourceTable.Properties.VariableNames)
        error('Sub-experiment metadata are missing excitation_type.');
    end
    values = unique(strtrim(string(sourceTable.excitation_type)), 'stable');
    values = values(~ismissing(values) & strlength(values) > 0);
    if numel(values) ~= 1
        error('Sub-experiment must contain exactly one excitation_type.');
    end
    value = values(1);
end

function tf = has_frequency_dimension(experiment)
    tf = isfield(experiment, 'design') && ...
        isfield(experiment.design, 'dimension_keys') && ...
        any(strcmp(string(experiment.design.dimension_keys), "frequency_Hz"));
end
