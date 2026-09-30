function test_results_summary_contract(context)
%TEST_RESULTS_SUMMARY_CONTRACT Exercise an unbalanced synthetic design.

    experiment = synthetic_experiment();
    experiment = oce.results.summarizeRepetitions(experiment);
    experiment = oce.results.summarizeAngles(experiment);
    T = oce.io.exportConditionSummaryTable(experiment, tempdir, ...
        "OutputFolder", tempdir, "WriteCSV", false, "WriteXLSX", false);

    if height(T) ~= 3
        error('OCE:Regression:SummaryContract', ...
            'Summary row count expected=3; actual=%d.', height(T));
    end
    requiredColumns = [ ...
        "condition_label"; "condition_file_label"; "frequency_Hz"; ...
        "phase_speed_mean_mps"; "phase_speed_angular_std_mps"; ...
        "phase_speed_sem_mps"; "phase_speed_ci95_mps"; ...
        "phase_speed_n"; "thickness_mean_um"; ...
        "thickness_angular_std_um"; "thickness_sem_um"; ...
        "thickness_ci95_um"; "thickness_n"];
    missingColumns = setdiff(requiredColumns, ...
        string(T.Properties.VariableNames));
    if ~isempty(missingColumns)
        error('OCE:Regression:SummaryContract', ...
            'Summary columns missing: %s.', strjoin(missingColumns, ', '));
    end

    expectedFrequency = ["2500"; "3500"; "4500"];
    if ~isequal(string(T.frequency_Hz), expectedFrequency)
        error('OCE:Regression:SummaryContract', ...
            'frequency_Hz expected=%s; actual=%s.', ...
            strjoin(expectedFrequency, ', '), strjoin(string(T.frequency_Hz), ', '));
    end
    if ~isequal(T.phase_speed_mean_mps, [3; 12; 23])
        error('OCE:Regression:SummaryContract', ...
            'phase_speed_mean_mps expected=[3;12;23]; actual=%s.', ...
            mat2str(T.phase_speed_mean_mps));
    end
    if ~isequal(T.phase_speed_n, [3; 1; 2])
        error('OCE:Regression:SummaryContract', ...
            'phase_speed_n expected=[3;1;2]; actual=%s.', ...
            mat2str(T.phase_speed_n));
    end
    repetitionSem = experiment.summary.repetition_sem_data{2};
    if ~all(isnan(repetitionSem.angular_phase_speed_m_per_s))
        error('OCE:Regression:SummaryContract', ...
            'Repetition SEM must be NaN when n=1.');
    end
    if ~isnan(T.phase_speed_ci95_mps(2))
        error('OCE:Regression:SummaryContract', ...
            'CI95 must be NaN when n=1; actual=%g.', T.phase_speed_ci95_mps(2));
    end
    if sum(cellfun(@isempty, experiment.data(:))) ~= 3
        error('OCE:Regression:SummaryContract', ...
            'Expected 3 empty repetition cells in the unbalanced grid.');
    end

    sampled = synthetic_experiment();
    sampled = oce.results.alignDispersionFrequencies(sampled);
    sampled = oce.results.summarizeRepetitions(sampled);
    sampled = oce.results.summarizeDispersionSamples(sampled, [100 180]);
    sampling = sampled.summary.dispersion_sampling;
    if ~isequal(sampling.selected_frequency_hz, [100; 200]) || ...
            ~isequal(sampling.frequency_error_hz, [0; 20])
        error('OCE:Regression:DispersionSamplingFrequency', ...
            'Dispersion sampling did not preserve nearest-bin provenance.');
    end
    firstMean = sampling.mean_data{1};
    firstN = sampling.n_data{1};
    if ~isequal(firstMean.phase_speed_m_per_s, [7 8; 9 10]) || ...
            ~isequal(firstN.phase_speed_m_per_s, 3 * ones(2, 2))
        error('OCE:Regression:DispersionSamplingStatistics', ...
            'Dispersion samples must reuse repetition statistics at selected bins.');
    end
end

function experiment = synthetic_experiment()
    experiment = struct();
    experiment.metadata = struct('resultsRoot', tempdir);
    experiment.design = struct();
    experiment.design.group_keys = "frequency_Hz";
    experiment.design.repetition_key = "rep_id";
    experiment.design.dimension_keys = ["frequency_Hz", "rep_id"];
    experiment.design.dimension_values = { ...
        {'2500', '3500', '4500'}, {'1', '2', '3'}};
    experiment.data = cell(3, 3);

    experiment.data{1,1} = make_result([1;3], 1);
    experiment.data{1,2} = make_result([2;4], 2);
    experiment.data{1,3} = make_result([3;5], 3);
    experiment.data{2,1} = make_result([10;14], 10);
    experiment.data{3,1} = make_result([20;24], 20);
    experiment.data{3,2} = make_result([22;26], 22);
end

function result = make_result(phaseSpeed, offset)
    result = struct();
    result.direction_frequency_axes_hz = {[100;200], [100;200]};
    result.direction_temporal_diagnostic_magnitude = ...
        {[1;2] + offset, [3;4] + offset};
    result.direction_smoothed_phase_speed_m_per_s = ...
        {[5;6] + offset, [7;8] + offset};
    result.angular_mean_thickness_mm = ([1;3] + offset) * 1e-4;
    result.angular_phase_speed_m_per_s = phaseSpeed;
    result.full_circle_angles_deg = [0;90];
end
