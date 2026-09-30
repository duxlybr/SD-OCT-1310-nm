function test_synthetic_scientific_golden(context)
%TEST_SYNTHETIC_SCIENTIFIC_GOLDEN Compare deterministic scientific baseline.

    manifest = context.goldenManifest;
    if ~isfile(manifest.goldenFile)
        error('OCE:Regression:MissingSyntheticGolden', ...
            ['Synthetic scientific golden is missing. Regenerate it only ' ...
             'with UpdateBaseline=true after explicit review.']);
    end

    loaded = load(manifest.goldenFile, 'baseline');
    if ~isfield(loaded, 'baseline') || ~isscalar(loaded.baseline)
        error('OCE:Regression:InvalidSyntheticGolden', ...
            'Golden file must contain exactly one scalar baseline struct.');
    end

    expected = loaded.baseline;
    actual = context.syntheticGolden.actual;
    assert_baseline_contract(expected);
    assert_baseline_contract(actual);
    assert_fixture_physics(actual.fixture);
    assert_border_truth(actual.fixture.border_truth, actual.border_result);
    assert_phase_speed_truth(actual.fixture, actual.scientific_result);
    oce.results.validateScientificResult(actual.scientific_result);
    assert_anterior_only_scientific_result();

    % Comparison view only: restore duplicated v2 fields from v3 common owners.
    % No file conversion, numeric exclusions, baseline writes or tolerance changes.
    result = actual.scientific_result;
    common = result.dispersion;
    kf = common.estimators.kf_ridge;
    options = result.processing.config.DispersionAnalysisOptions;
    options.target_frequency = common.target_frequency;
    result.processing.config.DispersionAnalysisOptions = options;
    for index = 1:numel(kf.directions)
        kf.directions(index).scan_axis_index = common.directions(index).scan_axis_index;
        kf.directions(index).direction = common.directions(index).direction;
        kf.directions(index).mean_thickness_mm = result.borders.directional_mean_thickness_mm(index);
        kf.directions(index).spectrum.input.direction = common.directions(index).direction;
        kf.directions(index).target_selection.requested_frequency_hz = common.target_frequency.requested_hz;
    end
    result.dispersion = rmfield(common, 'estimators');
    for name = string(fieldnames(kf))'
        result.dispersion.(name) = kf.(name);
    end
    result.dispersion.options = options;
    result.schema.version = 2;
    actual.scientific_result = result;
    compare_regression_values(expected, actual, ...
        "SyntheticScientificGolden", manifest.tolerances);
end

function assert_baseline_contract(value)
    required = {'schema', 'fixture', 'border_result', 'scientific_result'};
    if ~isstruct(value) || ~isscalar(value) || ...
            ~isequal(sort(fieldnames(value)), sort(required')) || ...
            ~isstruct(value.schema) || ...
            value.schema.name ~= "oce_synthetic_scientific_golden" || ...
            value.schema.version ~= 3
        error('OCE:Regression:InvalidSyntheticGolden', ...
            'Synthetic golden root contract is invalid.');
    end
end

function assert_fixture_physics(fixture)
    speed = fixture.component_frequency_hz ./ ...
        fixture.component_wavenumber_per_m;
    if fixture.name ~= "synthetic_border_and_traveling_wave" || ...
            fixture.version ~= 4 || ...
            fixture.scan_axis_count ~= 2 || ...
            fixture.expected_phase_speed_m_per_s ~= 2 || ...
            any(speed ~= fixture.expected_phase_speed_m_per_s) || ...
            ~ismember(fixture.target_frequency_hz, ...
                fixture.component_frequency_hz)
        error('OCE:Regression:SyntheticFixturePhysics', ...
            'Synthetic traveling-wave fixture contract changed unexpectedly.');
    end
end

function assert_border_truth(truth, result)
    anterior = result.indices.anterior(:);
    posterior = result.indices.posterior(:);
    thickness = result.thickness(:);
    if any(~isfinite(anterior)) || any(~isfinite(posterior)) || ...
            any(~isfinite(thickness))
        error('OCE:Regression:SyntheticBorderMissing', ...
            'Synthetic border detector produced missing final values.');
    end

    anteriorError = abs(anterior - truth.expected_anterior_index(:));
    posteriorError = abs(posterior - truth.expected_posterior_index(:));
    thicknessError = abs(thickness - truth.expected_thickness_mm(:));
    if max(anteriorError) > truth.index_tolerance_px || ...
            max(posteriorError) > truth.index_tolerance_px || ...
            max(thicknessError) > truth.thickness_tolerance_mm
        error('OCE:Regression:SyntheticBorderTruth', ...
            ['Synthetic borders exceeded truth tolerances. ' ...
             'max anterior=%g px; posterior=%g px; thickness=%g mm.'], ...
            max(anteriorError), max(posteriorError), max(thicknessError));
    end

    if ~isequal(result.intensity_mask.size, [500 262]) || ...
            result.intensity_mask.true_count <= 0 || ...
            numel(result.intensity_mask.column_true_count) ~= 262
        error('OCE:Regression:SyntheticBorderMask', ...
            'Synthetic border intensity-mask contract is invalid.');
    end
end

function assert_phase_speed_truth(fixture, result)
    directions = result.dispersion.estimators.kf_ridge.directions;
    expectedDirectionCount = 2 * fixture.scan_axis_count;
    if numel(directions) ~= expectedDirectionCount
        error('OCE:Regression:SyntheticPhaseSpeedTruth', ...
            'Expected %d directional results; actual=%d.', ...
            expectedDirectionCount, numel(directions));
    end

    selectedFrequencyHz = reshape(arrayfun(@(item) ...
        item.target_selection.selected_frequency_hz, directions), [], 1);
    selectedSpeed = reshape(arrayfun(@(item) ...
        item.target_selection.selected_phase_speed_m_per_s, directions), [], 1);
    expectedSpeed = fixture.expected_phase_speed_m_per_s;
    speedTolerance = 0.10;

    if any(~isfinite(selectedFrequencyHz)) || any(~isfinite(selectedSpeed)) || ...
            any(selectedFrequencyHz ~= fixture.target_frequency_hz)
        error('OCE:Regression:SyntheticPhaseSpeedTruth', ...
            ['Synthetic dispersion must select the known target frequency ' ...
             'for every propagation direction.']);
    end

    speedError = abs(selectedSpeed - expectedSpeed);
    if max(speedError) > speedTolerance
        error('OCE:Regression:SyntheticPhaseSpeedTruth', ...
            ['Synthetic phase-speed recovery exceeded the physical truth ' ...
             'tolerance. expected=%g m/s; max error=%g m/s; tolerance=%g m/s.'], ...
            expectedSpeed, max(speedError), speedTolerance);
    end
end

function assert_anterior_only_scientific_result()
    fixture = create_synthetic_scientific_golden_fixture();
    borderOptions = fixture.BorderOptions;
    borderOptions.surface_mode = "anterior_only";
    borderOptions.parameters.surface_mode = "anterior_only";
    borders = oce.borders.detectAndMask( ...
        fixture.acquisition_state, borderOptions);
    analysis = oce.dispersion.analyzeWindows( ...
        fixture.window_result, borders.thickness, ...
        fixture.DispersionAnalysisOptions);
    result = oce.results.buildScientificResult( ...
        fixture.processing_inputs, fixture.config_for_run, ...
        fixture.window_result, analysis);
    oce.results.validateScientificResult(result);

    thicknessStats = result.statistics.thickness;
    if borders.surface_mode ~= "anterior_only" || ...
            ~all(isnan(borders.indices.posterior)) || ...
            ~all(isnan(borders.thickness)) || ...
            ~all(isnan(result.angular.mean_thickness_mm)) || ...
            ~all(isnan([thicknessStats.mean_um, ...
                thicknessStats.standard_deviation_um, ...
                thicknessStats.range_um])) || ...
            any(~isfinite(result.angular.phase_speed_m_per_s))
        error('OCE:Regression:AnteriorOnlyScientificResult', ...
            ['Anterior-only geometry must preserve phase speed while keeping ' ...
             'posterior-derived thickness explicitly unavailable.']);
    end
end
