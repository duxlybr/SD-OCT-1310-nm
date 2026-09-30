function yLimit = resolveSpeedPreviewYLimit(analysis, scanAxisIndex)
%RESOLVESPEEDPREVIEWYLIMIT Resolve a robust display-only speed upper limit.

    directionIndices = [scanAxisIndex * 2 - 1, scanAxisIndex * 2];
    if ~isstruct(analysis) || ~isfield(analysis, 'directions') || ...
            any(directionIndices > numel(analysis.directions))
        error('OCE:Plotting:InvalidDispersionAnalysis', ...
            'Analysis does not contain the requested scan-axis directions.');
    end
    displayed = [];
    selected = [];
    for index = directionIndices
        direction = analysis.directions(index);
        curve = double(direction.phase_speed_curve. ...
            smoothed_phase_speed_m_per_s(:));
        frequency = double(direction.phase_speed_curve.frequency_hz(:));
        frequencyLimit = double(analysis.options.spectrum.crop. ...
            maximum_frequency_hz);
        mask = isfinite(curve) & curve > 0 & isfinite(frequency) & ...
            frequency >= 0 & frequency <= frequencyLimit;
        displayed = [displayed; curve(mask)]; %#ok<AGROW>
        target = double(direction.target_selection. ...
            selected_phase_speed_m_per_s);
        if isfinite(target) && target > 0
            selected(end + 1, 1) = target; %#ok<AGROW>
        end
    end
    if isempty(displayed)
        robustMaximum = 0;
    else
        displayed = sort(displayed);
        center = median(displayed);
        deviation = median(abs(displayed - center));
        if deviation > 0
            upperFence = center + 6 * 1.4826 * deviation;
        else
            upperFence = interpolated_quantile(displayed, 0.95);
        end
        displayed = min(displayed, upperFence);
        robustMaximum = interpolated_quantile(sort(displayed), 0.98);
    end
    yMaximum = max([20; 1.10 * robustMaximum; 1.10 * selected]);
    yLimit = [0 yMaximum];
end

function value = interpolated_quantile(sortedValues, probability)
    rank = 1 + (numel(sortedValues) - 1) * probability;
    lowerIndex = floor(rank);
    upperIndex = ceil(rank);
    fraction = rank - lowerIndex;
    value = (1 - fraction) * sortedValues(lowerIndex) + ...
        fraction * sortedValues(upperIndex);
end
