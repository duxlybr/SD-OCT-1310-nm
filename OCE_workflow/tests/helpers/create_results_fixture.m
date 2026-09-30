function fixture = create_results_fixture(rootDir)
%CREATE_RESULTS_FIXTURE Build deterministic filesystem inputs for results tests.

    if nargin < 1 || strlength(string(rootDir)) == 0
        rootDir = tempname;
    end
    rootDir = string(rootDir);
    experimentRoot = fullfile(rootDir, 'experiment');
    subExperiment = "SyntheticResults";
    paramsDir = fullfile(experimentRoot, 'Params', subExperiment);
    resultsRoot = fullfile(experimentRoot, 'Results', subExperiment);
    mkdir(paramsDir);
    mkdir(resultsRoot);

    run_id = ["R002"; "R004"; "R006"; "R001"; "R005"; "R003"];
    filename = "acq_" + run_id + ".bin";
    frequency_Hz = [3500; 2500; 4500; 2500; 4500; 2500];
    rep_id = [1; 2; 2; 1; 1; 3];
    nRows = numel(run_id);

    experiment_id = repmat("synthetic_experiment", nRows, 1);
    sub_experiment = repmat(subExperiment, nRows, 1);
    sample_type = repmat("phantom", nRows, 1);
    experiment_type = repmat("synthetic_oce", nRows, 1);
    excitation_type = repmat("synthetic", nRows, 1);
    acquisition_mode = repmat("mb_mode", nRows, 1);
    scan_geometry = repmat("angular_bmodes", nRows, 1);
    oct_system_profile = repmat("swept_source_1300", nRows, 1);

    acquisition_table = table( ...
        experiment_id, sub_experiment, run_id, filename, sample_type, ...
        experiment_type, excitation_type, acquisition_mode, scan_geometry, ...
        oct_system_profile, frequency_Hz, rep_id);

    paramsFile = fullfile(paramsDir, ...
        'AcquisitionParams_' + subExperiment + '.mat');
    save(paramsFile, 'acquisition_table');

    for rowIndex = 1:height(acquisition_table)
        [~, acquisitionName, ~] = fileparts(acquisition_table.filename(rowIndex));
        runFolder = fullfile(resultsRoot, acquisitionName);
        mkdir(runFolder);
        result = make_result(rowIndex);
        save_result(fullfile(runFolder, 'PhaseSpeed.mat'), result);
    end

    duplicateRunID = "R007";
    duplicateFilename = "acq_" + duplicateRunID + ".bin";
    [~, duplicateName, ~] = fileparts(duplicateFilename);
    duplicateFolder = fullfile(resultsRoot, duplicateName);
    mkdir(duplicateFolder);
    save_result(fullfile(duplicateFolder, 'PhaseSpeed.mat'), make_result(7));

    missingRow = acquisition_table(1, :);
    missingRow.run_id = "R404";
    missingRow.filename = "missing_acquisition.bin";
    missingRow.frequency_Hz = 5500;
    missingRow.rep_id = 1;

    duplicateRow = acquisition_table(1, :);
    duplicateRow.run_id = duplicateRunID;
    duplicateRow.filename = duplicateFilename;
    duplicateRow.frequency_Hz = 2500;
    duplicateRow.rep_id = 1;

    fixture = struct();
    fixture.rootDir = rootDir;
    fixture.experimentRoot = string(experimentRoot);
    fixture.subExperiment = subExperiment;
    fixture.paramsFile = string(paramsFile);
    fixture.resultsRoot = string(resultsRoot);
    fixture.summaryRoot = string(fullfile(rootDir, 'summary_output'));
    fixture.outputFolder = string(fullfile( ...
        rootDir, 'summary_output', 'Summary Tables'));
    fixture.acquisitionTable = acquisition_table;
    fixture.missingTable = [acquisition_table; missingRow];
    fixture.duplicateTable = [acquisition_table; duplicateRow];
end

function result = make_result(seed)
    result = struct();
    switch seed
        case 1
            frequency = [100; 200; 300];
        case 2
            frequency = [150; 250];
        case 3
            frequency = [100; 300];
        otherwise
            frequency = [100; 200; 300];
    end
    frequencies = {frequency, frequency};
    result.direction_frequency_axes_hz = frequencies;
    result.direction_temporal_diagnostic_magnitude = cellfun( ...
        @(v) seed + (1:numel(v))', frequencies, 'UniformOutput', false);
    result.direction_smoothed_phase_speed_m_per_s = cellfun( ...
        @(v) seed * 10 + (1:numel(v))', frequencies, 'UniformOutput', false);
    result.angular_mean_thickness_mm = ([1; 3] + seed) * 1e-4;
    result.angular_phase_speed_m_per_s = [seed; seed + 4];
    if seed == 2
        result.angular_phase_speed_m_per_s(2) = NaN;
    end
    result.full_circle_angles_deg = [0; 90];
end

function save_result(pathValue, result)
    [folder, ~, ~] = fileparts(pathValue);
    oceResult = make_scientific_result( ...
        result.direction_frequency_axes_hz{1}, ...
        result.direction_temporal_diagnostic_magnitude, ...
        result.direction_smoothed_phase_speed_m_per_s, ...
        result.angular_phase_speed_m_per_s, ...
        result.angular_mean_thickness_mm, ...
        result.full_circle_angles_deg);
    oce.io.saveScientificResult(folder, oceResult);
end
