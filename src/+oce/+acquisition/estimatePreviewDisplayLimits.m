function displayLimits = estimatePreviewDisplayLimits(intensityValues, varargin)
%ESTIMATEPREVIEWDISPLAYLIMITS Estimate robust preview limits in input units.
% Non-finite samples are ignored. TailFraction defaults to 0.001 to match
% the useful automatic-level behavior of the historical preview tool.

    if ~isnumeric(intensityValues) || isempty(intensityValues) || ...
            ~isreal(intensityValues)
        error('OCE:Acquisition:InvalidPreviewIntensity', ...
            'Preview intensities must be a nonempty real numeric array.');
    end

    parser = inputParser;
    addParameter(parser, 'TailFraction', 0.001, @valid_tail_fraction);
    parse(parser, varargin{:});

    finiteValues = double(intensityValues(isfinite(intensityValues)));
    if isempty(finiteValues)
        error('OCE:Acquisition:NoFinitePreviewIntensity', ...
            'Preview intensities must contain at least one finite value.');
    end

    finiteValues = sort(finiteValues(:));
    tailFraction = double(parser.Results.TailFraction);
    displayLimits = [interpolated_quantile(finiteValues, tailFraction), ...
        interpolated_quantile(finiteValues, 1 - tailFraction)];

    if displayLimits(1) == displayLimits(2)
        displayLimits = expand_constant_limit(displayLimits(1));
    end
end

function tf = valid_tail_fraction(value)
    tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
        isfinite(value) && value >= 0 && value < 0.5;
end

function value = interpolated_quantile(sortedValues, probability)
    rank = 1 + (numel(sortedValues) - 1) * probability;
    lowerIndex = floor(rank);
    upperIndex = ceil(rank);
    fraction = rank - lowerIndex;
    value = (1 - fraction) * sortedValues(lowerIndex) + ...
        fraction * sortedValues(upperIndex);
end

function limits = expand_constant_limit(value)
    delta = eps(max(1, abs(value)));
    lowerLimit = value - delta;
    upperLimit = value + delta;
    if ~isfinite(lowerLimit)
        lowerLimit = value;
    end
    if ~isfinite(upperLimit)
        upperLimit = value;
    end
    limits = [lowerLimit upperLimit];
end
