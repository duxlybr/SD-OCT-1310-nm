function experiment = buildSubexperimentResultSet( ...
        experimentRoot, subExperiment, groupKeys, repetitionKey, varargin)
%BUILDSUBEXPERIMENTRESULTSET Assemble one sub-experiment result set.
%
% Acquisition metadata are loaded through the canonical I/O owner. Processed
% scientific results are loaded from
% Results/<subExperiment>/<filename-without-extension>/PhaseSpeed.mat.
%
% Required inputs:
%   experimentRoot - Root experiment folder.
%   subExperiment  - Sub-experiment name.
%   groupKeys      - acquisition_table column(s) defining conditions.
%   repetitionKey  - acquisition_table column defining repetitions.
%
% Optional name-value arguments:
%   "MissingResultMode" default: "warn"  Options: "warn", "error", "skip"
%   "DuplicateMode"     default: "error" Options: "error", "first", "last"
%
% The last dimension of experiment.data is always the repetition key.

    if nargin < 4
        error('experimentRoot, subExperiment, groupKeys, and repetitionKey are required.');
    end

    parser = inputParser;
    addParameter(parser, 'MissingResultMode', 'warn', ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'DuplicateMode', 'error', ...
        @(x) ischar(x) || isstring(x));
    parse(parser, varargin{:});

    experimentRoot = char(experimentRoot);
    subExperiment = string(subExperiment);
    groupKeys = string(groupKeys(:))';
    repetitionKey = string(repetitionKey);
    dimensionKeys = [groupKeys repetitionKey];

    missingMode = lower(string(parser.Results.MissingResultMode));
    duplicateMode = lower(string(parser.Results.DuplicateMode));
    validate_mode(missingMode, ["warn", "error", "skip"], 'MissingResultMode');
    validate_mode(duplicateMode, ["error", "first", "last"], 'DuplicateMode');

    acquisitionTable = oce.io.loadAcquisitionTable( ...
        experimentRoot, subExperiment);
    validate_required_columns(acquisitionTable, dimensionKeys);

    resultsRoot = fullfile(experimentRoot, 'Results', char(subExperiment));
    [validRows, resultFiles, resultFolders] = locate_result_files( ...
        acquisitionTable, resultsRoot, missingMode);

    acquisitionTable = acquisitionTable(validRows, :);
    resultFiles = resultFiles(validRows);
    resultFolders = resultFolders(validRows);

    if height(acquisitionTable) == 0
        error('No valid processed results were found for sub-experiment: %s', ...
            subExperiment);
    end

    dimensionValues = build_dimension_values(acquisitionTable, dimensionKeys);
    dimensionUnits = infer_dimension_units(dimensionKeys);
    dimSizes = cellfun(@numel, dimensionValues);
    dataStorage = cell(dimSizes);

    sourceTable = acquisitionTable;
    sourceTable.result_folder = resultFolders;
    sourceTable.result_file = resultFiles;

    for rowIndex = 1:height(acquisitionTable)
        dimIndices = get_dimension_indices( ...
            acquisitionTable, rowIndex, dimensionKeys, dimensionValues);
        idxCell = num2cell(dimIndices);

        if ~isempty(dataStorage{idxCell{:}})
            dataStorage = handle_duplicate_assignment( ...
                dataStorage, idxCell, duplicateMode, acquisitionTable, ...
                rowIndex, dimensionKeys);
            if duplicateMode == "first"
                continue;
            end
        end

        oceResult = oce.io.loadScientificResult(resultFiles(rowIndex));
        experimentData = flatten_scientific_result(oceResult);
        experimentData.source_run_id = ...
            get_table_string(acquisitionTable, rowIndex, 'run_id');
        experimentData.source_filename = ...
            get_table_string(acquisitionTable, rowIndex, 'filename');
        experimentData.source_result_file = resultFiles(rowIndex);
        dataStorage{idxCell{:}} = experimentData;
    end

    experiment = struct();

    experiment.metadata = struct();
    experiment.metadata.experimentRoot = experimentRoot;
    experiment.metadata.subExperiment = char(subExperiment);
    experiment.metadata.resultsRoot = resultsRoot;
    experiment.metadata.loadFile = 'PhaseSpeed.mat';
    experiment.metadata.created_at = char(datetime('now'));

    experiment.design = struct();
    experiment.design.group_keys = groupKeys;
    experiment.design.repetition_key = repetitionKey;
    experiment.design.dimension_keys = dimensionKeys;
    experiment.design.dimension_values = dimensionValues;
    experiment.design.dimension_units = dimensionUnits;
    experiment.design.value_format = 'raw_table_values';

    experiment.source = struct();
    experiment.source.acquisition_table = sourceTable;
    experiment.source.result_files = resultFiles;
    experiment.source.result_folders = resultFolders;
    experiment.source.result_folder_key = "filename";

    experiment.data = dataStorage;
    experiment.result_schema = "oce_phase_speed_result";

    report_empty_cells(experiment.data);
end

function validate_mode(value, allowedValues, modeName)
    if ~ismember(value, allowedValues)
        error('%s must be one of: %s.', modeName, strjoin(allowedValues, ', '));
    end
end

function validate_required_columns(T, requiredColumns)
    actualColumns = string(T.Properties.VariableNames);
    missingColumns = setdiff(string(requiredColumns), actualColumns, 'stable');
    if ~isempty(missingColumns)
        error('Missing required column(s) in acquisition_table: %s', ...
            strjoin(missingColumns, ', '));
    end
end

function [validRows, resultFiles, resultFolders] = locate_result_files( ...
        T, resultsRoot, missingMode)
    nRows = height(T);
    validRows = true(nRows, 1);
    resultFiles = strings(nRows, 1);
    resultFolders = strings(nRows, 1);

    for rowIndex = 1:nRows
        filename = get_table_string(T, rowIndex, 'filename');
        [~, acquisitionName, ~] = fileparts(char(filename));
        resultFolder = fullfile(resultsRoot, acquisitionName);
        resultFile = fullfile(resultFolder, 'PhaseSpeed.mat');

        resultFolders(rowIndex) = string(resultFolder);
        resultFiles(rowIndex) = string(resultFile);

        if ~isfile(resultFile)
            message = sprintf('Processed result not found for row %d:\n%s', ...
                rowIndex, resultFile);
            switch missingMode
                case "error"
                    error('%s', message);
                case "warn"
                    warning('%s', message);
                    validRows(rowIndex) = false;
                case "skip"
                    validRows(rowIndex) = false;
            end
        end
    end
end

function dimensionValues = build_dimension_values(T, dimensionKeys)
    dimensionValues = cell(1, numel(dimensionKeys));
    for keyIndex = 1:numel(dimensionKeys)
        key = dimensionKeys(keyIndex);
        labels = strings(height(T), 1);
        for rowIndex = 1:height(T)
            labels(rowIndex) = format_value_for_key( ...
                get_table_string(T, rowIndex, key));
        end
        labels = labels(~ismissing(labels) & strlength(strtrim(labels)) > 0);
        dimensionValues{keyIndex} = cellstr(unique(labels, 'stable'));
    end
end

function dimensionUnits = infer_dimension_units(dimensionKeys)
    dimensionUnits = strings(1, numel(dimensionKeys));
    for keyIndex = 1:numel(dimensionKeys)
        key = string(dimensionKeys(keyIndex));
        if endsWith(key, '_Hz')
            dimensionUnits(keyIndex) = "Hz";
        elseif endsWith(key, '_kHz')
            dimensionUnits(keyIndex) = "kHz";
        elseif endsWith(key, '_us')
            dimensionUnits(keyIndex) = "us";
        elseif endsWith(key, '_ms')
            dimensionUnits(keyIndex) = "ms";
        elseif endsWith(key, '_mm')
            dimensionUnits(keyIndex) = "mm";
        elseif endsWith(key, '_um')
            dimensionUnits(keyIndex) = "um";
        elseif endsWith(key, '_mVpp')
            dimensionUnits(keyIndex) = "mVpp";
        elseif endsWith(key, '_percent')
            dimensionUnits(keyIndex) = "percent";
        else
            dimensionUnits(keyIndex) = "";
        end
    end
end

function dimIndices = get_dimension_indices(T, rowIndex, dimensionKeys, dimensionValues)
    dimIndices = zeros(1, numel(dimensionKeys));
    for keyIndex = 1:numel(dimensionKeys)
        key = dimensionKeys(keyIndex);
        label = format_value_for_key(get_table_string(T, rowIndex, key));
        idx = find(strcmp(dimensionValues{keyIndex}, char(label)), 1);
        if isempty(idx)
            error(['Could not map value "%s" for key "%s" to ' ...
                'experiment.design.dimension_values.'], label, key);
        end
        dimIndices(keyIndex) = idx;
    end
end

function dataStorage = handle_duplicate_assignment( ...
        dataStorage, idxCell, duplicateMode, T, rowIndex, dimensionKeys)
    switch duplicateMode
        case "error"
            keyValues = strings(1, numel(dimensionKeys));
            for keyIndex = 1:numel(dimensionKeys)
                keyValues(keyIndex) = format_value_for_key( ...
                    get_table_string(T, rowIndex, dimensionKeys(keyIndex)));
            end
            error('Duplicate experiment grid assignment detected for values: %s', ...
                strjoin(keyValues, ', '));
        case "first"
            return;
        case "last"
            dataStorage{idxCell{:}} = [];
    end
end

function data = flatten_scientific_result(result)
    frequency = result.dispersion.estimators.kf_ridge.frequency_axis_hz(:);
    directions = result.dispersion.estimators.kf_ridge.directions;
    sourceIndices = result.angular.source_direction_indices(:);
    orderedDirections = directions(sourceIndices);
    identities = result.dispersion.directions(sourceIndices);
    phaseGradientSpeed = ordered_phase_gradient_speed( ...
        result.dispersion.estimators.phase_gradient, sourceIndices, numel(directions));

    data = struct();
    data.full_circle_angles_deg = result.angular.full_circle_angles_deg(:);
    data.angular_phase_speed_m_per_s = result.angular.phase_speed_m_per_s(:);
    data.angular_phase_gradient_speed_m_per_s = phaseGradientSpeed;
    data.angular_mean_thickness_mm = result.angular.mean_thickness_mm(:);
    data.filter_effective_passband_hz = get_effective_filter_passband(result);
    data.direction_scan_axis_indices = reshape( ...
        [identities.scan_axis_index], [], 1);
    data.direction_names = string({identities.direction})';
    data.direction_target_phase_speed_m_per_s = reshape(arrayfun(@(item) ...
        item.target_selection.selected_phase_speed_m_per_s, ...
        orderedDirections), [], 1);
    data.direction_phase_gradient_speed_m_per_s = phaseGradientSpeed;
    data.direction_frequency_axes_hz = ...
        repmat({frequency}, numel(orderedDirections), 1);
    data.direction_temporal_diagnostic_magnitude = reshape(arrayfun(@(item) ...
        {item.spectrum.temporal_diagnostic_magnitude(:)}, ...
        orderedDirections), [], 1);
    data.direction_smoothed_phase_speed_m_per_s = reshape(arrayfun(@(item) ...
        {item.phase_speed_curve.smoothed_phase_speed_m_per_s(:)}, ...
        orderedDirections), [], 1);
end

function speed = ordered_phase_gradient_speed(gradient, sourceIndices, count)
    speed = NaN(count, 1);
    if ~gradient.enabled
        speed = speed(sourceIndices);
        return;
    end
    if numel(gradient.directions) ~= count
        error('OCE:Results:PhaseGradientDirectionCount', ...
            'Phase-gradient directions must align with common direction identities.');
    end
    speed = reshape([gradient.directions.phase_speed_m_per_s], [], 1);
    speed = speed(sourceIndices);
end

function passbandHz = get_effective_filter_passband(result)
    passbandHz = [];
    if ~isfield(result, 'processing') || ~isstruct(result.processing) || ...
            ~isfield(result.processing, 'config') || ...
            ~isstruct(result.processing.config) || ...
            ~isfield(result.processing.config, 'FilterOptions') || ...
            ~isstruct(result.processing.config.FilterOptions) || ...
            ~isfield(result.processing.config.FilterOptions, 'frequency') || ...
            ~isstruct(result.processing.config.FilterOptions.frequency) || ...
            ~isfield(result.processing.config.FilterOptions.frequency, ...
                'effective_passband_hz') || ...
            isempty(result.processing.config.FilterOptions.frequency.effective_passband_hz)
        return;
    end

    passbandHz = double( ...
        result.processing.config.FilterOptions.frequency.effective_passband_hz(:)');
    if numel(passbandHz) ~= 2 || any(~isfinite(passbandHz)) || ...
            passbandHz(1) < 0 || passbandHz(2) <= passbandHz(1)
        error('OCE:Results:InvalidFilterPassband', ...
            'Persisted effective filter passband must be [low high] in Hz.');
    end
end

function value = get_table_string(T, rowIndex, columnName)
    columnName = char(columnName);
    value = T.(columnName)(rowIndex);
    if iscell(value)
        value = value{1};
    end
    if isnumeric(value)
        if isnan(value)
            value = "";
        else
            value = string(value);
        end
    elseif isstring(value) || ischar(value) || iscategorical(value)
        value = string(value);
    else
        value = string(value);
    end
    value = strtrim(value);
end

function label = format_value_for_key(rawValue)
    rawValue = strtrim(string(rawValue));
    if ismissing(rawValue) || strlength(rawValue) == 0
        label = "";
        return;
    end
    numericValue = str2double(rawValue);
    if ~isnan(numericValue)
        label = sprintf('%g', numericValue);
    else
        label = rawValue;
    end
end

function report_empty_cells(dataStorage)
    nEmpty = nnz(cellfun(@isempty, dataStorage));
    if nEmpty > 0
        warning(['%d empty experiment.data cell(s) were found. ' ...
            'Summary functions may fail if the grid is incomplete.'], nEmpty);
    end
end
