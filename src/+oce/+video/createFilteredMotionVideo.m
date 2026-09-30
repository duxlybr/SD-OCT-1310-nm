function videoPath = createFilteredMotionVideo(filterResult, phaseResult, ...
        reconstructionResult, borderResult, geometry, videoOptions, ...
        outputDirectory, varargin)
%CREATEFILTEREDMOTIONVIDEO Write the optional complete filtered-motion MP4.
% Video generation is deliberately separate from scientific filtering. The
% depth phase is temporally filtered upstream; each rendered frame then removes
% its temporal background and applies visualization-only spatial median denoising.

    parser = inputParser;
    addParameter(parser, 'BmodeDisplayLimitsDb', [], @valid_optional_limits);
    addParameter(parser, 'CLimMode', "robust");
    addParameter(parser, 'CLim', []);
    addParameter(parser, 'MedianWindow', [5 3], @valid_median_window);
    addParameter(parser, 'Alpha', 0.5, @valid_alpha);
    addParameter(parser, 'ShowProgress', true, @valid_logical_scalar);
    parse(parser, varargin{:});

    validate_video_options(videoOptions);
    if ~isstruct(filterResult) || ~isscalar(filterResult) || ...
            ~isfield(filterResult, 'applied') || ~filterResult.applied || ...
            ~isfield(filterResult, 'depth') || ...
            ~isfield(filterResult, 'time_axis_s') || ...
            ~isfield(filterResult, 'design') || ...
            ~isfield(filterResult.design, 'delay_samples')
        error('OCE:Video:FilteringRequired', ...
            ['Filtered motion video requires an applied filter_result. ' ...
             'Run temporal filtering with FilterOptions.enabled=true first.']);
    end
    if ~isstruct(phaseResult) || ~isfield(phaseResult, 'options') || ...
            ~isfield(phaseResult.options, 'depth_resolved') || ...
            ~isfield(phaseResult, 'depth_resolved') || ...
            ~isfield(phaseResult.depth_resolved, 'quantity')
        error('OCE:Video:InvalidPhaseResult', ...
            'phaseResult depth-resolved options are required.');
    end
    if ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end

    cropStartIndex = double( ...
        reconstructionResult.crop.time.start_index_inclusive);
    dt = double(reconstructionResult.geometry.time_sample_interval_s);
    visualDelay = double(filterResult.design.delay_samples) * ...
        double(filterResult.applied);
    timeCount = numel(filterResult.time_axis_s);
    sourceTimeIndices = (visualDelay + 1):timeCount;
    displayDepth = filterResult.depth;
    displayDepth.values = displayDepth.values(:, :, sourceTimeIndices);
    displaySampleIndices = cropStartIndex + ...
        (0:numel(sourceTimeIndices) - 1);
    if string(phaseResult.depth_resolved.quantity) == "wrapped_phase"
        displayTimeAxisS = (displaySampleIndices - 1) * dt;
    else
        displayTimeAxisS = (displaySampleIndices - 0.5) * dt;
    end
    data = oce.plotting.prepareMotionVisualization( ...
        displayDepth, reconstructionResult, borderResult, geometry, ...
        displayTimeAxisS, phaseResult.options.depth_resolved, ...
        'BmodeMode', "all");
    bmodeLimits = parser.Results.BmodeDisplayLimitsDb;
    if isempty(bmodeLimits)
        bmodeLimits = oce.acquisition.estimatePreviewDisplayLimits( ...
            reconstructionResult.log_amplitude.values);
    end
    medianWindow = parser.Results.MedianWindow;
    phaseLimits = oce.plotting.resolveMotionOverlayCLim( ...
        data.panels, parser.Results.CLimMode, parser.Results.CLim, ...
        'MedianWindow', medianWindow);

    timeCount = numel(data.time_axis_s);
    startIndex = min(double(videoOptions.time_start_idx), timeCount);
    endIndex = min(timeCount, startIndex + double(videoOptions.max_frames) - 1);
    filename = string(videoOptions.filename);
    [~, ~, extension] = fileparts(filename);
    if lower(string(extension)) ~= ".mp4"
        error('OCE:Video:InvalidFilename', ...
            'Filtered motion video filename must use the .mp4 extension.');
    end
    videoPath = string(fullfile(outputDirectory, filename));

    verticalExaggeration = 2;
    panelWidth = 300;
    lateralSpan = max(eps, range(data.local_lateral_axis_mm));
    depthSpan = max(eps, range(data.depth_axis_mm));
    panelHeight = max(110, ...
        panelWidth * depthSpan / lateralSpan * verticalExaggeration);
    figureWidth = max(1260, ...
        panelWidth * data.selection.column_count + 80);
    figureHeight = max(300, ...
        data.selection.row_count * (panelHeight + 55) + 70);
    fig = figure('Name', 'Filtered depth-resolved phase motion', ...
        'Color', 'w', 'MenuBar', 'none', 'ToolBar', 'none');
    layout = tiledlayout(fig, data.selection.row_count, ...
        data.selection.column_count, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    layoutTitle = title(layout, sprintf('Filtered motion | t = %.3f ms', ...
        data.time_axis_ms(startIndex)), 'FontWeight', 'bold');
    imageHandles = gobjects(numel(data.panels), 1);
    axesHandles = gobjects(numel(data.panels), 1);
    phaseBackground = cell(numel(data.panels), 1);
    for panelIndex = 1:numel(data.panels)
        panel = data.panels(panelIndex);
        phaseBackground{panelIndex} = mean(panel.phase_values, 3, 'omitnan');
        frame = panel.phase_values(:, :, startIndex) - ...
            phaseBackground{panelIndex};
        frame = oce.plotting.postprocessMotionOverlayFrame( ...
            frame, medianWindow);
        rgb = oce.plotting.composeMotionOverlay( ...
            panel.background_db, frame, panel.visualization_mask, ...
            bmodeLimits, phaseLimits, parser.Results.Alpha);
        ax = nexttile(layout);
        axesHandles(panelIndex) = ax;
        imageHandles(panelIndex) = imagesc(ax, ...
            data.local_lateral_axis_mm, data.depth_axis_mm, rgb);
        rowIndex = ceil(panelIndex / data.selection.column_count);
        columnIndex = mod(panelIndex - 1, data.selection.column_count) + 1;
        if rowIndex == data.selection.row_count
            xlabel(ax, 'Lateral position (mm)');
        else
            xlabel(ax, '');
            xticklabels(ax, {});
        end
        if columnIndex == 1
            ylabel(ax, 'Depth (mm)');
        else
            ylabel(ax, '');
            yticklabels(ax, {});
        end
        title(ax, sprintf('%.1f deg', panel.angle_deg), 'FontWeight', 'bold');
        axis(ax, 'tight');
        box(ax, 'on');
        daspect(ax, [1 1 / verticalExaggeration 1]);
        if isprop(ax, 'Toolbar') && ~isempty(ax.Toolbar)
            ax.Toolbar.Visible = 'off';
        end
    end
    oce.plotting.applyPreviewStyle(fig, axesHandles, ...
        'FigureSize', [figureWidth figureHeight]);
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
    try
        for timeIndex = startIndex:endIndex
            for panelIndex = 1:numel(data.panels)
                panel = data.panels(panelIndex);
                frame = panel.phase_values(:, :, timeIndex) - ...
                    phaseBackground{panelIndex};
                frame = oce.plotting.postprocessMotionOverlayFrame( ...
                    frame, medianWindow);
                imageHandles(panelIndex).CData = oce.plotting.composeMotionOverlay( ...
                    panel.background_db, frame, panel.visualization_mask, ...
                    bmodeLimits, phaseLimits, parser.Results.Alpha);
            end
            layoutTitle.String = sprintf( ...
                'Filtered motion | t = %.3f ms', ...
                data.time_axis_ms(timeIndex));
            drawnow;
            writeVideo(writer, getframe(fig));
            completed = floor(100 * (timeIndex - startIndex + 1) / totalFrames);
            while parser.Results.ShowProgress && ...
                    nextProgress <= 100 && completed >= nextProgress
                fprintf('Filtered motion video: %d%%\n', nextProgress);
                nextProgress = nextProgress + 10;
            end
        end
        close(writer);
        if isgraphics(fig), close(fig); end
        clear cleanup
    catch errorValue
        clear cleanup
        rethrow(errorValue);
    end
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

function tf = valid_optional_limits(value)
    tf = isempty(value) || (isnumeric(value) && numel(value) == 2 && ...
        all(isfinite(value)) && value(1) < value(2));
end

function tf = valid_median_window(value)
    tf = isempty(value) || (isnumeric(value) && isvector(value) && ...
        numel(value) == 2 && all(isfinite(value)) && ...
        all(value >= 1) && all(value == round(value)));
end

function tf = valid_alpha(value)
    tf = isnumeric(value) && isscalar(value) && isfinite(value) && ...
        value >= 0 && value <= 1;
end

function tf = valid_logical_scalar(value)
    tf = islogical(value) && isscalar(value);
end
