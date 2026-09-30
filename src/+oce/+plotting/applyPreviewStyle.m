function applyPreviewStyle(figureHandle, axesHandles, varargin)
%APPLYPREVIEWSTYLE Apply the maintained visual convention to preview graphics.

    parser = inputParser;
    addParameter(parser, 'FigureSize', [], @valid_figure_size);
    parse(parser, varargin{:});

    if ~isempty(figureHandle)
        if ~isscalar(figureHandle) || ~isgraphics(figureHandle, 'figure')
            error('OCE:Plotting:InvalidFigure', ...
                'figureHandle must be empty or one valid figure.');
        end
        figureHandle.Color = 'w';
        figureHandle.GraphicsSmoothing = 'on';
        figureSize = parser.Results.FigureSize;
        if ~isempty(figureSize)
            position = figureHandle.Position;
            position(3:4) = figureSize;
            figureHandle.Position = position;
        end
    end

    axesHandles = axesHandles(:);
    for index = 1:numel(axesHandles)
        ax = axesHandles(index);
        if ~isgraphics(ax, 'axes')
            error('OCE:Plotting:InvalidAxes', ...
                'axesHandles must contain only valid Cartesian axes.');
        end
        set(ax, 'FontSize', 11, 'LineWidth', 0.8, 'Box', 'off', ...
            'Layer', 'top', 'TickDir', 'out');
    end
end

function tf = valid_figure_size(value)
    tf = isempty(value) || (isnumeric(value) && isreal(value) && ...
        isequal(size(value), [1 2]) && all(isfinite(value)) && ...
        all(value > 0));
end
