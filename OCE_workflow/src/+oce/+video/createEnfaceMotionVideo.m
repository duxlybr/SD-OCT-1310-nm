function videoPath = createEnfaceMotionVideo(filterResult, ...
        reconstructionResult, geometry, videoOptions, outputDirectory, varargin)
%CREATEENFACEMOTIONVIDEO Write the optional en-face (XY) surface-motion MP4.
% videoPath = createEnfaceMotionVideo(filterResult, reconstructionResult,
%     geometry, videoOptions, outputDirectory, Name, Value)
%
% Renders the filtered surface phase of a raster or polar acquisition as XY
% frames over time. videoOptions uses the maintained VideoOptions fields
% time_start_idx, max_frames, frame_rate and filename (.mp4). Name-value
% options: CLimMode, CLim, MedianWindow (display-only spatial median),
% Interpolation ("bilinear" or "nearest" pixel rendering), ShowProgress and
% FilePrefix (file name <FilePrefix>_<filename>, e.g. the acquisition name).
% Writes one file and creates outputDirectory when needed; scientific
% products are not modified.

    parser = inputParser;
    addParameter(parser, 'CLimMode', "robust");
    addParameter(parser, 'CLim', []);
    addParameter(parser, 'MedianWindow', [3 3]);
    addParameter(parser, 'Interpolation', "bilinear", ...
        @(value) ismember(lower(string(value)), ["bilinear", "nearest"]));
    addParameter(parser, 'ShowProgress', true, ...
        @(value) islogical(value) && isscalar(value));
    addParameter(parser, 'FilePrefix', "", @(value) ischar(value) || (isstring(value) && isscalar(value)));
    parse(parser, varargin{:});

    validate_video_options(videoOptions);
    if ~isstruct(filterResult) || ~isscalar(filterResult) || ...
            ~isfield(filterResult, 'applied') || ~filterResult.applied
        error('OCE:Video:FilteringRequired', ...
            ['En-face motion video requires an applied filter_result. ' ...
             'Run temporal filtering with FilterOptions.enabled=true first.']);
    end
    data = oce.plotting.prepareEnfaceMotionVisualization( ...
        filterResult, reconstructionResult, geometry, ...
        'MedianWindow', parser.Results.MedianWindow);
    phaseLimits = oce.plotting.resolveMotionOverlayCLim( ...
        struct('phase_values', data.frames, ...
            'visualization_mask', data.valid_mask), ...
        parser.Results.CLimMode, parser.Results.CLim);

    filename = string(videoOptions.filename);
    [~, ~, extension] = fileparts(filename);
    if lower(string(extension)) ~= ".mp4"
        error('OCE:Video:InvalidFilename', ...
            'En-face motion video filename must use the .mp4 extension.');
    end
    if strlength(parser.Results.FilePrefix) > 0
        filename = string(parser.Results.FilePrefix) + "_" + filename;
    end
    if ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end
    videoPath = string(fullfile(outputDirectory, filename));

    timeCount = numel(data.time_axis_s);
    startIndex = min(double(videoOptions.time_start_idx), timeCount);
    endIndex = min(timeCount, startIndex + double(videoOptions.max_frames) - 1);

    fig = figure('Name', 'En-face filtered surface motion', ...
        'Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none');
    ax = axes(fig);
    imageHandle = imagesc(ax, data.x_axis_mm, data.y_axis_mm, ...
        data.frames(:, :, startIndex));
    imageHandle.AlphaData = double(data.valid_mask);
    imageHandle.Interpolation = char(lower(string(parser.Results.Interpolation)));
    ax.Color = [0.6 0.6 0.6];
    ax.YDir = 'normal';
    axis(ax, 'image');
    colormap(ax, fireice(256));
    clim(ax, phaseLimits);
    bar = colorbar(ax);
    bar.Label.String = sprintf('Filtered surface %s (%s)', ...
        strrep(data.quantity, "_", " "), data.units);
    xlabel(ax, 'x (mm)');
    ylabel(ax, 'y (mm)');
    titleHandle = title(ax, frame_title(data.time_axis_ms(startIndex)));
    if isprop(ax, 'Toolbar') && ~isempty(ax.Toolbar)
        ax.Toolbar.Visible = 'off';
    end
    oce.plotting.applyPreviewStyle(fig, ax, 'FigureSize', [760 520]);
    figurePosition = fig.Position;
    figurePosition(1:2) = [20 60];
    fig.Position = figurePosition;

    writer = VideoWriter(char(videoPath), 'MPEG-4');
    writer.FrameRate = double(videoOptions.frame_rate);
    if isprop(writer, 'Quality')
        writer.Quality = 95;
    end
    open(writer);
    cleanup = onCleanup(@() close_resources(writer, fig));
    totalFrames = endIndex - startIndex + 1;
    nextProgress = 10;
    for timeIndex = startIndex:endIndex
        imageHandle.CData = data.frames(:, :, timeIndex);
        titleHandle.String = frame_title(data.time_axis_ms(timeIndex));
        drawnow;
        writeVideo(writer, getframe(fig));
        completed = floor(100 * (timeIndex - startIndex + 1) / totalFrames);
        while parser.Results.ShowProgress && ...
                nextProgress <= 100 && completed >= nextProgress
            fprintf('En-face motion video: %d%%\n', nextProgress);
            nextProgress = nextProgress + 10;
        end
    end
    close(writer);
    if isgraphics(fig), close(fig); end
    clear cleanup
end

function text = frame_title(timeMs)
    text = sprintf('En-face filtered surface motion | t = %.3f ms', timeMs);
end

function validate_video_options(options)
    required = {'time_start_idx', 'max_frames', 'frame_rate', 'filename'};
    if ~isstruct(options) || ~isscalar(options) || any(~isfield(options, required))
        error('OCE:Video:InvalidOptions', ...
            'VideoOptions must contain time_start_idx, max_frames, frame_rate, and filename.');
    end
    integerFields = {'time_start_idx', 'max_frames'};
    for index = 1:numel(integerFields)
        value = options.(integerFields{index});
        if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
                value < 1 || value ~= round(value)
            error('OCE:Video:InvalidOptions', ...
                '%s must be a positive integer.', integerFields{index});
        end
    end
    if ~isnumeric(options.frame_rate) || ~isscalar(options.frame_rate) || ...
            ~isfinite(options.frame_rate) || options.frame_rate <= 0
        error('OCE:Video:InvalidOptions', ...
            'frame_rate must be a positive finite scalar.');
    end
end

function close_resources(writer, fig)
    try
        close(writer);
    catch
    end
    if isgraphics(fig)
        close(fig);
    end
end
