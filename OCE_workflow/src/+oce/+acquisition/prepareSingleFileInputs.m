function inputs = prepareSingleFileInputs(binFile, acquisitionParameters, ...
        acquisitionMetadata, processingConfig, varargin)
%PREPARESINGLEFILEINPUTS Prepare one standalone .bin acquisition in memory.
% The single-file path does not require experimental_log.xlsx. It completes a
% canonical one-row acquisition contract from user metadata and prepared params.

    if nargin < 4
        error('OCE:Acquisition:MissingSingleFileInput', ...
            ['binFile, acquisitionParameters, acquisitionMetadata, and ' ...
             'processingConfig are required.']);
    end
    p = inputParser;
    addParameter(p, 'ResultsDirectory', "", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    parse(p, varargin{:});

    if ~(ischar(binFile) || (isstring(binFile) && isscalar(binFile)))
        error('OCE:Acquisition:InvalidSingleFile', ...
            'binFile must be a text scalar.');
    end
    fullBinPath = char(binFile);
    if ~isfile(fullBinPath)
        error('OCE:Acquisition:InvalidSingleFile', ...
            'Selected .bin file not found: %s.', fullBinPath);
    end
    [dataDir, fileBase, extension] = fileparts(fullBinPath);
    if isempty(dataDir)
        dataDir = pwd;
        fullBinPath = fullfile(dataDir, [fileBase extension]);
    end
    if ~strcmpi(extension, '.bin')
        error('OCE:Acquisition:InvalidSingleFile', ...
            'Selected acquisition must use the .bin extension: %s.', ...
            fullBinPath);
    end

    filename = [fileBase extension];
    oce.acquisition.validateAcquisitionParameters(acquisitionParameters);
    acquisitionRow = normalize_metadata(acquisitionMetadata, filename);
    acquisitionRow = complete_canonical_metadata( ...
        acquisitionRow, acquisitionParameters);
    acquisitionHeader = oce.io.readAcquisitionHeader(filename, dataDir);
    if ~isstruct(processingConfig) || ~isscalar(processingConfig) || ...
            isempty(fieldnames(processingConfig))
        error('OCE:Acquisition:InvalidSingleFileConfig', ...
            'processingConfig must be a nonempty scalar struct.');
    end

    subExperiment = string(acquisitionRow.sub_experiment);
    resultsDir = string(p.Results.ResultsDirectory);
    if ismissing(resultsDir) || strlength(strtrim(resultsDir)) == 0
        resultsDir = string(fullfile(dataDir, 'Results'));
    end

    inputs = struct();
    inputs.filename = filename;
    inputs.filepath = ensure_trailing_filesep(dataDir);
    inputs.fullfile = fullBinPath;
    inputs.experimentRoot = dataDir;
    inputs.subExperiment = char(subExperiment);
    inputs.resultsDir = char(resultsDir);
    inputs.acquisition_parameters = acquisitionParameters;
    inputs.acquisition_table = acquisitionRow;
    inputs.acquisition_row = acquisitionRow;
    inputs.acquisition_header = acquisitionHeader;
    inputs.processing_config = processingConfig;
    inputs.processingConfigFile = '';
    inputs.paramsInfo = struct( ...
        'source', "in_memory_single_file", ...
        'paramsFile', '', ...
        'acquisitionParamsFile', '', ...
        'numAcquisitions', 1);
end

function row = normalize_metadata(metadata, filename)
    if istable(metadata)
        if height(metadata) ~= 1
            error('OCE:Acquisition:InvalidSingleFileMetadata', ...
                'acquisitionMetadata table must contain exactly one row.');
        end
        row = metadata;
    elseif isstruct(metadata) && isscalar(metadata)
        row = struct2table(metadata, 'AsArray', true);
    else
        error('OCE:Acquisition:InvalidSingleFileMetadata', ...
            ['acquisitionMetadata must be a scalar struct or one-row ' ...
             'table.']);
    end

    reject_retired_metadata(row);
    if ismember('filename', row.Properties.VariableNames)
        metadataFilename = scalar_text(row.filename, 'filename');
        if ~strcmpi(metadataFilename, filename)
            error('OCE:Acquisition:SingleFileMetadataMismatch', ...
                ['acquisitionMetadata.filename must match the selected ' ...
                 'file. Metadata=%s Selected=%s.'], ...
                metadataFilename, filename);
        end
    else
        row.filename = string(filename);
    end
    if ~ismember('run_id', row.Properties.VariableNames)
        [~, fileBase] = fileparts(filename);
        row.run_id = string(fileBase);
    else
        scalar_text(row.run_id, 'run_id');
    end
end

function reject_retired_metadata(row)
    names = string(row.Properties.VariableNames);
    retired = intersect( ...
        ["acquisition_protocol"; "scan_type"; "study_type"], ...
        names, 'stable');
    if ~isempty(retired)
        error('OCE:Acquisition:LegacySingleFileMetadata', ...
            ['Standalone acquisition metadata contains retired field(s): %s. ' ...
             'Use experiment_type, excitation_type, acquisition_mode, ' ...
             'scan_geometry, and oct_system_profile.'], ...
            strjoin(retired, ', '));
    end
end

function row = complete_canonical_metadata(row, parameters)
    row = default_text(row, 'experiment_id', "manual_single");
    row = default_text(row, 'sub_experiment', "manual");
    row = default_text(row, 'experiment_type', "manual_single");
    row = taxonomy_field(row, 'acquisition_mode', ...
        string(parameters.acquisition_mode));
    row = taxonomy_field(row, 'scan_geometry', ...
        string(parameters.scan_geometry));
    row = taxonomy_field(row, 'oct_system_profile', ...
        string(parameters.source.oct_system_profile));
    if ~ismember('rep_id', row.Properties.VariableNames)
        row.rep_id = 1;
    end
    require_metadata_field(row, 'sample_type');
    require_metadata_field(row, 'excitation_type');
    validate_frequency_metadata(row);
end

function validate_frequency_metadata(row)
    if ~ismember('frequency_Hz', row.Properties.VariableNames)
        error('OCE:Acquisition:InvalidSingleFileMetadata', ...
            'acquisitionMetadata.frequency_Hz is required.');
    end
    excitationType = lower(strtrim(string(row.excitation_type)));
    raw = row.frequency_Hz;
    if iscell(raw) && isscalar(raw), raw = raw{1}; end
    if isnumeric(raw) && isscalar(raw)
        value = double(raw);
    elseif ischar(raw) || (isstring(raw) && isscalar(raw))
        value = str2double(string(raw));
    else
        value = NaN;
    end
    valid = isfinite(value) && value > 0;
    if excitationType == "pulse"
        valid = valid || isnan(value);
    end
    if ~valid
        error('OCE:Acquisition:InvalidSingleFileMetadata', ...
            ['acquisitionMetadata.frequency_Hz must be positive and finite, ' ...
             'or NaN when excitation_type="pulse".']);
    end
end

function row = default_text(row, name, fallback)
    if ~ismember(name, row.Properties.VariableNames)
        row.(name) = string(fallback);
        return;
    end
    scalar_text(row.(name), name);
end

function row = taxonomy_field(row, name, expected)
    expected = lower(strtrim(expected));
    if ~ismember(name, row.Properties.VariableNames)
        row.(name) = expected;
        return;
    end
    actual = lower(strtrim(string(scalar_text(row.(name), name))));
    if actual ~= expected
        error('OCE:Acquisition:SingleFileMetadataMismatch', ...
            'acquisitionMetadata.%s="%s" does not match prepared value "%s".', ...
            name, actual, expected);
    end
    row.(name) = actual;
end

function require_metadata_field(row, name)
    if ~ismember(name, row.Properties.VariableNames)
        error('OCE:Acquisition:InvalidSingleFileMetadata', ...
            'acquisitionMetadata.%s is required.', name);
    end
    value = row.(name);
    if isnumeric(value)
        if ~isscalar(value) || ~isfinite(value)
            error('OCE:Acquisition:InvalidSingleFileMetadata', ...
                'acquisitionMetadata.%s must contain one finite value.', name);
        end
        return;
    end
    scalar_text(value, name);
end

function value = scalar_text(rawValue, label)
    if iscell(rawValue) && isscalar(rawValue)
        rawValue = rawValue{1};
    end
    if ~(ischar(rawValue) || (isstring(rawValue) && isscalar(rawValue)))
        error('OCE:Acquisition:InvalidSingleFileMetadata', ...
            'acquisitionMetadata.%s must be a text scalar.', label);
    end
    value = char(strtrim(string(rawValue)));
    if isempty(value)
        error('OCE:Acquisition:InvalidSingleFileMetadata', ...
            'acquisitionMetadata.%s must not be empty.', label);
    end
end

function pathOut = ensure_trailing_filesep(pathIn)
    pathOut = char(pathIn);
    if pathOut(end) ~= filesep
        pathOut = [pathOut filesep];
    end
end
