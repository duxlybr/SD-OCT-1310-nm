function experiment = summarizeScanAxes(experiment)
%SUMMARIZESCANAXES Pair left/right directions within each repetition.
%
% For every acquisition repetition and scan axis:
%
%   c_axis,r = (c_left,r + c_right,r) / 2
%
% The paired values are then summarized across repetitions using mean, sample
% standard deviation, SEM, and a two-sided Student-t 95% CI half-width. When
% dispersion frequencies have already been aligned, the same pairing and
% repetition statistics are applied independently at every frequency bin.
%
% This function consumes assembled directional identity and phase-speed results.
% It performs no persisted scientific-result I/O and does not recalculate any
% acquisition-processing stage.

    validate_input(experiment);

    nRep = numel(experiment.design.dimension_values{end});
    dataByCondition = reshape(experiment.data, [], nRep);
    nConditions = size(dataByCondition, 1);
    dispersionFrequencyHz = aligned_frequency_axis(experiment);

    repetitionCells = cell(nConditions, 1);
    meanCells = cell(nConditions, 1);
    stdCells = cell(nConditions, 1);
    semCells = cell(nConditions, 1);
    ci95Cells = cell(nConditions, 1);
    nCells = cell(nConditions, 1);
    referenceScanAxes = [];

    for conditionIndex = 1:nConditions
        repetitionRow = dataByCondition(conditionIndex, :);
        validRepIdx = find(~cellfun(@isempty, repetitionRow));
        if isempty(validRepIdx)
            continue;
        end

        phaseValues = [];
        gradientValues = [];
        deltaValues = [];
        dispersionValues = [];

        for repetitionIndex = 1:nRep
            item = repetitionRow{repetitionIndex};
            if isempty(item)
                continue;
            end

            [scanAxes, pairedSpeed, pairedGradientSpeed, leftRightDelta, ...
                pairedDispersion] = pair_result_scan_axes( ...
                    item, conditionIndex, repetitionIndex, dispersionFrequencyHz);

            if isempty(referenceScanAxes)
                referenceScanAxes = scanAxes;
            elseif ~isequal(referenceScanAxes, scanAxes)
                error(['Scan-axis identities are inconsistent across ' ...
                    'assembled summary data.']);
            end

            if isempty(phaseValues)
                phaseValues = NaN(numel(scanAxes), nRep);
                gradientValues = NaN(numel(scanAxes), nRep);
                deltaValues = NaN(numel(scanAxes), nRep);
                if ~isempty(dispersionFrequencyHz)
                    dispersionValues = NaN( ...
                        numel(scanAxes), numel(dispersionFrequencyHz), nRep);
                end
            end
            phaseValues(:, repetitionIndex) = pairedSpeed;
            gradientValues(:, repetitionIndex) = pairedGradientSpeed;
            deltaValues(:, repetitionIndex) = leftRightDelta;
            if ~isempty(dispersionValues)
                dispersionValues(:, :, repetitionIndex) = pairedDispersion;
            end
        end

        repetitionValue = struct( ...
            'phase_speed_m_per_s', phaseValues, ...
            'phase_gradient_speed_m_per_s', gradientValues, ...
            'left_right_delta_m_per_s', deltaValues);
        meanValue = summarize_mean(phaseValues, gradientValues, deltaValues);
        stdValue = summarize_std(phaseValues, gradientValues, deltaValues);
        [semValue, ci95Value, nValue] = summarize_uncertainty( ...
            phaseValues, gradientValues, deltaValues);

        if ~isempty(dispersionValues)
            [dispersionMean, dispersionStd, dispersionSem, ...
                dispersionCi95, dispersionN] = ...
                summarize_dispersion(dispersionValues);
            repetitionValue.dispersion_phase_speed_m_per_s = dispersionValues;
            meanValue.dispersion_phase_speed_m_per_s = dispersionMean;
            stdValue.dispersion_phase_speed_m_per_s = dispersionStd;
            semValue.dispersion_phase_speed_m_per_s = dispersionSem;
            ci95Value.dispersion_phase_speed_m_per_s = dispersionCi95;
            nValue.dispersion_phase_speed_m_per_s = dispersionN;
        end

        repetitionCells{conditionIndex} = repetitionValue;
        meanCells{conditionIndex} = meanValue;
        stdCells{conditionIndex} = stdValue;
        semCells{conditionIndex} = semValue;
        ci95Cells{conditionIndex} = ci95Value;
        nCells{conditionIndex} = nValue;
    end

    if isempty(referenceScanAxes)
        error('No assembled scientific results were available for scan-axis summary.');
    end

    conditionSize = cellfun(@numel, experiment.design.dimension_values(1:end-1));
    if isscalar(conditionSize)
        conditionSize = [conditionSize 1];
    end

    if ~isfield(experiment, 'summary') || isempty(experiment.summary)
        experiment.summary = struct();
    end
    experiment.summary.scan_axis = struct();
    experiment.summary.scan_axis.indices = referenceScanAxes;
    experiment.summary.scan_axis.pairing = ...
        "mean_left_right_within_same_repetition";
    experiment.summary.scan_axis.uncertainty_basis = ...
        "repeated_acquisitions_same_condition";
    if ~isempty(dispersionFrequencyHz)
        experiment.summary.scan_axis.dispersion_frequency_axis_hz = ...
            dispersionFrequencyHz;
    end
    experiment.summary.scan_axis.repetition_data = ...
        reshape(repetitionCells, conditionSize);
    experiment.summary.scan_axis.mean_data = reshape(meanCells, conditionSize);
    experiment.summary.scan_axis.std_data = reshape(stdCells, conditionSize);
    experiment.summary.scan_axis.sem_data = reshape(semCells, conditionSize);
    experiment.summary.scan_axis.ci95_data = reshape(ci95Cells, conditionSize);
    experiment.summary.scan_axis.n_data = reshape(nCells, conditionSize);
end

function validate_input(experiment)
    required = {'design', 'data'};
    if any(~isfield(experiment, required))
        error('experiment.design and experiment.data are required.');
    end
    if ~isfield(experiment.design, 'dimension_values') || ...
            ~isfield(experiment.design, 'repetition_key')
        error('Experiment design dimension metadata is incomplete.');
    end
end

function frequencyHz = aligned_frequency_axis(experiment)
    frequencyHz = [];
    if ~isfield(experiment, 'summary') || ...
            ~isfield(experiment.summary, 'frequency_alignment') || ...
            ~isfield(experiment.summary.frequency_alignment, 'refFreq')
        return;
    end
    frequencyHz = double(experiment.summary.frequency_alignment.refFreq(:));
    if isempty(frequencyHz) || any(~isfinite(frequencyHz))
        error('Aligned dispersion frequency axis is missing or invalid.');
    end
end

function [scanAxes, pairedSpeed, pairedGradientSpeed, leftRightDelta, ...
        pairedDispersion] = pair_result_scan_axes( ...
        item, conditionIndex, repetitionIndex, dispersionFrequencyHz)
    required = {'direction_scan_axis_indices', 'direction_names', ...
        'direction_target_phase_speed_m_per_s'};
    if any(~isfield(item, required))
        error(['experiment.data cell at condition %d repetition %d is missing ' ...
            'assembled directional summary fields.'], ...
            conditionIndex, repetitionIndex);
    end

    scanAxisIndex = double(item.direction_scan_axis_indices(:));
    directionName = string(item.direction_names(:));
    selectedSpeed = double(item.direction_target_phase_speed_m_per_s(:));
    gradientSpeed = NaN(size(selectedSpeed));
    if isfield(item, 'direction_phase_gradient_speed_m_per_s')
        gradientSpeed = double(item.direction_phase_gradient_speed_m_per_s(:));
    end
    if numel(directionName) ~= numel(scanAxisIndex) || ...
            numel(selectedSpeed) ~= numel(scanAxisIndex) || ...
            numel(gradientSpeed) ~= numel(scanAxisIndex)
        error(['Directional summary fields have inconsistent lengths at ' ...
            'condition %d repetition %d.'], conditionIndex, repetitionIndex);
    end

    if ~isempty(dispersionFrequencyHz)
        dispersionRequired = {'direction_frequency_axes_hz', ...
            'direction_smoothed_phase_speed_m_per_s'};
        if any(~isfield(item, dispersionRequired)) || ...
                ~iscell(item.direction_frequency_axes_hz) || ...
                ~iscell(item.direction_smoothed_phase_speed_m_per_s) || ...
                numel(item.direction_frequency_axes_hz) ~= numel(scanAxisIndex) || ...
                numel(item.direction_smoothed_phase_speed_m_per_s) ~= ...
                    numel(scanAxisIndex)
            error(['Aligned directional dispersion fields are inconsistent at ' ...
                'condition %d repetition %d.'], ...
                conditionIndex, repetitionIndex);
        end
    end

    scanAxes = unique(scanAxisIndex, 'sorted');
    pairedSpeed = NaN(numel(scanAxes), 1);
    pairedGradientSpeed = NaN(numel(scanAxes), 1);
    leftRightDelta = NaN(numel(scanAxes), 1);
    pairedDispersion = NaN(numel(scanAxes), numel(dispersionFrequencyHz));

    for index = 1:numel(scanAxes)
        scanAxis = scanAxes(index);
        left = find(scanAxisIndex == scanAxis & directionName == "left");
        right = find(scanAxisIndex == scanAxis & directionName == "right");
        if numel(left) ~= 1 || numel(right) ~= 1
            error(['Scan axis %d must contain exactly one left and one right ' ...
                'direction.'], scanAxis);
        end

        leftSpeed = selectedSpeed(left);
        rightSpeed = selectedSpeed(right);
        pairedSpeed(index) = (leftSpeed + rightSpeed) / 2;
        leftGradientSpeed = gradientSpeed(left);
        rightGradientSpeed = gradientSpeed(right);
        pairedGradientSpeed(index) = ...
            (leftGradientSpeed + rightGradientSpeed) / 2;
        leftRightDelta(index) = leftSpeed - rightSpeed;

        if ~isempty(dispersionFrequencyHz)
            leftCurve = aligned_curve(item, left, dispersionFrequencyHz, ...
                conditionIndex, repetitionIndex);
            rightCurve = aligned_curve(item, right, dispersionFrequencyHz, ...
                conditionIndex, repetitionIndex);
            pairedDispersion(index, :) = ((leftCurve + rightCurve) / 2)';
        end
    end
end

function speed = aligned_curve(item, directionIndex, frequencyHz, ...
        conditionIndex, repetitionIndex)
    currentFrequency = double( ...
        item.direction_frequency_axes_hz{directionIndex}(:));
    speed = double( ...
        item.direction_smoothed_phase_speed_m_per_s{directionIndex}(:));
    if ~isequal(currentFrequency, frequencyHz) || ...
            numel(speed) ~= numel(frequencyHz)
        error(['Aligned dispersion curve does not match the reference axis at ' ...
            'condition %d repetition %d.'], conditionIndex, repetitionIndex);
    end
end

function value = summarize_mean(phaseValues, gradientValues, deltaValues)
    value = struct( ...
        'phase_speed_m_per_s', mean(phaseValues, 2, 'omitnan'), ...
        'phase_gradient_speed_m_per_s', mean(gradientValues, 2, 'omitnan'), ...
        'left_right_delta_m_per_s', mean(deltaValues, 2, 'omitnan'));
end

function value = summarize_std(phaseValues, gradientValues, deltaValues)
    value = struct( ...
        'phase_speed_m_per_s', std(phaseValues, 0, 2, 'omitnan'), ...
        'phase_gradient_speed_m_per_s', std(gradientValues, 0, 2, 'omitnan'), ...
        'left_right_delta_m_per_s', std(deltaValues, 0, 2, 'omitnan'));
end

function [semValue, ci95Value, nValue] = summarize_uncertainty( ...
        phaseValues, gradientValues, deltaValues)
    [phaseSem, phaseCi95, phaseN] = uncertainty_for_matrix(phaseValues);
    [gradientSem, gradientCi95, gradientN] = ...
        uncertainty_for_matrix(gradientValues);
    [deltaSem, deltaCi95, deltaN] = uncertainty_for_matrix(deltaValues);

    semValue = struct( ...
        'phase_speed_m_per_s', phaseSem, ...
        'phase_gradient_speed_m_per_s', gradientSem, ...
        'left_right_delta_m_per_s', deltaSem);
    ci95Value = struct( ...
        'phase_speed_m_per_s', phaseCi95, ...
        'phase_gradient_speed_m_per_s', gradientCi95, ...
        'left_right_delta_m_per_s', deltaCi95);
    nValue = struct( ...
        'phase_speed_m_per_s', phaseN, ...
        'phase_gradient_speed_m_per_s', gradientN, ...
        'left_right_delta_m_per_s', deltaN);
end

function [meanValue, stdValue, semValue, ci95Value, nValid] = ...
        summarize_dispersion(values)
    meanValue = mean(values, 3, 'omitnan');
    stdValue = std(values, 0, 3, 'omitnan');
    nValid = sum(isfinite(values), 3);
    semValue = stdValue ./ sqrt(nValid);
    semValue(nValid < 2) = NaN;
    ci95Value = NaN(size(stdValue));
    validMask = nValid >= 2;
    if any(validMask(:))
        tValue = tinv(0.975, nValid(validMask) - 1);
        ci95Value(validMask) = tValue .* semValue(validMask);
    end
end

function [semValue, ci95Value, nValid] = uncertainty_for_matrix(values)
    stdValue = std(values, 0, 2, 'omitnan');
    nValid = sum(isfinite(values), 2);
    semValue = NaN(size(stdValue));
    ci95Value = NaN(size(stdValue));

    validMask = nValid >= 2;
    if any(validMask)
        semValue(validMask) = stdValue(validMask) ./ sqrt(nValid(validMask));
        tValue = tinv(0.975, nValid(validMask) - 1);
        ci95Value(validMask) = tValue .* semValue(validMask);
    end
end
