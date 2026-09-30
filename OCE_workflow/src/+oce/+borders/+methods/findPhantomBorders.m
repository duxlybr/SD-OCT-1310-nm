function [thickness, border, anteriorSurface, posteriorSurface] = findPhantomBorders(storageAxis, localAxisMm, bmode, geometry, depthAxisMm, borderOptions)
%FINDPHANTOMBORDERS Detect phantom borders independently by B-mode.
% depthAxisMm is the reconstruction depth axis, already sample-corrected.

    samplesPerBmode = geometry.samples_per_bmode;
    bmodeCount = geometry.bmode_count;
    lateralCount = geometry.lateral_sample_count;
    thickness = nan(lateralCount, 1);
    border = struct( ...
        'Idx', nan(1, lateralCount), ...
        'Inten', nan(1, lateralCount), ...
        'Idx_Up', nan(1, lateralCount), ...
        'Idx_Down', nan(1, lateralCount));
    anteriorSurface = [storageAxis(:), nan(lateralCount, 1)];
    posteriorSurface = [storageAxis(:), nan(lateralCount, 1)];

    for bmodeIndex = 1:bmodeCount
        range = (bmodeIndex - 1) * samplesPerBmode + (1:samplesPerBmode);
        localGeometry = geometry;
        localGeometry.lateral_sample_count = samplesPerBmode;
        localGeometry.bmode_count = 1;
        [localThickness, localBorder, localAnterior, localPosterior] = ...
            detect_single_bmode(storageAxis(range), localAxisMm, bmode(:, range), ...
                localGeometry, depthAxisMm, borderOptions);
        thickness(range) = localThickness;
        border.Idx(range) = localBorder.Idx;
        border.Inten(range) = localBorder.Inten;
        border.Idx_Up(range) = localBorder.Idx_Up;
        border.Idx_Down(range) = localBorder.Idx_Down;
        anteriorSurface(range, 2) = localAnterior(:, 2);
        posteriorSurface(range, 2) = localPosterior(:, 2);
    end
end

function [thickness, border, anteriorSurface, posteriorSurface] = ...
        detect_single_bmode(storageAxis, localAxisMm, bmode, geometry, ...
            depthAxisMm, opts)
    topSystem = geometry;
    topSystem.PeakThresMult = opts.top_peak_multiplier;
    topSystem.PeakThresWinSize = opts.peak_window_size;
    topSearchOffset = 0;
    if isfield(opts, 'top_search_offset')
        topSearchOffset = opts.top_search_offset;
    end
    topSystem.initial_depth_index = topSearchOffset + 1;
    border = oce.borders.findSurface(bmode, topSystem);
    border.Idx = border.Idx - opts.top_index_offset;
    border.Idx(border.Idx < 1 | border.Idx > opts.max_depth_index) = NaN;

    topInvalid = find_short_lateral_excursions(border.Idx, ...
        opts.max_lateral_jump, opts.max_jump_gap);
    border.Idx(topInvalid) = NaN;

    % Keep rejected candidates visible as NaN in the diagnostic contract, but
    % provide LOWESS with a bounded local replacement. Otherwise an edge run of
    % rejected samples can be extrapolated into an artificial axial cliff even
    % though the offending candidates were correctly identified.
    topForSmoothing = fill_rejected_short_excursions(border.Idx, topInvalid);
    top = smooth(topForSmoothing, opts.smooth_span, 'lowess');
    border.Idx_Up = round(top)';
    border.Idx_Up = min(max(border.Idx_Up, 1), opts.max_depth_index);
    border.Idx_Down = nan(size(border.Idx_Up));

    anteriorSurface = [storageAxis(:), interp1( ...
        1:numel(depthAxisMm), depthAxisMm, border.Idx_Up(:), 'linear', NaN)];
    posteriorSurface = [storageAxis(:), nan(numel(storageAxis), 1)];
    thickness = nan(numel(storageAxis), 1);

    if string(opts.surface_mode) == "anterior_only"
        return;
    end

    background = estimate_local_background(bmode, opts.background_percentile);
    bottomInput = bmode;
    for column = 1:size(bmode, 2)
        cutoff = min(size(bmode, 1), ...
            border.Idx_Up(column) + opts.bottom_search_offset);
        bottomInput(cutoff:end, column) = background;
    end

    bottomSystem = geometry;
    bottomSystem.PeakThresMult = opts.bottom_peak_multiplier;
    bottomSystem.PeakThresWinSize = opts.peak_window_size;
    bottomDetected = oce.borders.findSurface(flip(bottomInput, 1), ...
        bottomSystem);
    bottomInvalid = find_short_lateral_excursions(bottomDetected.Idx, ...
        opts.max_lateral_jump, opts.max_jump_gap);
    bottomDetected.Idx(topInvalid | bottomInvalid) = NaN;
    bottomDetected.Idx = medfilt2(bottomDetected.Idx, ...
        opts.bottom_median_filter, 'Symmetric');
    bottom = smooth(bottomDetected.Idx, opts.smooth_span, 'lowess');
    border.Idx_Down = size(bmode, 1) - ...
        round(bottom' - opts.bottom_index_offset) + 1;

    posteriorSurface(:, 2) = interp1( ...
        1:numel(depthAxisMm), depthAxisMm, border.Idx_Down(:), 'linear', NaN);
    thickness = thickness_single_bmode(localAxisMm, ...
        anteriorSurface(:, 2), posteriorSurface(:, 2));
    thickness = smooth(thickness, opts.thickness_smooth_span, ...
        opts.thickness_smooth_method);
end

function invalid = find_short_lateral_excursions(borderIdx, maxLateralJump, maxJumpGap)
%FIND_SHORT_LATERAL_EXCURSIONS Reject locally unsupported large-jump branches.
% A jump marks the boundary between adjacent finite candidates. Interior short
% excursions remain defined by two nearby jumps. At a B-mode edge, however,
% missing candidates beyond a jump are evidence of lost surface support and must
% not make a one- or two-candidate false branch appear geometrically long. Edge
% classification therefore uses the number of contiguous finite candidates
% supported next to the jump, while requiring the remaining edge tail to be NaN.

    sampleCount = numel(borderIdx);
    invalid = false(size(borderIdx));
    if sampleCount < 2
        return;
    end

    delta = abs(diff(borderIdx));
    validPairs = isfinite(borderIdx(1:end - 1)) & isfinite(borderIdx(2:end));
    jumps = find(validPairs & delta > maxLateralJump);
    if isempty(jumps)
        return;
    end

    firstJump = jumps(1);
    leftEdge = 1:firstJump;
    if is_short_supported_edge_branch(borderIdx(leftEdge), maxJumpGap, "left")
        invalid(leftEdge) = true;
    end

    for index = 1:numel(jumps) - 1
        leftJump = jumps(index);
        rightJump = jumps(index + 1);
        excursionLength = rightJump - leftJump;
        if excursionLength <= maxJumpGap
            invalid(leftJump + 1:rightJump) = true;
        end
    end

    lastJump = jumps(end);
    rightEdge = lastJump + 1:sampleCount;
    if is_short_supported_edge_branch(borderIdx(rightEdge), maxJumpGap, "right")
        invalid(rightEdge) = true;
    end
end

function tf = is_short_supported_edge_branch(values, maxJumpGap, side)
%IS_SHORT_SUPPORTED_EDGE_BRANCH Classify a weak branch reaching a B-mode edge.
% A fully finite branch is short only when its complete length is within the
% configured gap. When detection disappears toward the edge, only the contiguous
% finite run adjacent to the large jump counts as supported branch length; all
% remaining samples must be missing before the branch is rejected.

    if isempty(values)
        tf = false;
        return;
    end

    if side == "left"
        values = fliplr(values);
    end

    finite = isfinite(values);
    firstMissing = find(~finite, 1, 'first');
    if isempty(firstMissing)
        tf = numel(values) <= maxJumpGap;
        return;
    end

    supportedLength = firstMissing - 1;
    tf = supportedLength > 0 && supportedLength <= maxJumpGap && ...
        all(~finite(firstMissing:end));
end

function filled = fill_rejected_short_excursions(values, invalid)
%FILL_REJECTED_SHORT_EXCURSIONS Stabilize only explicitly rejected short runs.
% Interior runs are linearly bridged between their adjacent retained anchors.
% Edge runs extend the nearest retained anchor rather than asking LOWESS to
% extrapolate across unsupported samples. Unrelated NaNs remain untouched.

    filled = values;
    if ~any(invalid)
        return;
    end

    transitions = diff([false, invalid, false]);
    starts = find(transitions == 1);
    stops = find(transitions == -1) - 1;

    for index = 1:numel(starts)
        first = starts(index);
        last = stops(index);
        hasLeft = first > 1 && isfinite(values(first - 1));
        hasRight = last < numel(values) && isfinite(values(last + 1));

        if hasLeft && hasRight
            bridge = linspace(values(first - 1), values(last + 1), last - first + 3);
            filled(first:last) = bridge(2:end - 1);
        elseif hasLeft
            filled(first:last) = values(first - 1);
        elseif hasRight
            filled(first:last) = values(last + 1);
        end
    end
end

function background = estimate_local_background(bmode, percentile)
%ESTIMATE_LOCAL_BACKGROUND Estimate a low-intensity floor without fixed ROI.

    values = double(bmode(:));
    values = values(isfinite(values) & values > 0);
    if isempty(values)
        background = eps;
        return;
    end

    background = prctile(values, percentile);
    if ~isfinite(background) || background <= 0
        background = min(values);
    end
end

function thickness = thickness_single_bmode(localAxisMm, anteriorDepth, posteriorDepth)
    anterior = [localAxisMm(:), anteriorDepth(:)];
    posterior = [localAxisMm(:), posteriorDepth(:)];
    [~, thickness] = knnsearch(posterior, anterior, 'K', 1);
end
