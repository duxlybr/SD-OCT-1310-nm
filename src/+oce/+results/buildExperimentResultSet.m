function experiment = buildExperimentResultSet( ...
        experimentRoot, subExperiments, groupKeys, repetitionKey, varargin)
%BUILDEXPERIMENTRESULTSET Combine canonical sub-experiment result sets.
%
% Each selected sub-experiment is loaded through the maintained
% buildSubexperimentResultSet owner. This function only combines those
% canonical cells onto one experiment-wide N-dimensional design grid. The
% last dimension remains the repetition key.

    if nargin < 4
        error(['experimentRoot, subExperiments, groupKeys, and ' ...
            'repetitionKey are required.']);
    end

    parser = inputParser;
    addParameter(parser, 'MissingResultMode', 'warn', ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'DuplicateMode', 'error', ...
        @(x) ischar(x) || isstring(x));
    parse(parser, varargin{:});

    experimentRoot = string(experimentRoot);
    subExperiments = unique(string(subExperiments(:)), 'stable');
    groupKeys = string(groupKeys(:))';
    repetitionKey = string(repetitionKey);
    dimensionKeys = [groupKeys repetitionKey];

    if isempty(subExperiments) || any(strlength(strtrim(subExperiments)) == 0)
        error('At least one nonblank sub-experiment is required.');
    end
    if isempty(groupKeys)
        error('At least one group key is required.');
    end

    parts = cell(numel(subExperiments), 1);
    for index = 1:numel(subExperiments)
        parts{index} = oce.results.buildSubexperimentResultSet( ...
            experimentRoot, subExperiments(index), groupKeys, repetitionKey, ...
            'MissingResultMode', parser.Results.MissingResultMode, ...
            'DuplicateMode', parser.Results.DuplicateMode);
    end

    dimensionValues = combine_dimension_values(parts, dimensionKeys);
    dimensionUnits = parts{1}.design.dimension_units;
    dataSize = cellfun(@numel, dimensionValues);
    dataStorage = cell(dataSize);

    duplicateMode = lower(string(parser.Results.DuplicateMode));
    sourceTables = cell(numel(parts), 1);
    resultFiles = strings(0, 1);
    resultFolders = strings(0, 1);

    for partIndex = 1:numel(parts)
        part = parts{partIndex};
        dataStorage = assign_part_data( ...
            dataStorage, dimensionValues, part, duplicateMode);
        sourceTables{partIndex} = part.source.acquisition_table;
        resultFiles = [resultFiles; part.source.result_files(:)]; %#ok<AGROW>
        resultFolders = [resultFolders; part.source.result_folders(:)]; %#ok<AGROW>
    end

    experiment = struct();
    experiment.metadata = struct();
    experiment.metadata.experimentRoot = char(experimentRoot);
    experiment.metadata.subExperiments = cellstr(subExperiments);
    experiment.metadata.resultsRoot = char(fullfile(experimentRoot, 'Results'));
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
    experiment.source.acquisition_table = vertcat(sourceTables{:});
    experiment.source.result_files = resultFiles;
    experiment.source.result_folders = resultFolders;
    experiment.source.result_folder_key = "filename";

    experiment.data = dataStorage;
    experiment.result_schema = "oce_phase_speed_result";

    nEmpty = nnz(cellfun(@isempty, dataStorage));
    if nEmpty > 0
        warning(['%d empty experiment.data cell(s) were found across selected ' ...
            'sub-experiments.'], nEmpty);
    end
end

function dimensionValues = combine_dimension_values(parts, dimensionKeys)
    dimensionValues = cell(1, numel(dimensionKeys));
    for dimensionIndex = 1:numel(dimensionKeys)
        values = strings(0, 1);
        for partIndex = 1:numel(parts)
            current = string(parts{partIndex}.design.dimension_values{dimensionIndex});
            values = [values; current(:)]; %#ok<AGROW>
        end
        dimensionValues{dimensionIndex} = cellstr(unique(values, 'stable'));
    end
end

function dataStorage = assign_part_data( ...
        dataStorage, globalValues, part, duplicateMode)
    nDimensions = numel(globalValues);
    localValues = part.design.dimension_values;
    localSize = cellfun(@numel, localValues);

    for linearIndex = 1:numel(part.data)
        localIndex = cell(1, nDimensions);
        [localIndex{:}] = ind2sub(localSize, linearIndex);
        value = part.data{localIndex{:}};
        if isempty(value)
            continue;
        end

        globalIndex = cell(1, nDimensions);
        for dimensionIndex = 1:nDimensions
            label = string(localValues{dimensionIndex}{localIndex{dimensionIndex}});
            match = find(strcmp(globalValues{dimensionIndex}, char(label)), 1);
            if isempty(match)
                error('Could not map combined experiment dimension value: %s.', label);
            end
            globalIndex{dimensionIndex} = match;
        end

        if isempty(dataStorage{globalIndex{:}})
            dataStorage{globalIndex{:}} = value;
            continue;
        end

        switch duplicateMode
            case "error"
                error(['Duplicate experiment-wide grid assignment across ' ...
                    'sub-experiments.']);
            case "first"
                continue;
            case "last"
                dataStorage{globalIndex{:}} = value;
            otherwise
                error('Unsupported DuplicateMode: %s.', duplicateMode);
        end
    end
end
