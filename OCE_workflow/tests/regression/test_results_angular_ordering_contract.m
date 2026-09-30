function test_results_angular_ordering_contract(~)
%TEST_RESULTS_ANGULAR_ORDERING_CONTRACT Preserve summary angle/curve alignment.

    temporaryRoot = tempname;
    fixture = create_results_fixture(temporaryRoot);
    cleanup = onCleanup(@() remove_temporary_root(temporaryRoot));

    subExperiment = "AngularOrdering";
    acquisitionTable = fixture.acquisitionTable(1, :);
    acquisitionTable.sub_experiment(:) = subExperiment;
    acquisitionTable.run_id(:) = "R001";
    acquisitionTable.filename(:) = "angular_ordering.bin";
    acquisitionTable.frequency_Hz(:) = 1000;
    acquisitionTable.rep_id(:) = 1;

    paramsDir = fullfile(fixture.experimentRoot, 'Params', subExperiment);
    mkdir(paramsDir);
    acquisition_table = acquisitionTable; %#ok<NASGU>
    save(fullfile(paramsDir, ...
        'AcquisitionParams_' + subExperiment + '.mat'), 'acquisition_table');

    frequencyHz = [100; 200];
    directionalSpeed = (11:18)';
    directionalThickness = (1:8)' * 1e-3;
    diagnostics = arrayfun(@(index) [index; index + 0.5], ...
        (1:8)', 'UniformOutput', false);
    curves = arrayfun(@(index) ...
        [directionalSpeed(index); 100 + index], ...
        (1:8)', 'UniformOutput', false);
    anglesDeg = (0:45:315)';

    result = make_scientific_result( ...
        frequencyHz, diagnostics, curves, directionalSpeed, ...
        directionalThickness, anglesDeg);
    sourceIndices = [1; 4; 5; 8; 2; 3; 6; 7];
    result.angular.source_direction_indices = sourceIndices;
    result.angular.phase_speed_m_per_s = directionalSpeed(sourceIndices);
    result.angular.mean_thickness_mm = directionalThickness(sourceIndices);
    oce.results.validateScientificResult(result);

    resultDir = fullfile(fixture.experimentRoot, 'Results', ...
        subExperiment, 'angular_ordering');
    mkdir(resultDir);
    oce.io.saveScientificResult(resultDir, result);

    experiment = oce.results.buildSubexperimentResultSet( ...
        fixture.experimentRoot, subExperiment, ...
        "frequency_Hz", "rep_id", 'MissingResultMode', 'error');
    item = experiment.data{1, 1};

    expectedSpeed = directionalSpeed(sourceIndices);
    if ~isequal(item.full_circle_angles_deg(:), anglesDeg) || ...
            ~isequal(item.angular_phase_speed_m_per_s(:), expectedSpeed)
        error('OCE:ResultsTest:AngularOrdering', ...
            'Maintained angular values are not in full-circle order.');
    end

    firstCurveValue = cellfun(@(value) value(1), ...
        item.direction_smoothed_phase_speed_m_per_s);
    if ~isequal(firstCurveValue(:), expectedSpeed)
        error('OCE:ResultsTest:AngularOrdering', ...
            ['Summary dispersion curves are not indexed by the same angular ' ...
             'order as full_circle_angles_deg.']);
    end

    expectedDiagnostics = diagnostics(sourceIndices);
    for angleIndex = 1:numel(sourceIndices)
        if ~isequal(item.direction_temporal_diagnostic_magnitude{angleIndex}, ...
                expectedDiagnostics{angleIndex})
            error('OCE:ResultsTest:AngularOrdering', ...
                ['Summary temporal diagnostics are not indexed by the same ' ...
                 'angular order as full_circle_angles_deg.']);
        end
    end

    orderedDirections = result.dispersion.directions(sourceIndices);
    expectedScanAxes = reshape([orderedDirections.scan_axis_index], [], 1);
    expectedNames = string({orderedDirections.direction})';
    expectedTargetSpeed = reshape(arrayfun(@(direction) ...
        direction.target_selection.selected_phase_speed_m_per_s, ...
        result.dispersion.estimators.kf_ridge.directions(sourceIndices)), [], 1);
    if ~isequal(item.direction_scan_axis_indices(:), expectedScanAxes) || ...
            ~isequal(string(item.direction_names(:)), expectedNames) || ...
            ~isequal(item.direction_target_phase_speed_m_per_s(:), ...
                expectedTargetSpeed)
        error('OCE:ResultsTest:AngularOrdering', ...
            ['Summary directional identity and target speed must preserve ' ...
             'the same canonical angular ordering as directional curves.']);
    end

    clear cleanup
end

function remove_temporary_root(pathValue)
    if isfolder(pathValue)
        rmdir(pathValue, 's');
    end
end
