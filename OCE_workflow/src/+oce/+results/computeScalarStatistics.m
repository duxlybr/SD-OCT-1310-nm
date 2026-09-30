function [meanValue, standardDeviation, rangeValue] = computeScalarStatistics(values)
%COMPUTESCALARSTATISTICS Compute maintained NaN-aware scalar statistics.

    values = values(:);
    values = values(~isnan(values));
    if isempty(values)
        meanValue = NaN;
        standardDeviation = NaN;
        rangeValue = NaN;
    else
        meanValue = mean(values);
        standardDeviation = std(values);
        rangeValue = max(values) - min(values);
    end
end
