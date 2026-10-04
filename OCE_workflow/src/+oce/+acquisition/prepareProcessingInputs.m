function inputs = prepareProcessingInputs(experimentRoot, subExperiment, queryValue, varargin)
%PREPAREPROCESSINGINPUTS Collect inputs required to process one acquisition.
%
% Input: experiment identity and an acquisition query.
% Output: validated paths plus persisted system, acquisition, and processing
% parameter contracts. Side effects are limited to non-blocking warnings when
% optional Experimental Log dimensions, or a quasi-harmonic frequency_Hz,
% disagree with the normalized raw header or its generator header.
% The acquisition package owns data preparation; output-producing functions
% create directories when needed.
%
% Expected experiment folder structure:
%
%   <experiment>/Data/<sub-experiment>/*.bin
%   <experiment>/Params/<sub-experiment>/Params_<sub-experiment>.mat
%   <experiment>/Params/<sub-experiment>/AcquisitionParams_<sub-experiment>.mat
%   <experiment>/Params/<sub-experiment>/ProcessingConfig_<sub-experiment>.mat
%   <experiment>/Results/<sub-experiment>/
%
% Usage:
%
%   inputs = oce.acquisition.prepareProcessingInputs( ...
%       experimentRoot, subExperiment, "R001", ...
%       "Key", "run_id")
%
%   inputs = oce.acquisition.prepareProcessingInputs( ...
%       experimentRoot, subExperiment, "file.bin", ...
%       "Key", "filename")
%
% Optional name-value arguments:
%
%   'Key'                     Column used to select the acquisition.
%                             Default: 'filename'
%   'RequireProcessingConfig' true/false. Default: false
%
% Output:
%
%   inputs.filename           .bin filename
%   inputs.filepath           path to Data/<sub-experiment>/
%   inputs.fullfile           full path to the .bin file
%   inputs.experimentRoot     experiment root folder
%   inputs.subExperiment      sub-experiment name
%   inputs.resultsDir         intended Results/<sub-experiment>/ folder
%   inputs.acquisition_parameters  persisted crop preparation artifact
%   inputs.acquisition_table  acquisition table for sub-experiment
%   inputs.acquisition_row    one-row table for selected acquisition
%   inputs.acquisition_header parsed header without raw samples
%   inputs.processing_config  processing configuration if available
%   inputs.processingConfigFile path to ProcessingConfig file if available
%   inputs.paramsInfo         loaded parameter file info
%
% Notes:
%   - The .bin file must be listed in acquisition_table.filename.
%   - If the selected acquisition file does not exist on disk, an error is thrown.
%   - ProcessingConfig is optional by default. Set RequireProcessingConfig=true
%     to make it mandatory.

    if nargin < 1 || isempty(experimentRoot)
        error('experimentRoot is required.');
    end
    if nargin < 2 || isempty(subExperiment)
        error('subExperiment is required.');
    end
    if nargin < 3 || isempty(queryValue)
        error('queryValue is required.');
    end

    p = inputParser;
    addParameter(p, 'Key', 'filename', @(x) ischar(x) || isstring(x));
    addParameter(p, 'RequireProcessingConfig', false, @islogical);
    parse(p, varargin{:});

    experimentRoot = char(experimentRoot);
    subExperiment = char(subExperiment);

    [acquisition_parameters, acquisition_table, paramsInfo] = ...
        oce.io.loadSubexperimentParameters(experimentRoot, subExperiment);
    acquisition_row = oce.acquisition.getAcquisitionRow( ...
        acquisition_table, queryValue, 'Key', p.Results.Key);
    filename = char(string(acquisition_row.filename));

    dataDir = fullfile(experimentRoot, 'Data', subExperiment);
    if ~exist(dataDir, 'dir')
        error('Data folder not found: %s', dataDir);
    end

    fullBinPath = fullfile(dataDir, filename);
    if ~isfile(fullBinPath)
        error('Selected .bin file not found: %s', fullBinPath);
    end

    resultsDir = fullfile(experimentRoot, 'Results', subExperiment);
    acquisitionHeader = oce.io.readAcquisitionHeader(filename, dataDir);
    warn_on_dimension_metadata_mismatch( ...
        acquisition_row, acquisitionHeader, filename);
    warn_on_excitation_metadata_mismatch( ...
        acquisition_row, acquisitionHeader, filename);
    [processing_config, processingConfigFile] = load_processing_config_if_available( ...
        experimentRoot, subExperiment, p.Results.RequireProcessingConfig);

    inputs = struct();
    inputs.filename = filename;
    inputs.filepath = ensure_trailing_filesep(dataDir);
    inputs.fullfile = fullBinPath;
    inputs.experimentRoot = experimentRoot;
    inputs.subExperiment = subExperiment;
    inputs.resultsDir = resultsDir;
    inputs.acquisition_parameters = acquisition_parameters;
    inputs.acquisition_table = acquisition_table;
    inputs.acquisition_row = acquisition_row;
    inputs.acquisition_header = acquisitionHeader;
    inputs.processing_config = processing_config;
    inputs.processingConfigFile = processingConfigFile;
    inputs.paramsInfo = paramsInfo;
end

function warn_on_dimension_metadata_mismatch(row, header, filename)
    metadataNames = ["alines_per_bscan"; "m_repetitions"; "bscan_count"];
    headerNames = ["Bframes_in_3Dscan"; "Alines_in_Bframe"; "No_3Dscans"];
    details = strings(0, 1);

    for index = 1:numel(metadataNames)
        metadataName = metadataNames(index);
        if ~ismember(metadataName, string(row.Properties.VariableNames))
            continue;
        end
        raw = row.(metadataName);
        if iscell(raw) && isscalar(raw)
            raw = raw{1};
        end
        if isnumeric(raw)
            value = double(raw(1));
        else
            value = str2double(string(raw(1)));
        end
        if isnan(value)
            continue;
        end

        headerValue = double(header.(char(headerNames(index))));
        if value ~= headerValue
            details(end + 1, 1) = sprintf('%s: log=%g, header=%g', ...
                metadataName, value, headerValue); %#ok<AGROW>
        end
    end

    if ~isempty(details)
        warning('OCE:Acquisition:MetadataHeaderMismatch', ...
            ['Acquisition dimension metadata differs from the normalized raw ' ...
             'header for "%s". Raw-header dimensions will be used for ' ...
             'processing. %s'], filename, strjoin(details, '; '));
    end
end

function warn_on_excitation_metadata_mismatch(row, header, filename)
    % The Experimental Log remains the batch frequency contract.
    if ~isfield(header, 'excitation') || ~header.excitation.available || ...
            lower(strtrim(string(row.excitation_type))) == "pulse"
        return;
    end
    raw = row.frequency_Hz;
    if iscell(raw) && isscalar(raw)
        raw = raw{1};
    end
    if isnumeric(raw)
        value = double(raw(1));
    else
        value = str2double(string(raw(1)));
    end
    if value ~= header.excitation.frequency_hz
        warning('OCE:Acquisition:MetadataHeaderMismatch', ...
            ['frequency_Hz differs from the generator header for "%s": ' ...
             'log=%g Hz, generator=%g Hz. The Experimental Log value is ' ...
             'used for processing.'], filename, value, ...
            header.excitation.frequency_hz);
    end
end

function [processing_config, processingConfigFile] = load_processing_config_if_available( ...
        experimentRoot, subExperiment, requireConfig)
    safeSubExperiment = matlab.lang.makeValidName(subExperiment);
    processingConfigFile = fullfile(experimentRoot, 'Params', subExperiment, ...
        ['ProcessingConfig_' safeSubExperiment '.mat']);

    if isfile(processingConfigFile)
        S = load(processingConfigFile, 'processing_config');
        if ~isfield(S, 'processing_config')
            error('Processing config file does not contain processing_config: %s', ...
                processingConfigFile);
        end
        processing_config = S.processing_config;
        return;
    end

    if requireConfig
        error(['Processing config file not found:\n%s\n\n' ...
               'Create it first with oce.config.getDefaultProcessingConfig(profile) ' ...
               'and oce.config.saveProcessingConfig().'], ...
               processingConfigFile);
    end

    processing_config = struct();
    processingConfigFile = '';
end

function pathOut = ensure_trailing_filesep(pathIn)
    pathOut = char(pathIn);
    if pathOut(end) ~= filesep
        pathOut = [pathOut filesep];
    end
end
