function resolved = resolveBorderOptions(baseOptions, acquisitionRow, resolvedCrop)
%RESOLVEBORDEROPTIONS Resolve one acquisition's effective border contract.
% Input: editable base BorderOptions, one acquisition metadata row, and
% the resolved acquisition crop.
% Output: one resolved method, its effective parameters, and selection
% provenance. Side effects: none.

    if nargin < 1 || ~isstruct(baseOptions) || ~isscalar(baseOptions)
        error('OCE:Config:InvalidBorderSelection', ...
            'BorderOptions must be a scalar editable configuration struct.');
    end
    if nargin < 2
        acquisitionRow = table();
    end
    if nargin < 3
        resolvedCrop = struct();
    end

    require_base_fields(baseOptions);
    selection = require_scalar_text(baseOptions.selection, ...
        'OCE:Config:InvalidBorderSelection', ...
        'BorderOptions.selection must be "automatic" or "manual".');
    selection = lower(strtrim(selection));

    switch selection
        case "automatic"
            [method, selectionMetadata] = resolve_automatic_method(acquisitionRow);
            selectionSource = "acquisition_row.sample_type";
        case "manual"
            method = require_manual_method(baseOptions);
            selectionSource = "manual_configuration";
            selectionMetadata = struct();
        otherwise
            error('OCE:Config:InvalidBorderSelection', ...
                ['Unsupported BorderOptions.selection "%s". Supported ' ...
                 'values are "automatic" and "manual".'], selection);
    end

    parameters = select_method_parameters( ...
        baseOptions, method, resolvedCrop);
    surfaceMode = resolved_surface_mode(method, parameters);
    lateralEdgeExclusion = resolve_lateral_edge_exclusion(baseOptions);
    resolved = struct( ...
        'selection', selection, ...
        'method', method, ...
        'surface_mode', surfaceMode, ...
        'selection_source', selectionSource, ...
        'selection_metadata', selectionMetadata, ...
        'mask_threshold', baseOptions.mask_threshold, ...
        'lateral_edge_exclusion', lateralEdgeExclusion, ...
        'parameters', parameters);
end

function require_base_fields(options)
    required = ["selection"; "method"; "mask_threshold"; ...
        "corneal_preprocessing"; "methods"];
    missing = required(~isfield(options, required));
    if ~isempty(missing)
        error('OCE:Config:InvalidBorderSelection', ...
            'Editable BorderOptions is missing field(s): %s.', ...
            strjoin(missing, ', '));
    end
    if ~isnumeric(options.mask_threshold) || ...
            ~isscalar(options.mask_threshold) || ...
            ~isfinite(options.mask_threshold)
        error('OCE:Config:InvalidBorderSelection', ...
            'BorderOptions.mask_threshold must be one finite numeric scalar.');
    end
    if ~isstruct(options.corneal_preprocessing) || ...
            ~isscalar(options.corneal_preprocessing) || ...
            ~isstruct(options.methods) || ~isscalar(options.methods)
        error('OCE:Config:InvalidBorderSelection', ...
            ['BorderOptions.corneal_preprocessing and BorderOptions.methods ' ...
             'must be scalar structs.']);
    end
end

function [method, metadata] = resolve_automatic_method(acquisitionRow)
    if ~istable(acquisitionRow) || height(acquisitionRow) ~= 1
        error('OCE:Config:AmbiguousSampleType', ...
            ['Automatic border selection requires exactly one acquisition ' ...
             'metadata row. Correct acquisition_row or use manual selection.']);
    end
    if ~ismember('sample_type', acquisitionRow.Properties.VariableNames)
        error('OCE:Config:UnknownSampleType', ...
            ['Automatic border selection requires acquisition_row.sample_type. ' ...
             'Add a supported sample_type or use manual selection.']);
    end

    rawValue = acquisitionRow.sample_type;
    if iscell(rawValue) && isscalar(rawValue)
        rawValue = rawValue{1};
    end
    values = string(rawValue);
    if numel(values) ~= 1
        error('OCE:Config:AmbiguousSampleType', ...
            ['Automatic border selection received multiple sample_type ' ...
             'values. Provide one value or use manual selection.']);
    end
    originalValue = strtrim(values);
    if ismissing(originalValue) || strlength(originalValue) == 0
        error('OCE:Config:UnknownSampleType', ...
            ['Automatic border selection received an empty sample_type. ' ...
             'Correct sample_type or use manual selection.']);
    end

    switch originalValue
        case "phantom"
            method = "phantom";
        case "in_vivo_eye"
            method = "in_vivo_corneal";
        case "ex_vivo_eye"
            method = "adaptive_corneal";
        otherwise
            error('OCE:Config:UnknownSampleType', ...
                ['Unsupported sample_type "%s" for automatic border ' ...
                 'selection. Correct sample_type or use manual selection.'], ...
                originalValue);
    end
    metadata = struct('sample_type', originalValue);
end

function method = require_manual_method(options)
    method = require_scalar_text(options.method, ...
        'OCE:Config:MissingBorderMethod', ...
        ['BorderOptions.method is required when ' ...
         'BorderOptions.selection="manual".']);
    method = strtrim(method);
    if strlength(method) == 0
        error('OCE:Config:MissingBorderMethod', ...
            ['BorderOptions.method is required when ' ...
             'BorderOptions.selection="manual".']);
    end
    validate_supported_method(method);
end

function parameters = select_method_parameters(options, method, resolvedCrop)
    validate_supported_method(method);
    if ~isfield(options.methods, char(method)) || ...
            ~isstruct(options.methods.(char(method))) || ...
            ~isscalar(options.methods.(char(method)))
        error('OCE:Config:InvalidBorderSelection', ...
            'BorderOptions.methods.%s must be a scalar struct.', method);
    end

    methodParameters = options.methods.(char(method));
    if method == "phantom" && isfield(methodParameters, 'edge_margin')
        methodParameters = rmfield(methodParameters, 'edge_margin');
    elseif method == "adaptive_corneal" && ...
            isfield(methodParameters, 'remove_lateral_edges')
        methodParameters = rmfield(methodParameters, 'remove_lateral_edges');
    end
    switch method
        case "phantom"
            parameters = resolve_phantom_parameters( ...
                methodParameters, resolvedCrop);
        case {"adaptive_corneal", "in_vivo_corneal"}
            parameters = merge_structs( ...
                options.corneal_preprocessing, methodParameters);
    end
end

function surfaceMode = resolved_surface_mode(method, parameters)
    if method == "phantom"
        surfaceMode = string(parameters.surface_mode);
    else
        surfaceMode = "anterior_posterior";
    end
end

function resolved = resolve_lateral_edge_exclusion(options)
    resolved = struct('enabled', false, 'fraction_per_side', 0.02);
    if isfield(options, 'lateral_edge_exclusion')
        resolved = options.lateral_edge_exclusion;
    end
    expected = ["enabled"; "fraction_per_side"];
    if ~isstruct(resolved) || ~isscalar(resolved) || ...
            ~isequal(string(fieldnames(resolved)), expected) || ...
            ~islogical(resolved.enabled) || ~isscalar(resolved.enabled) || ...
            ~isnumeric(resolved.fraction_per_side) || ...
            ~isscalar(resolved.fraction_per_side) || ...
            ~isreal(resolved.fraction_per_side) || ...
            ~isfinite(resolved.fraction_per_side) || ...
            resolved.fraction_per_side < 0 || ...
            resolved.fraction_per_side >= 0.5
        error('OCE:Config:InvalidBorderEdgeExclusion', ...
            ['BorderOptions.lateral_edge_exclusion requires logical scalar ' ...
             'enabled and finite fraction_per_side in [0, 0.5).']);
    end
end

function parameters = resolve_phantom_parameters(parameters, resolvedCrop)
    legacyFields = ["background_depth_range"; ...
        "background_lateral_range"; "min_depth_index"];
    for index = 1:numel(legacyFields)
        field = legacyFields(index);
        if isfield(parameters, field)
            parameters = rmfield(parameters, field);
        end
    end

    defaults = getDefaultBorderOptions("phantom").methods.phantom;
    if ~isfield(parameters, 'surface_mode')
        parameters.surface_mode = defaults.surface_mode;
    end
    surfaceMode = string(parameters.surface_mode);
    supportedSurfaceModes = ["anterior_posterior", "anterior_only"];
    if ~isscalar(surfaceMode) || ismissing(surfaceMode) || ...
            ~any(surfaceMode == supportedSurfaceModes)
        error('OCE:Config:InvalidBorderSurfaceMode', ...
            ['BorderOptions.methods.phantom.surface_mode must be ' ...
             '"anterior_posterior" or "anterior_only".']);
    end
    parameters.surface_mode = surfaceMode;

    if ~isfield(parameters, 'background_percentile')
        parameters.background_percentile = defaults.background_percentile;
    end
    if ~isnumeric(parameters.background_percentile) || ...
            ~isscalar(parameters.background_percentile) || ...
            ~isreal(parameters.background_percentile) || ...
            ~isfinite(parameters.background_percentile) || ...
            parameters.background_percentile <= 0 || ...
            parameters.background_percentile > 50
        error('OCE:Config:InvalidBorderSelection', ...
            ['BorderOptions.methods.phantom.background_percentile must be ' ...
             'one finite scalar in (0, 50].']);
    end

    if ~isfield(parameters, 'max_depth_index')
        error('OCE:Config:InvalidBorderSelection', ...
            'BorderOptions.methods.phantom is missing max_depth_index.');
    end
    if isempty(parameters.max_depth_index)
        if ~isstruct(resolvedCrop) || ...
                ~isfield(resolvedCrop, 'depth') || ...
                ~isstruct(resolvedCrop.depth) || ...
                ~isfield(resolvedCrop.depth, 'sample_count') || ...
                ~isnumeric(resolvedCrop.depth.sample_count) || ...
                ~isscalar(resolvedCrop.depth.sample_count) || ...
                ~isfinite(resolvedCrop.depth.sample_count) || ...
                resolvedCrop.depth.sample_count < 2
            error('OCE:Config:InvalidBorderSelection', ...
                ['Resolving phantom max_depth_index requires a valid ' ...
                 'resolved_crop.depth.sample_count value.']);
        end
        parameters.max_depth_index = min( ...
            900, round(resolvedCrop.depth.sample_count) - 1);
    end
end

function validate_supported_method(method)
    supported = ["phantom"; "adaptive_corneal"; "in_vivo_corneal"];
    if ~isscalar(method) || ~any(method == supported)
        error('OCE:Borders:UnsupportedMethod', ...
            ['Unsupported BorderOptions.method "%s". Supported methods are ' ...
             'phantom, adaptive_corneal, and in_vivo_corneal.'], ...
            join_for_error(method));
    end
end

function value = require_scalar_text(rawValue, identifier, message)
    if ~(ischar(rawValue) || isstring(rawValue))
        error(identifier, '%s', message);
    end
    value = string(rawValue);
    if ~isscalar(value) || ismissing(value)
        error(identifier, '%s', message);
    end
end

function base = merge_structs(base, override)
    names = fieldnames(override);
    for index = 1:numel(names)
        base.(names{index}) = override.(names{index});
    end
end

function value = join_for_error(method)
    value = string(method);
    if isempty(value)
        value = "<empty>";
    elseif ~isscalar(value)
        value = strjoin(value, ', ');
    end
end
