function runOutput = runSingleAcquisition(experimentRoot, subExperiment, ...
        acquisitionKey, varargin)
%RUNSINGLEACQUISITION Calculate, plot, and persist one acquisition explicitly.

    if nargin < 3 || isempty(acquisitionKey)
        error('OCE:Pipeline:MissingAcquisitionKey', ...
            'experimentRoot, subExperiment, and acquisitionKey are required.');
    end
    p = inputParser;
    addParameter(p, 'Key', 'run_id', @(x) ischar(x) || isstring(x));
    addParameter(p, 'RunOptions', struct(), ...
        @(x) isstruct(x) && isscalar(x));
    addParameter(p, 'OutputOptions', [], ...
        @(x) isempty(x) || (isstruct(x) && isscalar(x)));
    parse(p, varargin{:});

    if isempty(p.Results.OutputOptions)
        resolvedRun = oce.config.resolveRunOptions(p.Results.RunOptions);
    else
        resolvedRun = oce.config.resolveRunOptions( ...
            p.Results.RunOptions, p.Results.OutputOptions);
    end
    startedAt = string(datetime('now'));
    fprintf('\nSingle-acquisition OCE workflow\n');
    fprintf('-------------------------------\n');
    fprintf('Experiment root: %s\n', string(experimentRoot));
    fprintf('Sub-experiment: %s\n', string(subExperiment));
    fprintf('Acquisition key: %s\n', string(acquisitionKey));
    fprintf('Stop after: %s\n', resolvedRun.stop_after);

    % Selected-run preparation verifies the selected file. Whole-subexperiment
    % inventory auditing is an explicit diagnostic and must not repeat for
    % every acquisition when this entrypoint is used by batch processing.
    runContext = oce.pipeline.prepareAcquisitionRun( ...
        experimentRoot, subExperiment, acquisitionKey, ...
        'Key', p.Results.Key, 'ValidateFiles', false);

    if resolvedRun.parallel.enabled && ...
            any(resolvedRun.required_products == "phase_estimation")
        parallelState = oce.pipeline.prepareParallelExecution( ...
            resolvedRun.parallel);
        resolvedRun.parallel.active = parallelState.active;
        if parallelState.active
            if parallelState.started_pool
                action = "started";
            else
                action = "reused";
            end
            fprintf('Parallel execution: %s process pool (%d workers).\n', ...
                action, parallelState.worker_count);
        end
    end

    pipelineResult = oce.pipeline.processPreparedAcquisition( ...
        runContext.processing_inputs, runContext.config_for_run, resolvedRun);
    runContext.config_for_run = pipelineResult.config_for_run;
    resultDirectory = string(oce.pipeline.resolveOutputDirectory( ...
        runContext.processing_inputs));
    directoryCreated = false;
    generatedArtifacts = strings(0, 1);
    polarResults = struct();

    if resolvedRun.requires_output_directory
        if ~isfolder(resultDirectory)
            mkdir(resultDirectory);
            directoryCreated = true;
        end
        figuresBefore = findall(groot, 'Type', 'figure');
        cleanup = onCleanup(@() oce.plotting.closeGeneratedFigures( ...
            figuresBefore, resolvedRun.output_options.close_figures));
        [generatedArtifacts, polarResults] = generateRequestedOutputs( ...
            pipelineResult, runContext.processing_inputs, ...
            resultDirectory, resolvedRun, generatedArtifacts);
        if resolvedRun.persistence.scientific_result
            if ~pipelineResult.status.scientific_result_available
                error('OCE:Pipeline:PartialResultPersistence', ...
                    'A partial run cannot be persisted as PhaseSpeed.mat.');
            end
            resultPath = oce.io.saveScientificResult(resultDirectory, ...
                pipelineResult.outputs.scientific_result);
            generatedArtifacts(end + 1, 1) = string(resultPath);
            pipelineResult.status.persisted = true;
        end
        clear cleanup
    end

    pipelineResult.status.generated_artifacts = generatedArtifacts;
    pipelineResult = apply_return_policy(pipelineResult, ...
        resolvedRun.return_intermediate_products);
    runOutput = struct( ...
        'status', "completed", ...
        'started_at', startedAt, ...
        'completed_at', string(datetime('now')), ...
        'run_info', runContext, ...
        'pipeline_result', pipelineResult, ...
        'resolved_output', struct( ...
            'result_directory', resultDirectory, ...
            'directory_created', directoryCreated), ...
        'polar_results', polarResults);
    fprintf('Completed through: %s\n', ...
        pipelineResult.status.completed_through);
    if resolvedRun.requires_output_directory
        fprintf('Output folder:\n%s\n', resultDirectory);
    else
        fprintf('In-memory run completed without output directories.\n');
    end
end

function result = apply_return_policy(result, mode)
    if mode == "none"
        result.acquisition_state = struct();
        result.products = struct();
    end
end
