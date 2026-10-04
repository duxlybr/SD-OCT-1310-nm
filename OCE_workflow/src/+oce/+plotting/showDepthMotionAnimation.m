function fig = showDepthMotionAnimation(phaseResult, reconstructionResult, ...
        borderResult, geometry, varargin)
%SHOWDEPTHMOTIONANIMATION Preview unfiltered depth-resolved phase motion.
% Displays only representative B-modes nearest 0 and 90 degrees. No video
% file is written; this is an optional manual-workflow visualization.

    parser = inputParser;
    addParameter(parser, 'BmodeDisplayLimitsDb', [], @valid_optional_limits);
    addParameter(parser, 'CLimMode', "robust");
    addParameter(parser, 'CLim', []);
    addParameter(parser, 'Alpha', 0.5, @valid_alpha);
    addParameter(parser, 'StartIndex', 1, @valid_positive_integer);
    addParameter(parser, 'MaxFrames', 350, @valid_positive_integer);
    addParameter(parser, 'PlaybackFrameRate', 30, @valid_positive_scalar);
    parse(parser, varargin{:});

    if ~isstruct(phaseResult) || ~isfield(phaseResult, 'depth_resolved') || ...
            ~isfield(phaseResult, 'options') || ...
            ~isfield(phaseResult.options, 'depth_resolved')
        error('OCE:Plotting:InvalidPhaseResult', ...
            'phaseResult must contain depth-resolved values and options.');
    end
    timeCount = size(phaseResult.depth_resolved.values, 3);
    rawTimeAxis = reconstructionResult.axes.time.values;
    startCropIndex = double( ...
        reconstructionResult.crop.time.start_index_inclusive);
    dt = double(reconstructionResult.geometry.time_sample_interval_s);
    timeOffsetS = (startCropIndex - 0.5) * dt;
    if isfield(phaseResult.depth_resolved, 'quantity') && ...
            string(phaseResult.depth_resolved.quantity) == "wrapped_phase"
        timeOffsetS = (startCropIndex - 1) * dt;
    end
    timeAxisS = rawTimeAxis(1:timeCount) + timeOffsetS;
    data = oce.plotting.prepareMotionVisualization( ...
        phaseResult.depth_resolved, reconstructionResult, borderResult, ...
        geometry, timeAxisS, phaseResult.options.depth_resolved, ...
        'BmodeMode', "representative");

    bmodeLimits = parser.Results.BmodeDisplayLimitsDb;
    if isempty(bmodeLimits)
        bmodeLimits = oce.acquisition.estimatePreviewDisplayLimits( ...
            reconstructionResult.log_amplitude.values);
    end
    phaseLimits = oce.plotting.resolveMotionOverlayCLim( ...
        data.panels, parser.Results.CLimMode, parser.Results.CLim);
    startIndex = min(parser.Results.StartIndex, timeCount);
    endIndex = min(timeCount, startIndex + parser.Results.MaxFrames - 1);

    fig = figure('Name', 'Preliminary raw depth motion');
    layout = tiledlayout(fig, data.selection.row_count, ...
        data.selection.column_count, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    imageHandles = gobjects(numel(data.panels), 1);
    axesHandles = gobjects(numel(data.panels), 1);
    phaseBackground = cell(numel(data.panels), 1);
    for panelIndex = 1:numel(data.panels)
        panel = data.panels(panelIndex);
        phaseBackground{panelIndex} = mean( ...
            panel.phase_values, 3, 'omitnan');
        frame = panel.phase_values(:, :, startIndex) - ...
            phaseBackground{panelIndex};
        rgb = oce.plotting.composeMotionOverlay( ...
            panel.background_db, frame, panel.visualization_mask, ...
            bmodeLimits, phaseLimits, parser.Results.Alpha);
        ax = nexttile(layout);
        axesHandles(panelIndex) = ax;
        imageHandles(panelIndex) = imagesc(ax, ...
            data.local_lateral_axis_mm, data.depth_axis_mm, rgb);
        xlabel(ax, 'Lateral position (mm)');
        ylabel(ax, 'Depth (mm)');
        title(ax, sprintf('Preliminary raw motion | %s', panel.label));
    end
    oce.plotting.applyPreviewStyle(fig, axesHandles, ...
        'FigureSize', [1200 520]);

    for timeIndex = startIndex:endIndex
        if ~isgraphics(fig)
            break;
        end
        for panelIndex = 1:numel(data.panels)
            panel = data.panels(panelIndex);
            frame = panel.phase_values(:, :, timeIndex) - ...
                phaseBackground{panelIndex};
            rgb = oce.plotting.composeMotionOverlay( ...
                panel.background_db, frame, panel.visualization_mask, ...
                bmodeLimits, phaseLimits, parser.Results.Alpha);
            imageHandles(panelIndex).CData = rgb;
            title(axesHandles(panelIndex), sprintf( ...
                'Preliminary raw motion | %s | t = %.3f ms', ...
                panel.label, data.time_axis_ms(timeIndex)));
        end
        drawnow limitrate;
        pause(1 / parser.Results.PlaybackFrameRate);
    end
end

function tf = valid_optional_limits(value)
    tf = isempty(value) || (isnumeric(value) && numel(value) == 2 && ...
        all(isfinite(value)) && value(1) < value(2));
end

function tf = valid_alpha(value)
    tf = isnumeric(value) && isscalar(value) && isfinite(value) && ...
        value >= 0 && value <= 1;
end

function tf = valid_positive_integer(value)
    tf = isnumeric(value) && isscalar(value) && isfinite(value) && ...
        value >= 1 && value == round(value);
end

function tf = valid_positive_scalar(value)
    tf = isnumeric(value) && isscalar(value) && isfinite(value) && value > 0;
end
