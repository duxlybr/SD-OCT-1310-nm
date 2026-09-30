function [acceptedOptions, windowResult] = tuneDispersionWindows( ...
        filterResult, editableOptions, resolvedFilter, geometry, ...
        localLateralAxisMm, varargin)
%TUNEDISPERSIONWINDOWS Tune maintained dispersion-window strategies visually.
% Method selectors and numeric controls edit DispersionWindowOptions directly.
% ROI graphics are display-only: every candidate is resolved by
% oce.dispersion.buildWindows and rendered by plotDispersionWindowContext.

    parser = inputParser;
    addParameter(parser, 'TimeSampleStartIndex', 1, ...
        @(x) isnumeric(x) && isscalar(x) && isfinite(x) && ...
            x >= 1 && x == round(x));
    addParameter(parser, 'TimeSampleEndIndex', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && ...
            isfinite(x) && x >= 2 && x == round(x)));
    parse(parser, varargin{:});
    timeSampleStartIndex = double(parser.Results.TimeSampleStartIndex);
    timeSampleEndIndex = parser.Results.TimeSampleEndIndex;
    if isempty(timeSampleEndIndex)
        timeSampleEndIndex = timeSampleStartIndex + ...
            size(filterResult.surface_postprocessed.values, 2);
    end
    timeSampleEndIndex = double(timeSampleEndIndex);

    validate_geometry(geometry, localLateralAxisMm);
    workingOptions = initialize_options( ...
        editableOptions, resolvedFilter, geometry, filterResult, ...
        timeSampleStartIndex);
    currentResult = build_candidate(workingOptions);

    acceptedOptions = struct();
    windowResult = struct();
    cancelled = true;
    bmodeCount = geometry.bmode_count;
    samplesPerBmode = geometry.samples_per_bmode;

    methods = struct( ...
        'center', ["middle", "max_rms_phase_increment", ...
            "max_mirrored_correlation", "manual_local_index"], ...
        'spatial', ["fraction_of_bmode", "manual_interval_count"], ...
        'temporal', ["cycle_count", "manual_interval_count", "to_end"]);
    callbacks = struct( ...
        'preview_bmode_changed', @preview_bmode_changed, ...
        'center_method_changed', @center_method_changed, ...
        'center_changed', @(index, value) center_changed(index, value), ...
        'search_range_changed', @search_range_changed, ...
        'rms_smoothing_changed', @rms_smoothing_changed, ...
        'mirrored_half_width_changed', @mirrored_half_width_changed, ...
        'mirrored_score_smoothing_changed', ...
            @mirrored_score_smoothing_changed, ...
        'spatial_method_changed', @spatial_method_changed, ...
        'spatial_fraction_changed', @spatial_fraction_changed, ...
        'spatial_manual_changed', @spatial_manual_changed, ...
        'left_offset_changed', @left_offset_changed, ...
        'right_offset_changed', @right_offset_changed, ...
        'temporal_method_changed', @temporal_method_changed, ...
        'start_changed', @start_changed, ...
        'cycle_changed', @cycle_changed, ...
        'temporal_manual_changed', @temporal_manual_changed, ...
        'accept', @accept_tuning, ...
        'cancel', @cancel_tuning);
    ui = createDispersionWindowTunerUI( ...
        workingOptions, methods, manual_center_display_values(), ...
        manual_spatial_display_value(), manual_temporal_display_value(), ...
        callbacks);

    sync_controls();
    render_preview(1);
    uiwait(ui.window);
    if isvalid(ui.window)
        delete(ui.window);
    end
    if cancelled
        error('OCE:Interaction:DispersionWindowTuningCancelled', ...
            'Dispersion-window tuning was cancelled before acceptance.');
    end

    function preview_bmode_changed(source, ~)
        render_preview(parse_bmode_value(source.Value));
    end

    function center_method_changed(source, ~)
        candidate = workingOptions;
        requestedMethod = string(source.Value);
        if requestedMethod == "manual_local_index" && ...
                string(workingOptions.center.method) ~= "manual_local_index"
            candidate.center.manual_local_index = ...
                currentResult.resolved_options.center.local_indices(:);
        end
        candidate.center.method = requestedMethod;
        try_update(candidate);
    end

    function center_changed(index, proposed)
        candidate = workingOptions;
        values = candidate.center.manual_local_index(:);
        if numel(values) ~= bmodeCount
            values = currentResult.resolved_options.center.local_indices(:);
        end
        values(index) = round(proposed);
        candidate.center.manual_local_index = values;
        try_update(candidate);
    end

    function search_range_changed(~, ~)
        candidate = workingOptions;
        candidate.center.search_range_fraction = ...
            [ui.search_start_field.Value ui.search_end_field.Value];
        try_update(candidate);
    end

    function rms_smoothing_changed(source, ~)
        candidate = workingOptions;
        candidate.center.max_rms_phase_increment.smoothing_span_fraction = ...
            source.Value;
        try_update(candidate);
    end

    function mirrored_half_width_changed(source, ~)
        candidate = workingOptions;
        candidate.center.max_mirrored_correlation.half_width_fraction = ...
            source.Value;
        try_update(candidate);
    end

    function mirrored_score_smoothing_changed(source, ~)
        candidate = workingOptions;
        candidate.center.max_mirrored_correlation.score_smoothing_span_fraction = ...
            source.Value;
        try_update(candidate);
    end

    function spatial_method_changed(source, ~)
        candidate = workingOptions;
        requestedMethod = string(source.Value);
        if requestedMethod == "manual_interval_count"
            candidate.spatial.manual_interval_count = ...
                currentResult.resolved_options.spatial.interval_count;
        elseif requestedMethod == "fraction_of_bmode"
            candidate.spatial.interval_fraction = ...
                currentResult.resolved_options.spatial.interval_count / ...
                samplesPerBmode;
        end
        candidate.spatial.method = requestedMethod;
        try_update(candidate);
    end

    function spatial_fraction_changed(source, ~)
        candidate = workingOptions;
        candidate.spatial.interval_fraction = source.Value;
        try_update(candidate);
    end

    function spatial_manual_changed(source, ~)
        candidate = workingOptions;
        candidate.spatial.manual_interval_count = round(source.Value);
        try_update(candidate);
    end

    function left_offset_changed(source, ~)
        candidate = workingOptions;
        candidate.directional_offsets.left_samples = round(source.Value);
        try_update(candidate);
    end

    function right_offset_changed(source, ~)
        candidate = workingOptions;
        candidate.directional_offsets.right_samples = round(source.Value);
        try_update(candidate);
    end

    function temporal_method_changed(source, ~)
        candidate = workingOptions;
        requestedMethod = string(source.Value);
        currentIntervals = currentResult.resolved_options.temporal.interval_count;
        if requestedMethod == "manual_interval_count"
            candidate.temporal.manual_interval_count = currentIntervals;
        elseif requestedMethod == "cycle_count"
            candidate.temporal.cycle_count = currentIntervals * ...
                resolvedFilter.sample_interval_s * ...
                resolvedFilter.frequency.center_hz;
        end
        candidate.temporal.method = requestedMethod;
        try_update(candidate);
    end

    function start_changed(source, ~)
        candidate = workingOptions;
        candidate.temporal.start_index_inclusive = round(source.Value);
        try_update(candidate);
    end

    function cycle_changed(source, ~)
        candidate = workingOptions;
        candidate.temporal.cycle_count = source.Value;
        try_update(candidate);
    end

    function temporal_manual_changed(source, ~)
        candidate = workingOptions;
        candidate.temporal.manual_interval_count = round(source.Value);
        try_update(candidate);
    end

    function try_update(candidate)
        previousOptions = workingOptions;
        previousResult = currentResult;
        ui.status_label.Text = 'Updating ROI...';
        drawnow;
        try
            candidate = oce.config.resolveDispersionWindowOptions(candidate);
            candidateResult = build_candidate(candidate);
            workingOptions = candidate;
            currentResult = candidateResult;
            sync_controls();
            render_preview(parse_bmode_value(ui.bmode_selector.Value));
        catch ME
            workingOptions = previousOptions;
            currentResult = previousResult;
            sync_controls();
            ui.status_label.Text = 'Previous ROI retained';
            uialert(ui.window, ME.message, 'Dispersion window is invalid');
        end
    end

    function result = build_candidate(candidateOptions)
        previewConfig = struct( ...
            'DispersionWindowOptions', candidateOptions, ...
            'resolved_crop', struct('time', struct( ...
                'start_index_inclusive', timeSampleStartIndex, ...
                'end_index_inclusive', timeSampleEndIndex)));
        result = oce.dispersion.buildWindows( ...
            previewConfig, filterResult, localLateralAxisMm, ...
            resolvedFilter, geometry);
    end

    function sync_controls()
        ui.center_selector.Value = char(string(workingOptions.center.method));
        ui.spatial_selector.Value = char(string(workingOptions.spatial.method));
        ui.temporal_selector.Value = char(string(workingOptions.temporal.method));

        centers = manual_center_display_values();
        for fieldIndex = 1:bmodeCount
            ui.center_fields{fieldIndex}.Value = centers(fieldIndex);
        end
        ui.search_start_field.Value = ...
            workingOptions.center.search_range_fraction(1);
        ui.search_end_field.Value = ...
            workingOptions.center.search_range_fraction(2);
        ui.rms_smoothing_field.Value = ...
            workingOptions.center.max_rms_phase_increment.smoothing_span_fraction;
        ui.mirrored_half_width_field.Value = ...
            workingOptions.center.max_mirrored_correlation.half_width_fraction;
        ui.mirrored_score_smoothing_field.Value = ...
            workingOptions.center.max_mirrored_correlation. ...
                score_smoothing_span_fraction;
        ui.spatial_fraction_field.Value = workingOptions.spatial.interval_fraction;
        ui.spatial_manual_field.Value = manual_spatial_display_value();
        ui.left_offset_field.Value = workingOptions.directional_offsets.left_samples;
        ui.right_offset_field.Value = workingOptions.directional_offsets.right_samples;
        ui.start_field.Value = workingOptions.temporal.start_index_inclusive;
        ui.cycle_field.Value = workingOptions.temporal.cycle_count;
        ui.temporal_manual_field.Value = manual_temporal_display_value();
        update_control_state();
        update_center_summary();
    end

    function update_control_state()
        centerMethod = string(workingOptions.center.method);
        manualEnabled = centerMethod == "manual_local_index";
        searchEnabled = any(centerMethod == ...
            ["max_rms_phase_increment", "max_mirrored_correlation"]);
        for fieldIndex = 1:bmodeCount
            ui.center_fields{fieldIndex}.Enable = on_off(manualEnabled);
        end
        ui.search_start_field.Enable = on_off(searchEnabled);
        ui.search_end_field.Enable = on_off(searchEnabled);
        ui.rms_smoothing_field.Enable = on_off( ...
            centerMethod == "max_rms_phase_increment");
        ui.mirrored_half_width_field.Enable = on_off( ...
            centerMethod == "max_mirrored_correlation");
        ui.mirrored_score_smoothing_field.Enable = on_off( ...
            centerMethod == "max_mirrored_correlation");

        ui.spatial_fraction_field.Enable = on_off( ...
            string(workingOptions.spatial.method) == "fraction_of_bmode");
        ui.spatial_manual_field.Enable = on_off( ...
            string(workingOptions.spatial.method) == "manual_interval_count");
        ui.cycle_field.Enable = on_off( ...
            string(workingOptions.temporal.method) == "cycle_count");
        ui.temporal_manual_field.Enable = on_off( ...
            string(workingOptions.temporal.method) == "manual_interval_count");
    end

    function update_center_summary()
        resolution = currentResult.resolved_options.center;
        indices = string(resolution.local_indices(:)');
        text = "Resolved centers [" + strjoin(indices, " ") + "]";
        if isfield(resolution, 'fallback_used') && any(resolution.fallback_used)
            text = text + " | fallback used";
        end
        ui.resolved_center_label.Text = char(text);
    end

    function render_preview(bmodeIndex)
        oce.plotting.plotDispersionWindowContext( ...
            currentResult, filterResult, localLateralAxisMm, ...
            bmodeIndex, 'Axes', ui.preview_axes, ...
            'TimeSampleStartIndex', timeSampleStartIndex);
        spatial = currentResult.resolved_options.spatial;
        temporal = currentResult.resolved_options.temporal;
        widthMm = range(currentResult.bmodes(bmodeIndex).right.x_axis_mm);
        ui.status_label.Text = sprintf( ...
            ['Ready | center %s | spatial %d samples (%.3f mm) | ' ...
             'temporal %d samples (%.3f ms)'], ...
            char(string(workingOptions.center.method)), ...
            spatial.sample_count, widthMm, temporal.sample_count, ...
            1e3 * temporal.effective_duration_s);
        update_center_summary();
        drawnow limitrate;
    end

    function values = manual_center_display_values()
        values = workingOptions.center.manual_local_index(:);
        if numel(values) ~= bmodeCount || any(~isfinite(values)) || ...
                any(values < 1) || any(values > samplesPerBmode)
            values = currentResult.resolved_options.center.local_indices(:);
        end
    end

    function value = manual_spatial_display_value()
        value = workingOptions.spatial.manual_interval_count;
        if isempty(value) || ~isscalar(value) || ~isfinite(value)
            value = currentResult.resolved_options.spatial.interval_count;
        end
    end

    function value = manual_temporal_display_value()
        value = workingOptions.temporal.manual_interval_count;
        if isempty(value) || ~isscalar(value) || ~isfinite(value)
            value = currentResult.resolved_options.temporal.interval_count;
        end
    end

    function accept_tuning(~, ~)
        acceptedOptions = workingOptions;
        windowResult = currentResult;
        cancelled = false;
        uiresume(ui.window);
    end

    function cancel_tuning(~, ~)
        cancelled = true;
        uiresume(ui.window);
    end
end

function options = initialize_options( ...
        options, resolvedFilter, geometry, filterResult, timeSampleStartIndex)
    samplesPerBmode = geometry.samples_per_bmode;
    bmodeCount = geometry.bmode_count;
    timeCount = size(filterResult.surface_postprocessed.values, 2);
    filterDelaySamples = double(filterResult.design.delay_samples) * ...
        double(filterResult.applied);
    alignedTimeCount = timeCount - filterDelaySamples;
    absoluteTimeEndIndex = timeSampleStartIndex + alignedTimeCount - 1;

    centerMethod = lower(strtrim(string(options.center.method)));
    if centerMethod == "manual_local_index"
        centers = options.center.manual_local_index(:);
        if ~(isscalar(centers) || numel(centers) == bmodeCount) || ...
                isempty(centers) || any(~isfinite(centers)) || ...
                any(centers < 1) || any(centers > samplesPerBmode)
            centers = repmat(round(samplesPerBmode / 2), bmodeCount, 1);
        elseif isscalar(centers)
            centers = repmat(round(centers), bmodeCount, 1);
        else
            centers = round(centers);
        end
        options.center.manual_local_index = centers;
    end

    if ~isnumeric(options.spatial.interval_fraction) || ...
            ~isscalar(options.spatial.interval_fraction) || ...
            ~isfinite(options.spatial.interval_fraction) || ...
            options.spatial.interval_fraction <= 0 || ...
            options.spatial.interval_fraction >= 1
        options.spatial.interval_fraction = 0.30;
    end
    if lower(strtrim(string(options.spatial.method))) == "manual_interval_count"
        count = options.spatial.manual_interval_count;
        if isempty(count) || ~isscalar(count) || ~isfinite(count) || ...
                count < 1 || count >= samplesPerBmode
            count = max(1, min(samplesPerBmode - 1, ...
                round(options.spatial.interval_fraction * samplesPerBmode)));
        end
        options.spatial.manual_interval_count = round(count);
    end

    startIndex = options.temporal.start_index_inclusive;
    if ~isnumeric(startIndex) || ~isscalar(startIndex) || ~isfinite(startIndex)
        startIndex = 1;
    end
    startIndex = round(startIndex);
    startIndex = max(timeSampleStartIndex, ...
        min(absoluteTimeEndIndex, startIndex));
    options.temporal.start_index_inclusive = startIndex;

    frequencyHz = resolvedFilter.frequency.center_hz;
    sampleIntervalS = resolvedFilter.sample_interval_s;
    maximumCycles = (absoluteTimeEndIndex - startIndex) * ...
        sampleIntervalS * frequencyHz;
    if ~isfinite(maximumCycles) || maximumCycles <= 0
        error('OCE:Interaction:InvalidDispersionWindowDomain', ...
            'The retained time domain cannot contain a dispersion window.');
    end
    cycleCount = options.temporal.cycle_count;
    if isempty(cycleCount) || ~isnumeric(cycleCount) || ...
            ~isscalar(cycleCount) || ~isfinite(cycleCount) || cycleCount <= 0
        cycleCount = min(3, 0.9 * maximumCycles);
    elseif cycleCount >= maximumCycles
        cycleCount = 0.9 * maximumCycles;
    end
    options.temporal.cycle_count = cycleCount;

    if lower(strtrim(string(options.temporal.method))) == "manual_interval_count"
        count = options.temporal.manual_interval_count;
        if isempty(count) || ~isscalar(count) || ~isfinite(count) || ...
                count < 1 || count >= alignedTimeCount
            count = round(cycleCount / frequencyHz / sampleIntervalS);
            count = max(1, min(alignedTimeCount - 1, count));
        end
        options.temporal.manual_interval_count = round(count);
    end

    options.directional_offsets.left_samples = ...
        round(options.directional_offsets.left_samples);
    options.directional_offsets.right_samples = ...
        round(options.directional_offsets.right_samples);
    options = oce.config.resolveDispersionWindowOptions(options);
end

function index = parse_bmode_value(value)
    text = char(string(value));
    token = regexp(text, '(\d+)$', 'tokens', 'once');
    if isempty(token)
        error('OCE:Interaction:InvalidDispersionGeometry', ...
            'Preview B-mode selector is invalid.');
    end
    index = str2double(token{1});
end

function value = on_off(condition)
    if condition
        value = 'on';
    else
        value = 'off';
    end
end

function validate_geometry(geometry, localLateralAxisMm)
    required = {'samples_per_bmode', 'bmode_count'};
    if ~isstruct(geometry) || any(~isfield(geometry, required)) || ...
            ~isscalar(geometry.samples_per_bmode) || ...
            ~isscalar(geometry.bmode_count) || ...
            geometry.samples_per_bmode < 2 || geometry.bmode_count < 1
        error('OCE:Interaction:InvalidDispersionGeometry', ...
            'Canonical B-mode geometry is required for ROI tuning.');
    end
    if ~isnumeric(localLateralAxisMm) || ...
            numel(localLateralAxisMm) ~= geometry.samples_per_bmode || ...
            any(~isfinite(localLateralAxisMm)) || ...
            any(diff(localLateralAxisMm(:)) <= 0)
        error('OCE:Interaction:InvalidDispersionGeometry', ...
            'localLateralAxisMm must match one increasing B-mode axis.');
    end
end
