function yLimit = resolvePhaseSpeedYLimit(values, ci95)
%RESOLVEPHASESPEEDYLIMIT Resolve a robust display-only phase-speed limit.
%
% The upper display bound is derived from the visible upper envelope
% (value + CI95 when available). Isolated high outliers are excluded only
% from display-scale resolution using a median absolute deviation criterion.
% Scientific values and rendered curves are not modified.

    if nargin < 2 || isempty(ci95)
        ci95 = zeros(size(values));
    end

    values = double(values(:));
    ci95 = double(ci95(:));
    if numel(ci95) ~= numel(values)
        error('OCE:Plotting:SummarySpeedLimitShape', ...
            'Phase-speed values and CI95 values must have matching sizes.');
    end

    validValues = isfinite(values) & values > 0;
    if ~any(validValues)
        yLimit = [0 15];
        return;
    end

    upperValues = values;
    finiteCi = validValues & isfinite(ci95);
    upperValues(finiteCi) = ...
        values(finiteCi) + abs(ci95(finiteCi));
    upperValues = upperValues(validValues & isfinite(upperValues) & ...
        upperValues > 0);

    if isempty(upperValues)
        yLimit = [0 15];
        return;
    end

    centerValue = median(upperValues);
    madValue = median(abs(upperValues - centerValue));
    inlierMask = true(size(upperValues));

    if isfinite(madValue) && madValue > 0
        modifiedZ = 0.674489750196082 * ...
            (upperValues - centerValue) ./ madValue;
        inlierMask = modifiedZ <= 3.5;
    end

    if ~any(inlierMask)
        inlierMask(:) = true;
    end

    robustMaximum = max(upperValues(inlierMask));
    paddedMaximum = 1.10 * robustMaximum;
    roundingStep = 5;
    upperLimit = roundingStep * ceil(paddedMaximum / roundingStep);

    if ~isfinite(upperLimit) || upperLimit <= 0
        upperLimit = 15;
    end

    yLimit = [0 upperLimit];
end
