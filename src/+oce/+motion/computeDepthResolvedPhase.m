function result = computeDepthResolvedPhase(complexVolume, resolvedOptions, varargin)
%COMPUTEDEPTHRESOLVEDPHASE Estimate depth-resolved phase in radians.
%
% complexVolume layout is [lateral, depth, time]. The resolved options must
% come from oce.config.resolvePhaseEstimationOptions. This function does not
% convert phase to displacement or velocity and is silent by default.

    parser = inputParser;
    addParameter(parser, 'UseParallel', false, ...
        @(value) islogical(value) && isscalar(value));
    parse(parser, varargin{:});
    useParallel = parser.Results.UseParallel;

    validate_complex_volume(complexVolume);
    options = validate_resolved_options(resolvedOptions);
    numLateral = size(complexVolume, 1);
    showProgress = resolvedOptions.show_progress;
    if showProgress
        fprintf('Depth-resolved phase: starting\n');
    end

    switch options.estimator
        case "direct_phase"
            values = -angle(complexVolume);

        case "unwrap_then_difference"
            phase = -angle(complexVolume);
            values = diff(unwrap(phase, [], 3), 1, 3);

        case "loupas"
            window = options.loupas.axial_window_samples;
            if window > size(complexVolume, 2)
                error('OCE:Motion:InvalidLoupasWindow', ...
                    'The Loupas axial window exceeds the volume depth.');
            end
            values = zeros(numLateral, ...
                size(complexVolume, 2) - window + 1, ...
                size(complexVolume, 3) - 1, 'like', complexVolume);
            nextProgressPercent = 10;
            for lateralIndex = 1:numLateral
                frame = squeeze(complexVolume(lateralIndex, :, :));
                values(lateralIndex, :, :) = ...
                    oce.motion.estimateLoupasPhaseIncrement(frame, window);
                nextProgressPercent = update_progress( ...
                    showProgress, lateralIndex, numLateral, ...
                    nextProgressPercent, "Depth-resolved phase");
            end
    end

    values = smooth_depth_traces( ...
        values, options.smoothing, showProgress, useParallel);
    result = struct( ...
        'values', values, ...
        'quantity', options.quantity, ...
        'units', options.units, ...
        'estimator', options.estimator, ...
        'layout', options.layout, ...
        'difference_axis', resolvedOptions.difference_axis, ...
        'smoothing', options.smoothing);
    if showProgress
        fprintf('Depth-resolved phase: complete\n');
    end
end

function options = validate_resolved_options(resolved)
    if ~isstruct(resolved) || ~isscalar(resolved) || ...
            ~isfield(resolved, 'depth_resolved') || ...
            ~isfield(resolved, 'difference_axis') || ...
            ~isfield(resolved, 'show_progress')
        error('OCE:Motion:InvalidResolvedOptions', ...
            'A resolved phase-estimation contract is required.');
    end
    options = resolved.depth_resolved;
    required = ["quantity"; "estimator"; "units"; "layout"; ...
        "loupas"; "smoothing"];
    if any(~isfield(options, required)) || ...
            options.units ~= "rad" || ...
            options.layout ~= "lateral_depth_time" || ...
            resolved.difference_axis ~= "time" || ...
            ~valid_combination(options.quantity, options.estimator)
        error('OCE:Motion:InvalidResolvedOptions', ...
            'The depth-resolved phase contract is incomplete or invalid.');
    end
end

function valid = valid_combination(quantity, estimator)
    valid = (quantity == "wrapped_phase" && estimator == "direct_phase") || ...
        (quantity == "phase_increment" && ...
        ismember(estimator, ["unwrap_then_difference", "loupas"]));
end

function values = smooth_depth_traces(values, smoothing, showProgress, useParallel)
    if smoothing.method == "none"
        return;
    end
    span = smoothing.span_fraction;
    numLateral = size(values, 1);
    smoothed = zeros(size(values), 'like', values);

    if useParallel
        parfor lateralIndex = 1:numLateral
            localInput = squeeze(values(lateralIndex, :, :));
            localOutput = zeros(size(localInput), 'like', localInput);
            for depthIndex = 1:size(localInput, 1)
                trace = localInput(depthIndex, :).';
                localOutput(depthIndex, :) = ...
                    smooth(trace, span, 'lowess').';
            end
            smoothed(lateralIndex, :, :) = reshape( ...
                localOutput, 1, size(localOutput, 1), size(localOutput, 2));
        end
        values = smoothed;
        return;
    end

    nextProgressPercent = 10;
    for lateralIndex = 1:numLateral
        for depthIndex = 1:size(values, 2)
            trace = squeeze(values(lateralIndex, depthIndex, :));
            smoothed(lateralIndex, depthIndex, :) = ...
                smooth(trace, span, 'lowess');
        end
        nextProgressPercent = update_progress( ...
            showProgress, lateralIndex, numLateral, nextProgressPercent, ...
            "Depth-resolved phase");
    end
    values = smoothed;
end

function validate_complex_volume(value)
    validateattributes(value, {'numeric'}, {'nonempty', '3d'}, ...
        mfilename, 'complexVolume');
    if isreal(value)
        error('OCE:Motion:RealInput', ...
            'complexVolume must contain complex OCT data.');
    end
end

function nextPercent = update_progress( ...
        enabled, current, total, nextPercent, label)
    if ~enabled
        return;
    end
    completedPercent = floor(100 * current / total);
    while nextPercent <= 100 && completedPercent >= nextPercent
        print_progress(label, nextPercent);
        nextPercent = nextPercent + 10;
    end
end

function print_progress(label, percent)
    completedBlocks = percent / 10;
    bar = [repmat('#', 1, completedBlocks), ...
        repmat('.', 1, 10 - completedBlocks)];
    fprintf('%s [%s] %d%%\n', label, bar, percent);
end
