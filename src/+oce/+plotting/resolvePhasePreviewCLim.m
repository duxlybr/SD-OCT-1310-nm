function limits = resolvePhasePreviewCLim(values, mode, configured, varargin)
%RESOLVEPHASEPREVIEWCLIM Resolve display-only phase color limits.
% auto -> MATLAB axes autoscaling (returns []); robust -> shared symmetric
% two-stage temporal/spatial robust limit; manual -> explicit scalar or
% [low high]. CenterDimension optionally removes the mean along one trace
% dimension before robust scaling without changing default preview behavior.

    parser = inputParser;
    addParameter(parser, 'CenterDimension', [], @valid_center_dimension);
    parse(parser, varargin{:});
    centerDimension = parser.Results.CenterDimension;

    mode = lower(string(mode));
    if iscell(values)
        arrays = values;
    else
        arrays = {values};
    end
    switch mode
        case "auto"
            limits = [];
        case "manual"
            if isempty(configured) || ~isnumeric(configured) || ...
                    any(~isfinite(configured(:))) || ...
                    ~(isscalar(configured) || numel(configured) == 2)
                error('OCE:Plotting:MissingManualCLim', ...
                    'Manual CLim must be a finite scalar or [low high].');
            end
            if isscalar(configured)
                value = abs(double(configured));
                if value <= 0
                    error('OCE:Plotting:InvalidManualCLim', ...
                        'Scalar manual CLim must be positive.');
                end
                limits = [-value value];
            else
                limits = reshape(double(configured), 1, 2);
                if limits(1) >= limits(2)
                    error('OCE:Plotting:InvalidManualCLim', ...
                        'Manual CLim must contain increasing limits.');
                end
            end
        case "robust"
            scaleCount = expected_scale_count(arrays, centerDimension);
            lateralScales = nan(scaleCount, 1);
            scaleIndex = 0;
            for index = 1:numel(arrays)
                current = double(arrays{index});
                if ~isempty(centerDimension)
                    current = current - mean(current, centerDimension, 'omitnan');
                    current = reshape_traces(current, centerDimension);
                elseif isvector(current)
                    current = reshape(current, 1, []);
                end
                current = abs(current);
                for lateralIndex = 1:size(current, 1)
                    row = current(lateralIndex, :);
                    row = sort(row(isfinite(row)));
                    if ~isempty(row)
                        scaleIndex = scaleIndex + 1;
                        lateralScales(scaleIndex) = ...
                            interpolated_quantile(row, 0.99);
                    end
                end
            end
            lateralScales = lateralScales(1:scaleIndex);
            if isempty(lateralScales)
                limits = [-0.05 0.05];
                return;
            end
            lateralScales = sort(lateralScales);
            value = robust_spatial_scale(lateralScales);
            if ~isfinite(value) || value <= 0
                value = 0.05;
            end
            limits = [-value value];
        otherwise
            error('OCE:Plotting:InvalidCLimMode', ...
                'CLimMode must be "auto", "robust", or "manual".');
    end
end

function count = expected_scale_count(arrays, centerDimension)
    if isempty(centerDimension)
        count = sum(cellfun(@(current) max(1, size(current, 1)), arrays));
        return;
    end
    count = sum(cellfun(@(current) ...
        numel(current) / max(1, size(current, centerDimension)), arrays));
end

function traces = reshape_traces(values, traceDimension)
    dimensionCount = max(ndims(values), traceDimension);
    dimensions = 1:dimensionCount;
    otherDimensions = dimensions(dimensions ~= traceDimension);
    reordered = permute(values, [otherDimensions traceDimension]);
    traces = reshape(reordered, [], size(values, traceDimension));
end

function value = robust_spatial_scale(sortedScales)
    center = median(sortedScales);
    deviation = median(abs(sortedScales - center));
    if deviation > 0
        upperFence = center + 6 * 1.4826 * deviation;
    else
        upperFence = interpolated_quantile(sortedScales, 0.95);
    end
    winsorized = min(sortedScales, upperFence);
    value = interpolated_quantile(sort(winsorized), 0.99);
end

function value = interpolated_quantile(sortedValues, probability)
    rank = 1 + (numel(sortedValues) - 1) * probability;
    lowerIndex = floor(rank);
    upperIndex = ceil(rank);
    fraction = rank - lowerIndex;
    value = (1 - fraction) * sortedValues(lowerIndex) + ...
        fraction * sortedValues(upperIndex);
end

function tf = valid_center_dimension(value)
    tf = isempty(value) || (isnumeric(value) && isscalar(value) && ...
        isfinite(value) && value >= 1 && value == round(value));
end
