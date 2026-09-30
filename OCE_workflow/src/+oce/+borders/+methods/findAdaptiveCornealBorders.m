function [DistBorder, Border, TopBorder, BottomBorder] = findAdaptiveCornealBorders(storageAxis, localAxisMm, Bmode, geometry, depthAxisMm, BorderOptions)
%FINDADAPTIVECORNEALBORDERS Detect each corneal B-mode independently.
% depthAxisMm is the reconstruction depth axis, already sample-corrected.

    samplesPerBmode = geometry.samples_per_bmode;
    bmodeCount = geometry.bmode_count;
    lateralCount = geometry.lateral_sample_count;
    DistBorder = nan(lateralCount, 1);
    Border = struct( ...
        'Idx', nan(1, lateralCount), ...
        'Inten', nan(1, lateralCount), ...
        'Idx_Up', nan(1, lateralCount), ...
        'Idx_Down', nan(1, lateralCount));
    TopBorder = [storageAxis(:), nan(lateralCount, 1)];
    BottomBorder = [storageAxis(:), nan(lateralCount, 1)];

    for bmodeIndex = 1:bmodeCount
        range = (bmodeIndex - 1) * samplesPerBmode + ...
            (1:samplesPerBmode);
        localGeometry = geometry;
        localGeometry.lateral_sample_count = samplesPerBmode;
        localGeometry.bmode_count = 1;
        [localThickness, localBorder, localTop, localBottom] = ...
            detect_single_bmode(storageAxis(range), localAxisMm, ...
                Bmode(:, range), localGeometry, depthAxisMm, ...
                BorderOptions);
        DistBorder(range) = localThickness;
        Border.Idx(range) = localBorder.Idx;
        Border.Inten(range) = localBorder.Inten;
        Border.Idx_Up(range) = localBorder.Idx_Up;
        Border.Idx_Down(range) = localBorder.Idx_Down;
        TopBorder(range, 2) = localTop(:, 2);
        BottomBorder(range, 2) = localBottom(:, 2);
    end
end

function [DistBorder, Border, TopBorder, BottomBorder] = ...
        detect_single_bmode(storageAxis, localAxisMm, Bmode, geometry, ...
            depthAxisMm, BorderOptions)
%DETECT_SINGLE_BMODE Detect corneal top and bottom borders adaptively.
%
% This detector uses column-wise adaptive thresholding,
% vertical-cluster cleanup, first-nonzero surface detection, outlier filling,
% and per-B-mode polynomial fitting.

    opts = BorderOptions;

    samplesPerBmode = geometry.samples_per_bmode;
    bmodeCount = geometry.bmode_count;
    nDepth = size(Bmode, 1);

    %% Top border segmentation
    BmodeTop = adaptive_threshold_columns(Bmode, geometry, opts);
    BmodeTop = medfilt2(BmodeTop, opts.median_filter_size, 'symmetric');
    BmodeTop = remove_vertical_projection_outliers(BmodeTop, geometry, opts);

    Border = find_surface_first_nonzero(BmodeTop, geometry);
    Border.Idx = fill_border_outliers(Border.Idx, opts);

    topFitRange = build_bmode_fit_range( ...
        samplesPerBmode, bmodeCount, opts.fit_margin_px, opts.fit_extra_margin_top_px);

    fittedTop = fit_border_by_bmode( ...
        Border.Idx, samplesPerBmode, bmodeCount, topFitRange, opts.fit_type);

    Border.Idx_Up = fittedTop;

    %% Bottom border segmentation
    BmodeBottom = BmodeTop;
    for i = 1:size(Bmode, 2)
        topIdx = fittedTop(i);

        if isnan(topIdx) || ~isfinite(topIdx)
            continue;
        end

        cutoffIdx = round(topIdx) + opts.bottom_search_offset_px;
        cutoffIdx = max(1, min(cutoffIdx, nDepth));
        BmodeBottom(cutoffIdx:end, i) = 0;
    end

    BorderB = find_surface_first_nonzero(flip(BmodeBottom, 1), geometry);
    BorderB.Idx = fill_border_outliers(BorderB.Idx, opts);

    bottomFitRange = build_bmode_fit_range( ...
        samplesPerBmode, bmodeCount, opts.fit_margin_px, 0);

    fittedBottom = fit_border_by_bmode( ...
        BorderB.Idx, samplesPerBmode, bmodeCount, bottomFitRange, opts.fit_type);

    Border.Idx_Down = fittedBottom;
    Border.Idx_Down = nDepth - Border.Idx_Down + 1;

    %% Convert to physical coordinates
    TopBorder(:, 1) = storageAxis(:);
    TopBorder(:, 2) = interp1( ...
        1:numel(depthAxisMm), depthAxisMm, Border.Idx_Up(:), 'linear', NaN);

    BottomBorder(:, 1) = storageAxis(:);
    BottomBorder(:, 2) = interp1( ...
        1:numel(depthAxisMm), depthAxisMm, Border.Idx_Down(:), 'linear', NaN);

    %% Thickness
    DistBorder = thickness_by_bmode(localAxisMm, TopBorder(:, 2), ...
        BottomBorder(:, 2), samplesPerBmode, bmodeCount);

    if opts.apply_thickness_smoothing
        DistBorder = smooth(DistBorder, opts.thickness_smooth_span, opts.thickness_smooth_method);
    end
end

function thickness = thickness_by_bmode(localAxisMm, topDepth, ...
        bottomDepth, samplesPerBmode, bmodeCount)
    thickness = nan(samplesPerBmode * bmodeCount, 1);
    for bmodeIndex = 1:bmodeCount
        range = (bmodeIndex - 1) * samplesPerBmode + ...
            (1:samplesPerBmode);
        top = [localAxisMm(:), topDepth(range)];
        bottom = [localAxisMm(:), bottomDepth(range)];
        [~, thickness(range)] = knnsearch(bottom, top, 'K', 1);
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

function BmodeOut = remove_vertical_projection_outliers(BmodeIn, geometry, opts)
    BmodeOut = BmodeIn;
    verticalProfile = sum(BmodeOut, 2);
    activeProfile = verticalProfile > 0;

    [L, nClusters] = bwlabel(activeProfile);
    outlierIdx = [];
    minClusterSize = geometry.depth_sample_count * ...
        opts.vertical_cluster_min_fraction;

    for i = 1:nClusters
        clusterSize = sum(L == i);
        if clusterSize < minClusterSize
            outlierIdx = union(outlierIdx, find(L == i));
        end
    end

    BmodeOut(outlierIdx, :) = 0;
end

function Border = find_surface_first_nonzero(Bmode, geometry)

    Border = struct();
    Border.Idx = NaN(1, geometry.lateral_sample_count);
    Border.Inten = NaN(1, geometry.lateral_sample_count);

    for i = 1:geometry.lateral_sample_count
        profile = Bmode(:, i);
        loc = find(profile, 1, 'first');

        if isempty(loc)
            continue;
        end

        Border.Idx(i) = loc;
        Border.Inten(i) = 20 * log10(Bmode(loc, i));
    end
end

function idxOut = fill_border_outliers(idxIn, opts)
    idxOut = idxIn;

    try
        idxOut = filloutliers(idxOut, opts.filloutliers_method, 'movmedian', opts.filloutliers_window);
    catch ME
        warning('OCE:Borders:FillOutliersFallback', ...
            'filloutliers failed (%s). Using fillmissing with makima fallback.', ...
            ME.message);
        idxOut = fillmissing(idxOut, 'makima');
    end
end

function fitRange = build_bmode_fit_range(samplesPerBmode, bmodeCount, margin, extraMargin)
    fitRange = cell(1, bmodeCount);

    for bmodeIndex = 1:bmodeCount
        idxStart = samplesPerBmode * (bmodeIndex - 1) + 1;
        idxEnd = samplesPerBmode * bmodeIndex;

        localStart = idxStart + margin - extraMargin;
        localEnd = idxEnd - margin + extraMargin;

        localStart = max(idxStart, localStart);
        localEnd = min(idxEnd, localEnd);

        fitRange{bmodeIndex} = localStart:localEnd;
    end
end

function fitted = fit_border_by_bmode(rawIdx, samplesPerBmode, bmodeCount, fitRange, fitType)
    fitted = NaN(1, samplesPerBmode * bmodeCount);
    xAll = 1:numel(fitted);
    degree = parse_poly_degree(fitType, 5);

    for bmodeIndex = 1:bmodeCount
        xIdx = fitRange{bmodeIndex};
        y = rawIdx(xIdx);
        valid = ~isnan(y) & isfinite(y);

        if nnz(valid) < degree + 1
            warning('Not enough valid border points for B-mode %d. Using filled raw border fallback.', bmodeIndex);
            yFilled = fillmissing(y, 'makima');
            fitted(xIdx) = yFilled;
            continue;
        end

        xValid = xAll(xIdx(valid));
        yValid = y(valid);

        try
            if exist('fit', 'file') == 2
                sf = fit(xValid(:), yValid(:), char(fitType));
                fitted(xIdx) = feval(sf, xAll(xIdx));
            else
                coeff = polyfit(xValid(:), yValid(:), degree);
                fitted(xIdx) = polyval(coeff, xAll(xIdx));
            end
        catch ME
            warning('Border fitting failed for B-mode %d (%s). Using polyfit fallback.', bmodeIndex, ME.message);
            coeff = polyfit(xValid(:), yValid(:), min(degree, nnz(valid) - 1));
            fitted(xIdx) = polyval(coeff, xAll(xIdx));
        end
    end
end

function degree = parse_poly_degree(fitType, fallbackDegree)
    fitType = string(fitType);
    token = regexp(fitType, '^poly(\d+)$', 'tokens', 'once');

    if isempty(token)
        degree = fallbackDegree;
    else
        degree = str2double(token{1});
    end
end
