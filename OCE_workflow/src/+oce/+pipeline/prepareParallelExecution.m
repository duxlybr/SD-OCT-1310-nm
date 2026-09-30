function state = prepareParallelExecution(options)
%PREPAREPARALLELEXECUTION Ensure the requested process pool is available.
%
% Pool creation/reuse is an execution concern owned outside the scientific
% calculation domain. The pool is intentionally left open so later stages and
% subsequent batch acquisitions can reuse it.

    validate_options(options);
    state = struct( ...
        'active', false, ...
        'started_pool', false, ...
        'reused_pool', false, ...
        'worker_count', 0, ...
        'pool_type', "none");
    if ~options.enabled
        return;
    end
    if ~license('test', 'Distrib_Computing_Toolbox')
        warning('OCE:Pipeline:ParallelUnavailable', ...
            ['Parallel execution was requested, but Parallel Computing ' ...
             'Toolbox is unavailable. Continuing serially.']);
        return;
    end

    pool = gcp('nocreate');
    if ~isempty(pool)
        isThreadPool = contains(string(class(pool)), "ThreadPool");
        wrongWorkerCount = pool.NumWorkers ~= options.worker_count;
        if isThreadPool || wrongWorkerCount
            delete(pool);
            pool = [];
        end
    end

    if isempty(pool)
        pool = start_process_pool(options.worker_count);
        if isempty(pool)
            return;
        end
        state.started_pool = true;
    else
        state.reused_pool = true;
    end

    state.active = true;
    state.worker_count = pool.NumWorkers;
    state.pool_type = "processes";
end

function pool = start_process_pool(workerCount)
    pool = [];
    try
        pool = parpool("Processes", workerCount);
        return;
    catch primaryError
        try
            pool = parpool("local", workerCount);
            return;
        catch fallbackError
            warning('OCE:Pipeline:ParallelUnavailable', ...
                ['Failed to start a process-based parallel pool. ' ...
                 'Continuing serially. Primary error: %s. ' ...
                 'Fallback error: %s.'], ...
                primaryError.message, fallbackError.message);
        end
    end
end

function validate_options(options)
    required = ["enabled"; "worker_count"; "pool_type"; "active"];
    if ~isstruct(options) || ~isscalar(options) || ...
            any(~isfield(options, required)) || ...
            ~islogical(options.enabled) || ~isscalar(options.enabled) || ...
            ~isnumeric(options.worker_count) || ...
            ~isscalar(options.worker_count) || ...
            ~isfinite(options.worker_count) || options.worker_count < 1 || ...
            options.worker_count ~= round(options.worker_count) || ...
            string(options.pool_type) ~= "processes" || ...
            ~islogical(options.active) || ~isscalar(options.active)
        error('OCE:Pipeline:InvalidParallelOptions', ...
            'Resolved parallel execution options are invalid.');
    end
end
