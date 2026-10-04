function test_dispersion_analysis_contract(~)
%TEST_DISPERSION_ANALYSIS_CONTRACT Validate structured analysis contracts.

    fixture = create_dispersion_analysis_fixture();
    options = fixture.DispersionAnalysisOptions;
    analysis = oce.dispersion.analyzeWindows( ...
        fixture.window_result, fixture.DistBorder, options);

    assert_structured_contract(analysis, fixture);
    assert_fft_axis_contract(fixture);
    assert_bidirectional_ordering_contract(analysis);
    assert_prefft_windowing(fixture);
    assert_option_validation(fixture);
    assert_invalid_direction(fixture, options);
    assert_invalid_window_result(fixture, options);
    assert_phase_gradient_physics();
    assert_phase_gradient_motion();
    assert_phase_gradient_configuration(fixture);
    assert_phase_gradient_runtime(fixture);
end

function assert_phase_gradient_physics()
    frequency = 1000;
    speed = 2;
    x = linspace(0.17, 1.17, 41)'; % span=1 mm=lambda/2
    t = (0:199) * 5e-5;
    for signValue = [-1 1]
        values = cos(2*pi*frequency*t + signValue*2*pi*500*x*1e-3 + 0.37);
        result = oce.dispersion.computePhaseGradientSpeed(values, x, t, frequency);
        assert(result.status == "valid");
        assert(abs(result.phase_speed_m_per_s / speed - 1) < 1e-10);
        assert(abs(result.wavenumber_cycles_per_m / 500 - 1) < 1e-10);
        assert(abs(result.phase_slope_rad_per_m / (signValue*2*pi*500) - 1) < 1e-10);
        assert(result.spatial_sample_count == 41 && abs(result.spatial_span_mm - 1) < 4*eps);
        assert(abs(result.r_squared - 1) < 1e-12 && result.phase_rmse_rad < 1e-12);
    end
    for badFrequency = [NaN Inf 0 -1 10000 11000]
        assert_identifier('OCE:PhaseGradient:InvalidPhysicalFrequency', @() ...
            oce.dispersion.computePhaseGradientSpeed(values, x, t, badFrequency));
    end
    missing = values; missing(20, 17) = NaN;
    result = oce.dispersion.computePhaseGradientSpeed(missing, x, t, frequency);
    assert(result.status == "nonfinite_signal" && isnan(result.phase_speed_m_per_s));
    missing(20, 17) = Inf;
    result = oce.dispersion.computePhaseGradientSpeed(missing, x, t, frequency);
    assert(result.status == "nonfinite_signal");
    result = oce.dispersion.computePhaseGradientSpeed(zeros(size(values)), x, t, frequency);
    assert(result.status == "undefined_projection" && isnan(result.phase_speed_m_per_s));
    uniform = repmat(cos(2*pi*frequency*t), numel(x), 1);
    result = oce.dispersion.computePhaseGradientSpeed(uniform, x, t, frequency);
    assert(result.status == "degenerate_slope" && isnan(result.phase_speed_m_per_s));
    gap = values; gap(20, :) = 0;
    result = oce.dispersion.computePhaseGradientSpeed(gap, x, t, frequency);
    assert(result.status == "undefined_projection"); % never bridge a missing row

    % Inclusive endpoints and fractional cycle counts are not an orthogonal
    % DFT record. Independently derive the conjugate-frequency leakage rather
    % than treating the short-record estimate as exact truth.
    frequency = 3500;
    t = (0:171) * 5e-6;
    x = linspace(0, 0.5 * speed/frequency * 1e3, 41)';
    spatialPhase = -2*pi*(frequency/speed)*x*1e-3 + 0.37;
    values = cos(2*pi*frequency*t + spatialPhase);
    result = oce.dispersion.computePhaseGradientSpeed(values, x, t, frequency);
    expectedProjection = numel(t)/2 * exp(1i*spatialPhase) + ...
        0.5 * exp(-1i*spatialPhase) * sum(exp(-1i*4*pi*frequency*t));
    expectedFit = polyfit(x*1e-3, unwrap(angle(expectedProjection)), 1);
    expectedSpeed = 2*pi*frequency / abs(expectedFit(1));
    assert(abs(result.phase_speed_m_per_s - expectedSpeed) < 1e-10);
    assert(abs(result.phase_speed_m_per_s/speed - 1) < 0.01);
end

function assert_phase_gradient_motion()
    frequency = 1000;
    x = linspace(0, 1, 41)';
    dt = 5e-5;
    t = (0:200) * dt;
    defaults = oce.config.getDefaultProcessingConfig("phantom");
    for estimator = ["unwrap_then_difference", "loupas"]
        for smoothing = ["none", "lowess"]
            editable = defaults.MotionOptions;
            editable.surface.estimator = estimator;
            editable.surface.smoothing.method = smoothing;
            if smoothing == "none"
                editable.surface.smoothing.span_fraction = [];
            end
            options = oce.config.resolvePhaseEstimationOptions(editable);
            for signValue = [-1 1]
                opticalPhase = 0.1*sin(2*pi*frequency*t + signValue*2*pi*500*x*1e-3);
                volume = repmat(reshape(exp(-1i*opticalPhase), 41, 1, 201), 1, 40, 1);
                phase = oce.motion.computeSurfacePhase(volume, 12*ones(41, 1), options);
                result = oce.dispersion.computePhaseGradientSpeed( ...
                    phase.values, x, t(1:end-1) + dt/2, frequency);
                assert(result.status == "valid");
                assert(sign(result.phase_slope_rad_per_m) == signValue);
                if smoothing == "none"
                    assert(abs(result.phase_speed_m_per_s/2 - 1) < 1e-10);
                else
                    % Fixed default LOWESS edges on a finite record: <=1%.
                    assert(abs(result.phase_speed_m_per_s/2 - 1) < 0.01);
                end
            end
        end
    end
end

function assert_phase_gradient_configuration(fixture)
    editable = fixture.config_for_run.DispersionAnalysisOptions;
    row = table("quasi_harmonic", 1000, ...
        'VariableNames', {'excitation_type', 'frequency_Hz'});
    editable.phase_gradient.enabled = true;
    [kf, gradient] = oce.config.resolveDispersionAnalysisOptions(editable, fixture.FilterOptions, row);
    assert(isequaln(kf, fixture.DispersionAnalysisOptions));
    assert(gradient.enabled && gradient.target_frequency_hz == 1000);
    assert(gradient.frequency_source == "acquisition_row.frequency_Hz");
    textRow = row; textRow.frequency_Hz = "1000";
    assert(isequaln(gradient, resolve_gradient_options(editable, fixture.FilterOptions, textRow)));
    assert_identifier('OCE:PhaseGradient:RuntimeOutputRequired', @() ...
        oce.config.resolveDispersionAnalysisOptions(editable, fixture.FilterOptions, row));
    assert_identifier('OCE:PhaseGradient:InvalidPhysicalFrequency', @() ...
        resolve_gradient_options(editable, fixture.FilterOptions, table()));
    for frequency = [NaN Inf 0 -1]
        row.frequency_Hz = frequency;
        assert_identifier('OCE:PhaseGradient:InvalidPhysicalFrequency', @() ...
            resolve_gradient_options(editable, fixture.FilterOptions, row));
    end
    row.frequency_Hz = 1000; row.excitation_type = "pulse";
    assert_identifier('OCE:PhaseGradient:InvalidPhysicalFrequency', @() ...
        resolve_gradient_options(editable, fixture.FilterOptions, row));
    row.excitation_type = "quasi_harmonic"; row.frequency_Hz = 999;
    assert_identifier('OCE:PhaseGradient:TargetFrequencyMismatch', @() ...
        resolve_gradient_options(editable, fixture.FilterOptions, row));
    row.frequency_Hz = 1000;
    editable.target_frequency.source = "not_available";
    assert_identifier('OCE:PhaseGradient:TargetFrequencyMismatch', @() ...
        resolve_gradient_options(editable, fixture.FilterOptions, row));
    editable.phase_gradient.enabled = false;
    [pulse, gradient] = oce.config.resolveDispersionAnalysisOptions(editable, fixture.FilterOptions);
    assert(~gradient.enabled && isnan(pulse.target_frequency.requested_hz));
    editable.phase_gradient.enabled = 1;
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_gradient_options(editable, fixture.FilterOptions, row));
end

function gradient = resolve_gradient_options(editable, filter, row)
    [~, gradient] = oce.config.resolveDispersionAnalysisOptions(editable, filter, row);
end

function assert_phase_gradient_runtime(analysisFixture)
    fixture = create_dispersion_windows_fixture();
    % Broadband deterministic filtered input supplies interior FFT peaks even
    % in boundary-shifted windows. It deliberately differs from the raw phase.
    fixture.filter_result.surface_postprocessed.values = sin((1:93)'*(1:121)*sqrt(2));
    config = fixture.cases.manualByBmode;
    config.resolved_crop.time.start_index_inclusive = 5;
    config.resolved_crop.time.end_index_inclusive = 126;
    row = table("quasi_harmonic", 1000, ...
        'VariableNames', {'excitation_type', 'frequency_Hz'});
    editable = analysisFixture.config_for_run.DispersionAnalysisOptions;
    editable.spectrum.crop.maximum_wavenumber_per_m = 5000;
    editable.phase_gradient.enabled = true;
    [kf, gradient] = oce.config.resolveDispersionAnalysisOptions(editable, fixture.resolved_filter, row);
    phase = struct('values', 0.1*cos((1:93)'/7 + 2*pi*1000*(0:120)*5e-5), ...
        'quantity', "phase_increment", 'units', "rad", 'layout', "lateral_time", ...
        'estimator', "loupas", 'difference_axis', "time");
    for applied = [false true]
        filtered = fixture.filter_result;
        filtered.applied = applied;
        filtered.enabled = applied;
        windows = oce.dispersion.buildWindows(config, filtered, fixture.x_axis_mm, ...
            fixture.resolved_filter, fixture.geometry);
        original = windows;
        thickness = ones(93, 1);
        disabled = oce.dispersion.analyzeWindows(windows, thickness, kf);
        enabled = oce.dispersion.analyzeWindows(windows, thickness, kf, ...
            'PhaseGradientOptions', gradient, 'SurfacePhase', phase, 'PhaseTimeStartIndex', 5);
        assert(isequaln(windows, original));
        assert(isequaln(rmfield(disabled, 'phase_gradient'), rmfield(enabled, 'phase_gradient')));
        assert(~disabled.phase_gradient.enabled && isempty(disabled.phase_gradient.directions));
        for index = 1:6
            name = enabled.directions(index).direction;
            window = windows.bmodes(ceil(index/2)).(name);
            expected = oce.dispersion.computePhaseGradientSpeed( ...
                phase.values(window.global_lateral_indices, window.time_indices - 4), ...
                window.x_axis_mm, window.time_axis_s, 1000);
            assert(isequaln(enabled.phase_gradient.directions(index), expected));
        end
        gradient.enabled = false;
        off = oce.dispersion.analyzeWindows(windows, thickness, kf, ...
            'PhaseGradientOptions', gradient); % no raw phase required when disabled
        assert(isequaln(off, disabled));
        gradient.enabled = true;
        assert_identifier('OCE:PhaseGradient:InvalidPhaseSource', @() ...
            oce.dispersion.analyzeWindows(windows, thickness, kf, 'PhaseGradientOptions', gradient));
        assert_identifier('OCE:PhaseGradient:InvalidTimeAlignment', @() ...
            oce.dispersion.analyzeWindows(windows, thickness, kf, ...
            'PhaseGradientOptions', gradient, 'SurfacePhase', phase, 'PhaseTimeStartIndex', 999));
    end
end

function assert_fft_axis_contract(fixture)
    window = fixture.window_result.bmodes(1).right;
    options = fixture.DispersionAnalysisOptions;
    [spectrum, ~] = oce.dispersion.computeDispersionSpectrum( ...
        window.values, window.x_axis_mm, window.time_axis_s, options, ...
        fixture.window_result.source, "right");

    frequencyBinHz = 1 / ( ...
        options.spectrum.fft.time_bin_count * spectrum.input.sample_interval_s);
    wavenumberBinPerM = 1 / ( ...
        options.spectrum.fft.spatial_bin_count * ...
        spectrum.input.spatial_interval_m);
    frequency = spectrum.frequency_axis_hz(:);
    wavenumber = spectrum.wavenumber_axis_per_m(:);
    expectedFrequency = (0:numel(frequency) - 1)' * frequencyBinHz;
    expectedWavenumber = (0:numel(wavenumber) - 1)' * wavenumberBinPerM;

    frequencyTolerance = 100 * eps(max(1, max(abs(expectedFrequency))));
    wavenumberTolerance = 100 * eps(max(1, max(abs(expectedWavenumber))));
    if any(abs(frequency - expectedFrequency) > frequencyTolerance) || ...
            any(abs(wavenumber - expectedWavenumber) > wavenumberTolerance)
        error('OCE:DispersionAnalysis:FFTPhysicalAxes', ...
            ['FFT axes must use DFT bin spacing 1/(N*sampleInterval). ' ...
             'Observed df=%g Hz, expected=%g Hz; observed dk=%g 1/m, ' ...
             'expected=%g 1/m.'], ...
            frequency(2) - frequency(1), frequencyBinHz, ...
            wavenumber(2) - wavenumber(1), wavenumberBinPerM);
    end
end

function assert_prefft_windowing(fixture)
    window = fixture.window_result.bmodes(1).right;
    baseOptions = fixture.DispersionAnalysisOptions;
    configurations = [false false; true false; false true; true true];
    temporalMagnitudeByConfiguration = cell(size(configurations, 1), 1);
    for index = 1:size(configurations, 1)
        timeEnabled = configurations(index, 1);
        spaceEnabled = configurations(index, 2);
        options = baseOptions;
        options.spectrum.window.time.enabled = timeEnabled;
        options.spectrum.window.space.enabled = spaceEnabled;
        [spectrum, ~] = oce.dispersion.computeDispersionSpectrum( ...
            window.values, window.x_axis_mm, window.time_axis_s, options, ...
            fixture.window_result.source, "right");
        expectedDxM = (window.x_axis_mm(2) - ...
            window.x_axis_mm(1)) * 1e-3;
        if spectrum.input.spatial_interval_m ~= expectedDxM
            error('OCE:DispersionAnalysis:LocalSpatialInterval', ...
                'Dispersion did not use the supplied local B-mode axis.');
        end
        expected = expected_spectrum_magnitude( ...
            window.values, options, "right", size(spectrum.magnitude));
        if ~isequaln(spectrum.magnitude, expected)
            error('OCE:DispersionAnalysis:PrefftWindowing', ...
                'The configured pre-FFT taper does not match its reference.');
        end
        expectedTemporal = expected_temporal_magnitude( ...
            window.values, options, "right", ...
            numel(spectrum.temporal_magnitude_mean));
        if ~isequaln(spectrum.temporal_magnitude_mean, expectedTemporal)
            error('OCE:DispersionAnalysis:TemporalDiagnosticWindowing', ...
                ['The temporal diagnostic does not match its configured ' ...
                 'time-only taper reference.']);
        end
        temporalMagnitudeByConfiguration{index} = ...
            spectrum.temporal_magnitude_mean;
        provenance = spectrum.window;
        if provenance.time.enabled ~= timeEnabled || ...
                provenance.space.enabled ~= spaceEnabled || ...
                provenance.time.method ~= "hann_symmetric" || ...
                provenance.space.method ~= "hann_symmetric" || ...
                provenance.time.sample_count ~= size(window.values, 2) || ...
                provenance.space.sample_count ~= size(window.values, 1)
            error('OCE:DispersionAnalysis:WindowProvenance', ...
                'Spectrum window provenance is incomplete or incorrect.');
        end
    end
    if ~isequaln(temporalMagnitudeByConfiguration{1}, ...
            temporalMagnitudeByConfiguration{3}) || ...
            ~isequaln(temporalMagnitudeByConfiguration{2}, ...
                temporalMagnitudeByConfiguration{4}) || ...
            isequaln(temporalMagnitudeByConfiguration{1}, ...
                temporalMagnitudeByConfiguration{2})
        error('OCE:DispersionAnalysis:TemporalDiagnosticIndependence', ...
            ['The temporal diagnostic must depend only on the temporal ' ...
             'window flag.']);
    end

    timeWindow = hann(size(window.values, 2), "symmetric");
    spaceWindow = hann(size(window.values, 1), "symmetric");
    if timeWindow(1) ~= 0 || timeWindow(end) ~= 0 || ...
            spaceWindow(1) ~= 0 || spaceWindow(end) ~= 0 || ...
            ~isequal(timeWindow, flip(timeWindow)) || ...
            ~isequal(spaceWindow, flip(spaceWindow))
        error('OCE:DispersionAnalysis:HannConvention', ...
            'The analytical fixture does not use symmetric Hann vectors.');
    end

    left = fixture.window_result.bmodes(1).left;
    options = baseOptions;
    options.spectrum.window.time.enabled = true;
    options.spectrum.window.space.enabled = true;
    [leftSpectrum, ~] = oce.dispersion.computeDispersionSpectrum( ...
        left.values, left.x_axis_mm, left.time_axis_s, options, ...
        fixture.window_result.source, "left");
    expectedLeft = expected_spectrum_magnitude( ...
        left.values, options, "left", size(leftSpectrum.magnitude));
    if ~isequaln(leftSpectrum.magnitude, expectedLeft)
        error('OCE:DispersionAnalysis:LeftWindowingOrder', ...
            'Left normalization and taper order changed.');
    end

    legacy = fixture.config_for_run.DispersionAnalysisOptions;
    resolvedLegacy = oce.config.resolveDispersionAnalysisOptions( ...
        legacy, fixture.FilterOptions);
    explicitOff = legacy;
    explicitOff.spectrum.window = resolvedLegacy.spectrum.window;
    resolvedExplicit = oce.config.resolveDispersionAnalysisOptions( ...
        explicitOff, fixture.FilterOptions);
    if ~isequaln(resolvedLegacy, resolvedExplicit) || ...
            resolvedLegacy.spectrum.window.time.enabled || ...
            resolvedLegacy.spectrum.window.space.enabled
        error('OCE:DispersionAnalysis:LegacyWindowDefaults', ...
            'Legacy configs did not normalize once to explicit OFF/OFF.');
    end
end

function expected = expected_temporal_magnitude( ...
        values, options, direction, outputLength)
    map = values';
    if direction == "left"
        map = flip(map, 2);
    end
    if options.spectrum.window.time.enabled
        map = map .* hann(size(map, 1), "symmetric");
    end
    timeCount = options.spectrum.fft.time_bin_count;
    fullMagnitude = abs(fftshift(fft(map, timeCount)))';
    fullMagnitude = fullMagnitude(:, end:-1:1);
    centerTime = (timeCount + 1) / 2;
    expected = mean(fullMagnitude(:, ...
        centerTime:centerTime + outputLength - 1), 1)';
end

function expected = expected_spectrum_magnitude( ...
        values, options, direction, outputSize)
    map = values';
    if direction == "left"
        map = flip(map, 2);
    end
    if options.spectrum.window.time.enabled
        map = map .* hann(size(map, 1), "symmetric");
    end
    if options.spectrum.window.space.enabled
        map = map .* hann(size(map, 2), "symmetric").';
    end
    timeCount = options.spectrum.fft.time_bin_count;
    spaceCount = options.spectrum.fft.spatial_bin_count;
    fullMagnitude = abs(fftshift(fft2(map, timeCount, spaceCount)))';
    fullMagnitude = fullMagnitude(:, end:-1:1);
    centerTime = (timeCount + 1) / 2;
    centerSpace = (spaceCount + 1) / 2;
    expected = fullMagnitude( ...
        centerSpace:centerSpace + outputSize(1) - 1, ...
        centerTime:centerTime + outputSize(2) - 1);
end

function assert_structured_contract(analysis, fixture)
    if analysis.method ~= "windowed_fft_ridge" || ...
            analysis.target_frequency.source ~= "resolved_filter_center" || ...
            analysis.target_frequency.requested_hz ~= ...
                fixture.DispersionAnalysisOptions.target_frequency.requested_hz || ...
            numel(analysis.directions) ~= 6 || analysis.scan_axis_count ~= 3 || ...
            ~isequal(analysis.scan_axis_angles_deg, [0 60 120])
        error('OCE:DispersionAnalysis:StructuredContract', ...
            'The structured analysis header is invalid.');
    end
    required = {'requested_frequency_hz', 'selected_bin_index', ...
        'selected_frequency_hz', 'frequency_error_hz', ...
        'selected_wavenumber_per_m', 'selected_phase_speed_m_per_s'};
    for index = 1:numel(analysis.directions)
        direction = analysis.directions(index);
        selection = direction.target_selection;
        curve = direction.phase_speed_curve;
        if any(~isfield(selection, required)) || ...
                direction.spectrum.input.units ~= "rad" || ...
                direction.spectrum.input.layout ~= "time_space" || ...
                ~isequal(size(direction.ridge.valid_mask), ...
                    size(curve.frequency_hz)) || ...
                selection.selected_frequency_hz ~= ...
                    curve.frequency_hz(selection.selected_bin_index) || ...
                selection.selected_phase_speed_m_per_s ~= ...
                    curve.smoothed_phase_speed_m_per_s( ...
                        selection.selected_bin_index)
            error('OCE:DispersionAnalysis:StructuredContract', ...
                'Directional structured output is incomplete or inconsistent.');
        end
    end
end

function assert_bidirectional_ordering_contract(analysis)
    [sourceIndices, anglesDeg] = oce.dispersion.orderBidirectionalAngles( ...
        analysis.scan_axis_count);
    if ~isequal(sourceIndices(:), [1; 4; 5; 2; 3; 6]) || ...
            ~isequal(anglesDeg, (0:60:300)')
        error('OCE:DispersionAnalysis:AngularOrdering', ...
            'Bidirectional direction ordering changed.');
    end
    % GUI meridians all run toward theta: right windows lie at theta and
    % left windows at theta + 180 deg.
    [guiIndices, guiAngles] = oce.dispersion.orderBidirectionalAngles( ...
        4, [0 45 90 135]);
    [linearIndices, linearAngles] = oce.dispersion.orderBidirectionalAngles( ...
        2, [90 90]);
    if ~isequal(guiIndices, [2 4 6 8 1 3 5 7]) || ...
            ~isequal(guiAngles, (0:45:315)') || ...
            ~isequal(linearIndices, [2 4 1 3]) || ...
            ~isequal(linearAngles, [90; 90; 270; 270])
        error('OCE:DispersionAnalysis:AngularOrdering', ...
            'Scan directions did not order directions counterclockwise.');
    end
    selected = reshape(arrayfun(@(item) ...
        item.target_selection.selected_phase_speed_m_per_s, ...
        analysis.directions), [], 1);
    thickness = reshape(arrayfun(@(item) ...
        item.mean_thickness_mm, analysis.directions), [], 1);
    orderedSpeed = selected(sourceIndices);
    orderedThickness = thickness(sourceIndices);
    if numel(orderedSpeed) ~= 2 * analysis.scan_axis_count || ...
            numel(orderedThickness) ~= 2 * analysis.scan_axis_count || ...
            any(~isfinite(orderedSpeed)) || any(~isfinite(orderedThickness))
        error('OCE:DispersionAnalysis:AngularOrdering', ...
            'Ordered directional quantities are invalid.');
    end
end

function assert_option_validation(fixture)
    editable = fixture.config_for_run.DispersionAnalysisOptions;
    filter = fixture.FilterOptions;
    assert_identifier('OCE:DispersionAnalysis:UnsupportedMethod', @() ...
        resolve_changed(editable, filter, 'method', "unknown"));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        oce.config.resolveDispersionAnalysisOptions( ...
        struct('FFT_Nt', 129), filter));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(editable, filter, ...
        'spectrum.fft.time_bin_count', 128));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(editable, filter, ...
        'spectrum.crop.maximum_frequency_hz', -1));
    explicit = editable;
    explicit.spectrum.window = fixture.DispersionAnalysisOptions.spectrum.window;
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(explicit, filter, ...
        'spectrum.window.time.enabled', 1));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(explicit, filter, ...
        'spectrum.window.space.method', "hann_periodic"));
    missingAxisField = explicit;
    missingAxisField.spectrum.window.time = rmfield( ...
        missingAxisField.spectrum.window.time, 'method');
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        oce.config.resolveDispersionAnalysisOptions( ...
            missingAxisField, filter));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(editable, filter, ...
        'ridge.maximum_wavenumber_jump_per_m', -1));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(editable, filter, ...
        'ridge.minimum_relative_magnitude', 1.1));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(editable, filter, ...
        'ridge.interpolation.method', "spline"));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(editable, filter, ...
        'ridge.interpolation.extrapolate', false));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(editable, filter, ...
        'phase_speed.smoothing.method', "movmean"));
    assert_identifier('OCE:Config:InvalidDispersionAnalysisOptions', @() ...
        resolve_changed(editable, filter, ...
        'phase_speed.smoothing.span_fraction', 2));
    invalidFilter = filter;
    invalidFilter.frequency.center_hz = NaN;
    assert_identifier('OCE:DispersionAnalysis:InvalidTargetFrequency', @() ...
        oce.config.resolveDispersionAnalysisOptions(editable, invalidFilter));

    tooSmall = fixture.DispersionAnalysisOptions;
    tooSmall.spectrum.fft.time_bin_count = 79;
    window = fixture.window_result.bmodes(1).left;
    assert_identifier('OCE:DispersionAnalysis:FFTTooSmall', @() ...
        oce.dispersion.computeDispersionSpectrum(window.values, ...
        window.x_axis_mm, window.time_axis_s, tooSmall, ...
        fixture.window_result.source, window.direction));
end

function value = resolve_changed(base, filter, pathValue, replacement)
    parts = split(string(pathValue), '.');
    value = set_nested(base, parts, replacement);
    value = oce.config.resolveDispersionAnalysisOptions(value, filter);
end

function value = set_nested(value, parts, replacement)
    name = char(parts(1));
    if isscalar(parts)
        value.(name) = replacement;
    else
        value.(name) = set_nested(value.(name), parts(2:end), replacement);
    end
end

function assert_identifier(expected, action)
    try
        action();
    catch ME
        if strcmp(ME.identifier, expected)
            return;
        end
        error('OCE:DispersionAnalysis:UnexpectedError', ...
            'Expected %s; actual %s.', expected, ME.identifier);
    end
    error('OCE:DispersionAnalysis:ExpectedError', ...
        'Expected error %s was not raised.', expected);
end

function assert_invalid_direction(fixture, options)
    window = fixture.window_result.bmodes(1).left;
    assert_identifier('OCE:DispersionAnalysis:InvalidDirection', @() ...
        oce.dispersion.computeDispersionSpectrum(window.values, ...
        window.x_axis_mm, window.time_axis_s, options, ...
        fixture.window_result.source, "sideways"));
end

function assert_invalid_window_result(fixture, options)
    invalid = fixture.window_result;
    invalid.bmodes(1).left.values = invalid.bmodes(1).left.values(1:end-1, :);
    assert_identifier('OCE:DispersionAnalysis:InvalidWindowResult', @() ...
        oce.dispersion.analyzeWindows(invalid, fixture.DistBorder, options));
end
