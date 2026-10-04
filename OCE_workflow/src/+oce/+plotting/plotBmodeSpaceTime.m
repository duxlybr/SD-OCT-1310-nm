function [fig, preview] = plotBmodeSpaceTime(values, timeAxisMs, ...
        units, geometry, titlePrefix, varargin)
%PLOTBMODESPACETIME Render sample-first space-time B-mode maps.
% Physical axes are display-only overlays. Delay compensation crops and
% aligns plotted values without modifying the supplied scientific array.

    if ~isnumeric(values) || ~ismatrix(values) || isempty(values)
        error('OCE:Plotting:InvalidSpaceTimeValues', ...
            'Space-time values must be a nonempty lateral-by-time matrix.');
    end
    timeAxisMs = double(timeAxisMs(:)');
    if numel(timeAxisMs) ~= size(values, 2) || ...
            any(~isfinite(timeAxisMs)) || any(diff(timeAxisMs) <= 0)
        error('OCE:Plotting:InvalidSpaceTimeAxis', ...
            'timeAxisMs must match the time dimension and increase.');
    end
    parser = inputParser;
    addParameter(parser, 'CLimMode', "robust", @valid_clim_mode);
    addParameter(parser, 'CLim', [], @valid_clim_value);
    addParameter(parser, 'BmodeMode', "representative", @valid_bmode_mode);
    addParameter(parser, 'BmodeIndices', [], @valid_bmode_indices);
    addParameter(parser, 'DelaySamples', 0, @valid_delay);
    addParameter(parser, 'TimeSampleIndices', [], @valid_time_sample_indices);
    addParameter(parser, 'Axes', [], @valid_axes);
    parse(parser, varargin{:});

    selection = resolve_selection(geometry, size(values, 1), ...
        parser.Results.BmodeMode, parser.Results.BmodeIndices);
    delaySamples = double(parser.Results.DelaySamples);
    timeCount = size(values, 2);
    timeSampleIndices = parser.Results.TimeSampleIndices;
    if isempty(timeSampleIndices)
        timeSampleIndices = 1:timeCount;
    else
        timeSampleIndices = double(timeSampleIndices(:)');
        if numel(timeSampleIndices) ~= timeCount || ...
                any(diff(timeSampleIndices) <= 0)
            error('OCE:Plotting:InvalidSpaceTimeSamples', ...
                ['TimeSampleIndices must match the time dimension and ' ...
                 'increase strictly.']);
        end
    end
    if delaySamples >= timeCount - 1
        error('OCE:Plotting:InvalidPreviewDelay', ...
            'DelaySamples must leave at least two displayed time samples.');
    end
    displayTimeIndices = 1:(timeCount - delaySamples);
    sourceTimeIndices = (delaySamples + 1):timeCount;
    displayTimeAxisMs = timeAxisMs(displayTimeIndices);
    displayTimeSamples = timeSampleIndices(displayTimeIndices);

    selectedMaps = cell(numel(selection.indices), 1);
    for index = 1:numel(selection.indices)
        range = selection.global_lateral_ranges(index, 1): ...
            selection.global_lateral_ranges(index, 2);
        selectedMaps{index} = values(range, sourceTimeIndices);
    end
    sharedCLim = oce.plotting.resolvePhasePreviewCLim( ...
        selectedMaps, parser.Results.CLimMode, parser.Results.CLim);

    suppliedAxes = parser.Results.Axes;
    if isempty(suppliedAxes)
        [fig, layout, primaryAxes] = create_standalone_layout( ...
            selection, titlePrefix);
        embedded = false;
    else
        if numel(selection.indices) ~= 1
            error('OCE:Plotting:EmbeddedSpaceTimeSelection', ...
                'A supplied Axes requires exactly one selected B-mode.');
        end
        fig = ancestor(suppliedAxes, 'figure');
        primaryAxes = suppliedAxes;
        embedded = true;
    end

    secondaryAxes = gobjects(0, 1);
    physicalUnitLabels = gobjects(0, 1);
    imageHandles = gobjects(numel(selection.indices), 1);
    panelTitles = strings(numel(selection.indices), 1);

    if ~embedded
        secondaryAxes = gobjects(numel(selection.indices), 1);
        physicalUnitLabels = gobjects(numel(selection.indices), 1);
    end

    for index = 1:numel(selection.indices)
        if embedded
            ax = primaryAxes;
            cla(ax);
            rowIndex = 1;
            columnIndex = 1;
        else
            ax = nexttile(layout);
            primaryAxes(index) = ax;
            rowIndex = ceil(index / selection.column_count);
            columnIndex = mod(index - 1, selection.column_count) + 1;
        end
        imageHandles(index) = imagesc(ax, ...
            1:selection.samples_per_bmode, displayTimeSamples, ...
            selectedMaps{index}');
        colormap(ax, fireice);
        if isempty(sharedCLim)
            clim(ax, 'auto');
        else
            clim(ax, sharedCLim);
        end
        xlabel(ax, 'Lateral sample');
        if embedded || columnIndex == 1
            ylabel(ax, 'Time sample');
        else
            ylabel(ax, '');
            yticklabels(ax, {});
        end
        axis(ax, 'tight');
        panelTitles(index) = selection.labels(index);
        text(ax, 0.02, 0.98, panelTitles(index), ...
            'Units', 'normalized', 'VerticalAlignment', 'top', ...
            'FontSize', 9, 'FontWeight', 'bold', ...
            'BackgroundColor', 'w', 'Margin', 2, ...
            'HitTest', 'off', 'PickableParts', 'none');

        if ~embedded
            isRightEdge = mod(index, selection.column_count) == 0 || ...
                index == numel(selection.indices);
            overlay = physical_overlay(ax, ...
                selection.local_lateral_axis_mm, displayTimeSamples, ...
                displayTimeAxisMs, selection.samples_per_bmode, ...
                rowIndex == 1, isRightEdge);
            secondaryAxes(index) = overlay;
            physicalUnitLabels(index) = text(overlay, 0.98, 0.98, 'mm', ...
                'Units', 'normalized', 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'top', 'FontSize', 8, ...
                'BackgroundColor', 'w', 'Margin', 1, ...
                'HitTest', 'off', 'PickableParts', 'none');
            if rowIndex ~= 1
                physicalUnitLabels(index).Visible = 'off';
            end
        end
    end

    colorbarHandle = colorbar(primaryAxes(end));
    colorbarHandle.Label.String = char(units);
    colorbarHandle.FontSize = 10;
    if embedded
        oce.plotting.applyPreviewStyle([], primaryAxes);
    else
        colorbarHandle.Layout.Tile = 'south';
        figureWidth = max(980, 280 * selection.column_count + 170);
        figureHeight = 350 * selection.row_count + 120;
        oce.plotting.applyPreviewStyle(fig, primaryAxes, ...
            'FigureSize', [figureWidth figureHeight]);
        set(secondaryAxes, 'FontSize', 10, 'LineWidth', 0.8, ...
            'Box', 'off', 'TickDir', 'out');
    end

    preview = struct( ...
        'selection', selection, ...
        'primary_axes', primaryAxes, ...
        'secondary_axes', secondaryAxes, ...
        'image_handles', imageHandles, ...
        'panel_titles', panelTitles, ...
        'physical_unit_labels', physicalUnitLabels, ...
        'colorbar', colorbarHandle, ...
        'delay_samples', delaySamples, ...
        'source_time_indices', sourceTimeIndices, ...
        'display_time_indices', displayTimeIndices, ...
        'display_time_samples', displayTimeSamples, ...
        'display_time_axis_ms', displayTimeAxisMs);
end

function selection = resolve_selection(geometry, lateralCount, mode, indices)
    if isempty(indices)
        selection = oce.plotting.resolveBmodeLayout( ...
            geometry, lateralCount, mode);
        return;
    end

    complete = oce.plotting.resolveBmodeLayout(geometry, lateralCount, "all");
    indices = double(indices(:)');
    if any(indices > numel(complete.indices)) || ...
            numel(unique(indices, 'stable')) ~= numel(indices)
        error('OCE:Plotting:InvalidBmodeIndices', ...
            'BmodeIndices must contain unique existing B-mode indices.');
    end

    selection = complete;
    selection.mode = "selected";
    selection.indices = indices;
    selection.angles_deg = complete.angles_deg(indices);
    selection.labels = complete.labels(indices);
    selection.global_lateral_ranges = ...
        complete.global_lateral_ranges(indices, :);
    selection.row_count = ceil(numel(indices) / 4);
    selection.column_count = min(4, numel(indices));
end

function [fig, layout, axesHandles] = create_standalone_layout( ...
        selection, titlePrefix)
    fig = figure('Name', char(titlePrefix));
    layout = tiledlayout(fig, selection.row_count, selection.column_count, ...
        'TileSpacing', 'compact', 'Padding', 'loose');
    title(layout, char(titlePrefix), ...
        'FontSize', 12, 'FontWeight', 'bold');
    axesHandles = gobjects(numel(selection.indices), 1);
end

function overlay = physical_overlay(primary, lateralAxisMm, ...
        timeSamples, timeAxisMs, lateralCount, showXAxis, showYAxis)
    % Round physical values; time ticks stay inside the axis so they never
    % meet the lateral tick labels at the right-hand corners.
    xValues = nice_ticks(lateralAxisMm(1), lateralAxisMm(end));
    yValues = nice_ticks(timeAxisMs(1), timeAxisMs(end));
    margin = 0.05 * (timeAxisMs(end) - timeAxisMs(1));
    interior = yValues > timeAxisMs(1) + margin & ...
        yValues < timeAxisMs(end) - margin;
    if any(interior)
        yValues = yValues(interior);
    else
        yValues = mean(timeAxisMs([1 end]));
    end
    xTicks = interp1(lateralAxisMm, 1:lateralCount, xValues, 'linear');
    yTicks = interp1(timeAxisMs, timeSamples, yValues, 'linear');
    % Sharing the primary tile keeps both axes aligned and lets the layout
    % reserve room for the top/right physical tick labels.
    overlay = axes(primary.Parent, 'Color', 'none', ...
        'XAxisLocation', 'top', 'YAxisLocation', 'right', ...
        'XLim', primary.XLim, 'YLim', primary.YLim, ...
        'YDir', primary.YDir, 'XTick', xTicks, 'YTick', yTicks, ...
        'XTickLabel', compose('%g', xValues), ...
        'YTickLabel', compose('%g', yValues), ...
        'HitTest', 'off', 'PickableParts', 'none', ...
        'HandleVisibility', 'off');
    overlay.Layout.Tile = primary.Layout.Tile;
    if ~showXAxis
        overlay.XTick = [];
    end
    if showYAxis
        timeLabel = ylabel(overlay, 'ms');
        timeLabel.Units = 'normalized';
        timeLabel.Position = [1.08 0.5 0];
    else
        overlay.YTick = [];
    end
end

function values = nice_ticks(lower, upper)
    span = upper - lower;
    if ~(span > 0)
        values = lower;
        return;
    end
    rawStep = span / 3;
    magnitude = 10 ^ floor(log10(rawStep));
    candidates = [1 2 2.5 5 10] * magnitude;
    step = candidates(find(candidates >= rawStep * (1 - 1e-9), 1));
    values = (ceil(lower / step - 1e-9):floor(upper / step + 1e-9)) * step;
    values = min(max(values, lower), upper);
    values(values == 0) = 0;  % print 0, not -0
end

function tf = valid_clim_mode(value)
    tf = (ischar(value) || (isstring(value) && isscalar(value))) && ...
        ismember(lower(string(value)), ["auto", "robust", "manual"]);
end

function tf = valid_clim_value(value)
    tf = isempty(value) || (isnumeric(value) && isreal(value) && ...
        all(isfinite(value(:))) && (isscalar(value) || numel(value) == 2));
end

function tf = valid_bmode_mode(value)
    tf = (ischar(value) || (isstring(value) && isscalar(value))) && ...
        ismember(lower(string(value)), ["representative", "all"]);
end

function tf = valid_bmode_indices(value)
    tf = isempty(value) || (isnumeric(value) && isvector(value) && ...
        all(isfinite(value)) && all(value >= 1) && ...
        all(value == round(value)));
end

function tf = valid_delay(value)
    tf = isnumeric(value) && isscalar(value) && isfinite(value) && ...
        value >= 0 && value == round(value);
end

function tf = valid_time_sample_indices(value)
    tf = isempty(value) || (isnumeric(value) && isvector(value) && ...
        all(isfinite(value)) && all(value == round(value)));
end

function tf = valid_axes(value)
    tf = isempty(value) || (isscalar(value) && isgraphics(value, 'axes'));
end
