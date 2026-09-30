function fig = plotEnfaceMotionSnapshots(filterResult, reconstructionResult, ...
        geometry, varargin)
%PLOTENFACEMOTIONSNAPSHOTS Display en-face surface-motion frames of a raster.
% fig = plotEnfaceMotionSnapshots(filterResult, reconstructionResult,
%     geometry, Name, Value)
%
% Renders SnapshotCount evenly spaced XY frames (or the frames nearest the
% requested TimesMs) from prepareEnfaceMotionVisualization. CLimMode/CLim and
% MedianWindow follow the en-face video. Opens one figure; writes no file.

    parser = inputParser;
    addParameter(parser, 'SnapshotCount', 8, @(value) isnumeric(value) && ...
        isscalar(value) && value >= 1 && value == round(value));
    addParameter(parser, 'TimesMs', [], @(value) isempty(value) || ...
        (isnumeric(value) && isvector(value) && all(isfinite(value))));
    addParameter(parser, 'CLimMode', "robust");
    addParameter(parser, 'CLim', []);
    addParameter(parser, 'MedianWindow', [3 3]);
    parse(parser, varargin{:});

    data = oce.plotting.prepareEnfaceMotionVisualization( ...
        filterResult, reconstructionResult, geometry, ...
        'MedianWindow', parser.Results.MedianWindow);
    phaseLimits = oce.plotting.resolveMotionOverlayCLim( ...
        struct('phase_values', data.frames, ...
            'visualization_mask', data.valid_mask), ...
        parser.Results.CLimMode, parser.Results.CLim);

    timeCount = numel(data.time_axis_ms);
    if isempty(parser.Results.TimesMs)
        frameIndices = unique(round(linspace(1, timeCount, ...
            min(parser.Results.SnapshotCount, timeCount))));
    else
        frameIndices = zeros(1, numel(parser.Results.TimesMs));
        for index = 1:numel(frameIndices)
            [~, frameIndices(index)] = min(abs( ...
                data.time_axis_ms - parser.Results.TimesMs(index)));
        end
    end

    columnCount = min(4, numel(frameIndices));
    rowCount = ceil(numel(frameIndices) / columnCount);
    fig = figure('Name', 'En-face filtered surface motion snapshots');
    layout = tiledlayout(fig, rowCount, columnCount, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    title(layout, 'En-face filtered surface motion', 'FontWeight', 'bold');
    axesHandles = gobjects(numel(frameIndices), 1);
    for index = 1:numel(frameIndices)
        ax = nexttile(layout);
        axesHandles(index) = ax;
        imageHandle = imagesc(ax, data.x_axis_mm, data.y_axis_mm, ...
            data.frames(:, :, frameIndices(index)));
        imageHandle.AlphaData = double(data.valid_mask);
        ax.Color = [0.6 0.6 0.6];
        ax.YDir = 'normal';
        axis(ax, 'image');
        colormap(ax, fireice(256));
        clim(ax, phaseLimits);
        title(ax, sprintf('t = %.2f ms', data.time_axis_ms(frameIndices(index))));
        xlabel(ax, 'x (mm)');
        ylabel(ax, 'y (mm)');
    end
    bar = colorbar(axesHandles(end));
    bar.Layout.Tile = 'east';
    bar.Label.String = sprintf('Filtered surface %s (%s)', ...
        strrep(data.quantity, "_", " "), data.units);
    oce.plotting.applyPreviewStyle(fig, axesHandles, ...
        'FigureSize', [320 * columnCount + 120, 260 * rowCount + 80]);
end
