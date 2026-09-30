function resolvedCrop = resolveCropOptions(acquisitionParameters, scanInfo, ...
        acquisitionMode, scanGeometry)
%RESOLVECROPOPTIONS Resolve persisted crop parameters for one acquisition.

    oce.acquisition.validateAcquisitionParameters(acquisitionParameters);
    validate_runtime_taxonomy(acquisitionParameters, ...
        acquisitionMode, scanGeometry);
    validate_header_match(acquisitionParameters.source.header, scanInfo);

    resolvedCrop = struct( ...
        'depth', resolved_range(acquisitionParameters.crop.depth), ...
        'time', resolved_range(acquisitionParameters.crop.time), ...
        'selection_source', "acquisition_parameters");
end

function validate_runtime_taxonomy(parameters, runtimeMode, runtimeGeometry)
    persistedMode = lower(strtrim(string(parameters.acquisition_mode)));
    persistedGeometry = lower(strtrim(string(parameters.scan_geometry)));
    mode = require_runtime_text(runtimeMode, ...
        'OCE:Acquisition:AcquisitionModeMismatch', ...
        'resolved acquisition mode');
    geometry = require_runtime_text(runtimeGeometry, ...
        'OCE:Acquisition:ScanGeometryMismatch', ...
        'resolved scan geometry');

    if mode ~= persistedMode
        error('OCE:Acquisition:AcquisitionModeMismatch', ...
            ['Persisted acquisition mode "%s" does not match runtime ' ...
             'acquisition mode "%s".'], persistedMode, mode);
    end
    if geometry ~= persistedGeometry
        error('OCE:Acquisition:ScanGeometryMismatch', ...
            ['Persisted scan geometry "%s" does not match runtime ' ...
             'scan geometry "%s".'], persistedGeometry, geometry);
    end
end

function validate_header_match(snapshot, scanInfo)
    if ~isstruct(scanInfo) || ~isscalar(scanInfo)
        error('OCE:Acquisition:HeaderMismatch', ...
            'Runtime acquisition header must be a scalar struct.');
    end

    numericFields = ["samples_in_Aline"; "Alines_in_Bframe"; ...
        "Bframes_in_3Dscan"; "No_3Dscans"; "Hor_scan_length_mm"; ...
        "Ver_scan_length_mm"];
    requiredFields = [numericFields; "type"; "pattern_control"];
    for index = 1:numel(requiredFields)
        name = requiredFields(index);
        if ~isfield(scanInfo, name)
            error('OCE:Acquisition:HeaderMismatch', ...
                'Runtime acquisition header is missing required field %s.', name);
        end
    end

    for index = 1:numel(numericFields)
        name = numericFields(index);
        if ~isequal(snapshot.(name), scanInfo.(name))
            error('OCE:Acquisition:HeaderMismatch', ...
                ['Persisted header field %s does not match the current ' ...
                 'acquisition header. Persisted=%s Runtime=%s.'], ...
                name, value_text(snapshot.(name)), value_text(scanInfo.(name)));
        end
    end

    persistedType = lower(strtrim(string(snapshot.type)));
    runtimeType = require_runtime_text(scanInfo.type, ...
        'OCE:Acquisition:HeaderMismatch', 'runtime header.type');
    if persistedType ~= runtimeType
        error('OCE:Acquisition:HeaderMismatch', ...
            ['Persisted header field type does not match the current ' ...
             'acquisition header. Persisted="%s" Runtime="%s".'], ...
            persistedType, runtimeType);
    end

    persistedPattern = optional_text(snapshot.pattern_control);
    runtimePattern = optional_runtime_text(scanInfo.pattern_control, ...
        'runtime header.pattern_control');
    if persistedPattern ~= runtimePattern
        error('OCE:Acquisition:HeaderMismatch', ...
            ['Persisted header field pattern_control does not match the ' ...
             'current acquisition header. Persisted="%s" Runtime="%s".'], ...
            persistedPattern, runtimePattern);
    end
end

function resolved = resolved_range(source)
    resolved = struct( ...
        'selection', lower(strtrim(string(source.selection))), ...
        'start_index_inclusive', source.start_index_inclusive, ...
        'end_index_inclusive', source.end_index_inclusive, ...
        'sample_count', ...
            source.end_index_inclusive - source.start_index_inclusive + 1);
end

function value = require_runtime_text(value, identifier, label)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error(identifier, '%s must be a text scalar.', label);
    end
    value = lower(strtrim(string(value)));
    if ismissing(value) || strlength(value) == 0
        error(identifier, '%s must not be empty.', label);
    end
end

function value = optional_text(value)
    value = lower(strtrim(string(value)));
    if ismissing(value)
        value = "";
    end
end

function value = optional_runtime_text(value, label)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('OCE:Acquisition:HeaderMismatch', ...
            '%s must be a text scalar.', label);
    end
    value = optional_text(value);
end

function text = value_text(value)
    if isnumeric(value) && isscalar(value)
        text = string(value);
    else
        text = "<invalid>";
    end
end
