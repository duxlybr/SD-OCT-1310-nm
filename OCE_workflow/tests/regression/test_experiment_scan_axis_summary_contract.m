function test_experiment_scan_axis_summary_contract(context)
%TEST_EXPERIMENT_SCAN_AXIS_SUMMARY_CONTRACT Exercise multi-subexperiment pairing.

    fixture = create_results_fixture(tempname);
    cleanup = onCleanup(@() remove_fixture(fixture.rootDir));

    firstSub = fixture.subExperiment;
    secondSub = "SyntheticResultsStrain10";
    configure_subexperiment(fixture, firstSub, 0, false);
    configure_subexperiment(fixture, secondSub, 10, true);

    experiment = oce.results.buildExperimentResultSet( ...
        fixture.experimentRoot, [firstSub secondSub], ...
        ["strain_percent", "frequency_Hz"], "rep_id", ...
        "MissingResultMode", "error", ...
        "DuplicateMode", "error");

    for fileIndex = 1:numel(experiment.source.result_files)
        delete(experiment.source.result_files(fileIndex));
    end

    experiment = oce.results.summarizeRepetitions(experiment);
    experiment = oce.results.summarizeScanAxes(experiment);
    T = oce.results.buildScanAxisSummaryTable(experiment);

    expectedSize = [2 3 3];
    if ~isequal(size(experiment.data), expectedSize)
        error('OCE:Regression:ExperimentScanAxisSummary', ...
            'Combined experiment.data expected size=%s; actual=%s.', ...
            mat2str(expectedSize), mat2str(size(experiment.data)));
    end
    if ~isfield(experiment.summary, 'repetition_mean_data') || ...
            isempty(experiment.summary.repetition_mean_data{1, 1}) || ...
            ~isfield(experiment.summary.repetition_mean_data{1, 1}, ...
                'full_circle_angles_deg') || ...
            ~isfield(experiment.summary.repetition_mean_data{1, 1}, ...
                'angular_phase_speed_m_per_s')
        error('OCE:Regression:ExperimentScanAxisSummary', ...
            'Experiment summary must preserve the maintained angular repetition summary.');
    end
    if ~isequal(experiment.summary.scan_axis.indices, 1)
        error('OCE:Regression:ExperimentScanAxisSummary', ...
            'Synthetic fixture must resolve one physical scan axis.');
    end
    if experiment.summary.scan_axis.pairing ~= ...
            "mean_left_right_within_same_repetition"
        error('OCE:Regression:ExperimentScanAxisSummary', ...
            'Scan-axis pairing provenance is incorrect.');
    end

    row2500 = select_row(T, "0", "2500", 1);
    if row2500.phase_speed_mean_mps ~= 7 || ...
            row2500.phase_speed_n ~= 2 || ...
            row2500.phase_speed_sem_mps ~= 1
        error('OCE:Regression:ExperimentScanAxisSummary', ...
            '2500-Hz paired repetition statistics are incorrect.');
    end

    row3500 = select_row(T, "0", "3500", 1);
    if row3500.phase_speed_mean_mps ~= 3 || ...
            row3500.phase_speed_n ~= 1 || ...
            ~isnan(row3500.phase_speed_sem_mps) || ...
            ~isnan(row3500.phase_speed_ci95_mps) || ...
            row3500.left_right_delta_mean_mps ~= -4
        error('OCE:Regression:ExperimentScanAxisSummary', ...
            ['n=1 uncertainty or within-repetition left/right pairing ' ...
             'is incorrect.']);
    end

    row4500 = select_row(T, "10", "4500", 1);
    if row4500.phase_speed_mean_mps ~= 6 || ...
            row4500.phase_speed_n ~= 2
        error('OCE:Regression:ExperimentScanAxisSummary', ...
            'Second sub-experiment was not mapped to strain_percent correctly.');
    end

    verify_aligned_dispersion_pairing();

    clear cleanup
    remove_fixture(fixture.rootDir);
end

function verify_aligned_dispersion_pairing()
    frequencyHz = [100; 200; 300];
    experiment = struct();
    experiment.design = struct( ...
        'dimension_values', {{{'0'}, {'1', '2'}}}, ...
        'repetition_key', "rep_id");
    experiment.data = cell(1, 2);

    experiment.data{1, 1} = make_dispersion_result( ...
        frequencyHz, [2; 4; 6], [4; 6; 8]);
    experiment.data{1, 2} = make_dispersion_result( ...
        frequencyHz, [4; 6; 8], [6; NaN; 10]);
    experiment.summary = struct( ...
        'frequency_alignment', struct('refFreq', frequencyHz));

    experiment = oce.results.summarizeScanAxes(experiment);
    scanAxis = experiment.summary.scan_axis;
    meanS = scanAxis.mean_data{1};
    semS = scanAxis.sem_data{1};
    nS = scanAxis.n_data{1};

    if ~isequal(scanAxis.dispersion_frequency_axis_hz, frequencyHz) || ...
            ~isequaln(meanS.dispersion_phase_speed_m_per_s, [4 5 8]) || ...
            ~isequaln(semS.dispersion_phase_speed_m_per_s, [1 NaN 1]) || ...
            ~isequal(nS.dispersion_phase_speed_m_per_s, [2 1 2])
        error('OCE:Regression:ExperimentScanAxisSummary', ...
            ['Aligned dispersion must pair left/right within each repetition ' ...
             'before repetition statistics are calculated.']);
    end
end

function result = make_dispersion_result(frequencyHz, leftCurve, rightCurve)
    result = struct( ...
        'direction_scan_axis_indices', [1; 1], ...
        'direction_names', ["left"; "right"], ...
        'direction_target_phase_speed_m_per_s', [NaN; NaN], ...
        'direction_phase_gradient_speed_m_per_s', [NaN; NaN], ...
        'direction_frequency_axes_hz', {{frequencyHz, frequencyHz}}, ...
        'direction_smoothed_phase_speed_m_per_s', ...
            {{leftCurve, rightCurve}});
end

function configure_subexperiment(fixture, subExperiment, strainPercent, copyResults)
    sourceSub = fixture.subExperiment;
    T = fixture.acquisitionTable;
    T.sub_experiment(:) = subExperiment;
    T.experiment_type(:) = "uniaxial_prestrain";
    T.excitation_type(:) = "quasi_harmonic";
    T.strain_percent = repmat(strainPercent, height(T), 1);

    paramsDir = fullfile(fixture.experimentRoot, 'Params', subExperiment);
    if ~isfolder(paramsDir)
        mkdir(paramsDir);
    end
    acquisition_table = T; %#ok<NASGU>
    save(fullfile(paramsDir, ...
        'AcquisitionParams_' + subExperiment + '.mat'), 'acquisition_table');

    if copyResults
        sourceResults = fullfile(fixture.experimentRoot, 'Results', sourceSub);
        targetResults = fullfile(fixture.experimentRoot, 'Results', subExperiment);
        copyfile(sourceResults, targetResults);
    end
end

function row = select_row(T, strainPercent, frequencyHz, scanAxisIndex)
    mask = string(T.strain_percent) == strainPercent & ...
        string(T.frequency_Hz) == frequencyHz & ...
        T.scan_axis_index == scanAxisIndex;
    if nnz(mask) ~= 1
        error('OCE:Regression:ExperimentScanAxisSummary', ...
            'Expected exactly one summary-table row for requested condition.');
    end
    row = T(mask, :);
end

function remove_fixture(rootDir)
    if isfolder(rootDir)
        rmdir(rootDir, 's');
    end
end
