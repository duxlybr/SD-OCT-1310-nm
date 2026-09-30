function options = resolveDispersionWindowOptions(options)
%RESOLVEDISPERSIONWINDOWOPTIONS Validate editable dispersion-window intent.

    expected = {'center', 'spatial', 'directional_offsets', 'temporal', ...
        'boundary_policy', 'show_progress'};
    require_exact_struct(options, expected, "DispersionWindowOptions");

    centerFields = {'method', 'manual_local_index', ...
        'search_range_fraction', 'max_rms_phase_increment', ...
        'max_mirrored_correlation'};
    require_exact_struct(options.center, centerFields, ...
        "DispersionWindowOptions.center");
    options.center.method = validate_method(options.center.method, ...
        ["middle", "manual_local_index", "max_rms_phase_increment", ...
         "max_mirrored_correlation"], "center.method");
    validate_manual_indices(options.center.manual_local_index, ...
        options.center.method);
    validate_fraction_range(options.center.search_range_fraction, ...
        "center.search_range_fraction");

    require_exact_struct(options.center.max_rms_phase_increment, ...
        {'smoothing_span_fraction'}, ...
        "DispersionWindowOptions.center.max_rms_phase_increment");
    validate_positive_scalar( ...
        options.center.max_rms_phase_increment.smoothing_span_fraction, ...
        "center.max_rms_phase_increment.smoothing_span_fraction", false);

    symmetryFields = {'half_width_fraction', 'half_width_samples', ...
        'minimum_half_width_samples', 'score_smoothing_span_fraction'};
    symmetry = options.center.max_mirrored_correlation;
    require_exact_struct(symmetry, symmetryFields, ...
        "DispersionWindowOptions.center.max_mirrored_correlation");
    validate_positive_scalar(symmetry.half_width_fraction, ...
        "center.max_mirrored_correlation.half_width_fraction", false);
    validate_optional_positive_integer(symmetry.half_width_samples, ...
        "center.max_mirrored_correlation.half_width_samples");
    validate_positive_scalar(symmetry.minimum_half_width_samples, ...
        "center.max_mirrored_correlation.minimum_half_width_samples", true);
    validate_positive_scalar(symmetry.score_smoothing_span_fraction, ...
        "center.max_mirrored_correlation.score_smoothing_span_fraction", false);

    require_exact_struct(options.spatial, ...
        {'method', 'interval_fraction', 'manual_interval_count'}, ...
        "DispersionWindowOptions.spatial");
    options.spatial.method = validate_method(options.spatial.method, ...
        ["fraction_of_bmode", "manual_interval_count"], ...
        "spatial.method");
    validate_positive_scalar(options.spatial.interval_fraction, ...
        "spatial.interval_fraction", false);
    validate_optional_positive_integer(options.spatial.manual_interval_count, ...
        "spatial.manual_interval_count");
    if options.spatial.method == "manual_interval_count" && ...
            isempty(options.spatial.manual_interval_count)
        invalid('spatial.manual_interval_count is required for its method.');
    end

    require_exact_struct(options.directional_offsets, ...
        {'left_samples', 'right_samples'}, ...
        "DispersionWindowOptions.directional_offsets");
    validate_integer_scalar(options.directional_offsets.left_samples, ...
        "directional_offsets.left_samples");
    validate_integer_scalar(options.directional_offsets.right_samples, ...
        "directional_offsets.right_samples");

    require_exact_struct(options.temporal, ...
        {'start_index_inclusive', 'method', 'manual_interval_count', ...
         'cycle_count'}, "DispersionWindowOptions.temporal");
    validate_positive_scalar(options.temporal.start_index_inclusive, ...
        "temporal.start_index_inclusive", true);
    options.temporal.method = validate_method(options.temporal.method, ...
        ["manual_interval_count", "cycle_count", "to_end"], ...
        "temporal.method");
    validate_optional_positive_integer(options.temporal.manual_interval_count, ...
        "temporal.manual_interval_count");
    validate_positive_scalar(options.temporal.cycle_count, ...
        "temporal.cycle_count", false);
    if options.temporal.method == "manual_interval_count" && ...
            isempty(options.temporal.manual_interval_count)
        invalid('temporal.manual_interval_count is required for its method.');
    end

    options.boundary_policy = validate_method(options.boundary_policy, ...
        "shift_to_fit", "boundary_policy");
    if ~islogical(options.show_progress) || ~isscalar(options.show_progress)
        invalid('show_progress must be a logical scalar.');
    end
end

function require_exact_struct(value, expectedFields, pathValue)
    if ~isstruct(value) || ~isscalar(value)
        invalid('%s must be a scalar struct.', pathValue);
    end
    actual = fieldnames(value);
    missing = expectedFields(~ismember(expectedFields, actual));
    extra = actual(~ismember(actual, expectedFields));
    if ~isempty(missing) || ~isempty(extra)
        invalid('%s fields are invalid. Missing=%s; extra=%s.', pathValue, ...
            join_names(missing), join_names(extra));
    end
end

function value = validate_method(value, supported, fieldName)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        invalid('%s must be a supported string scalar.', fieldName);
    end
    value = lower(strtrim(string(value)));
    if ~any(value == supported)
        invalid('Unsupported %s: %s.', fieldName, value);
    end
end

function validate_manual_indices(value, method)
    if isempty(value)
        if method == "manual_local_index"
            invalid('center.manual_local_index is required for its method.');
        end
        return;
    end
    if ~isnumeric(value) || ~isvector(value) || any(~isfinite(value)) || ...
            any(value < 1) || any(value ~= round(value))
        invalid('center.manual_local_index must contain positive integers.');
    end
end

function validate_fraction_range(value, fieldName)
    if ~isnumeric(value) || ~isequal(size(value), [1 2]) || ...
            any(~isfinite(value)) || value(1) < 0 || value(2) > 1 || ...
            value(1) >= value(2)
        invalid('%s must be an increasing two-value row within [0, 1].', ...
            fieldName);
    end
end

function validate_optional_positive_integer(value, fieldName)
    if ~isempty(value)
        validate_positive_scalar(value, fieldName, true);
    end
end

function validate_positive_scalar(value, fieldName, requireInteger)
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0 || ...
            (requireInteger && value ~= round(value))
        invalid('%s must be a positive finite%s scalar.', fieldName, ...
            conditional(requireInteger, ' integer', ''));
    end
end

function validate_integer_scalar(value, fieldName)
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
            value ~= round(value)
        invalid('%s must be a finite integer scalar.', fieldName);
    end
end

function value = conditional(condition, trueValue, falseValue)
    if condition, value = trueValue; else, value = falseValue; end
end

function value = join_names(names)
    if isempty(names), value = '<none>'; else, value = strjoin(names, ', '); end
end

function invalid(message, varargin)
    error('OCE:Config:InvalidDispersionWindowOptions', message, varargin{:});
end
