function batchOutput = runBatchProcessing(experimentRoot, subExperiment, ...
        acquisitionKeys, varargin)
%RUNBATCHPROCESSING Process acquisitions through the canonical single run.

    if nargin < 3 || isempty(acquisitionKeys)
        error('OCE:Pipeline:MissingAcquisitionKey', ...
            'experimentRoot, subExperiment, and acquisitionKeys are required.');
    end
    p = inputParser;
    addParameter(p, 'Key', 'run_id', @(x) ischar(x) || isstring(x));
    addParameter(p, 'RunOptions', struct(), ...
        @(x) isstruct(x) && isscalar(x));
    addParameter(p, 'OutputOptions', [], ...
        @(x) isempty(x) || (isstruct(x) && isscalar(x)));
    addParameter(p, 'StopOnError', false, @islogical);
    addParameter(p, 'KeepFullOutput', false, @islogical);
    addParameter(p, 'DuplicateMode', 'error', ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'SingleRunFunction', ...
        @oce.pipeline.runSingleAcquisition, ...
        @(x) isa(x, 'function_handle'));
    parse(p, varargin{:});
    duplicateMode = lower(string(p.Results.DuplicateMode));
    if ~ismember(duplicateMode, ["error", "unique", "allow"])
        error('OCE:Pipeline:InvalidDuplicateMode', ...
            'DuplicateMode must be "error", "unique", or "allow".');
    end
    originalKeys = string(acquisitionKeys(:));
    [keys, duplicateKeys] = handle_duplicates(originalKeys, duplicateMode);
    nRuns = numel(keys);
    batchOutput = initialize_output(experimentRoot, subExperiment, ...
        p.Results.Key, originalKeys, keys, duplicateMode, duplicateKeys, ...
        p.Results.KeepFullOutput, nRuns);
    fprintf('\nBatch OCE workflow\n------------------\n');
    fprintf('Number of acquisitions: %d\n', nRuns);

    for index = 1:nRuns
        key = keys(index);
        item = empty_result();
        item.index = index;
        item.run_id = key;
        item.started_at = string(datetime('now'));
        try
            if isempty(p.Results.OutputOptions)
                runOutput = p.Results.SingleRunFunction( ...
                    experimentRoot, subExperiment, key, ...
                    'Key', p.Results.Key, ...
                    'RunOptions', p.Results.RunOptions);
            else
                runOutput = p.Results.SingleRunFunction( ...
                    experimentRoot, subExperiment, key, ...
                    'Key', p.Results.Key, ...
                    'RunOptions', p.Results.RunOptions, ...
                    'OutputOptions', p.Results.OutputOptions);
            end
            item = populate_success(item, runOutput);
            if p.Results.KeepFullOutput
                item.run_output = runOutput;
            end
            batchOutput.success_keys(end + 1, 1) = key;
        catch ME
            item.status = "failed";
            item.error_message = string(ME.message);
            item.error_identifier = string(ME.identifier);
            item.completed_at = string(datetime('now'));
            batchOutput.failed_keys(end + 1, 1) = key;
            warning('[%d/%d] Failed: %s\n%s', ...
                index, nRuns, key, ME.message);
            if p.Results.StopOnError
                batchOutput.results(index) = item;
                batchOutput.status = "stopped_on_error";
                batchOutput.completed_at = string(datetime('now'));
                batchOutput.summary = build_summary(batchOutput);
                rethrow(ME);
            end
        end
        batchOutput.results(index) = item;
    end
    batchOutput.status = "completed";
    batchOutput.completed_at = string(datetime('now'));
    batchOutput.summary = build_summary(batchOutput);
    fprintf('Batch completed: %d success, %d failure.\n', ...
        numel(batchOutput.success_keys), numel(batchOutput.failed_keys));
end

function item = populate_success(item, runOutput)
    result = runOutput.pipeline_result;
    item.status = "completed";
    item.completed_through = result.status.completed_through;
    item.generated_artifacts = result.status.generated_artifacts;
    item.scientific_result_path = artifact_with_name( ...
        result.status.generated_artifacts, "PhaseSpeed.mat");
    item.completed_at = string(datetime('now'));
    if result.status.scientific_result_available
        statistics = result.outputs.scientific_result.statistics;
        item.mean_phase_speed_m_per_s = ...
            statistics.phase_speed.mean_m_per_s;
        item.std_phase_speed_m_per_s = ...
            statistics.phase_speed.standard_deviation_m_per_s;
        item.mean_thickness_um = statistics.thickness.mean_um;
        item.std_thickness_um = ...
            statistics.thickness.standard_deviation_um;
    end
end

function pathValue = artifact_with_name(artifacts, fileName)
    pathValue = "";
    if isempty(artifacts)
        return;
    end
    [~, names, extensions] = arrayfun(@fileparts, artifacts, ...
        'UniformOutput', false);
    matches = string(names) + string(extensions) == fileName;
    if any(matches)
        pathValue = artifacts(find(matches, 1));
    end
end

function output = initialize_output(root, sub, keyType, original, keys, ...
        mode, duplicates, keep, count)
    output = struct( ...
        'status', "started", ...
        'started_at', string(datetime('now')), ...
        'experiment_root', string(root), ...
        'sub_experiment', string(sub), ...
        'key_type', string(keyType), ...
        'acquisition_keys_original', original, ...
        'acquisition_keys', keys, ...
        'duplicate_mode', mode, ...
        'duplicate_keys', duplicates, ...
        'keep_full_output', keep, ...
        'success_keys', strings(0, 1), ...
        'failed_keys', strings(0, 1), ...
        'results', repmat(empty_result(), count, 1));
end

function [keys, duplicates] = handle_duplicates(original, mode)
    [uniqueKeys, ~, groups] = unique(original, 'stable');
    counts = accumarray(groups, 1);
    duplicates = uniqueKeys(counts > 1);
    if isempty(duplicates)
        keys = original;
        return;
    end
    switch mode
        case "error"
            error('OCE:Pipeline:DuplicateAcquisitionKey', ...
                ['Duplicate acquisition keys detected. Remove duplicates or ' ...
                 'select DuplicateMode="unique" or "allow".']);
        case "unique"
            keys = unique(original, 'stable');
        case "allow"
            keys = original;
    end
end

function result = empty_result()
    result = struct( ...
        'index', [], ...
        'run_id', "", ...
        'status', "not_started", ...
        'completed_through', "", ...
        'scientific_result_path', "", ...
        'generated_artifacts', strings(0, 1), ...
        'mean_phase_speed_m_per_s', NaN, ...
        'std_phase_speed_m_per_s', NaN, ...
        'mean_thickness_um', NaN, ...
        'std_thickness_um', NaN, ...
        'error_message', "", ...
        'error_identifier', "", ...
        'started_at', "", ...
        'completed_at', "", ...
        'run_output', []);
end

function summary = build_summary(output)
    count = numel(output.results);
    run_id = strings(count, 1);
    completed_through = strings(count, 1);
    status = strings(count, 1);
    scientific_result_path = strings(count, 1);
    generated_artifacts = cell(count, 1);
    error_identifier = strings(count, 1);
    for index = 1:count
        item = output.results(index);
        run_id(index) = item.run_id;
        completed_through(index) = item.completed_through;
        status(index) = item.status;
        scientific_result_path(index) = item.scientific_result_path;
        generated_artifacts{index} = item.generated_artifacts;
        error_identifier(index) = item.error_identifier;
    end
    summary = table(run_id, completed_through, status, ...
        scientific_result_path, generated_artifacts, error_identifier);
end
