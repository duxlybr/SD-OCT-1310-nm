function validateAcquisitionParameters(parameters)
%VALIDATEACQUISITIONPARAMETERS Validate the canonical persisted acquisition schema.

    assert_exact_fields(parameters, ...
        ["schema_version"; "acquisition_mode"; "scan_geometry"; ...
         "source"; "crop"; "preview_display"], ...
        'OCE:Acquisition:InvalidParameterSchema', ...
        'acquisition_parameters');

    if ~isnumeric(parameters.schema_version) || ...
            ~isscalar(parameters.schema_version) || ...
            ~isfinite(parameters.schema_version) || ...
            parameters.schema_version ~= 4
        error('OCE:Acquisition:InvalidParameterSchema', ...
            'Canonical acquisition_parameters must use schema_version 4.');
    end

    acquisitionMode = require_text(parameters.acquisition_mode, ...
        'acquisition_parameters.acquisition_mode');
    if acquisitionMode ~= "mb_mode"
        error('OCE:Acquisition:AcquisitionModeMismatch', ...
            'Canonical acquisition_parameters supports only acquisition mode "mb_mode".');
    end

    scanGeometry = require_text(parameters.scan_geometry, ...
        'acquisition_parameters.scan_geometry');
    if ~ismember(scanGeometry, ["angular_bmodes", "raster"])
        error('OCE:Acquisition:ScanGeometryMismatch', ...
            ['Canonical acquisition_parameters supports scan geometry ' ...
             '"angular_bmodes" or "raster".']);
    end

    validate_source(parameters.source);
    validate_crop(parameters.crop, parameters.source.header);
    validate_preview_display(parameters.preview_display);
end

function validate_source(source)
    assert_exact_fields(source, ...
        ["filename"; "header"; "oct_system_profile"], ...
        'OCE:Acquisition:InvalidParameterSchema', ...
        'acquisition_parameters.source');
    require_text(source.filename, 'acquisition_parameters.source.filename');
    require_text(source.oct_system_profile, ...
        'acquisition_parameters.source.oct_system_profile');
    validate_header_snapshot(source.header);
end

function validate_header_snapshot(header)
    numericFields = ["samples_in_Aline"; "Alines_in_Bframe"; ...
        "Bframes_in_3Dscan"; "No_3Dscans"; "Hor_scan_length_mm"; ...
        "Ver_scan_length_mm"];
    assert_exact_fields(header, [numericFields; "type"; "pattern_control"], ...
        'OCE:Acquisition:InvalidParameterSchema', ...
        'acquisition_parameters.source.header');

    for index = 1:numel(numericFields)
        name = numericFields(index);
        value = header.(name);
        if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
            error('OCE:Acquisition:InvalidParameterSchema', ...
                'acquisition_parameters.source.header.%s must be finite numeric scalar.', ...
                name);
        end
    end
    require_text(header.type, 'acquisition_parameters.source.header.type');
    optional_text(header.pattern_control, ...
        'acquisition_parameters.source.header.pattern_control');
end

function validate_crop(crop, header)
    assert_exact_fields(crop, ["depth"; "time"], ...
        'OCE:Acquisition:InvalidParameterSchema', ...
        'acquisition_parameters.crop');

    depthLimit = floor(header.samples_in_Aline / 2);
    timeLimit = header.Alines_in_Bframe;
    validate_range(crop.depth, depthLimit, ...
        'OCE:Acquisition:InvalidDepthCrop', 'depth');
    validate_range(crop.time, timeLimit, ...
        'OCE:Acquisition:InvalidTimeCrop', 'time');
end

function validate_range(rangeValue, limit, identifier, label)
    assert_exact_fields(rangeValue, ...
        ["selection"; "start_index_inclusive"; "end_index_inclusive"], ...
        identifier, label + " crop");

    selection = require_text(rangeValue.selection, label + " crop selection", ...
        identifier);
    if ~ismember(selection, ["interactive", "manual_indices"])
        error('OCE:Acquisition:UnsupportedCropSelection', ...
            ['Unsupported %s crop selection "%s". Maintained selections ' ...
             'are "interactive" and "manual_indices".'], label, selection);
    end

    startIndex = require_positive_integer( ...
        rangeValue.start_index_inclusive, identifier, ...
        label + " start_index_inclusive");
    endIndex = require_positive_integer( ...
        rangeValue.end_index_inclusive, identifier, ...
        label + " end_index_inclusive");
    if startIndex > endIndex
        error(identifier, ...
            '%s crop start index must not exceed its end index.', label);
    end
    if ~isnumeric(limit) || ~isscalar(limit) || ~isfinite(limit) || ...
            endIndex > limit
        error(identifier, ...
            '%s crop end index %d exceeds the valid limit %g.', ...
            label, endIndex, limit);
    end
end

function validate_preview_display(previewDisplay)
    assert_exact_fields(previewDisplay, "bmode_intensity_limits_db", ...
        'OCE:Acquisition:InvalidParameterSchema', ...
        'acquisition_parameters.preview_display');

    limits = previewDisplay.bmode_intensity_limits_db;
    if ~isnumeric(limits) || ~isvector(limits) || numel(limits) ~= 2 || ...
            any(~isfinite(limits)) || limits(1) >= limits(2)
        error('OCE:Acquisition:InvalidDisplayLimits', ...
            ['bmode_intensity_limits_db must be a finite numeric ' ...
             'two-element vector with low < high.']);
    end
end

function value = require_text(value, label, identifier)
    if nargin < 3
        identifier = 'OCE:Acquisition:InvalidParameterSchema';
    end
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error(identifier, '%s must be a text scalar.', label);
    end
    value = lower(strtrim(string(value)));
    if ismissing(value) || strlength(value) == 0
        error(identifier, '%s must not be empty.', label);
    end
end

function optional_text(value, label)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('OCE:Acquisition:InvalidParameterSchema', ...
            '%s must be a text scalar.', label);
    end
end

function value = require_positive_integer(value, identifier, label)
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
            value < 1 || value ~= round(value)
        error(identifier, '%s must be a positive integer scalar.', label);
    end
end

function assert_exact_fields(source, names, identifier, label)
    if ~isstruct(source) || ~isscalar(source)
        error(identifier, '%s must be a scalar struct.', label);
    end
    actual = sort(string(fieldnames(source)));
    expected = sort(string(names));
    if ~isequal(actual, expected)
        error(identifier, ...
            '%s must contain exactly these fields: %s.', ...
            label, strjoin(names, ', '));
    end
end
