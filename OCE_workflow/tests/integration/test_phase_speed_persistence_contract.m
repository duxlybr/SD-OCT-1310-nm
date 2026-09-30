function test_phase_speed_persistence_contract(~)
%TEST_PHASE_SPEED_PERSISTENCE_CONTRACT Verify strict structured result IO.

    fixture = create_dispersion_analysis_fixture();
    analysis = oce.dispersion.analyzeWindows(fixture.window_result, ...
        fixture.DistBorder, fixture.DispersionAnalysisOptions);
    config = fixture.config_for_run;
    config.DispersionAnalysisOptions = fixture.DispersionAnalysisOptions;
    result = oce.results.buildScientificResult( ...
        fixture.processing_inputs, config, fixture.window_result, analysis);
    assert_contract(result);

    pulseEditable = fixture.config_for_run.DispersionAnalysisOptions;
    pulseEditable.target_frequency.source = "not_available";
    pulseOptions = oce.config.resolveDispersionAnalysisOptions( ...
        pulseEditable, fixture.FilterOptions);
    pulseAnalysis = oce.dispersion.analyzeWindows( ...
        fixture.window_result, fixture.DistBorder, pulseOptions);
    pulseConfig = config;
    pulseConfig.DispersionAnalysisOptions = pulseOptions;
    pulseResult = oce.results.buildScientificResult( ...
        fixture.processing_inputs, pulseConfig, fixture.window_result, ...
        pulseAnalysis);
    if pulseResult.dispersion.target_frequency.source ~= "not_available" || ...
            ~isnan(pulseResult.dispersion.target_frequency.requested_hz) || ...
            any(~isnan(pulseResult.angular.phase_speed_m_per_s)) || ...
            ~isnan(pulseResult.statistics.phase_speed.mean_m_per_s)
        error('OCE:ResultTest:PulseTarget', ...
            'Pulse result must preserve broadband curves without a target speed.');
    end

    temporaryRoot = tempname;
    mkdir(temporaryRoot);
    cleanup = onCleanup(@() remove_root(temporaryRoot));
    assert(~result.dispersion.estimators.phase_gradient.enabled && ...
        isempty(result.dispersion.estimators.phase_gradient.directions));
    assert(isequaln(oce.io.loadScientificResult( ...
        oce.io.saveScientificResult(temporaryRoot, result)), result));
    % Use the same resolved windows and a real runtime phase-gradient result.
    defaults = oce.config.getDefaultProcessingConfig("phantom");
    config.MotionOptions = oce.config.resolvePhaseEstimationOptions(defaults.MotionOptions);
    surface = config.MotionOptions.surface;
    surface.difference_axis = "time"; surface.values = fixture.SpaceTime;
    surface.values(1, 1) = NaN; % Enabled but invalid first direction.
    windows = fixture.window_result;
    for index = 1:numel(windows.bmodes)
        for name = ["left", "right"]
            windows.bmodes(index).(name).time_axis_s = ...
                (windows.bmodes(index).(name).time_indices - 0.5)*windows.sample_interval_s;
        end
    end
    gradient = struct('enabled', true, 'target_frequency_hz', 1000, ...
        'frequency_source', "acquisition_row.frequency_Hz");
    analysis = oce.dispersion.analyzeWindows(windows, fixture.DistBorder, ...
        fixture.DispersionAnalysisOptions, 'PhaseGradientOptions', gradient, ...
        'SurfacePhase', surface, 'PhaseTimeStartIndex', 1);
    fixture.processing_inputs.acquisition_row.excitation_type = "quasi_harmonic";
    fixture.processing_inputs.acquisition_row.frequency_Hz = "1000";
    result = oce.results.buildScientificResult(fixture.processing_inputs, config, windows, analysis);
    persisted = result.dispersion.estimators.phase_gradient;
    assert(persisted.enabled && ~isfield(persisted.directions, 'diagnostic'));
    assert(isequaln(persisted.directions, rmfield(analysis.phase_gradient.directions, 'diagnostic')));
    assert(persisted.directions(1).status ~= "valid" && isnan(persisted.directions(1).phase_speed_m_per_s));
    assert(persisted.directions(2).status == "valid");
    resultPath = oce.io.saveScientificResult(temporaryRoot, result);
    variables = whos('-file', resultPath);
    if numel(variables) ~= 1 || string(variables.name) ~= "oce_result"
        error('OCE:ResultTest:RootVariable', ...
            'PhaseSpeed.mat must contain only oce_result.');
    end
    if ~isequaln(oce.io.loadScientificResult(resultPath), result)
        error('OCE:ResultTest:RoundTrip', ...
            'Scientific result did not round-trip exactly.');
    end
    if isfile(fullfile(temporaryRoot, 'PhaseSpeed.tmp.mat'))
        error('OCE:ResultTest:TemporaryFile', ...
            'Scientific-result writer left a temporary file.');
    end

    flat = fullfile(temporaryRoot, 'flat.mat');
    PhaseSpeed = 1;
    save(flat, 'PhaseSpeed');
    assert_identifier('OCE:Result:MissingRootVariable', ...
        @() oce.io.loadScientificResult(flat));
    extra = fullfile(temporaryRoot, 'extra.mat');
    oce_result = result; extra_value = 1;
    save(extra, 'oce_result', 'extra_value');
    assert_identifier('OCE:Result:UnexpectedVariables', ...
        @() oce.io.loadScientificResult(extra));

    changed = result; changed.schema.version = 2;
    oce_result = changed; save(fullfile(temporaryRoot, 'v2.mat'), 'oce_result');
    assert_identifier('OCE:Result:UnsupportedSchema', ...
        @() oce.io.loadScientificResult(fullfile(temporaryRoot, 'v2.mat')));
    changed = result; changed.dispersion.estimators.kf_ridge.frequency_axis_units = "kHz";
    assert_identifier('OCE:Result:InvalidContract', ...
        @() oce.results.validateScientificResult(changed));
    changed = result; changed.angular.source_direction_indices(1) = 2;
    assert_identifier('OCE:Result:InvalidContract', ...
        @() oce.results.validateScientificResult(changed));
    changed = result; changed.statistics.phase_speed.mean_m_per_s = ...
        changed.statistics.phase_speed.mean_m_per_s + 1;
    assert_identifier('OCE:Result:InvalidContract', ...
        @() oce.results.validateScientificResult(changed));
    changed = result;
    changed.dispersion.estimators.kf_ridge.directions(1).target_selection.selected_bin_index = 0;
    assert_identifier('OCE:Result:InvalidContract', ...
        @() oce.results.validateScientificResult(changed));
    changed = result;
    changed.dispersion.estimators.kf_ridge.directions(1).target_selection.selected_frequency_hz = ...
        changed.dispersion.estimators.kf_ridge.directions(1).target_selection. ...
        selected_frequency_hz + 1;
    assert_identifier('OCE:Result:InvalidContract', ...
        @() oce.results.validateScientificResult(changed));
    clear cleanup
end

function assert_contract(result)
    expected = {'schema'; 'acquisition'; 'processing'; 'borders'; ...
        'windows'; 'dispersion'; 'angular'; 'statistics'};
    if ~isequal(fieldnames(result), expected) || ...
            result.schema.name ~= "oce_phase_speed_result" || ...
            result.schema.version ~= 3 || ...
            any(isfield(result, {'PhaseSpeed_New', 'Thickness_New'}))
        error('OCE:ResultTest:Contract', ...
            'Structured scientific-result root contract is invalid.');
    end
    frequency = result.dispersion.estimators.kf_ridge.frequency_axis_hz;
    for index = 1:numel(result.dispersion.estimators.kf_ridge.directions)
        direction = result.dispersion.estimators.kf_ridge.directions(index);
        if numel(direction.spectrum.temporal_diagnostic_magnitude) ~= ...
                numel(frequency) || ...
                isfield(direction.phase_speed_curve, 'frequency_hz')
            error('OCE:ResultTest:DuplicateFrequency', ...
                'Directional data do not use the shared frequency axis.');
        end
    end
end

function assert_identifier(expected, action)
    try
        action();
    catch exception
        if strcmp(exception.identifier, expected), return; end
        error('OCE:ResultTest:UnexpectedIdentifier', ...
            'Expected %s; actual %s.', expected, exception.identifier);
    end
    error('OCE:ResultTest:MissingError', ...
        'Expected error %s was not raised.', expected);
end

function remove_root(pathValue)
    if isfolder(pathValue), rmdir(pathValue, 's'); end
end
