function resolvedOptions = resolvePhaseEstimationOptions(baseOptions)
%RESOLVEPHASEESTIMATIONOPTIONS Validate and resolve phase estimators once.
%
% The editable configuration owns quantity, estimator, surface sampling,
% Loupas windows, and smoothing. The resolved contract adds fixed provenance:
% values are in radians and temporal differences are along the time axis.

    if nargin < 1 || ~isstruct(baseOptions) || ~isscalar(baseOptions)
        error('OCE:Motion:InvalidOptions', ...
            'MotionOptions must be a scalar structure.');
    end

    require_fields(baseOptions, ...
        ["depth_resolved"; "surface"; "show_progress"], "MotionOptions");

    resolvedOptions = struct();
    resolvedOptions.depth_resolved = resolve_depth_options( ...
        baseOptions.depth_resolved);
    resolvedOptions.surface = resolve_surface_options(baseOptions.surface);
    resolvedOptions.difference_axis = "time";
    resolvedOptions.show_progress = validate_logical_scalar( ...
        baseOptions.show_progress, "MotionOptions.show_progress");
end

function options = resolve_depth_options(base)
    require_fields(base, ["quantity"; "estimator"; "loupas"; "smoothing"], ...
        "MotionOptions.depth_resolved");

    options = struct();
    options.quantity = validate_quantity(base.quantity, ...
        "MotionOptions.depth_resolved.quantity");
    options.estimator = validate_estimator(base.estimator, ...
        "MotionOptions.depth_resolved.estimator");
    validate_combination(options.quantity, options.estimator, ...
        "depth-resolved");
    options.units = "rad";
    options.layout = "lateral_depth_time";
    options.loupas = resolve_loupas(base.loupas, options.estimator, ...
        "MotionOptions.depth_resolved.loupas");
    options.smoothing = resolve_smoothing(base.smoothing, ...
        "MotionOptions.depth_resolved.smoothing");
end

function options = resolve_surface_options(base)
    require_fields(base, ["quantity"; "estimator"; "surface_reference"; ...
        "depth_offset_samples"; "aggregation_band_samples"; "loupas"; ...
        "smoothing"], "MotionOptions.surface");

    options = struct();
    options.quantity = validate_quantity(base.quantity, ...
        "MotionOptions.surface.quantity");
    options.estimator = validate_estimator(base.estimator, ...
        "MotionOptions.surface.estimator");
    validate_combination(options.quantity, options.estimator, "surface");
    options.units = "rad";
    options.layout = "lateral_time";

    reference = validate_string_scalar(base.surface_reference, ...
        'OCE:Motion:InvalidSurfaceSampling', ...
        "MotionOptions.surface.surface_reference");
    reference = lower(strtrim(reference));
    if reference ~= "anterior"
        error('OCE:Motion:UnsupportedSurfaceReference', ...
            ['Unsupported surface reference "%s". The maintained phase ' ...
            'estimator accepts only "anterior".'], reference);
    end
    options.surface_reference = reference;
    options.depth_offset_samples = validate_integer_scalar( ...
        base.depth_offset_samples, false, ...
        "MotionOptions.surface.depth_offset_samples");
    options.aggregation_band_samples = validate_integer_scalar( ...
        base.aggregation_band_samples, true, ...
        "MotionOptions.surface.aggregation_band_samples");
    options.loupas = resolve_loupas(base.loupas, options.estimator, ...
        "MotionOptions.surface.loupas");
    options.smoothing = resolve_smoothing(base.smoothing, ...
        "MotionOptions.surface.smoothing");
end

function loupas = resolve_loupas(base, estimator, path)
    if ~isstruct(base) || ~isscalar(base) || ...
            ~isfield(base, 'axial_window_samples')
        error('OCE:Motion:InvalidLoupasWindow', ...
            '%s.axial_window_samples is required.', path);
    end

    value = base.axial_window_samples;
    if estimator == "loupas"
        value = validate_loupas_window(value, path);
        if value < 2
            error('OCE:Motion:InvalidLoupasWindow', ...
                '%s.axial_window_samples must be at least 2.', path);
        end
    elseif ~isempty(value)
        value = validate_loupas_window(value, path);
    end
    loupas = struct('axial_window_samples', value);
end

function smoothing = resolve_smoothing(base, path)
    if ~isstruct(base) || ~isscalar(base)
        error('OCE:Motion:InvalidSmoothing', ...
            '%s must be a scalar structure.', path);
    end
    require_fields(base, ["method"; "span_fraction"], path);
    method = validate_string_scalar(base.method, ...
        'OCE:Motion:InvalidSmoothing', path + ".method");
    method = lower(strtrim(method));
    if ~ismember(method, ["lowess", "none"])
        error('OCE:Motion:InvalidSmoothing', ...
            'Unsupported smoothing method "%s" at %s.', method, path);
    end

    if method == "lowess"
        span = base.span_fraction;
        if ~isnumeric(span) || ~isscalar(span) || ~isfinite(span) || ...
                span <= 0 || span > 1
            error('OCE:Motion:InvalidSmoothing', ...
                '%s.span_fraction must satisfy 0 < span <= 1.', path);
        end
    else
        if ~isempty(base.span_fraction)
            error('OCE:Motion:InvalidSmoothing', ...
                '%s.span_fraction must be empty when method="none".', path);
        end
        span = [];
    end
    smoothing = struct('method', method, 'span_fraction', span);
end

function quantity = validate_quantity(value, path)
    quantity = validate_string_scalar(value, ...
        'OCE:Motion:InvalidQuantity', path);
    quantity = lower(strtrim(quantity));
    if ~ismember(quantity, ["wrapped_phase", "phase_increment"])
        error('OCE:Motion:InvalidQuantity', ...
            ['Unsupported phase quantity "%s" at %s. Supported values are ' ...
            '"wrapped_phase" and "phase_increment".'], quantity, path);
    end
end

function estimator = validate_estimator(value, path)
    estimator = validate_string_scalar(value, ...
        'OCE:Motion:UnsupportedEstimator', path);
    estimator = lower(strtrim(estimator));
    if ~ismember(estimator, ...
            ["direct_phase", "unwrap_then_difference", "loupas"])
        error('OCE:Motion:UnsupportedEstimator', ...
            ['Unsupported phase estimator "%s" at %s. Supported values are ' ...
            '"direct_phase", "unwrap_then_difference", and "loupas".'], ...
            estimator, path);
    end
end

function validate_combination(quantity, estimator, owner)
    valid = (quantity == "wrapped_phase" && estimator == "direct_phase") || ...
        (quantity == "phase_increment" && ...
        ismember(estimator, ["unwrap_then_difference", "loupas"]));
    if ~valid
        error('OCE:Motion:InvalidEstimatorCombination', ...
            'Quantity "%s" is incompatible with estimator "%s" for %s phase.', ...
            quantity, estimator, owner);
    end
end

function value = validate_string_scalar(value, identifier, path)
    if ~(ischar(value) || (isstring(value) && isscalar(value))) || ...
            (isstring(value) && ismissing(value))
        error(identifier, '%s must be a nonmissing string scalar.', path);
    end
    value = string(value);
    if strlength(strtrim(value)) == 0
        error(identifier, '%s must not be empty.', path);
    end
end

function value = validate_integer_scalar(value, positive, path)
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
            value ~= fix(value) || (positive && value < 1)
        error('OCE:Motion:InvalidSurfaceSampling', ...
            '%s must be a finite integer.', path);
    end
end

function value = validate_loupas_window(value, path)
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
            value ~= fix(value) || value < 1
        error('OCE:Motion:InvalidLoupasWindow', ...
            '%s.axial_window_samples must be a positive finite integer.', ...
            path);
    end
end

function value = validate_logical_scalar(value, path)
    if ~(islogical(value) && isscalar(value))
        error('OCE:Motion:InvalidOptions', ...
            '%s must be a logical scalar.', path);
    end
end

function require_fields(value, names, path)
    if ~isstruct(value) || ~isscalar(value)
        error('OCE:Motion:InvalidOptions', ...
            '%s must be a scalar structure.', path);
    end
    for index = 1:numel(names)
        if ~isfield(value, names(index))
            error('OCE:Motion:MissingOption', ...
                'Missing required phase-estimation option: %s.%s.', ...
                path, names(index));
        end
    end
    unexpected = setdiff(string(fieldnames(value)), names, 'stable');
    if ~isempty(unexpected)
        error('OCE:Motion:InvalidOptions', ...
            'Unexpected phase-estimation option at %s: %s.', ...
            path, strjoin(unexpected, ', '));
    end
end
