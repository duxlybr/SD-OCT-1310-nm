function T = buildConditionSummaryTable(experiment)
%BUILDCONDITIONSUMMARYTABLE Build one row per experimental condition.

    validate_experiment_summary(experiment);

    dimensionKeys = string(experiment.design.dimension_keys);
    dimensionValues = experiment.design.dimension_values;
    groupKeys = string(experiment.design.group_keys);
    nVars = numel(groupKeys);

    angleMeanData = experiment.summary.angle_mean_data;
    angleStdData  = experiment.summary.angle_std_data;
    angleSemData  = experiment.summary.angle_sem_data;
    angleCi95Data = experiment.summary.angle_ci95_data;
    angleNData    = experiment.summary.angle_n_data;

    summarySize = size(angleMeanData);
    nCond = numel(angleMeanData);

    rows = cell(nCond, 1);

    for pIdx = 1:nCond
        idxCellFull = cell(1, numel(summarySize));
        [idxCellFull{:}] = ind2sub(summarySize, pIdx);
        idxCell = idxCellFull(1:nVars);

        [conditionLabel, conditionFileLabel] = oce.results.formatConditionLabel( ...
            dimensionKeys, dimensionValues, idxCell, 1:nVars);

        meanS = angleMeanData{idxCell{:}};
        stdS  = angleStdData{idxCell{:}};
        semS  = angleSemData{idxCell{:}};
        ciS   = angleCi95Data{idxCell{:}};
        nS    = angleNData{idxCell{:}};

        row = struct();
        row.condition_label = string(conditionLabel);
        row.condition_file_label = string(conditionFileLabel);

        for d = 1:nVars
            key = char(groupKeys(d));
            safeKey = matlab.lang.makeValidName(key);
            row.(safeKey) = string(dimensionValues{d}{idxCell{d}});
        end

        % Maintained phase_speed_* columns remain the k-f estimator.
        row.phase_speed_mean_mps = get_scalar(meanS, 'angular_phase_speed_m_per_s', NaN);
        row.phase_speed_angular_std_mps = get_scalar(stdS, 'angular_phase_speed_m_per_s', NaN);
        row.phase_speed_sem_mps = get_scalar(semS, 'angular_phase_speed_m_per_s', NaN);
        row.phase_speed_ci95_mps = get_scalar(ciS, 'angular_phase_speed_m_per_s', NaN);
        row.phase_speed_n = get_scalar(nS, 'angular_phase_speed_m_per_s', NaN);

        row.phase_gradient_speed_mean_mps = ...
            get_scalar(meanS, 'angular_phase_gradient_speed_m_per_s', NaN);
        row.phase_gradient_speed_angular_std_mps = ...
            get_scalar(stdS, 'angular_phase_gradient_speed_m_per_s', NaN);
        row.phase_gradient_speed_sem_mps = ...
            get_scalar(semS, 'angular_phase_gradient_speed_m_per_s', NaN);
        row.phase_gradient_speed_ci95_mps = ...
            get_scalar(ciS, 'angular_phase_gradient_speed_m_per_s', NaN);
        row.phase_gradient_speed_n = ...
            get_scalar(nS, 'angular_phase_gradient_speed_m_per_s', NaN);

        row.thickness_mean_um = 1000 * get_scalar(meanS, 'angular_mean_thickness_mm', NaN);
        row.thickness_angular_std_um = 1000 * get_scalar(stdS, 'angular_mean_thickness_mm', NaN);
        row.thickness_sem_um = 1000 * get_scalar(semS, 'angular_mean_thickness_mm', NaN);
        row.thickness_ci95_um = 1000 * get_scalar(ciS, 'angular_mean_thickness_mm', NaN);
        row.thickness_n = get_scalar(nS, 'angular_mean_thickness_mm', NaN);

        rows{pIdx} = row;
    end

    T = struct2table(vertcat(rows{:}));

end

function validate_experiment_summary(experiment)
    requiredTop = {'design', 'summary'};
    for i = 1:numel(requiredTop)
        if ~isfield(experiment, requiredTop{i})
            error('experiment.%s is required.', requiredTop{i});
        end
    end

    requiredDesign = {'dimension_keys', 'dimension_values', 'group_keys'};
    for i = 1:numel(requiredDesign)
        if ~isfield(experiment.design, requiredDesign{i})
            error('experiment.design.%s is required.', requiredDesign{i});
        end
    end

    requiredSummary = { ...
        'angle_mean_data', ...
        'angle_std_data', ...
        'angle_sem_data', ...
        'angle_ci95_data', ...
        'angle_n_data'};

    for i = 1:numel(requiredSummary)
        if ~isfield(experiment.summary, requiredSummary{i})
            error('experiment.summary.%s is required. Run oce.results.summarizeAngles first.', requiredSummary{i});
        end
    end
end

function value = get_scalar(S, fieldName, defaultValue)
    value = defaultValue;

    if ~isstruct(S) || ~isfield(S, fieldName)
        return;
    end

    rawValue = S.(fieldName);

    if isempty(rawValue)
        return;
    end

    if isnumeric(rawValue) || islogical(rawValue)
        value = rawValue(1);
    else
        value = defaultValue;
    end
end
