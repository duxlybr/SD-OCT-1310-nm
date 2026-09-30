function runContext = prepareAcquisitionRun(experimentRoot, subExperiment, queryValue, varargin)
%PREPAREACQUISITIONRUN Resolve and validate one acquisition explicitly.
% Input: experiment identity, acquisition selector, and resolution options.
% Output: prepared inputs, final per-run configuration, and optional
% sub-experiment-wide file-inventory validation.
% Side effects: none beyond warnings for detected inventory inconsistencies.
% runSingleAcquisition is the next consumer and owns user-facing reporting.
%
% Successful return means the selected acquisition exists and its processing
% inputs and configuration were resolved. file_validation, when requested,
% reports whole-sub-experiment inventory consistency and does not determine
% whether the selected acquisition itself is processable.

    if nargin < 3 || isempty(experimentRoot) || ...
            isempty(subExperiment) || isempty(queryValue)
        error('experimentRoot, subExperiment, and queryValue are required.');
    end

    p = inputParser;
    addParameter(p, 'Key', 'filename', @(x) ischar(x) || isstring(x));
    addParameter(p, 'ValidateFiles', true, @islogical);
    parse(p, varargin{:});

    processingInputs = oce.acquisition.prepareProcessingInputs( ...
        experimentRoot, subExperiment, queryValue, ...
        'Key', p.Results.Key, 'RequireProcessingConfig', true);
    configForRun = oce.config.buildProcessingConfigForAcquisition( ...
        processingInputs);

    fileValidation = struct();
    if p.Results.ValidateFiles
        fileValidation = oce.acquisition.validateAcquisitionFiles( ...
            experimentRoot, subExperiment, processingInputs.acquisition_table);
    end

    runContext = struct('processing_inputs', processingInputs, ...
        'config_for_run', configForRun, 'file_validation', fileValidation);

    if p.Results.ValidateFiles && isfield(fileValidation, 'isValid') && ...
            ~fileValidation.isValid
        warning(['File validation found whole-sub-experiment inventory issues. ' ...
            'The selected acquisition was prepared successfully; review ' ...
            'runContext.file_validation separately.']);
    end
end
