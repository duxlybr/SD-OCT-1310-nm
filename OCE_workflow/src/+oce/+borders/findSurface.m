function Border = findSurface(Bmode, geometry)
%FINDSURFACE Detect one surface peak independently in each lateral column.
% The first axial samples are intentionally skipped to avoid the near-zero-depth
% OCT DC region; sample-specific depth priors belong outside this helper.
% Returns indices and peak intensity only; reconstruction owns physical depth.
% Optional geometry.surface_method="max_in_search" selects the strongest
% filtered amplitude inside the supplied axial interval, with contrast above
% its median. The caller must bound that interval; a bright OCT band alone
% does not establish an anatomical interface. Legacy first-peak behavior is
% unchanged when the method is omitted or "inherited_threshold".

    initialDepthIndex = 10;
    if isfield(geometry, 'initial_depth_index')
        initialDepthIndex = geometry.initial_depth_index;
    end
    peakThresholdOffset = geometry.PeakThresMult;
    peakThresholdWindowSize = geometry.PeakThresWinSize;

    filteredLogBmode = 20 * log10(medfilt2(Bmode, [3 3], 'symmetric'));

    if isfield(geometry, 'surface_method') && ...
            string(geometry.surface_method) == "max_in_search"
        Border = struct('Idx', nan(1, geometry.lateral_sample_count), ...
            'Inten', nan(1, geometry.lateral_sample_count));
        for lateralIndex = 1:geometry.lateral_sample_count
            profile = filteredLogBmode(initialDepthIndex:end, lateralIndex);
            finite = isfinite(profile);
            if ~any(finite), continue; end
            profile(~finite) = -Inf;
            [peak, location] = max(profile);
            if peak < median(profile(finite)) + peakThresholdOffset
                continue;
            end
            index = initialDepthIndex + location - 1;
            Border.Idx(lateralIndex) = index;
            Border.Inten(lateralIndex) = 20 * log10(Bmode(index, lateralIndex));
        end
        return;
    end

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
