function fig = plotStructuralEnface(enface, varargin)
%PLOTSTRUCTURALENFACE Display a depth-averaged structural en-face map.
% fig = plotStructuralEnface(enface, 'DisplayLimitsDb', [low high])
%
% Renders enface.log_values from oce.acquisition.computeStructuralEnface in
% grayscale with x/y in mm. DisplayLimitsDb defaults to robust preview
% limits of the map. Opens one figure; writes no file.

    parser = inputParser;
    addParameter(parser, 'DisplayLimitsDb', [], @(value) isempty(value) || ...
        (isnumeric(value) && numel(value) == 2 && all(isfinite(value)) && ...
        value(1) < value(2)));
    parse(parser, varargin{:});

    if ~isstruct(enface) || ~isfield(enface, 'log_values') || ...
            ~isfield(enface, 'x_axis_mm') || ~isfield(enface, 'y_axis_mm') || ...
            ~isfield(enface, 'a_scan_average') || ~isfield(enface, 'depth_average')
        error('OCE:Plotting:InvalidStructuralEnface', ...
            'A structural en-face product is required.');
    end
    limits = parser.Results.DisplayLimitsDb;
    if isempty(limits)
        limits = oce.acquisition.estimatePreviewDisplayLimits(enface.log_values);
    end

    fig = figure('Name', 'Structural en-face');
    ax = axes(fig);
    imagesc(ax, enface.x_axis_mm, enface.y_axis_mm, enface.log_values);
    ax.YDir = 'normal';
    axis(ax, 'image');
    colormap(ax, gray(256));
    clim(ax, limits);
    bar = colorbar(ax);
    bar.Label.String = 'Depth-averaged OCT amplitude (dB)';
    xlabel(ax, 'x (mm)');
    ylabel(ax, 'y (mm)');
    average = enface.a_scan_average;
    depthMm = enface.depth_average.range_mm;
    title(ax, {'Structural en-face'; sprintf( ...
        'A-scan average N = %d (M %d-%d) | depth %.2f-%.2f mm', ...
        average.count, average.first_m_repetition, ...
        average.last_m_repetition, depthMm(1), depthMm(2))});
    oce.plotting.applyPreviewStyle(fig, ax, 'FigureSize', [820 520]);
end
