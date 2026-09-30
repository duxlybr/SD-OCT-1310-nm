function test_plotting_summary_contract(~)
%TEST_PLOTTING_SUMMARY_CONTRACT Validate summary rendering and persistence.

    fixture = create_plotting_fixture(tempname);
    oldVisibility = get(groot, 'defaultFigureVisible');
    cleanup = onCleanup(@() cleanup_test(fixture.rootDir, oldVisibility));
    set(groot, 'defaultFigureVisible', 'off');

    plotFunctions = { ...
        @oce.plotting.summary.plotPhaseSpeedPolarSummary, ...
        @oce.plotting.summary.plotThicknessPolarSummary, ...
        @oce.plotting.summary.plotRepetitionAveragedDispersionSummary, ...
        @oce.plotting.summary.plotAngleAveragedDispersionSummary, ...
        @oce.plotting.summary.plotPhaseSpeedVsFrequencyByAngle, ...
        @oce.plotting.summary.plotPhaseSpeedVsFrequencyAngleAveraged};
    saveFunctions = { ...
        @oce.plotting.summary.savePhaseSpeedPolarSummary, ...
        @oce.plotting.summary.saveThicknessPolarSummary, ...
        @oce.plotting.summary.saveRepetitionAveragedDispersionSummary, ...
        @oce.plotting.summary.saveAngleAveragedDispersionSummary, ...
        @oce.plotting.summary.savePhaseSpeedVsFrequencyByAngle, ...
        @oce.plotting.summary.savePhaseSpeedVsFrequencyAngleAveraged};

    figureDir = fullfile(fixture.summaryRoot, 'Summary Figures');
    for index = 1:numel(plotFunctions)
        before = findall(groot, 'Type', 'figure');
        [figures, fileNames] = plotFunctions{index}(fixture.experiment);
        created = setdiff(findall(groot, 'Type', 'figure'), before);
        if isempty(created) || isempty(figures) || ...
                numel(figures) ~= numel(fileNames)
            error('OCE:PlottingTest:MissingSummaryFigure', ...
                'Summary renderer %d did not return its figure set.', index);
        end
        if has_persisted_files(figureDir)
            error('OCE:PlottingTest:RendererPersistence', ...
                'A plot* summary renderer persisted output files.');
        end
        close(created);
    end

    scaleExperiment = make_scale_experiment(fixture.experiment);
    [polarFigures, ~] = ...
        oce.plotting.summary.plotPhaseSpeedPolarSummary(scaleExperiment);
    [angleFigures, ~] = ...
        oce.plotting.summary.plotPhaseSpeedVsFrequencyByAngle(scaleExperiment);
    [averageFigures, ~] = ...
        oce.plotting.summary.plotPhaseSpeedVsFrequencyAngleAveraged(scaleExperiment);
    byAngleTargetLimits = zeros(0, 2);
    for index = 1:numel(polarFigures)
        pax = findall(polarFigures(index), 'Type', 'polaraxes');
        byAngleTargetLimits(end + 1, :) = rlim(pax(1)); %#ok<AGROW>
    end
    byAngleTargetLimits(end + 1, :) = ...
        ylim(findall(angleFigures(1), 'Type', 'axes')); %#ok<AGROW>
    angleAverageTargetLimit = ...
        ylim(findall(averageFigures(1), 'Type', 'axes'));

    if any(abs(byAngleTargetLimits - byAngleTargetLimits(1, :)) > 1e-12, 'all') || ...
            any(abs(byAngleTargetLimits(:, 1)) > 1e-12) || ...
            byAngleTargetLimits(1, 2) >= 50
        error('OCE:PlottingTest:SharedTargetScale', ...
            ['By-angle target summaries must share one zero-based robust ' ...
             'phase-speed display scale.']);
    end
    if abs(angleAverageTargetLimit(1)) > 1e-12 || ...
            angleAverageTargetLimit(2) >= 50 || ...
            abs(angleAverageTargetLimit(2) - byAngleTargetLimits(1, 2)) < 1e-12
        error('OCE:PlottingTest:AngleAverageTargetScale', ...
            ['Angle-averaged target summaries must use their own zero-based ' ...
             'robust phase-speed display scale.']);
    end
    close([polarFigures; angleFigures; averageFigures]);

    [repetitionFigures, ~] = ...
        oce.plotting.summary.plotRepetitionAveragedDispersionSummary( ...
            scaleExperiment);
    [angleDispersionFigures, ~] = ...
        oce.plotting.summary.plotAngleAveragedDispersionSummary( ...
            scaleExperiment);
    dispersionFigures = [repetitionFigures; angleDispersionFigures];

    repetitionLimits = NaN(numel(repetitionFigures), 2);
    for index = 1:numel(repetitionFigures)
        ax = findall(repetitionFigures(index), 'Type', 'axes');
        yyaxis(ax(1), 'left');
        repetitionLimits(index, :) = ylim(ax(1));
    end
    if isempty(repetitionLimits) || ...
            any(abs(repetitionLimits - repetitionLimits(1, :)) > 1e-12, 'all') || ...
            any(abs(repetitionLimits(:, 1)) > 1e-12) || ...
            repetitionLimits(1, 2) >= 20
        error('OCE:PlottingTest:SharedDispersionScale', ...
            ['By-angle dispersion summaries must share one zero-based robust ' ...
             'in-passband speed scale.']);
    end

    angleDispersionLimits = NaN(numel(angleDispersionFigures), 2);
    for index = 1:numel(angleDispersionFigures)
        ax = findall(angleDispersionFigures(index), 'Type', 'axes');
        yyaxis(ax(1), 'left');
        angleDispersionLimits(index, :) = ylim(ax(1));
    end
    if isempty(angleDispersionLimits) || ...
            any(abs(angleDispersionLimits - angleDispersionLimits(1, :)) > 1e-12, 'all') || ...
            any(abs(angleDispersionLimits(:, 1)) > 1e-12) || ...
            angleDispersionLimits(1, 2) >= 20
        error('OCE:PlottingTest:AngleAverageDispersionScale', ...
            ['Angle-averaged dispersion summaries must share their own ' ...
             'zero-based robust in-passband speed scale.']);
    end
    for index = 1:numel(repetitionFigures)
        speedLine = findall(repetitionFigures(index), 'Type', 'line', ...
            'DisplayName', 'Speed mean');
        if isempty(speedLine) || numel(speedLine(1).XData) ~= 3
            error('OCE:PlottingTest:DispersionCurveExtent', ...
                ['The repetition dispersion speed curve must retain the full ' ...
                 'frequency axis; the passband is display-scale provenance only.']);
        end
    end
    for index = 1:numel(angleDispersionFigures)
        speedLine = findall(angleDispersionFigures(index), 'Type', 'line', ...
            'DisplayName', 'Angle-averaged speed');
        if isempty(speedLine) || numel(speedLine(1).XData) ~= 3
            error('OCE:PlottingTest:DispersionCurveExtent', ...
                ['The angle-averaged dispersion speed curve must retain the ' ...
                 'full frequency axis; the passband must not crop the curve.']);
        end
    end
    close(dispersionFigures);

    for index = 1:numel(saveFunctions)
        before = findall(groot, 'Type', 'figure');
        artifacts = saveFunctions{index}(fixture.experiment, fixture.summaryRoot);
        created = setdiff(findall(groot, 'Type', 'figure'), before);
        if isempty(artifacts) || any(~isfile(artifacts))
            error('OCE:PlottingTest:MissingSummaryFiles', ...
                'Summary save owner %d did not persist its artifacts.', index);
        end
        close(created);
    end

    scanAxisExperiment = make_scan_axis_summary_experiment();
    before = findall(groot, 'Type', 'figure');
    [figures, fileNames] = ...
        oce.plotting.summary.plotPhaseSpeedVsFrequencyByScanAxis( ...
            scanAxisExperiment);
    created = setdiff(findall(groot, 'Type', 'figure'), before);
    if numel(figures) ~= 2 || numel(fileNames) ~= 2 || numel(created) ~= 2
        error('OCE:PlottingTest:ScanAxisSummaryFigure', ...
            'Scan-axis renderer must return one figure per physical scan axis.');
    end
    scanAxisLimits = NaN(numel(figures), 2);
    for figureIndex = 1:numel(figures)
        ax = findall(figures(figureIndex), 'Type', 'axes');
        scanAxisLimits(figureIndex, :) = ylim(ax(1));
    end
    if any(abs(scanAxisLimits - scanAxisLimits(1, :)) > 1e-12, 'all') || ...
            any(abs(scanAxisLimits(:, 1)) > 1e-12)
        error('OCE:PlottingTest:ScanAxisSummaryScale', ...
            ['Scan-axis comparison figures must share one zero-based robust ' ...
             'phase-speed scale.']);
    end
    close(created);

    before = findall(groot, 'Type', 'figure');
    artifacts = oce.plotting.summary.savePhaseSpeedVsFrequencyByScanAxis( ...
        scanAxisExperiment, fixture.summaryRoot);
    created = setdiff(findall(groot, 'Type', 'figure'), before);
    if isempty(artifacts) || any(~isfile(artifacts))
        error('OCE:PlottingTest:ScanAxisSummaryFiles', ...
            'Scan-axis summary save owner did not persist its artifacts.');
    end
    close(created);

    overlayExperiment = make_angular_overlay_experiment();
    before = findall(groot, 'Type', 'figure');
    [figures, fileNames] = ...
        oce.plotting.summary.plotPhaseSpeedPolarSummary( ...
            overlayExperiment, 'OverlayDimension', 'strain_percent');
    created = setdiff(findall(groot, 'Type', 'figure'), before);
    if numel(figures) ~= 2 || numel(fileNames) ~= 2 || numel(created) ~= 2 || ...
            ~all(contains(fileNames, ["2500Hz"; "3500Hz"]))
        error('OCE:PlottingTest:PolarOverlayFigure', ...
            ['Polar overlay must return one figure per frequency with ' ...
             'strain_percent overlaid.']);
    end
    polarLimits = NaN(numel(figures), 2);
    for figureIndex = 1:numel(figures)
        pax = findall(figures(figureIndex), 'Type', 'polaraxes');
        polarLimits(figureIndex, :) = rlim(pax(1));
    end
    if any(abs(polarLimits - polarLimits(1, :)) > 1e-12, 'all') || ...
            any(abs(polarLimits(:, 1)) > 1e-12)
        error('OCE:PlottingTest:PolarOverlayScale', ...
            ['Polar overlay figures must share one zero-based robust radial ' ...
             'phase-speed scale.']);
    end
    if has_new_persisted_overlay(figureDir)
        error('OCE:PlottingTest:RendererPersistence', ...
            'Polar overlay plot* renderer persisted output files.');
    end
    close(created);

    before = findall(groot, 'Type', 'figure');
    artifacts = oce.plotting.summary.savePhaseSpeedPolarSummary( ...
        overlayExperiment, fixture.summaryRoot, ...
        'OverlayDimension', 'strain_percent');
    created = setdiff(findall(groot, 'Type', 'figure'), before);
    if numel(artifacts) ~= 4 || any(~isfile(artifacts))
        error('OCE:PlottingTest:PolarOverlayFiles', ...
            'Polar overlay save owner did not persist both frequency figures.');
    end
    close(created);

    pulseExperiment = make_pulse_summary_experiment(fixture.experiment);
    [pulseScanAxisFigures, ~] = ...
        oce.plotting.summary.plotPhaseSpeedVsFrequencyByScanAxis(pulseExperiment);
    if numel(pulseScanAxisFigures) ~= 1 || ...
            numel(findall(pulseScanAxisFigures(1), 'Type', 'line')) ~= 2
        error('OCE:PlottingTest:PulseScanAxisCurves', ...
            ['Pulse experiment summary must return one scan-axis figure with ' ...
             'one curve per group condition.']);
    end

    [pulsePolarFigures, pulsePolarNames] = ...
        oce.plotting.summary.plotPhaseSpeedPolarSummary( ...
            pulseExperiment, 'OverlayDimension', 'strain_percent');
    if numel(pulsePolarFigures) ~= 2 || ...
            ~all(contains(pulsePolarNames, ["1000Hz"; "1500Hz"]))
        error('OCE:PlottingTest:PulseSampledPolarFigures', ...
            'Pulse sampled polar summary must return one figure per sample frequency.');
    end
    for figureIndex = 1:numel(pulsePolarFigures)
        if numel(findall(pulsePolarFigures(figureIndex), 'Type', 'polaraxes')) ~= 1
            error('OCE:PlottingTest:PulseSampledPolarEstimator', ...
                'Pulse sampled polar summary must render k-f only.');
        end
    end
    close([pulseScanAxisFigures; pulsePolarFigures]);

    details = persisted_files(figureDir);
    if isempty(details) || any([details.bytes] <= 0)
        error('OCE:PlottingTest:MissingSummaryFiles', ...
            'Summary persistence produced missing or empty artifacts.');
    end

    beforeNames = sort(reshape(string({details.name}), [], 1));
    before = findall(groot, 'Type', 'figure');
    oce.plotting.summary.savePhaseSpeedPolarSummary( ...
        fixture.experiment, fixture.summaryRoot);
    created = setdiff(findall(groot, 'Type', 'figure'), before);
    close(created);
    afterDetails = persisted_files(figureDir);
    afterNames = sort(reshape(string({afterDetails.name}), [], 1));
    if ~isequal(beforeNames, afterNames)
        error('OCE:PlottingTest:OverwriteContract', ...
            'Repeating a summary save changed the artifact filename inventory.');
    end
    clear cleanup
end

function experiment = make_scale_experiment(experiment)
    experiment.data = cell(2, 1);
    for conditionIndex = 1:2
        experiment.data{conditionIndex, 1} = struct( ...
            'filter_effective_passband_hz', [900 1600]);

        meanS = experiment.summary.repetition_mean_data{conditionIndex, 1};
        ciS = experiment.summary.repetition_ci95_data{conditionIndex, 1};
        for angleIndex = 1:numel(meanS.direction_smoothed_phase_speed_m_per_s)
            curve = meanS.direction_smoothed_phase_speed_m_per_s{angleIndex};
            curve(1) = 40 + 5 * angleIndex + conditionIndex;
            meanS.direction_smoothed_phase_speed_m_per_s{angleIndex} = curve;
        end
        if conditionIndex == 2
            meanS.direction_smoothed_phase_speed_m_per_s{2}(2) = 120;
            ciS.direction_smoothed_phase_speed_m_per_s{2}(2) = 140;
            ciS.angular_phase_speed_m_per_s(end) = 150;
        end
        experiment.summary.repetition_mean_data{conditionIndex, 1} = meanS;
        experiment.summary.repetition_ci95_data{conditionIndex, 1} = ciS;

        angleMeanS = experiment.summary.angle_mean_data{conditionIndex, 1};
        angleCiS = experiment.summary.angle_ci95_data{conditionIndex, 1};
        angleMeanS.angular_phase_speed_m_per_s = 14 + conditionIndex;
        angleMeanS.direction_smoothed_phase_speed_m_per_s(1) = ...
            45 + conditionIndex;
        if conditionIndex == 2
            angleMeanS.direction_smoothed_phase_speed_m_per_s(2) = 100;
            angleCiS.direction_smoothed_phase_speed_m_per_s(2) = 140;
        end
        experiment.summary.angle_mean_data{conditionIndex, 1} = angleMeanS;
        experiment.summary.angle_ci95_data{conditionIndex, 1} = angleCiS;
    end
end

function experiment = make_scan_axis_summary_experiment()
    meanData = cell(2, 2);
    ci95Data = cell(2, 2);
    for strainIndex = 1:2
        for frequencyIndex = 1:2
            base = 4 + strainIndex + frequencyIndex;
            meanData{strainIndex, frequencyIndex} = struct( ...
                'phase_speed_m_per_s', [base; base + 2], ...
                'left_right_delta_m_per_s', [-0.2; 0.1]);
            ci95Data{strainIndex, frequencyIndex} = struct( ...
                'phase_speed_m_per_s', [0.25; 0.30], ...
                'left_right_delta_m_per_s', [0.1; 0.1]);
        end
    end

    experiment = struct();
    experiment.design = struct();
    experiment.design.group_keys = ["strain_percent", "frequency_Hz"];
    experiment.design.repetition_key = "rep_id";
    experiment.design.dimension_keys = ...
        ["strain_percent", "frequency_Hz", "rep_id"];
    experiment.design.dimension_values = { ...
        {'0', '10'}, {'2500', '3500'}, {'1', '2'}};
    experiment.design.dimension_units = ["percent", "Hz", ""];
    experiment.summary = struct();
    experiment.summary.scan_axis = struct( ...
        'indices', [1; 2], ...
        'mean_data', {meanData}, ...
        'ci95_data', {ci95Data});
end

function experiment = make_angular_overlay_experiment()
    anglesDeg = [0; 90; 180; 270];
    meanData = cell(2, 2);
    ci95Data = cell(2, 2);

    for strainIndex = 1:2
        for frequencyIndex = 1:2
            base = 4 + strainIndex + frequencyIndex;
            meanData{strainIndex, frequencyIndex} = struct( ...
                'full_circle_angles_deg', anglesDeg, ...
                'angular_phase_speed_m_per_s', ...
                    [base; base + 1; base + 0.5; base + 1.5]);
            ci95Data{strainIndex, frequencyIndex} = struct( ...
                'angular_phase_speed_m_per_s', 0.2 * ones(4, 1));
        end
    end

    experiment = struct();
    experiment.design = struct( ...
        'dimension_keys', ["strain_percent", "frequency_Hz", "rep_id"], ...
        'dimension_values', {{{'0', '10'}, {'2500', '3500'}, {'1', '2'}}}, ...
        'dimension_units', ["percent", "Hz", ""]);
    experiment.summary = struct( ...
        'repetition_mean_data', {meanData}, ...
        'repetition_ci95_data', {ci95Data});
end

function experiment = make_pulse_summary_experiment(experiment)
    experiment.design.group_keys = "strain_percent";
    experiment.design.dimension_keys = ["strain_percent", "rep_id"];
    experiment.design.dimension_values = {{'0', '10'}, {'1'}};
    experiment.design.dimension_units = ["percent", ""];

    meanData = experiment.summary.repetition_mean_data;
    ci95Data = experiment.summary.repetition_ci95_data;
    sampledMean = cell(size(meanData));
    sampledCi95 = cell(size(ci95Data));
    scanMean = cell(size(meanData));
    scanCi95 = cell(size(ci95Data));
    selectedIndex = [2; 3];
    frequencyHz = meanData{1}.direction_frequency_axes_hz{1};
    for conditionIndex = 1:numel(meanData)
        meanS = meanData{conditionIndex};
        ci95S = ci95Data{conditionIndex};
        meanValues = NaN(numel(meanS.full_circle_angles_deg), 2);
        ci95Values = NaN(size(meanValues));
        for angleIndex = 1:size(meanValues, 1)
            meanValues(angleIndex, :) = ...
                meanS.direction_smoothed_phase_speed_m_per_s{angleIndex}(selectedIndex)';
            ci95Values(angleIndex, :) = ...
                ci95S.direction_smoothed_phase_speed_m_per_s{angleIndex}(selectedIndex)';
        end
        sampledMean{conditionIndex} = struct( ...
            'full_circle_angles_deg', meanS.full_circle_angles_deg, ...
            'phase_speed_m_per_s', meanValues);
        sampledCi95{conditionIndex} = struct( ...
            'phase_speed_m_per_s', ci95Values);

        scanMean{conditionIndex} = struct( ...
            'dispersion_phase_speed_m_per_s', ...
            mean([meanS.direction_smoothed_phase_speed_m_per_s{1}(:)'; ...
                  meanS.direction_smoothed_phase_speed_m_per_s{2}(:)'], 1, 'omitnan'));
        scanCi95{conditionIndex} = struct( ...
            'dispersion_phase_speed_m_per_s', ...
            0.2 * ones(1, numel(frequencyHz)));
    end

    experiment.summary.dispersion_sampling = struct( ...
        'method', "nearest_aligned_bin", ...
        'requested_frequency_hz', [1000; 1500], ...
        'selected_frequency_hz', [1000; 1500], ...
        'frequency_error_hz', [0; 0], ...
        'selected_bin_index', selectedIndex, ...
        'mean_data', {sampledMean}, ...
        'ci95_data', {sampledCi95});
    experiment.summary.scan_axis = struct( ...
        'indices', 1, ...
        'dispersion_frequency_axis_hz', frequencyHz(:), ...
        'mean_data', {scanMean}, ...
        'ci95_data', {scanCi95});
end

function tf = has_persisted_files(folder)
    tf = ~isempty(persisted_files(folder));
end

function tf = has_new_persisted_overlay(folder)
    details = persisted_files(folder);
    if isempty(details)
        tf = false;
        return;
    end
    tf = any(contains(string({details.name}), '_By_strain_percent'));
end

function details = persisted_files(folder)
    if ~isfolder(folder)
        details = struct('name', {}, 'bytes', {}, 'isdir', {});
        return;
    end
    details = dir(folder);
    details = details(~[details.isdir]);
end

function cleanup_test(rootDir, oldVisibility)
    close all force;
    set(groot, 'defaultFigureVisible', oldVisibility);
    if isfolder(rootDir)
        rmdir(rootDir, 's');
    end
end
