function experiment = summarizeAngles(experiment)
%SUMMARIZEANGLES Summarize repetition-averaged result data across angles.
%
% Statistical convention:
%   angle_mean_data - mean across angles after repetition averaging.
%   angle_std_data  - descriptive angular variability, not uncertainty.
%   angle_sem_data  - SEM of angle-averaged values across repetitions.
%   angle_ci95_data - 95% CI half-width of the angle-averaged mean across
%                     independent repetitions. NaN when nValid < 2.

    if ~isfield(experiment, 'summary') || ...
            ~isfield(experiment.summary, 'repetition') || ...
            ~isfield(experiment.summary, 'repetition_mean_data')
        error(['Repetition summary data not found. Run ' ...
            'oce.results.summarizeRepetitions first.']);
    end

    repetitionSummary = experiment.summary.repetition;
    requiredFieldGroups = { ...
        'fields_cell_vectors', 'fields_angle_vectors', 'fields_copy'};
    if any(~isfield(repetitionSummary, requiredFieldGroups))
        error('Repetition summary field ownership is incomplete.');
    end

    fieldsCellVectors = repetitionSummary.fields_cell_vectors;
    fieldsAngleVectors = repetitionSummary.fields_angle_vectors;
    fieldsCopy = repetitionSummary.fields_copy;
    meanData = experiment.summary.repetition_mean_data;

    experiment.summary.angle = struct();
    experiment.summary.angle.fields_cell_vectors = fieldsCellVectors;
    experiment.summary.angle.fields_angle_vectors = fieldsAngleVectors;
    experiment.summary.angle.fields_copy = fieldsCopy;

    summarySize = size(meanData);
    nCond = numel(meanData);
    meanFlat = meanData(:);

    angleMeanCells = cell(nCond, 1);
    angleStdCells = cell(nCond, 1);
    angleSemCells = cell(nCond, 1);
    angleCi95Cells = cell(nCond, 1);
    angleNCells = cell(nCond, 1);

    for conditionIndex = 1:nCond
        repetitionMean = meanFlat{conditionIndex};
        if isempty(repetitionMean)
            warning(['Empty repetition_mean_data cell found at condition %d. ' ...
                'Leaving angle summary cell empty.'], conditionIndex);
            continue;
        end

        angleMeanStruct = struct();
        angleStdStruct = struct();
        angleSemStruct = struct();
        angleCi95Struct = struct();
        angleNStruct = struct();
        repetitionData = get_condition_repetition_data( ...
            experiment, conditionIndex);

        %% Fields stored as cells of vectors
        for fieldIndex = 1:numel(fieldsCellVectors)
            field = fieldsCellVectors{fieldIndex};
            validate_field(repetitionMean, field, conditionIndex);

            nAngles = numel(repetitionMean.(field));
            vectorLength = numel(repetitionMean.(field){1});
            angleValues = NaN(nAngles, vectorLength);

            for angleIndex = 1:nAngles
                angleValues(angleIndex, :) = ...
                    repetitionMean.(field){angleIndex};
            end

            angleMeanStruct.(field) = mean(angleValues, 1, 'omitnan')';
            angleStdStruct.(field) = std(angleValues, 0, 1, 'omitnan')';

            repetitionMeans = build_angle_averaged_repetition_matrix( ...
                repetitionData, field, true, vectorLength);
            [semVector, ci95Vector, nVector] = ...
                compute_sem_ci95_from_repetitions(repetitionMeans);

            angleSemStruct.(field) = semVector(:);
            angleCi95Struct.(field) = ci95Vector(:);
            angleNStruct.(field) = nVector(:);
        end

        %% Fields stored as angle-indexed numeric vectors
        for fieldIndex = 1:numel(fieldsAngleVectors)
            field = fieldsAngleVectors{fieldIndex};
            validate_field(repetitionMean, field, conditionIndex);

            angleValues = repetitionMean.(field)(:);
            angleMeanStruct.(field) = mean(angleValues, 'omitnan');
            angleStdStruct.(field) = std(angleValues, 0, 'omitnan');

            repetitionMeans = build_angle_averaged_repetition_matrix( ...
                repetitionData, field, false, 1);
            [semValue, ci95Value, nValue] = ...
                compute_sem_ci95_from_repetitions(repetitionMeans);

            angleSemStruct.(field) = semValue;
            angleCi95Struct.(field) = ci95Value;
            angleNStruct.(field) = nValue;
        end

        %% Metadata fields copied without averaging
        for fieldIndex = 1:numel(fieldsCopy)
            field = fieldsCopy{fieldIndex};
            validate_field(repetitionMean, field, conditionIndex);

            angleMeanStruct.(field) = repetitionMean.(field);
            angleStdStruct.(field) = [];
            angleSemStruct.(field) = [];
            angleCi95Struct.(field) = [];
            angleNStruct.(field) = [];
        end

        angleMeanCells{conditionIndex} = angleMeanStruct;
        angleStdCells{conditionIndex} = angleStdStruct;
        angleSemCells{conditionIndex} = angleSemStruct;
        angleCi95Cells{conditionIndex} = angleCi95Struct;
        angleNCells{conditionIndex} = angleNStruct;
    end

    experiment.summary.angle_mean_data = reshape(angleMeanCells, summarySize);
    experiment.summary.angle_std_data = reshape(angleStdCells, summarySize);
    experiment.summary.angle_sem_data = reshape(angleSemCells, summarySize);
    experiment.summary.angle_ci95_data = reshape(angleCi95Cells, summarySize);
    experiment.summary.angle_n_data = reshape(angleNCells, summarySize);
end

function validate_field(result, field, conditionIndex)
    if ~isfield(result, field)
        error('Field "%s" is missing at condition %d.', field, conditionIndex);
    end
end

function repetitionData = get_condition_repetition_data(experiment, conditionIndex)
    data = experiment.data;
    dataSize = size(data);
    nRep = dataSize(end);
    dataByCondition = reshape(data, [], nRep);
    repetitionData = dataByCondition(conditionIndex, :);
end

function matrix = build_angle_averaged_repetition_matrix( ...
        repetitionData, field, isCellVectorField, vectorLength)
    nRep = numel(repetitionData);
    matrix = NaN(nRep, vectorLength);

    for repetitionIndex = 1:nRep
        result = repetitionData{repetitionIndex};
        if isempty(result) || ~isfield(result, field)
            continue;
        end

        if isCellVectorField
            nAngles = numel(result.(field));
            angleValues = NaN(nAngles, vectorLength);
            for angleIndex = 1:nAngles
                currentVector = result.(field){angleIndex}(:);
                nCopy = min(vectorLength, numel(currentVector));
                angleValues(angleIndex, 1:nCopy) = currentVector(1:nCopy);
            end
            matrix(repetitionIndex, :) = mean(angleValues, 1, 'omitnan');
        else
            values = result.(field)(:);
            matrix(repetitionIndex, 1) = mean(values, 'omitnan');
        end
    end
end

function [semValue, ci95Value, nValid] = ...
        compute_sem_ci95_from_repetitions(values)
    stdValue = std(values, 0, 1, 'omitnan');
    nValid = sum(~isnan(values), 1);
    semValue = stdValue ./ sqrt(nValid);
    ci95Value = NaN(size(stdValue));

    validMask = nValid >= 2;
    if any(validMask(:))
        tValue = NaN(size(stdValue));
        tValue(validMask) = tinv(0.975, nValid(validMask) - 1);
        ci95Value(validMask) = tValue(validMask) .* semValue(validMask);
    end
end
