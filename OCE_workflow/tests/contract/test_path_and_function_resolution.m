function test_path_and_function_resolution(context)
%TEST_PATH_AND_FUNCTION_RESOLUTION Verify canonical maintained resolution.

    expected = {
        'oce.pipeline.prepareAcquisitionRun', 'src/+oce/+pipeline/prepareAcquisitionRun.m';
        'oce.pipeline.runSingleAcquisition', 'src/+oce/+pipeline/runSingleAcquisition.m';
        'oce.pipeline.runBatchProcessing', 'src/+oce/+pipeline/runBatchProcessing.m';
        'oce.pipeline.runSubexperimentSummary', 'src/+oce/+pipeline/runSubexperimentSummary.m';
        'oce.pipeline.runExperimentSummary', 'src/+oce/+pipeline/runExperimentSummary.m';
        'oce.pipeline.processPreparedAcquisition', 'src/+oce/+pipeline/processPreparedAcquisition.m';
        'oce.dispersion.buildWindows', 'src/+oce/+dispersion/buildWindows.m'};

    for idx = 1:size(expected, 1)
        name = expected{idx, 1};
        locations = string(which(name, '-all'));
        locations = locations(strlength(locations) > 0);
        if numel(locations) ~= 1
            error('OCE:Regression:Resolution', ...
                'Expected exactly one resolution for %s; actual count=%d; values=%s.', ...
                name, numel(locations), strjoin(locations, ', '));
        end
        expectedPath = fullfile(context.repoRoot, expected{idx, 2});
        if ~strcmpi(normalize_path(locations(1)), normalize_path(expectedPath))
            error('OCE:Regression:Resolution', ...
                'Function %s expected at %s but resolved to %s.', ...
                name, expectedPath, locations(1));
        end
    end

    retired = ["prepare_acquisition_run", "run_full_processing_single", ...
        "run_batch_processing", "run_results_summary", ...
        "PP_MBmode_Phantom_test_v2", "oceproc.build_dispersion_windows", ...
        "oce.pipeline.runResultsSummary", ...
        "oce.pipeline.runExperimentMeridianSummary"];
    for idx = 1:numel(retired)
        if ~isempty(which(char(retired(idx)), '-all'))
            error('OCE:Regression:RetiredResolution', ...
                'Retired compatibility name still resolves: %s.', retired(idx));
        end
    end
end

function value = normalize_path(value)
    value = replace(string(value), ["/", "\"], filesep);
end
