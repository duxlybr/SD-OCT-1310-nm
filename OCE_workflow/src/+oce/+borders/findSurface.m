function Border = findSurface(Bmode, geometry)
%FINDSURFACE Detect one surface peak independently in each lateral column.
% The first axial samples are intentionally skipped to avoid the near-zero-depth
% OCT DC region; sample-specific depth priors belong outside this helper.
% Returns indices and peak intensity only; reconstruction owns physical depth.

    initialDepthIndex = 10;
    if isfield(geometry, 'initial_depth_index')
        initialDepthIndex = geometry.initial_depth_index;
    end
    peakThresholdOffset = geometry.PeakThresMult;
    peakThresholdWindowSize = geometry.PeakThresWinSize;

    filteredLogBmode = 20 * log10(medfilt2(Bmode, [3 3], 'symmetric'));

    for lateralIndex = 1:geometry.lateral_sample_count
        profile = filteredLogBmode(initialDepthIndex:end, lateralIndex);
        threshold = mean(profile(1:peakThresholdWindowSize)) + ...
            peakThresholdOffset;

        if any(profile > threshold)
            [~, peakLocations] = findpeaks(profile, ...
                'MinPeakHeight', threshold, 'NPeaks', 1);
        else
            peakLocations = [];
        end

        if isempty(peakLocations)
            Border.Idx(lateralIndex) = NaN;
            Border.Inten(lateralIndex) = NaN;
        else
            peakLocation = peakLocations(1);
            Border.Idx(lateralIndex) = peakLocation + initialDepthIndex;
            Border.Inten(lateralIndex) = ...
                20 * log10(Bmode(peakLocation + initialDepthIndex, lateralIndex));
        end
    end
end
