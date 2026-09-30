function [DistBorder, Border, TopBorder, BottomBorder] = findInVivoCornealBorders(storageAxis, ~, Bmode, geometry, depthAxisMm, BorderOptions)
%FINDINVIVOCORNEALBORDERS Detect each in-vivo B-mode independently.
% depthAxisMm and geometry.depth_sample_interval_mm come from reconstruction.

    samplesPerBmode = geometry.samples_per_bmode;
    bmodeCount = geometry.bmode_count;
    lateralCount = geometry.lateral_sample_count;
    DistBorder = nan(lateralCount, 1);
    Border = struct( ...
        'Idx', nan(1, lateralCount), ...
        'Idx_Up', nan(1, lateralCount), ...
        'Idx_Down', nan(1, lateralCount), ...
        'BadColumns', false(1, lateralCount), ...
        'TopSearchRange', nan(bmodeCount, 2), ...
        'BottomSearchRange', nan(bmodeCount, 2), ...
        'CornealBand', nan(bmodeCount, 2), ...
        'ThicknessRangePx', nan(1, 2));
    TopBorder = [storageAxis(:), nan(lateralCount, 1)];
    BottomBorder = [storageAxis(:), nan(lateralCount, 1)];

    for bmodeIndex = 1:bmodeCount
        range = (bmodeIndex - 1) * samplesPerBmode + ...
            (1:samplesPerBmode);
        localGeometry = geometry;
        localGeometry.lateral_sample_count = samplesPerBmode;
        localGeometry.bmode_count = 1;
        [localThickness, localBorder, localTop, localBottom] = ...
            detect_single_bmode(storageAxis(range), Bmode(:, range), ...
                localGeometry, depthAxisMm, BorderOptions);
        DistBorder(range) = localThickness;
        Border.Idx(range) = localBorder.Idx;
        Border.Idx_Up(range) = localBorder.Idx_Up;
        Border.Idx_Down(range) = localBorder.Idx_Down;
        Border.BadColumns(range) = localBorder.BadColumns;
        Border.TopSearchRange(bmodeIndex, :) = localBorder.TopSearchRange;
        Border.BottomSearchRange(bmodeIndex, :) = localBorder.BottomSearchRange;
        Border.CornealBand(bmodeIndex, :) = localBorder.CornealBand;
        Border.ThicknessRangePx = localBorder.ThicknessRangePx;
        TopBorder(range, 2) = localTop(:, 2);
        BottomBorder(range, 2) = localBottom(:, 2);
    end
end

function [DistBorder, Border, TopBorder, BottomBorder] = ...
        detect_single_bmode(storageAxis, Bmode, geometry, depthAxisMm, BorderOptions)
%DETECT_SINGLE_BMODE Detect corneal borders in one in-vivo eye B-mode image.
%
% This detector is designed for in-vivo images where eyelashes, iris,
% specular reflections, and saturated central columns can corrupt direct
% first-surface detection.
%
% Main strategy:
%   1. Column-wise adaptive thresholding.
%   2. Detection of unreliable vertical-reflection columns.
%   3. Coarse corneal-band estimation from vertical projection.
%   4. Top-border candidates inside an adaptive vertical search band.
%   5. Outlier rejection, interpolation, and robust smoothing.
%   6. Bottom-border candidates constrained by a physiological thickness range.
%   7. Continuous output borders for surface phase-map generation.
%
% The unreliable columns are not used as detection points, but the final
% border is interpolated through them to preserve a continuous trajectory.

    opts = BorderOptions;

    nDepth = size(Bmode, 1);
    nCols = size(Bmode, 2);

    %% Preprocessing
    BmodeThresholded = adaptive_threshold_columns(Bmode, geometry, opts);
    BmodeThresholded = medfilt2(BmodeThresholded, opts.median_filter_size, 'symmetric');

    badColumns = detect_vertical_artifact_columns(BmodeThresholded, opts);

    %% Coarse corneal band
    [bandTop, bandBottom] = estimate_corneal_band( ...
        BmodeThresholded, badColumns, geometry, opts);

    topSearchRange = [ ...
        max(1, bandTop - opts.top_search_padding_px), ...
        min(nDepth, bandBottom + opts.top_search_padding_px)];

    %% Top border candidates
    topRaw = detect_first_surface_in_range(BmodeThresholded, topSearchRange, badColumns, opts);
    topClean = clean_border_candidates(topRaw, topSearchRange, opts);
    topFilled = fill_and_smooth_border(topClean, opts);

    %% Bottom border candidates constrained by thickness range
    thicknessRangePx = thickness_mm_to_px( ...
        opts.thickness_range_mm, geometry.depth_sample_interval_mm);
    bottomRaw = detect_bottom_surface_from_top(BmodeThresholded, topFilled, thicknessRangePx, badColumns, opts);

    bottomSearchRange = [ ...
        max(1, floor(min(topFilled, [], 'omitnan') + thicknessRangePx(1))), ...
        min(nDepth, ceil(max(topFilled, [], 'omitnan') + thicknessRangePx(2)))];

    bottomClean = clean_border_candidates(bottomRaw, bottomSearchRange, opts);
    bottomFilled = fill_and_smooth_border(bottomClean, opts);

    %% Output
    Border = struct();
    Border.Idx = topRaw;
    Border.Idx_Up = topFilled;
    Border.Idx_Down = bottomFilled;
    Border.BadColumns = badColumns;
    Border.TopSearchRange = topSearchRange;
    Border.BottomSearchRange = bottomSearchRange;
    Border.CornealBand = [bandTop bandBottom];
    Border.ThicknessRangePx = thicknessRangePx;

    TopBorder = zeros(nCols, 2);
    TopBorder(:, 1) = storageAxis(:);
    TopBorder(:, 2) = interp1( ...
        1:numel(depthAxisMm), depthAxisMm, Border.Idx_Up(:), 'linear', NaN);

    BottomBorder = zeros(nCols, 2);
    BottomBorder(:, 1) = storageAxis(:);
    BottomBorder(:, 2) = interp1( ...
        1:numel(depthAxisMm), depthAxisMm, Border.Idx_Down(:), 'linear', NaN);

    DistBorder = BottomBorder(:, 2) - TopBorder(:, 2);

    if opts.apply_thickness_smoothing
        DistBorder = smooth(DistBorder, opts.thickness_smooth_span, opts.thickness_smooth_method);
    end
end

function BmodeOut = adaptive_threshold_columns(Bmode, geometry, opts)
    BmodeOut = Bmode;
    nDepth = size(Bmode, 1);
    nCols = size(Bmode, 2);

    excludeBottom = round(geometry.depth_sample_count * ...
        opts.adaptive_exclude_bottom_fraction);
    lastIdx = max(1, min(nDepth, nDepth - excludeBottom));

    for i = 1:nCols
        refProfile = Bmode(1:lastIdx, i);
        threshold = mean(refProfile, 'omitnan') + opts.adaptive_threshold_k * std(refProfile, 'omitnan');
        BmodeOut(Bmode(:, i) < threshold, i) = 0;
    end
end

function badColumns = detect_vertical_artifact_columns(BmodeThresholded, opts)
    nDepth = size(BmodeThresholded, 1);
    activeHeight = sum(BmodeThresholded > 0, 1);
    columnEnergy = sum(BmodeThresholded, 1, 'omitnan');

    if ~opts.vertical_artifact_enabled
        badColumns = false(1, size(BmodeThresholded, 2));
        return;
    end

    energyZ = robust_zscore(columnEnergy);
    tallColumns = activeHeight > opts.vertical_artifact_min_height_fraction * nDepth;
    brightColumns = energyZ > opts.vertical_artifact_zscore;

    badColumns = tallColumns | brightColumns;
end

function z = robust_zscore(x)
    x = double(x(:)');
    medVal = median(x, 'omitnan');
    madVal = median(abs(x - medVal), 'omitnan');

    if madVal == 0 || isnan(madVal)
        sdVal = std(x, 'omitnan');
        if sdVal == 0 || isnan(sdVal)
            z = zeros(size(x));
        else
            z = (x - mean(x, 'omitnan')) ./ sdVal;
        end
    else
        z = 0.6745 * (x - medVal) ./ madVal;
    end
end

function [bandTop, bandBottom] = estimate_corneal_band( ...
        BmodeThresholded, badColumns, geometry, opts)
    B = BmodeThresholded;
    B(:, badColumns) = 0;

    verticalProfile = sum(B > 0, 2);
    verticalProfile = smooth_vector(verticalProfile, opts.vertical_projection_smooth_span_px, 'movmean');

    if all(verticalProfile == 0)
        warning('Could not estimate corneal band from vertical projection. Using broad fallback band.');
        bandTop = max(1, round(0.20 * geometry.depth_sample_count));
        bandBottom = min(size(B, 1), ...
            round(0.75 * geometry.depth_sample_count));
        return;
    end

    threshold = 0.20 * max(verticalProfile);
    activeRows = find(verticalProfile >= threshold);

    if isempty(activeRows)
        [~, peakRow] = max(verticalProfile);
        bandTop = max(1, peakRow - opts.min_band_height_px);
        bandBottom = min(size(B, 1), peakRow + opts.min_band_height_px);
    else
        bandTop = min(activeRows);
        bandBottom = max(activeRows);
    end

    if bandBottom - bandTop < opts.min_band_height_px
        bandCenter = round((bandTop + bandBottom) / 2);
        bandTop = max(1, bandCenter - round(opts.min_band_height_px / 2));
        bandBottom = min(size(B, 1), bandCenter + round(opts.min_band_height_px / 2));
    end
end

function idx = detect_first_surface_in_range(BmodeThresholded, searchRange, badColumns, opts)
    nCols = size(BmodeThresholded, 2);
    idx = NaN(1, nCols);
    r1 = max(1, searchRange(1));
    r2 = min(size(BmodeThresholded, 1), searchRange(2));

    for i = 1:nCols
        if badColumns(i)
            continue;
        end

        profile = BmodeThresholded(r1:r2, i) > 0;
        localIdx = find_first_run(profile, opts.min_run_length_px);

        if ~isnan(localIdx)
            idx(i) = r1 + localIdx - 1;
        end
    end
end

function idx = detect_bottom_surface_from_top(BmodeThresholded, topBorder, thicknessRangePx, badColumns, opts)
    nDepth = size(BmodeThresholded, 1);
    nCols = size(BmodeThresholded, 2);
    idx = NaN(1, nCols);

    for i = 1:nCols
        if badColumns(i) || isnan(topBorder(i))
            continue;
        end

        r1 = max(1, round(topBorder(i) + thicknessRangePx(1)));
        r2 = min(nDepth, round(topBorder(i) + thicknessRangePx(2)));

        if r2 <= r1
            continue;
        end

        profile = BmodeThresholded(r1:r2, i) > 0;

        switch lower(string(opts.bottom_signal_mode))
            case "last"
                localIdx = find_last_run(profile, opts.min_run_length_px);
            case "first"
                localIdx = find_first_run(profile, opts.min_run_length_px);
            otherwise
                localIdx = find_last_run(profile, opts.min_run_length_px);
        end

        if ~isnan(localIdx)
            idx(i) = r1 + localIdx - 1;
        end
    end
end

function localIdx = find_first_run(binaryProfile, minRunLength)
    localIdx = NaN;
    binaryProfile = binaryProfile(:);
    d = diff([false; binaryProfile; false]);
    runStarts = find(d == 1);
    runEnds = find(d == -1) - 1;
    runLengths = runEnds - runStarts + 1;
    good = find(runLengths >= minRunLength, 1, 'first');

    if ~isempty(good)
        localIdx = runStarts(good);
    end
end

function localIdx = find_last_run(binaryProfile, minRunLength)
    localIdx = NaN;
    binaryProfile = binaryProfile(:);
    d = diff([false; binaryProfile; false]);
    runStarts = find(d == 1);
    runEnds = find(d == -1) - 1;
    runLengths = runEnds - runStarts + 1;
    good = find(runLengths >= minRunLength, 1, 'last');

    if ~isempty(good)
        localIdx = runEnds(good);
    end
end

function idxClean = clean_border_candidates(idxRaw, searchRange, opts)
    idxClean = idxRaw;

    idxClean(idxClean < searchRange(1) | idxClean > searchRange(2)) = NaN;

    dIdx = [NaN abs(diff(idxClean))];
    idxClean(dIdx > opts.max_jump_px) = NaN;

    try
        idxClean = filloutliers(idxClean, NaN, 'movmedian', max(5, opts.smooth_span_px));
    catch
        % Keep current candidates if filloutliers is unavailable or fails.
    end
end

function idxFilled = fill_and_smooth_border(idxClean, opts)
    idxFilled = idxClean;
    x = 1:numel(idxClean);
    valid = ~isnan(idxClean) & isfinite(idxClean);

    if nnz(valid) < 2
        warning('Too few valid border points. Returning raw border with NaN values.');
        return;
    end

    idxFilled(~valid) = interp1(x(valid), idxClean(valid), x(~valid), char(opts.fill_method), 'extrap');

    spanPx = max(3, round(opts.smooth_span_px));
    if mod(spanPx, 2) == 0
        spanPx = spanPx + 1;
    end

    try
        idxFilled = smooth(idxFilled, spanPx, char(opts.smooth_method))';
    catch
        idxFilled = smooth_vector(idxFilled, spanPx, 'movmedian');
    end

    idxFilled = round(idxFilled);
end

function y = smooth_vector(x, spanPx, method)
    spanPx = max(3, round(spanPx));
    x = double(x(:));

    switch lower(string(method))
        case "movmedian"
            y = movmedian(x, spanPx, 'omitnan');
        otherwise
            y = movmean(x, spanPx, 'omitnan');
    end

    y = y(:);
end

function thicknessRangePx = thickness_mm_to_px(thicknessRangeMm, ...
        depthIntervalMm)
    thicknessRangePx = thicknessRangeMm / depthIntervalMm;
    thicknessRangePx = round(thicknessRangePx);
    thicknessRangePx = sort(reshape(thicknessRangePx, 1, []));
end
