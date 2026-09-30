function validateProcessingConfig(processingConfig)
%VALIDATEPROCESSINGCONFIG Validate the canonical editable ProcessingConfig schema.

    expectedFields = ["profile"; "created_by"; "created_at"; ...
        "AcquisitionOptions"; "OCTSystemOptions"; ...
        "SampleOpticalOptions"; ...
        "DispersionAnalysisOptions"; "FilterOptions"; "BorderOptions"; ...
        "MotionOptions"; "DispersionWindowOptions"; ...
        "VisualizationOptions"; "VideoOptions"; "per_acquisition"];

    if ~isstruct(processingConfig) || ~isscalar(processingConfig)
        invalid('processing_config must be a scalar struct.');
    end

    actualFields = string(fieldnames(processingConfig));
    missing = expectedFields(~ismember(expectedFields, actualFields));
    extra = actualFields(~ismember(actualFields, expectedFields));
    if ~isempty(missing) || ~isempty(extra)
        invalid('processing_config fields are invalid. Missing=%s; extra=%s.', ...
            join_names(missing), join_names(extra));
    end

    profile = require_text(processingConfig.profile, 'profile');
    supportedProfiles = ["phantom", "in_vivo_eye", "ex_vivo_eye"];
    if ~ismember(profile, supportedProfiles)
        invalid('Unsupported processing profile "%s".', profile);
    end

    require_text(processingConfig.created_by, 'created_by');
    require_text(processingConfig.created_at, 'created_at');

    structFields = ["AcquisitionOptions"; "OCTSystemOptions"; ...
        "SampleOpticalOptions"; ...
        "DispersionAnalysisOptions"; "FilterOptions"; "BorderOptions"; ...
        "MotionOptions"; "DispersionWindowOptions"; ...
        "VisualizationOptions"; "VideoOptions"; "per_acquisition"];
    for index = 1:numel(structFields)
        name = structFields(index);
        value = processingConfig.(name);
        if ~isstruct(value) || ~isscalar(value)
            invalid('processing_config.%s must be a scalar struct.', name);
        end
    end

    validate_optics_contract(processingConfig, 'processing_config');

    overrideNames = fieldnames(processingConfig.per_acquisition);
    for index = 1:numel(overrideNames)
        name = overrideNames{index};
        override = processingConfig.per_acquisition.(name);
        if ~isstruct(override) || ~isscalar(override)
            invalid('processing_config.per_acquisition.%s must be a scalar struct.', ...
                name);
        end
        validate_optics_contract(override, ...
            'processing_config.per_acquisition.' + string(name));
    end
end

function validate_optics_contract(value, label)
    if isfield(value, 'OCT_defaults')
        invalid('%s must not contain retired OCT_defaults.', label);
    end
    if isfield(value, 'OCTSystemOptions')
        oce.config.resolveOCTSystemOptions(value.OCTSystemOptions);
    end
    if isfield(value, 'SampleOpticalOptions')
        oce.config.resolveSampleOpticalOptions(value.SampleOpticalOptions);
    end
end

function value = require_text(value, fieldName)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        invalid('processing_config.%s must be a text scalar.', fieldName);
    end
    value = strtrim(string(value));
    if ismissing(value) || strlength(value) == 0
        invalid('processing_config.%s must not be empty.', fieldName);
    end
end

function value = join_names(names)
    if isempty(names)
        value = '<none>';
    else
        value = strjoin(names, ', ');
    end
end

function invalid(message, varargin)
    error('OCE:Config:InvalidProcessingConfig', message, varargin{:});
end
