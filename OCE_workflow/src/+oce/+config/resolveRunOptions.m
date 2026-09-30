function resolved = resolveRunOptions(runOptions, outputOptions)
%RESOLVERUNOPTIONS Resolve fixed-order pipeline and side-effect options.

    if nargin < 1 || isempty(runOptions)
        runOptions = struct();
    end
    outputWasProvided = nargin >= 2 && ~isempty(outputOptions);
    if ~outputWasProvided
        outputOptions = struct();
    end
    validate_scalar_struct(runOptions, 'RunOptions');
    validate_scalar_struct(outputOptions, 'OutputOptions');
    allowedRun = ["stop_after"; "return_intermediate_products"; "parallel"];
    assert_no_unknown_fields(runOptions, allowedRun, ...
        'OCE:Pipeline:InvalidRunOptions', 'RunOptions');
    stages = ["reconstruction"; "borders"; "phase_estimation"; ...
        "filtering"; "dispersion_windows"; "dispersion_analysis"; ...
        "scientific_result"];
    stopAfter = string_value(runOptions, 'stop_after', "scientific_result");
    if ~isscalar(stopAfter) || ~ismember(stopAfter, stages)
        error('OCE:Pipeline:UnknownStopAfter', ...
            'Unknown RunOptions.stop_after value: "%s".', stopAfter);
    end
    returnMode = string_value(runOptions, ...
        'return_intermediate_products', "required");
    if ~isscalar(returnMode) || ...
            ~ismember(returnMode, ["none", "required", "all"])
        error('OCE:Pipeline:InvalidRunOptions', ...
            ['RunOptions.return_intermediate_products must be ' ...
             '"none", "required", or "all".']);
    end
    parallel = resolve_parallel_options(runOptions);
    outputDefaults = default_output_options( ...
        stopAfter == "scientific_result" && ~outputWasProvided);
    output = merge_output_options(outputDefaults, outputOptions);
    requiredProducts = stages(1:find(stages == stopAfter, 1));
    validate_output_availability(output, requiredProducts);
    resolved = struct( ...
        'stop_after', stopAfter, ...
        'required_products', requiredProducts, ...
        'return_intermediate_products', returnMode, ...
        'parallel', parallel, ...
        'plotting', struct( ...
            'reconstruction_preview', output.save_reconstruction_preview, ...
            'border_preview', output.save_border_preview, ...
            'filter_preview', output.save_filter_preview, ...
            'dispersion_window_context', ...
                output.save_dispersion_window_context, ...
            'kf_plots', output.save_kf_plots, ...
            'dispersion_plots', output.save_dispersion_plots, ...
            'polar_plots', output.save_polar_plots), ...
        'video', struct( ...
            'filtered_motion', output.save_filtered_motion_video), ...
        'persistence', struct( ...
            'scientific_result', output.save_scientific_result), ...
        'output_options', output, ...
        'requires_output_directory', any_output(output));
end

function parallel = resolve_parallel_options(runOptions)
    parallel = struct( ...
        'enabled', true, ...
        'worker_count', 4, ...
        'pool_type', "processes", ...
        'active', false);
    if ~isfield(runOptions, 'parallel')
        return;
    end
    supplied = runOptions.parallel;
    if ~isstruct(supplied) || ~isscalar(supplied)
        error('OCE:Pipeline:InvalidParallelOptions', ...
            'RunOptions.parallel must be a scalar struct.');
    end
    allowed = ["enabled"; "worker_count"];
    assert_no_unknown_fields(supplied, allowed, ...
        'OCE:Pipeline:InvalidParallelOptions', 'RunOptions.parallel');
    if isfield(supplied, 'enabled')
        if ~islogical(supplied.enabled) || ~isscalar(supplied.enabled)
            error('OCE:Pipeline:InvalidParallelOptions', ...
                'RunOptions.parallel.enabled must be a logical scalar.');
        end
        parallel.enabled = supplied.enabled;
    end
    if isfield(supplied, 'worker_count')
        count = supplied.worker_count;
        if ~isnumeric(count) || ~isscalar(count) || ~isfinite(count) || ...
                count < 1 || count ~= round(count)
            error('OCE:Pipeline:InvalidParallelOptions', ...
                ['RunOptions.parallel.worker_count must be a positive ' ...
                 'integer scalar.']);
        end
        parallel.worker_count = double(count);
    end
end

function output = default_output_options(fullDefaults)
    output = struct( ...
        'save_scientific_result', fullDefaults, ...
        'save_reconstruction_preview', false, ...
        'save_border_preview', fullDefaults, ...
        'save_filter_preview', fullDefaults, ...
        'save_dispersion_window_context', false, ...
        'save_kf_plots', false, ...
        'save_dispersion_plots', fullDefaults, ...
        'save_polar_plots', fullDefaults, ...
        'save_filtered_motion_video', false, ...
        'phase_clim_mode', "robust", ...
        'phase_clim', [], ...
        'video_clim_mode', "robust", ...
        'video_clim', [], ...
        'close_figures', false);
end

function merged = merge_output_options(defaults, supplied)
    allowed = string(fieldnames(defaults));
    assert_no_unknown_fields(supplied, allowed, ...
        'OCE:Pipeline:InvalidOutputOption', 'OutputOptions');
    merged = defaults;
    climFields = ["phase_clim_mode", "phase_clim", ...
        "video_clim_mode", "video_clim"];
    names = fieldnames(supplied);
    for index = 1:numel(names)
        name = string(names{index});
        value = supplied.(names{index});
        if ismember(name, climFields)
            merged.(names{index}) = value;
            continue;
        end
        if ~islogical(value) || ~isscalar(value)
            error('OCE:Pipeline:InvalidOutputOption', ...
                'OutputOptions.%s must be a logical scalar.', names{index});
        end
        merged.(names{index}) = value;
    end
    merged = resolve_clim_options(merged, "phase");
    merged = resolve_clim_options(merged, "video");
end

function output = resolve_clim_options(output, prefix)
    modeField = char(prefix + "_clim_mode");
    climField = char(prefix + "_clim");
    mode = output.(modeField);
    if ~(ischar(mode) || (isstring(mode) && isscalar(mode)))
        error('OCE:Pipeline:InvalidOutputCLimMode', ...
            'OutputOptions.%s must be a text scalar.', modeField);
    end
    mode = lower(strtrim(string(mode)));
    if ~ismember(mode, ["auto", "robust", "manual"])
        error('OCE:Pipeline:InvalidOutputCLimMode', ...
            'OutputOptions.%s must be "auto", "robust", or "manual".', ...
            modeField);
    end
    output.(modeField) = mode;

    configured = output.(climField);
    if mode ~= "manual"
        if ~isempty(configured)
            error('OCE:Pipeline:UnexpectedOutputCLim', ...
                'OutputOptions.%s must be empty unless %s="manual".', ...
                climField, modeField);
        end
        return;
    end
    if isempty(configured) || ~isnumeric(configured) || ...
            any(~isfinite(configured(:))) || ...
            ~(isscalar(configured) || numel(configured) == 2)
        error('OCE:Pipeline:InvalidOutputCLim', ...
            ['Manual OutputOptions.%s must be a positive scalar or an ' ...
             'increasing [low high] pair.'], climField);
    end
    if isscalar(configured)
        if configured <= 0
            error('OCE:Pipeline:InvalidOutputCLim', ...
                'Scalar manual OutputOptions.%s must be positive.', climField);
        end
        output.(climField) = double(configured);
        return;
    end

    configured = reshape(double(configured), 1, 2);
    if configured(1) >= configured(2)
        error('OCE:Pipeline:InvalidOutputCLim', ...
            'Manual OutputOptions.%s must contain increasing limits.', ...
            climField);
    end
    output.(climField) = configured;
end

function validate_output_availability(output, available)
    requirements = {
        'save_reconstruction_preview', 'reconstruction';
        'save_border_preview', 'borders';
        'save_filter_preview', 'filtering';
        'save_filtered_motion_video', 'filtering';
        'save_dispersion_window_context', 'dispersion_windows';
        'save_kf_plots', 'dispersion_analysis';
        'save_dispersion_plots', 'dispersion_analysis';
        'save_polar_plots', 'scientific_result';
        'save_scientific_result', 'scientific_result'};
    for index = 1:size(requirements, 1)
        option = requirements{index, 1};
        product = requirements{index, 2};
        if output.(option) && ~ismember(string(product), available)
            error('OCE:Pipeline:MissingRequiredProduct', ...
                ['OutputOptions.%s requires product "%s", but the run ' ...
                 'stops after "%s".'], option, product, available(end));
        end
    end
end

function tf = any_output(output)
    names = string(fieldnames(output));
    saveNames = cellstr(names(startsWith(names, "save_")));
    tf = any(cellfun(@(name) output.(name), saveNames));
end

function value = string_value(source, name, fallback)
    if isfield(source, name)
        candidate = source.(name);
        if ~(ischar(candidate) || (isstring(candidate) && isscalar(candidate)))
            error('OCE:Pipeline:InvalidRunOptions', ...
                'RunOptions.%s must be a text scalar.', name);
        end
        value = lower(strtrim(string(candidate)));
    else
        value = fallback;
    end
end

function validate_scalar_struct(value, label)
    if ~isstruct(value) || ~isscalar(value)
        error('OCE:Pipeline:InvalidRunOptions', ...
            '%s must be a scalar struct.', label);
    end
end

function assert_no_unknown_fields(value, allowed, identifier, label)
    unknown = setdiff(string(fieldnames(value)), allowed);
    if ~isempty(unknown)
        error(identifier, '%s contains unsupported field: %s.', ...
            label, unknown(1));
    end
end
