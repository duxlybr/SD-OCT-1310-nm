function yLimit = resolveSummaryPhaseSpeedLimit(experiment, source, family)
%RESOLVESUMMARYPHASESPEEDLIMIT Resolve one shared display-only speed limit.
%
% source = "target" uses scalar target-frequency summaries.
% source = "dispersion" uses smoothed dispersion curves only inside each
% condition's persisted effective temporal-filter passband. The complete
% dispersion curve remains available to renderers; the passband is used only
% for display-scale resolution.
%
% family selects the summary population that may control the scale:
%   "by_angle"       - repetition-averaged directional/angular summaries
%   "angle_averaged" - angle-averaged summaries
%   "scan_axis"      - paired scan-axis summaries

    source = lower(strtrim(string(source)));
    family = lower(strtrim(string(family)));

    switch source
        case "target"
            [values, ci95] = collect_target_values(experiment, family);
        case "dispersion"
            [values, ci95] = collect_dispersion_values(experiment, family);
        otherwise
            error('OCE:Plotting:SummarySpeedLimitSource', ...
                'Unsupported summary phase-speed limit source: %s.', source);
    end

    yLimit = resolvePhaseSpeedYLimit(values, ci95);
end

function [values, ci95] = collect_target_values(experiment, family)
    values = zeros(0, 1);
    ci95 = zeros(0, 1);
    if ~isfield(experiment, 'summary') || isempty(experiment.summary)
        return;
    end

    summary = experiment.summary;
    switch family
        case "by_angle"
            if ~isfield(summary, 'repetition_mean_data')
                return;
            end
            ciData = get_cell_summary(summary, 'repetition_ci95_data', ...
                size(summary.repetition_mean_data));
            [values, ci95] = append_struct_field(values, ci95, ...
                summary.repetition_mean_data, ciData, ...
                'angular_phase_speed_m_per_s');

        case "angle_averaged"
            if ~isfield(summary, 'angle_mean_data')
                return;
            end
            ciData = get_cell_summary(summary, 'angle_ci95_data', ...
                size(summary.angle_mean_data));
            [values, ci95] = append_struct_field(values, ci95, ...
                summary.angle_mean_data, ciData, ...
                'angular_phase_speed_m_per_s');

        case "scan_axis"
            if ~isfield(summary, 'scan_axis') || ...
                    ~isstruct(summary.scan_axis) || ...
                    ~isfield(summary.scan_axis, 'mean_data')
                return;
            end
            ciData = get_cell_summary(summary.scan_axis, 'ci95_data', ...
                size(summary.scan_axis.mean_data));
            [values, ci95] = append_struct_field(values, ci95, ...
                summary.scan_axis.mean_data, ciData, ...
                'phase_speed_m_per_s');

        otherwise
            error('OCE:Plotting:SummarySpeedLimitFamily', ...
                'Unsupported target summary family: %s.', family);
    end
end

function [values, ci95] = collect_dispersion_values(experiment, family)
    values = zeros(0, 1);
    ci95 = zeros(0, 1);
    if ~isfield(experiment, 'summary') || isempty(experiment.summary)
        return;
    end

    switch family
        case "by_angle"
            meanField = 'repetition_mean_data';
            ciField = 'repetition_ci95_data';
        case "angle_averaged"
            meanField = 'angle_mean_data';
            ciField = 'angle_ci95_data';
        case "scan_axis"
            if ~isfield(experiment.summary, 'scan_axis') || ...
                    ~isstruct(experiment.summary.scan_axis) || ...
                    ~isfield(experiment.summary.scan_axis, ...
                        'dispersion_frequency_axis_hz') || ...
                    ~isfield(experiment.summary.scan_axis, 'mean_data')
                return;
            end
            scanAxis = experiment.summary.scan_axis;
            ciData = get_cell_summary( ...
                scanAxis, 'ci95_data', size(scanAxis.mean_data));
            [values, ci95] = append_scan_axis_dispersion_summary( ...
                values, ci95, experiment, scanAxis.mean_data, ciData, ...
                scanAxis.dispersion_frequency_axis_hz);
            return;
        otherwise
            error('OCE:Plotting:SummarySpeedLimitFamily', ...
                'Unsupported dispersion summary family: %s.', family);
    end

    if ~isfield(experiment.summary, meanField)
        return;
    end

    meanData = experiment.summary.(meanField);
    ciData = get_cell_summary(experiment.summary, ciField, size(meanData));
    [values, ci95] = append_dispersion_summary( ...
        values, ci95, experiment, meanData, ciData);
end

function [values, ci95] = append_struct_field( ...
        values, ci95, meanData, ciData, fieldName)
    meanFlat = meanData(:);
    ciFlat = ciData(:);
    for index = 1:numel(meanFlat)
        meanS = meanFlat{index};
        if isempty(meanS) || ~isstruct(meanS) || ~isfield(meanS, fieldName)
            continue;
        end
        currentValues = double(meanS.(fieldName)(:));
        currentCi = NaN(size(currentValues));
        if index <= numel(ciFlat)
            ciS = ciFlat{index};
            if ~isempty(ciS) && isstruct(ciS) && isfield(ciS, fieldName)
                rawCi = double(ciS.(fieldName)(:));
                nCopy = min(numel(currentCi), numel(rawCi));
                currentCi(1:nCopy) = rawCi(1:nCopy);
            end
        end
        values = [values; currentValues]; %#ok<AGROW>
        ci95 = [ci95; currentCi]; %#ok<AGROW>
    end
end

function [values, ci95] = append_dispersion_summary( ...
        values, ci95, experiment, meanData, ciData)
    if ~isfield(experiment, 'design') || ...
            ~isfield(experiment.design, 'dimension_keys')
        return;
    end
    nConditionDims = numel(experiment.design.dimension_keys) - 1;
    meanSize = size(meanData);

    for linearIndex = 1:numel(meanData)
        meanS = meanData{linearIndex};
        if isempty(meanS) || ~isstruct(meanS) || ...
                ~isfield(meanS, 'direction_frequency_axes_hz') || ...
                ~isfield(meanS, 'direction_smoothed_phase_speed_m_per_s')
            continue;
        end

        idxFull = cell(1, numel(meanSize));
        [idxFull{:}] = ind2sub(meanSize, linearIndex);
        idxCell = idxFull(1:nConditionDims);
        ciS = struct();
        if linearIndex <= numel(ciData) && ...
                ~isempty(ciData{linearIndex}) && isstruct(ciData{linearIndex})
            ciS = ciData{linearIndex};
        end

        freqField = meanS.direction_frequency_axes_hz;
        speedField = meanS.direction_smoothed_phase_speed_m_per_s;
        if iscell(freqField) || iscell(speedField)
            if ~iscell(freqField) || ~iscell(speedField)
                continue;
            end
            nCurves = min(numel(freqField), numel(speedField));
            for curveIndex = 1:nCurves
                currentCi = [];
                if isfield(ciS, 'direction_smoothed_phase_speed_m_per_s') && ...
                        iscell(ciS.direction_smoothed_phase_speed_m_per_s) && ...
                        numel(ciS.direction_smoothed_phase_speed_m_per_s) >= curveIndex
                    currentCi = ...
                        ciS.direction_smoothed_phase_speed_m_per_s{curveIndex};
                end
                [values, ci95] = append_dispersion_curve( ...
                    values, ci95, experiment, idxCell, ...
                    freqField{curveIndex}, speedField{curveIndex}, currentCi);
            end
        else
            currentCi = [];
            if isfield(ciS, 'direction_smoothed_phase_speed_m_per_s') && ...
                    ~iscell(ciS.direction_smoothed_phase_speed_m_per_s)
                currentCi = ciS.direction_smoothed_phase_speed_m_per_s;
            end
            [values, ci95] = append_dispersion_curve( ...
                values, ci95, experiment, idxCell, ...
                freqField, speedField, currentCi);
        end
    end
end

function [values, ci95] = append_scan_axis_dispersion_summary( ...
        values, ci95, experiment, meanData, ciData, frequencyHz)
    if ~isfield(experiment, 'design') || ...
            ~isfield(experiment.design, 'dimension_keys')
        return;
    end
    frequencyHz = double(frequencyHz(:));
    nConditionDims = numel(experiment.design.dimension_keys) - 1;
    meanSize = size(meanData);

    for linearIndex = 1:numel(meanData)
        meanS = meanData{linearIndex};
        if isempty(meanS) || ~isstruct(meanS) || ...
                ~isfield(meanS, 'dispersion_phase_speed_m_per_s')
            continue;
        end

        idxFull = cell(1, numel(meanSize));
        [idxFull{:}] = ind2sub(meanSize, linearIndex);
        idxCell = idxFull(1:nConditionDims);
        speedMatrix = double(meanS.dispersion_phase_speed_m_per_s);
        ciMatrix = NaN(size(speedMatrix));
        if linearIndex <= numel(ciData)
            ciS = ciData{linearIndex};
            if ~isempty(ciS) && isstruct(ciS) && ...
                    isfield(ciS, 'dispersion_phase_speed_m_per_s')
                rawCi = double(ciS.dispersion_phase_speed_m_per_s);
                if isequal(size(rawCi), size(speedMatrix))
                    ciMatrix = rawCi;
                end
            end
        end

        for scanAxisPosition = 1:size(speedMatrix, 1)
            [values, ci95] = append_dispersion_curve( ...
                values, ci95, experiment, idxCell, frequencyHz, ...
                speedMatrix(scanAxisPosition, :)', ...
                ciMatrix(scanAxisPosition, :)');
        end
    end
end

function [values, ci95] = append_dispersion_curve( ...
        values, ci95, experiment, idxCell, frequencyHz, speed, speedCi)
    frequencyHz = double(frequencyHz(:));
    speed = double(speed(:));
    speedCi = double(speedCi(:));
    n = min(numel(frequencyHz), numel(speed));
    if n == 0
        return;
    end
    frequencyHz = frequencyHz(1:n);
    speed = speed(1:n);
    currentCi = NaN(n, 1);
    nCi = min(n, numel(speedCi));
    if nCi > 0
        currentCi(1:nCi) = speedCi(1:nCi);
    end

    [passbandMask, ~] = resolveDispersionPassbandMask( ...
        experiment, idxCell, frequencyHz);
    valid = passbandMask & isfinite(speed) & speed > 0;
    if ~any(valid)
        return;
    end
    values = [values; speed(valid)]; %#ok<AGROW>
    ci95 = [ci95; currentCi(valid)]; %#ok<AGROW>
end

function data = get_cell_summary(container, fieldName, targetSize)
    if isfield(container, fieldName) && iscell(container.(fieldName))
        data = container.(fieldName);
    else
        data = cell(targetSize);
    end
end
