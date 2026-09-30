function options = resolveSummaryPlotOptions(supplied)
%RESOLVESUMMARYPLOTOPTIONS Resolve summary-plot output controls.

    if nargin < 1 || isempty(supplied)
        supplied = struct();
    end
    if ~isstruct(supplied) || ~isscalar(supplied)
        error('OCE:Pipeline:InvalidSummaryPlotOptions', ...
            'PlotOptions must be a scalar struct.');
    end

    options = struct( ...
        'phase_speed_vs_frequency', true, ...
        'phase_speed_polar', true, ...
        'thickness_polar', true, ...
        'repetition_averaged_dispersion', true, ...
        'angle_averaged_dispersion', true, ...
        'angle_averaged_phase_speed_vs_frequency', false);

    unknown = setdiff(string(fieldnames(supplied)), string(fieldnames(options)));
    if ~isempty(unknown)
        error('OCE:Pipeline:InvalidSummaryPlotOptions', ...
            'PlotOptions contains unsupported field: %s.', unknown(1));
    end

    names = fieldnames(supplied);
    for index = 1:numel(names)
        value = supplied.(names{index});
        if ~islogical(value) || ~isscalar(value)
            error('OCE:Pipeline:InvalidSummaryPlotOptions', ...
                'PlotOptions.%s must be a logical scalar.', names{index});
        end
        options.(names{index}) = value;
    end
end
