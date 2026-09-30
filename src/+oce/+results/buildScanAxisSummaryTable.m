function T = buildScanAxisSummaryTable(experiment)
%BUILDSCANAXISSUMMARYTABLE Build one row per condition and scan axis.

    validate_summary(experiment);

    groupKeys = string(experiment.design.group_keys);
    dimensionValues = experiment.design.dimension_values;
    nGroupDims = numel(groupKeys);
    scanAxisSummary = experiment.summary.scan_axis;
    scanAxisIndices = scanAxisSummary.indices(:);

    meanData = scanAxisSummary.mean_data;
    stdData = scanAxisSummary.std_data;
    semData = scanAxisSummary.sem_data;
    ci95Data = scanAxisSummary.ci95_data;
    nData = scanAxisSummary.n_data;

    conditionSize = cellfun(@numel, dimensionValues(1:nGroupDims));
    if isscalar(conditionSize)
        conditionSize = [conditionSize 1];
    end
    nConditions = prod(conditionSize);
    rows = cell(nConditions * numel(scanAxisIndices), 1);
    rowCounter = 0;

    for conditionLinear = 1:nConditions
        conditionIndex = cell(1, nGroupDims);
        [conditionIndex{:}] = ind2sub(conditionSize, conditionLinear);

        meanS = meanData{conditionIndex{:}};
        stdS = stdData{conditionIndex{:}};
        semS = semData{conditionIndex{:}};
        ci95S = ci95Data{conditionIndex{:}};
        nS = nData{conditionIndex{:}};
        if isempty(meanS)
            continue;
        end

        for scanAxisPosition = 1:numel(scanAxisIndices)
            rowCounter = rowCounter + 1;
            row = struct();

            for dimensionIndex = 1:nGroupDims
                key = char(groupKeys(dimensionIndex));
                row.(matlab.lang.makeValidName(key)) = string( ...
                    dimensionValues{dimensionIndex}{conditionIndex{dimensionIndex}});
            end

            row.scan_axis_index = scanAxisIndices(scanAxisPosition);
            % Maintained phase_speed_* columns remain the k-f estimator.
            row.phase_speed_mean_mps = ...
                meanS.phase_speed_m_per_s(scanAxisPosition);
            row.phase_speed_repetition_std_mps = ...
                stdS.phase_speed_m_per_s(scanAxisPosition);
            row.phase_speed_sem_mps = ...
                semS.phase_speed_m_per_s(scanAxisPosition);
            row.phase_speed_ci95_mps = ...
                ci95S.phase_speed_m_per_s(scanAxisPosition);
            row.phase_speed_n = nS.phase_speed_m_per_s(scanAxisPosition);

            row.phase_gradient_speed_mean_mps = ...
                meanS.phase_gradient_speed_m_per_s(scanAxisPosition);
            row.phase_gradient_speed_repetition_std_mps = ...
                stdS.phase_gradient_speed_m_per_s(scanAxisPosition);
            row.phase_gradient_speed_sem_mps = ...
                semS.phase_gradient_speed_m_per_s(scanAxisPosition);
            row.phase_gradient_speed_ci95_mps = ...
                ci95S.phase_gradient_speed_m_per_s(scanAxisPosition);
            row.phase_gradient_speed_n = ...
                nS.phase_gradient_speed_m_per_s(scanAxisPosition);

            row.left_right_delta_mean_mps = ...
                meanS.left_right_delta_m_per_s(scanAxisPosition);
            row.left_right_delta_repetition_std_mps = ...
                stdS.left_right_delta_m_per_s(scanAxisPosition);
            row.left_right_delta_sem_mps = ...
                semS.left_right_delta_m_per_s(scanAxisPosition);
            row.left_right_delta_ci95_mps = ...
                ci95S.left_right_delta_m_per_s(scanAxisPosition);
            row.left_right_delta_n = ...
                nS.left_right_delta_m_per_s(scanAxisPosition);

            rows{rowCounter} = row;
        end
    end

    rows = rows(1:rowCounter);
    if isempty(rows)
        T = table();
    else
        T = struct2table(vertcat(rows{:}));
    end
end

function validate_summary(experiment)
    if ~isfield(experiment, 'design') || ...
            ~isfield(experiment.design, 'group_keys') || ...
            ~isfield(experiment.design, 'dimension_values')
        error('Experiment design metadata is incomplete.');
    end
    if ~isfield(experiment, 'summary') || ...
            ~isfield(experiment.summary, 'scan_axis')
        error(['Scan-axis summary not found. Run ' ...
            'oce.results.summarizeScanAxes first.']);
    end

    required = {'indices', 'mean_data', 'std_data', 'sem_data', ...
        'ci95_data', 'n_data'};
    if any(~isfield(experiment.summary.scan_axis, required))
        error('Scan-axis summary is incomplete.');
    end
end
