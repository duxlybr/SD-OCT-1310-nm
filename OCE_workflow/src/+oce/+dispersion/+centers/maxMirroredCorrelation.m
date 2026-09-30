function resolution = maxMirroredCorrelation(values, options, samplesPerBmode, bmodeCount, timeIndices, showProgress)
%MAXMIRROREDCORRELATION Select the first maximum mirrored correlation.

    searchRange = resolve_search_range( ...
        options.search_range_fraction, samplesPerBmode);
    methodOptions = options.max_mirrored_correlation;
    if isempty(methodOptions.half_width_samples)
        baseHalfWidth = round( ...
            methodOptions.half_width_fraction * samplesPerBmode);
    else
        baseHalfWidth = methodOptions.half_width_samples;
    end
    minimumHalfWidth = methodOptions.minimum_half_width_samples;
    scoreSmoothSpan = max(3, round( ...
        methodOptions.score_smoothing_span_fraction * samplesPerBmode));
    localIndices = zeros(bmodeCount, 1);
    bestScores = NaN(bmodeCount, 1);
    fallbackUsed = false(bmodeCount, 1);
    searchRanges = repmat(searchRange, bmodeCount, 1);

    if showProgress
        fprintf(['Max-mirrored-correlation center search uses local ' ...
            'indices %d:%d and time indices %d:%d.\n'], ...
            searchRange(1), searchRange(2), ...
            timeIndices(1), timeIndices(end));
    end
    for bmodeIndex = 1:bmodeCount
        rows = (bmodeIndex - 1) * samplesPerBmode + ...
            (1:samplesPerBmode);
        block = values(rows, timeIndices);
        candidates = searchRange(1):searchRange(2);
        scores = NaN(size(candidates));
        for candidatePosition = 1:numel(candidates)
            center = candidates(candidatePosition);
            halfWidth = min([baseHalfWidth, center - 1, ...
                samplesPerBmode - center]);
            if halfWidth < minimumHalfWidth
                continue;
            end
            left = block(center-halfWidth:center-1, :);
            right = flipud(block(center+1:center+halfWidth, :));
            left = left(:);
            right = right(:);
            finiteMask = isfinite(left) & isfinite(right);
            left = left(finiteMask);
            right = right(finiteMask);
            if numel(left) < 10
                continue;
            end
            left = left - mean(left, 'omitnan');
            right = right - mean(right, 'omitnan');
            denominator = norm(left) * norm(right);
            if denominator <= eps
                continue;
            end
            scores(candidatePosition) = (left' * right) / denominator;
        end
        if all(isnan(scores))
            warning('OCE:DispersionWindows:SymmetryFallback', ...
                ['Max mirrored correlation failed for B-mode %d. ' ...
                 'Falling back to middle.'], bmodeIndex);
            localIndices(bmodeIndex) = round(samplesPerBmode / 2);
            fallbackUsed(bmodeIndex) = true;
            continue;
        end
        smoothedScores = smoothdata( ...
            scores, 'movmean', scoreSmoothSpan, 'omitnan');
        [bestScores(bmodeIndex), bestPosition] = max(smoothedScores);
        localIndices(bmodeIndex) = candidates(bestPosition);
    end
    resolution = struct( ...
        'local_indices', localIndices, ...
        'search_ranges', searchRanges, ...
        'fallback_used', fallbackUsed, ...
        'scores', bestScores);
end

function rangeValue = resolve_search_range(fractions, sampleCount)
    rangeValue = [max(1, round(fractions(1) * sampleCount)), ...
        min(sampleCount, round(fractions(2) * sampleCount))];
    if rangeValue(2) <= rangeValue(1)
        rangeValue = [max(1, round(0.30 * sampleCount)), ...
            min(sampleCount, round(0.70 * sampleCount))];
    end
end
