function config_for_run = buildProcessingConfigForAcquisition(inputs, varargin)
%BUILDPROCESSINGCONFIGFORACQUISITION Resolve final config for one acquisition.
% Input: saved processing configuration, selected acquisition metadata, and
% persisted acquisition parameters.
% Output: resolved config_for_run consumed by processPreparedAcquisition.

    if nargin < 1 || isempty(inputs)
        error('inputs is required.');
    end
    if ~isempty(varargin)
        error('OCE:Config:UnsupportedBuildOption', ...
            'buildProcessingConfigForAcquisition accepts no name-value options.');
    end

    validate_inputs_struct(inputs);
    processing_config = inputs.processing_config;
    if isempty(fieldnames(processing_config))
        error(['inputs.processing_config is empty. Create and save a ' ...
            'ProcessingConfig first, then run ' ...
            'oce.acquisition.prepareProcessingInputs again.']);
    end
    oce.config.validateProcessingConfig(processing_config);

    acquisition_row = inputs.acquisition_row;
    acquisition_header = inputs.acquisition_header;
    acquisition_parameters = inputs.acquisition_parameters;

    config_for_run = initialize_run_config(processing_config, acquisition_row);
    config_for_run = applyProcessingConfigOverrides( ...
        config_for_run, processing_config, acquisition_row);

    if istable(acquisition_row) && height(acquisition_row) == 1 && ...
            ismember('excitation_type', acquisition_row.Properties.VariableNames) && ...
            lower(strtrim(string(acquisition_row.excitation_type))) == "pulse"
        config_for_run.DispersionAnalysisOptions.target_frequency.source = ...
            "not_available";
    end

    config_for_run.OCTSystemOptions = resolveAcquisitionOCTSystem( ...
        config_for_run.OCTSystemOptions, acquisition_row, ...
        acquisition_parameters);
    config_for_run.SampleOpticalOptions = ...
        oce.config.resolveSampleOpticalOptions( ...
            config_for_run.SampleOpticalOptions);

    config_for_run.MotionOptions = ...
        oce.config.resolvePhaseEstimationOptions(config_for_run.MotionOptions);
    config_for_run.AcquisitionOptions = ...
        oce.config.resolveAcquisitionOptions( ...
            config_for_run.AcquisitionOptions, acquisition_row, ...
            acquisition_header);
    config_for_run.resolved_crop = oce.acquisition.resolveCropOptions( ...
        acquisition_parameters, acquisition_header, ...
        config_for_run.AcquisitionOptions.acquisition_mode, ...
        config_for_run.AcquisitionOptions.scan_geometry);
    config_for_run.DispersionWindowOptions = ...
        oce.config.resolveDispersionWindowOptions( ...
            config_for_run.DispersionWindowOptions);
    config_for_run.VideoOptions = resolveRunVideoOptions( ...
        config_for_run.VideoOptions, config_for_run.resolved_crop);
    config_for_run.BorderOptions = oce.config.resolveBorderOptions( ...
        config_for_run.BorderOptions, acquisition_row, ...
        config_for_run.resolved_crop);

    config_for_run.metadata = build_metadata(inputs);
end

function config = initialize_run_config(processingConfig, acquisitionRow)
    config = struct();
    config.processing_config_base = processingConfig;
    config.acquisition_row = acquisitionRow;
    config.AcquisitionOptions = processingConfig.AcquisitionOptions;
    config.OCTSystemOptions = processingConfig.OCTSystemOptions;
    config.SampleOpticalOptions = processingConfig.SampleOpticalOptions;
    config.DispersionAnalysisOptions = processingConfig.DispersionAnalysisOptions;
    config.FilterOptions = processingConfig.FilterOptions;
    config.BorderOptions = processingConfig.BorderOptions;
    config.MotionOptions = processingConfig.MotionOptions;
    config.DispersionWindowOptions = processingConfig.DispersionWindowOptions;
    config.VisualizationOptions = processingConfig.VisualizationOptions;
    config.VideoOptions = processingConfig.VideoOptions;
end

function metadata = build_metadata(inputs)
    metadata = struct();
    metadata.created_by = 'build_processing_config_for_acquisition';
    metadata.created_at = string(datetime('now'));
    metadata.filename = inputs.filename;
    metadata.fullfile = inputs.fullfile;
    metadata.experimentRoot = inputs.experimentRoot;
    metadata.subExperiment = inputs.subExperiment;
    metadata.resultsDir = inputs.resultsDir;
    metadata.processingConfigFile = inputs.processingConfigFile;
end

function validate_inputs_struct(inputs)
    requiredFields = [ ...
        "filename"; "fullfile"; "experimentRoot"; "subExperiment"; ...
        "resultsDir"; "acquisition_parameters"; "acquisition_row"; ...
        "acquisition_header"; "processing_config"; "processingConfigFile"];
    if ~isstruct(inputs) || ~isscalar(inputs)
        error('OCE:Config:InvalidProcessingInputs', ...
            'inputs must be a scalar struct.');
    end
    for index = 1:numel(requiredFields)
        if ~isfield(inputs, requiredFields(index))
            error('OCE:Config:InvalidProcessingInputs', ...
                'inputs is missing required field: %s.', requiredFields(index));
        end
    end
end
