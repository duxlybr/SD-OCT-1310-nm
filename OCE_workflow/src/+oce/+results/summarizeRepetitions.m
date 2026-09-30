function experiment = summarizeRepetitions(experiment)
%SUMMARIZEREPETITIONS Summarize canonical result data across repetitions.
%
% The last dimension of experiment.data represents independent repetitions
% or runs of the same experimental condition. Empty repetition cells are
% ignored and represented by NaNs during averaging.
%
% Statistical convention:
%   mean  - mean across independent repetitions.
%   std   - standard deviation across independent repetitions.
%   sem   - standard error of the mean: std / sqrt(nValid).
%           sem is NaN when nValid < 2.
%   ci95  - 95% confidence interval half-width: t(0.975, nValid-1) * sem.
%           ci95 is NaN when nValid < 2.

    fieldsCellVectors = { ...
        'direction_frequency_axes_hz', ...
        'direction_temporal_diagnostic_magnitude', ...
        'direction_smoothed_phase_speed_m_per_s'};
    fieldsAngleVectors = { ...
        'angular_mean_thickness_mm', ...
        'angular_phase_speed_m_per_s'};
    if data_has_field(experiment.data, 'angular_phase_gradient_speed_m_per_s')
        fieldsAngleVectors{end + 1} = 'angular_phase_gradient_speed_m_per_s';
    end
    fieldsCopy = {'full_circle_angles_deg'};

    if ~isfield(experiment, 'summary') || isempty(experiment.summary)
        experiment.summary = struct();
    end

    experiment.summary.repetition = struct();
    experiment.summary.repetition.fields_cell_vectors = fieldsCellVectors;
    experiment.summary.repetition.fields_angle_vectors = fieldsAngleVectors;
    experiment.summary.repetition.fields_copy = fieldsCopy;

    data = experiment.data;
    dataSize = size(data);
    nRep = dataSize(end);
    nCond = numel(data) / nRep;
    experiment.summary.repetition.nRep = nRep;

    dataByCondition = reshape(data, [], nRep);
    meanCells = cell(nCond, 1);
    stdCells = cell(nCond, 1);
    semCells = cell(nCond, 1);
    ci95Cells = cell(nCond, 1);
    nCells = cell(nCond, 1);

    for conditionIndex = 1:nCond
        repetitionRow = dataByCondition(conditionIndex, :);
        validRepIdx = find(~cellfun(@isempty, repetitionRow));

        if isempty(validRepIdx)
            warning(['Condition %d has no valid repetitions. ' ...
                'Leaving summary cell empty.'], conditionIndex);
            continue;
        end

        firstResult = repetitionRow{validRepIdx(1)};
        meanStruct = struct();
        stdStruct = struct();
        semStruct = struct();
        ci95Struct = struct();
        nStruct = struct();

        %% Fields stored as cells of vectors
        for fieldIndex = 1:numel(fieldsCellVectors)
            field = fieldsCellVectors{fieldIndex};
            validate_field(firstResult, field, conditionIndex);

            nAngles = numel(firstResult.(field));
            vectorLength = numel(firstResult.(field){1});
            values = NaN(nAngles, vectorLength, nRep);

            for repetitionIndex = 1:nRep
                result = dataByCondition{conditionIndex, repetitionIndex};
                if isempty(result)
                    continue;
                end
                validate_field(result, field, conditionIndex);

                for angleIndex = 1:nAngles
                    currentVector = result.(field){angleIndex}(:);
                    nCopy = min(vectorLength, numel(currentVector));
                    values(angleIndex, 1:nCopy, repetitionIndex) = ...
                        currentVector(1:nCopy);
                end
            end

            meanMatrix = mean(values, 3, 'omitnan');
            stdMatrix = std(values, 0, 3, 'omitnan');
            nMatrix = sum(~isnan(values), 3);
            semMatrix = stdMatrix ./ sqrt(nMatrix);
            semMatrix(nMatrix < 2) = NaN;
            ci95Matrix = compute_ci95(stdMatrix, nMatrix);

            meanStruct.(field) = matrix_to_column_cells(meanMatrix);
            stdStruct.(field) = matrix_to_column_cells(stdMatrix);
            semStruct.(field) = matrix_to_column_cells(semMatrix);
            ci95Struct.(field) = matrix_to_column_cells(ci95Matrix);
            nStruct.(field) = matrix_to_column_cells(nMatrix);
        end

        %% Fields stored as angle-indexed numeric vectors
        for fieldIndex = 1:numel(fieldsAngleVectors)
            field = fieldsAngleVectors{fieldIndex};
            validate_field(firstResult, field, conditionIndex);

            nAngles = numel(firstResult.(field));
            values = NaN(nAngles, nRep);

            for repetitionIndex = 1:nRep
                result = dataByCondition{conditionIndex, repetitionIndex};
                if isempty(result)
                    continue;
                end
                validate_field(result, field, conditionIndex);
                currentValues = result.(field)(:);
                nCopy = min(nAngles, numel(currentValues));
                values(1:nCopy, repetitionIndex) = currentValues(1:nCopy);
            end

            meanVector = mean(values, 2, 'omitnan');
            stdVector = std(values, 0, 2, 'omitnan');
            nVector = sum(~isnan(values), 2);
            semVector = stdVector ./ sqrt(nVector);
            semVector(nVector < 2) = NaN;
            ci95Vector = compute_ci95(stdVector, nVector);

            meanStruct.(field) = meanVector;
            stdStruct.(field) = stdVector;
            semStruct.(field) = semVector;
            ci95Struct.(field) = ci95Vector;
            nStruct.(field) = nVector;
        end

        %% Non-averaged fields copied from the first valid repetition
        for fieldIndex = 1:numel(fieldsCopy)
            field = fieldsCopy{fieldIndex};
            validate_field(firstResult, field, conditionIndex);
            referenceValue = firstResult.(field);

            for repetitionIndex = validRepIdx(2:end)
                result = dataByCondition{conditionIndex, repetitionIndex};
                if ~isempty(result) && isfield(result, field) && ...
                        ~isequal(referenceValue, result.(field))
                    warning('Field "%s" changes across repetitions at condition %d.', ...
                        field, conditionIndex);
                end
            end

            meanStruct.(field) = referenceValue;
            stdStruct.(field) = [];
            semStruct.(field) = [];
            ci95Struct.(field) = [];
            nStruct.(field) = [];
        end

        meanCells{conditionIndex} = meanStruct;
        stdCells{conditionIndex} = stdStruct;
        semCells{conditionIndex} = semStruct;
        ci95Cells{conditionIndex} = ci95Struct;
        nCells{conditionIndex} = nStruct;
    end

    conditionSize = dataSize(1:end-1);
    if isscalar(conditionSize)
        conditionSize = [conditionSize 1];
    end

    experiment.summary.repetition_mean_data = reshape(meanCells, conditionSize);
    experiment.summary.repetition_std_data = reshape(stdCells, conditionSize);
    experiment.summary.repetition_sem_data = reshape(semCells, conditionSize);
    experiment.summary.repetition_ci95_data = reshape(ci95Cells, conditionSize);
    experiment.summary.repetition_n_data = reshape(nCells, conditionSize);
end

function tf = data_has_field(data, field)
    tf = false;
    for index = 1:numel(data)
        item = data{index};
        if ~isempty(item) && isstruct(item) && isfield(item, field)
            tf = true;
            return;
        end
    end
end

function validate_field(result, field, conditionIndex)
    if ~isfield(result, field)
        error('Field "%s" is missing at condition %d.', field, conditionIndex);
    end
end

function ci95 = compute_ci95(stdValue, nValid)
    ci95 = NaN(size(stdValue));
    validMask = nValid >= 2;
    if any(validMask(:))
        tValue = NaN(size(stdValue));
        tValue(validMask) = tinv(0.975, nValid(validMask) - 1);
        semValue = stdValue ./ sqrt(nValid);
        ci95(validMask) = tValue(validMask) .* semValue(validMask);
    end
end

function cellArray = matrix_to_column_cells(matrix)
    nRows = size(matrix, 1);
    cellArray = arrayfun(@(rowIndex) matrix(rowIndex, :)', ...
        1:nRows, 'UniformOutput', false);
end
