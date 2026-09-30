function resolution = maxRmsPhaseIncrement(values, options, samplesPerBmode, bmodeCount, timeIndices, showProgress)
%MAXRMSPHASEINCREMENT Select the first maximum RMS phase-increment index.

    searchRange = resolve_search_range( ...
        options.search_range_fraction, samplesPerBmode);
    smoothSpan = max(3, round( ...
        options.max_rms_phase_increment.smoothing_span_fraction * ...
        samplesPerBmode));
    localIndices = zeros(bmodeCount, 1);
    scores = zeros(bmodeCount, 1);
    searchRanges = repmat(searchRange, bmodeCount, 1);

    if showProgress
        fprintf('Max-RMS center search uses time indices %d:%d.\n', ...
            timeIndices(1), timeIndices(end));
    end
    for bmodeIndex = 1:bmodeCount
        rows = (bmodeIndex - 1) * samplesPerBmode + ...
            (1:samplesPerBmode);
        block = values(rows, timeIndices);
        profile = sqrt(mean(block .^ 2, 2, 'omitnan'));
        profile = smoothdata(profile, 'movmean', smoothSpan, 'omitnan');
        [scores(bmodeIndex), relativeIndex] = ...
            max(profile(searchRange(1):searchRange(2)));
        localIndices(bmodeIndex) = searchRange(1) + relativeIndex - 1;
    end
    resolution = struct( ...
        'local_indices', localIndices, ...
        'search_ranges', searchRanges, ...
        'scores', scores);
end

function rangeValue = resolve_search_range(fractions, sampleCount)
    rangeValue = [max(1, round(fractions(1) * sampleCount)), ...
        min(sampleCount, round(fractions(2) * sampleCount))];
    if rangeValue(2) <= rangeValue(1)
        rangeValue = [1 sampleCount];
    end
end
