function result = computeSurfacePhase( ...
        complexVolume, surfaceIndices, resolvedOptions, varargin)
%COMPUTESURFACEPHASE Estimate phase along the anterior surface.
%
% The input volume layout is [lateral, depth, time]. Surface indices follow
% lateral position. Values remain in radians; no physical conversion,
% intensity masking, or bulk correction is applied.

    parser = inputParser;
    addParameter(parser, 'UseParallel', false, ...
        @(value) islogical(value) && isscalar(value));
    parse(parser, varargin{:});
    useParallel = parser.Results.UseParallel;

    validate_complex_volume(complexVolume);
    options = validate_resolved_options(resolvedOptions);
    [numLateral, numDepth, numTime] = size(complexVolume);
    validate_surface_sampling(surfaceIndices, numLateral, numDepth, options);

    outputTime = numTime - double(options.quantity == "phase_increment");
    values = NaN(numLateral, outputTime, 'like', complexVolume);
    showProgress = resolvedOptions.show_progress;
    if showProgress
        fprintf('Surface phase: starting\n');
    end

    if useParallel
        parfor lateralIndex = 1:numLateral
            frame = squeeze(complexVolume(lateralIndex, :, :));
            values(lateralIndex, :) = compute_lateral_signal( ...
                frame, surfaceIndices(lateralIndex), outputTime, options);
        end
    else
        nextProgressPercent = 10;
        for lateralIndex = 1:numLateral
            frame = squeeze(complexVolume(lateralIndex, :, :));
            values(lateralIndex, :) = compute_lateral_signal( ...
                frame, surfaceIndices(lateralIndex), outputTime, options);
            nextProgressPercent = update_progress( ...
                showProgress, lateralIndex, numLateral, nextProgressPercent);
        end
    end

    result = struct( ...
        'values', values, ...
        'quantity', options.quantity, ...
        'units', options.units, ...
        'estimator', options.estimator, ...
        'layout', options.layout, ...
        'difference_axis', resolvedOptions.difference_axis, ...
        'surface_reference', options.surface_reference, ...
        'depth_offset_samples', options.depth_offset_samples, ...
        'aggregation_band_samples', options.aggregation_band_samples, ...
        'smoothing', options.smoothing);
    if showProgress
        fprintf('Surface phase: complete\n');
    end
end

function signalRow = compute_lateral_signal( ...
        frame, rawSurfaceIndex, outputTime, options)
    signalRow = NaN(1, outputTime, 'like', frame);
    if ~isfinite(rawSurfaceIndex)
        return;
    end

    surfaceIndex = round(rawSurfaceIndex) + options.depth_offset_samples;
    band = surfaceIndex:(surfaceIndex + ...
        options.aggregation_band_samples - 1);

    switch options.estimator
        case {"direct_phase", "unwrap_then_difference"}
            signal = -angle(mean(frame(band, :), 1).');
            if options.estimator == "unwrap_then_difference"
                signal = diff(unwrap(signal, [], 1), 1, 1);
            end

        case "loupas"
            window = options.loupas.axial_window_samples;
            phaseIncrement = oce.motion.estimateLoupasPhaseIncrement( ...
                frame, window);
            adjustedIndex = surfaceIndex - round(window / 2);
            adjustedIndex = min(max(adjustedIndex, 1), ...
                size(phaseIncrement, 1));
            if options.smoothing.method == "none"
                signal = phaseIncrement(adjustedIndex, :).';
            else
                % Preserved scientific contract: enabling temporal LOWESS
                % also enables axial aggregation of the Loupas estimate.
                adjustedBand = adjustedIndex:min( ...
                    size(phaseIncrement, 1), adjustedIndex + ...
                    options.aggregation_band_samples - 1);
                signal = mean(phaseIncrement(adjustedBand, :), 1).';
            end
    end

    if options.smoothing.method == "lowess"
        signal = smooth(signal, ...
            options.smoothing.span_fraction, 'lowess');
    end
    signalRow = signal(:).';
end

function options = validate_resolved_options(resolved)
    if ~isstruct(resolved) || ~isscalar(resolved) || ...
            ~isfield(resolved, 'surface') || ...
            ~isfield(resolved, 'difference_axis') || ...
            ~isfield(resolved, 'show_progress')
        error('OCE:Motion:InvalidResolvedOptions', ...
            'A resolved phase-estimation contract is required.');
    end
    options = resolved.surface;
    required = ["quantity"; "estimator"; "units"; "layout"; ...
        "surface_reference"; "depth_offset_samples"; ...
        "aggregation_band_samples"; "loupas"; "smoothing"];
    if any(~isfield(options, required)) || options.units ~= "rad" || ...
            options.layout ~= "lateral_time" || ...
            resolved.difference_axis ~= "time" || ...
            options.surface_reference ~= "anterior" || ...
            ~valid_combination(options.quantity, options.estimator)
        error('OCE:Motion:InvalidResolvedOptions', ...
            'The surface phase contract is incomplete or invalid.');
    end
end

function valid = valid_combination(quantity, estimator)
    valid = (quantity == "wrapped_phase" && estimator == "direct_phase") || ...
        (quantity == "phase_increment" && ...
        ismember(estimator, ["unwrap_then_difference", "loupas"]));
end

function validate_surface_sampling(indices, numLateral, numDepth, options)
    validateattributes(indices, {'numeric'}, {'vector', 'numel', numLateral}, ...
        mfilename, 'surfaceIndices');
    finiteIndices = round(indices(isfinite(indices))) + ...
        options.depth_offset_samples;
    if any(finiteIndices < 1 | finiteIndices > numDepth)
        error('OCE:Motion:SurfaceOutOfRange', ...
            'Offset anterior surface indices fall outside the volume depth.');
    end
    if any(finiteIndices + options.aggregation_band_samples - 1 > numDepth)
        error('OCE:Motion:SurfaceBandOutOfRange', ...
            'The complete surface aggregation band exceeds the volume depth.');
    end
end

function validate_complex_volume(value)
    validateattributes(value, {'numeric'}, {'nonempty', '3d'}, ...
        mfilename, 'complexVolume');
    if isreal(value)
        error('OCE:Motion:RealInput', ...
            'complexVolume must contain complex OCT data.');
    end
end

function nextPercent = update_progress(enabled, current, total, nextPercent)
    if ~enabled
        return;
    end
    completedPercent = floor(100 * current / total);
    while nextPercent <= 100 && completedPercent >= nextPercent
        print_progress(nextPercent);
        nextPercent = nextPercent + 10;
    end
end

function print_progress(percent)
    completedBlocks = percent / 10;
    bar = [repmat('#', 1, completedBlocks), ...
        repmat('.', 1, 10 - completedBlocks)];
    fprintf('Surface phase [%s] %d%%\n', bar, percent);
end
