function filterOptions = selectTemporalFilterPassband( ...
        surfacePhaseValues, configForRun, octSystem, geometry, filterOptions)
%SELECTTEMPORALFILTERPASSBAND Interactively select temporal FIR passband.
% Two vertical ROI lines initialize from the acquisition frequency when
% available, otherwise from a broad display-only range. Drag either line
% horizontally and double-click the spectrum to accept the interval.

    previewConfig = configForRun;
    previewOptions = filterOptions;

    automaticFrequencyAvailable = false;
    column = string(previewOptions.frequency.column);
    if isfield(configForRun, 'acquisition_row') && ...
            istable(configForRun.acquisition_row) && ...
            height(configForRun.acquisition_row) == 1 && ...
            ismember(char(column), ...
                configForRun.acquisition_row.Properties.VariableNames)
        rawValue = configForRun.acquisition_row.(char(column));
        if iscell(rawValue) && isscalar(rawValue), rawValue = rawValue{1}; end
        if isnumeric(rawValue) && isscalar(rawValue)
            automaticHz = double(rawValue);
        else
            automaticHz = str2double(string(rawValue));
        end
        automaticFrequencyAvailable = ...
            isfinite(automaticHz) && automaticHz > 0;
    end

    if automaticFrequencyAvailable
        previewOptions.frequency.selection_source = "acquisition_row";
        previewOptions.frequency.center_hz = [];
    else
        nyquistHz = double(octSystem.a_scan_rate) * 1e3 / 2;
        initialHighHz = min(8000, 0.90 * nyquistHz);
        initialLowHz = max(1, 0.05 * initialHighHz);
        previewOptions.frequency.selection_source = "manual_configuration";
        previewOptions.frequency.center_hz = ...
            mean([initialLowHz initialHighHz]);
        previewOptions.frequency.bandwidth.mode = "absolute_hz";
        previewOptions.frequency.bandwidth.hz = initialHighHz - initialLowHz;
        previewOptions.frequency.bandwidth.fraction = [];
    end
    previewConfig.FilterOptions = previewOptions;

    resolvedPreview = oce.config.resolveFilterOptions( ...
        previewConfig, surfacePhaseValues, octSystem);
    previewDesign = oce.filtering.designTemporalFilter( ...
        surfacePhaseValues, geometry, resolvedPreview);

    frequencyAxisHz = previewDesign.frequency_axis_hz;
    magnitude = abs(previewDesign.diagnostic.input_spectrum);
    ymax = max(magnitude, [], 'omitnan');
    if isempty(ymax) || ~isfinite(ymax) || ymax <= 0
        ymax = 1;
    end
    displayMaxHz = min(8000, frequencyAxisHz(end));
    current = resolvedPreview.frequency.effective_passband_hz;

    fig = figure('Name', 'Select temporal filter passband');
    ax = axes(fig);
    plot(ax, frequencyAxisHz, magnitude, 'LineWidth', 1);
    grid(ax, 'on');
    xlabel(ax, 'Frequency (Hz)');
    ylabel(ax, 'Magnitude (Arb.)');
    title(ax, {'Temporal FIR passband', ...
        'Drag limits; double-click the spectrum to accept'});
    xlim(ax, [0 displayMaxHz]);
    ylim(ax, [0 1.05 * ymax]);
    hold(ax, 'on');
    oce.plotting.applyPreviewStyle(fig, ax, 'FigureSize', [820 500]);

    lowLine = drawline(ax, 'Position', ...
        [current(1) 0; current(1) 1.05 * ymax], ...
        'InteractionsAllowed', 'translate');
    highLine = drawline(ax, 'Position', ...
        [current(2) 0; current(2) 1.05 * ymax], ...
        'InteractionsAllowed', 'translate');
    addlistener(lowLine, 'ROIMoved', @(src,~) normalize_vertical_line( ...
        src, 1.05 * ymax, displayMaxHz));
    addlistener(highLine, 'ROIMoved', @(src,~) normalize_vertical_line( ...
        src, 1.05 * ymax, displayMaxHz));

    setappdata(fig, 'OCEFilterPassbandAccepted', false);
    fig.WindowButtonDownFcn = ...
        @(source,~) accept_on_double_click(source, ax);
    uiwait(fig);

    if ~isgraphics(fig)
        error('OCE:Interaction:FilterSelectionCancelled', ...
            'Temporal filter passband selection was cancelled.');
    end
    if ~getappdata(fig, 'OCEFilterPassbandAccepted')
        close(fig);
        error('OCE:Interaction:FilterSelectionCancelled', ...
            'Temporal filter passband selection was cancelled.');
    end

    selectedHz = sort([mean(lowLine.Position(:, 1)), ...
        mean(highLine.Position(:, 1))]);
    if selectedHz(1) <= 0 || ...
            selectedHz(2) >= resolvedPreview.nyquist_frequency_hz || ...
            selectedHz(1) >= selectedHz(2)
        close(fig);
        error('OCE:Interaction:InvalidFilterPassband', ...
            'Selected passband must lie strictly between 0 Hz and Nyquist.');
    end

    filterOptions.frequency.selection_source = "manual_configuration";
    filterOptions.frequency.center_hz = mean(selectedHz);
    filterOptions.frequency.bandwidth.mode = "absolute_hz";
    filterOptions.frequency.bandwidth.hz = diff(selectedHz);
    filterOptions.frequency.bandwidth.fraction = [];
    close(fig);
end

function normalize_vertical_line(lineHandle, ymax, xmax)
    x = mean(lineHandle.Position(:, 1));
    x = min(max(x, eps), xmax);
    lineHandle.Position = [x 0; x ymax];
end

function accept_on_double_click(fig, ax)
    point = ax.CurrentPoint(1, 1:2);
    insideAxes = point(1) >= ax.XLim(1) && point(1) <= ax.XLim(2) && ...
        point(2) >= ax.YLim(1) && point(2) <= ax.YLim(2);
    if strcmp(fig.SelectionType, 'open') && insideAxes
        setappdata(fig, 'OCEFilterPassbandAccepted', true);
        uiresume(fig);
    end
end
