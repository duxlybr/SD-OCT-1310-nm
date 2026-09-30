function ui = createBorderTunerUI( ...
        method, specifications, parameterValues, maskValue, callbacks)
%CREATEBORDERTUNERUI Build the border-tuning controls and preview axes.

    window = uifigure( ...
        'Name', "Border tuning - " + method, ...
        'Position', [40 40 1540 900], ...
        'CloseRequestFcn', callbacks.cancel);
    mainGrid = uigridlayout(window, [1 2]);
    mainGrid.ColumnWidth = {'1x', 520};
    mainGrid.RowHeight = {'1x'};
    mainGrid.Padding = [14 14 14 14];
    mainGrid.ColumnSpacing = 16;

    previewGrid = uigridlayout(mainGrid, [2 1]);
    previewGrid.Layout.Row = 1;
    previewGrid.Layout.Column = 1;
    previewGrid.RowHeight = {'1x', '1x'};
    previewGrid.ColumnWidth = {'1x'};
    previewGrid.Padding = [0 0 0 0];
    previewGrid.RowSpacing = 14;

    borderAxes = uiaxes(previewGrid);
    borderAxes.Layout.Row = 1;
    borderAxes.Layout.Column = 1;
    maskAxes = uiaxes(previewGrid);
    maskAxes.Layout.Row = 2;
    maskAxes.Layout.Column = 1;

    controlsPanel = uipanel(mainGrid, ...
        'Title', "Effective method: " + method);
    controlsPanel.Layout.Row = 1;
    controlsPanel.Layout.Column = 2;

    layout = build_control_layout(specifications);
    controlGrid = uigridlayout(controlsPanel, [layout.row_count, 1]);
    controlGrid.RowHeight = layout.row_heights;
    controlGrid.ColumnWidth = {'1x'};
    controlGrid.Padding = [10 10 10 10];
    controlGrid.RowSpacing = 4;

    for groupIndex = 1:numel(layout.group_rows)
        groupLabel = uilabel(controlGrid, ...
            'Text', layout.group_names(groupIndex), ...
            'FontSize', 11, 'FontWeight', 'bold');
        groupLabel.Layout.Row = layout.group_rows(groupIndex);
        groupLabel.Layout.Column = 1;
    end

    sliders = cell(numel(specifications), 1);
    fields = cell(numel(specifications), 1);
    for index = 1:numel(specifications)
        specification = specifications(index);
        currentValue = parameterValues(index);
        limits = expanded_limits(specification.limits, currentValue);

        parameterGrid = uigridlayout(controlGrid, [1 3]);
        parameterGrid.Layout.Row = layout.parameter_rows(index);
        parameterGrid.Layout.Column = 1;
        parameterGrid.ColumnWidth = {190, '1x', 66};
        parameterGrid.RowHeight = {'1x'};
        parameterGrid.Padding = [0 0 0 0];
        parameterGrid.ColumnSpacing = 10;

        titleLabel = uilabel(parameterGrid, ...
            'Text', specification.label, 'FontSize', 10);
        titleLabel.Layout.Row = 1;
        titleLabel.Layout.Column = 1;

        sliders{index} = uislider(parameterGrid, ...
            'Limits', limits, 'Value', currentValue);
        sliders{index}.Layout.Row = 1;
        sliders{index}.Layout.Column = 2;
        set_compact_ticks(sliders{index}, limits);

        fields{index} = uieditfield(parameterGrid, 'numeric', ...
            'Limits', limits, 'Value', currentValue);
        fields{index}.Layout.Row = 1;
        fields{index}.Layout.Column = 3;

        controlIndex = index;
        sliders{index}.ValueChangedFcn = ...
            @(source, ~) callbacks.parameter_changed( ...
                controlIndex, source.Value);
        fields{index}.ValueChangedFcn = ...
            @(source, ~) callbacks.parameter_changed( ...
                controlIndex, source.Value);
    end

    maskGroupLabel = uilabel(controlGrid, ...
        'Text', 'Mask', 'FontSize', 11, 'FontWeight', 'bold');
    maskGroupLabel.Layout.Row = layout.mask_group_row;
    maskGroupLabel.Layout.Column = 1;

    maskGrid = uigridlayout(controlGrid, [1 3]);
    maskGrid.Layout.Row = layout.mask_row;
    maskGrid.Layout.Column = 1;
    maskGrid.ColumnWidth = {190, '1x', 66};
    maskGrid.RowHeight = {'1x'};
    maskGrid.Padding = [0 0 0 0];
    maskGrid.ColumnSpacing = 10;

    maskLabel = uilabel(maskGrid, 'Text', 'Mask threshold', 'FontSize', 10);
    maskLabel.Layout.Row = 1;
    maskLabel.Layout.Column = 1;

    maskLimits = expanded_limits([-20 160], maskValue);
    maskSlider = uislider(maskGrid, ...
        'Limits', maskLimits, 'Value', maskValue);
    maskSlider.Layout.Row = 1;
    maskSlider.Layout.Column = 2;
    set_compact_ticks(maskSlider, maskLimits);
    maskField = uieditfield(maskGrid, 'numeric', ...
        'Limits', maskLimits, 'Value', maskValue);
    maskField.Layout.Row = 1;
    maskField.Layout.Column = 3;
    maskSlider.ValueChangedFcn = ...
        @(source, ~) callbacks.mask_changed(source.Value);
    maskField.ValueChangedFcn = ...
        @(source, ~) callbacks.mask_changed(source.Value);

    statusLabel = uilabel(controlGrid, ...
        'Text', 'Ready', 'HorizontalAlignment', 'center');
    statusLabel.Layout.Row = layout.status_row;
    statusLabel.Layout.Column = 1;

    acceptButton = uibutton(controlGrid, 'push', ...
        'Text', 'Accept borders', 'ButtonPushedFcn', callbacks.accept);
    acceptButton.Layout.Row = layout.accept_row;
    acceptButton.Layout.Column = 1;
    cancelButton = uibutton(controlGrid, 'push', ...
        'Text', 'Cancel', 'ButtonPushedFcn', callbacks.cancel);
    cancelButton.Layout.Row = layout.cancel_row;
    cancelButton.Layout.Column = 1;

    ui = struct( ...
        'window', window, ...
        'border_axes', borderAxes, ...
        'mask_axes', maskAxes, ...
        'sliders', {sliders}, ...
        'fields', {fields}, ...
        'mask_slider', maskSlider, ...
        'mask_field', maskField, ...
        'status_label', statusLabel);
end

function layout = build_control_layout(specifications)
    parameterRows = zeros(numel(specifications), 1);
    groupRows = zeros(0, 1);
    groupNames = strings(0, 1);
    rowHeights = cell(0, 1);
    currentRow = 0;
    previousGroup = "";

    for index = 1:numel(specifications)
        group = string(specifications(index).group);
        if index == 1 || group ~= previousGroup
            currentRow = currentRow + 1;
            groupRows(end + 1, 1) = currentRow; %#ok<AGROW>
            groupNames(end + 1, 1) = group; %#ok<AGROW>
            rowHeights{end + 1, 1} = 24; %#ok<AGROW>
            previousGroup = group;
        end

        currentRow = currentRow + 1;
        parameterRows(index) = currentRow;
        rowHeights{end + 1, 1} = 44; %#ok<AGROW>
    end

    currentRow = currentRow + 1;
    maskGroupRow = currentRow;
    rowHeights{end + 1, 1} = 24;
    currentRow = currentRow + 1;
    maskRow = currentRow;
    rowHeights{end + 1, 1} = 44;
    currentRow = currentRow + 1;
    statusRow = currentRow;
    rowHeights{end + 1, 1} = 28;
    currentRow = currentRow + 1;
    acceptRow = currentRow;
    rowHeights{end + 1, 1} = 38;
    currentRow = currentRow + 1;
    cancelRow = currentRow;
    rowHeights{end + 1, 1} = 38;

    layout = struct( ...
        'row_count', currentRow, ...
        'row_heights', {rowHeights.'}, ...
        'parameter_rows', parameterRows, ...
        'group_rows', groupRows, ...
        'group_names', groupNames, ...
        'mask_group_row', maskGroupRow, ...
        'mask_row', maskRow, ...
        'status_row', statusRow, ...
        'accept_row', acceptRow, ...
        'cancel_row', cancelRow);
end

function limits = expanded_limits(limits, value)
    limits = double(limits);
    limits(1) = min(limits(1), value);
    limits(2) = max(limits(2), value);
    if limits(1) == limits(2)
        limits = limits + [-1 1];
    end
end

function set_compact_ticks(slider, limits)
    midpoint = mean(limits);
    slider.MajorTicks = unique([limits(1), midpoint, limits(2)]);
    slider.MinorTicks = [];
end
