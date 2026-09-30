function [fig, details] = plotCompleteSpaceTime(phaseResult, filterResult, ...
        reconstructionResult, geometry, varargin)
%PLOTCOMPLETESPACETIME Render every B-mode from the best available source.
% An applied filter_result is preferred. Empty or disabled filtering falls
% back explicitly to phase_result without changing either scientific array.

    validate_phase_result(phaseResult);

    source = "phase";
    values = phaseResult.surface.values;
    units = phaseResult.surface.units;
    delaySamples = 0;
    titlePrefix = "Final space-time (unfiltered)";
    timeCount = size(values, 2);
    startIndex = double(reconstructionResult.crop.time.start_index_inclusive);
    dt = double(reconstructionResult.geometry.time_sample_interval_s);
    timeOffsetS = (startIndex - 0.5) * dt;
    if isfield(phaseResult.surface, 'quantity') && ...
            string(phaseResult.surface.quantity) == "wrapped_phase"
        timeOffsetS = (startIndex - 1) * dt;
    end
    timeAxisMs = (reconstructionResult.axes.time.values(1:timeCount) + ...
        timeOffsetS) * 1e3;
    timeSampleIndices = startIndex + (0:timeCount - 1);

    if ~isempty(filterResult)
        validate_filter_result(filterResult);
        if filterResult.applied
            source = "filtered";
            values = filterResult.surface_postprocessed.values;
            units = filterResult.surface_postprocessed.units;
            delaySamples = filterResult.design.delay_samples;
            timeOffsetS = (startIndex - 0.5) * dt;
            timeAxisMs = (filterResult.time_axis_s + timeOffsetS) * 1e3;
            titlePrefix = "Final space-time (filtered)";
        end
    end

    [fig, preview] = oce.plotting.plotBmodeSpaceTime( ...
        values, timeAxisMs, units, geometry, titlePrefix, ...
        'BmodeMode', "all", 'DelaySamples', delaySamples, ...
        'TimeSampleIndices', timeSampleIndices, varargin{:});
    details = struct('source', source, 'filter_applied', source == "filtered", ...
        'preview', preview);
end

function validate_phase_result(value)
    if ~isstruct(value) || ~isscalar(value) || ...
            ~isfield(value, 'surface') || ...
            ~isfield(value.surface, 'values') || ...
            ~isfield(value.surface, 'units')
        error('OCE:Plotting:InvalidPhaseResult', ...
            'phaseResult.surface must contain values and units.');
    end
end

function validate_filter_result(value)
    required = {'applied', 'surface_postprocessed', 'design', 'time_axis_s'};
    if ~isstruct(value) || ~isscalar(value) || any(~isfield(value, required)) || ...
            ~islogical(value.applied) || ~isscalar(value.applied)
        error('OCE:Plotting:InvalidFilterResult', ...
            'filterResult must contain applied, surface_postprocessed, design, and time_axis_s.');
    end
    if value.applied && (~isfield(value.surface_postprocessed, 'values') || ...
            ~isfield(value.surface_postprocessed, 'units') || ...
            ~isfield(value.design, 'delay_samples'))
        error('OCE:Plotting:InvalidFilterResult', ...
            'Applied filterResult lacks display values, units, or delay_samples.');
    end
end
