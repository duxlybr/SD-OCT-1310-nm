function test_results_summary_persistence_contract(~)
%TEST_RESULTS_SUMMARY_PERSISTENCE_CONTRACT Verify summary MAT persistence.

    temporaryRoot = tempname;
    fixture = create_results_fixture(temporaryRoot);
    cleanup = onCleanup(@() remove_temporary_root(temporaryRoot));

    [experiment, T] = oce.pipeline.runSubexperimentSummary( ...
        fixture.experimentRoot, fixture.subExperiment, ...
        'RootDir', fixture.summaryRoot, 'RunPlots', false, ...
        'RunFrequencyPlots', false, 'ExportTable', true, ...
        'SaveSummary', false);

    summaryPath = fullfile(fixture.summaryRoot, 'summary.mat');
    oce.io.saveResultsSummary(summaryPath, experiment, T, true);
    assert_mat_variables(summaryPath, ["T"; "experiment"]);
    persisted = load(summaryPath);
    if ~isequaln(persisted.experiment, experiment) || ~isequaln(persisted.T, T)
        error('OCE:ResultsTest:SummaryRoundTrip', ...
            'summary.mat did not preserve experiment and T exactly.');
    end

    noTablePath = fullfile(fixture.summaryRoot, 'summary_no_table.mat');
    oce.io.saveResultsSummary(noTablePath, experiment, T, false);
    assert_mat_variables(noTablePath, "experiment");
    persistedNoTable = load(noTablePath);
    if ~isequaln(persistedNoTable.experiment, experiment) || ...
            isfield(persistedNoTable, 'T')
        error('OCE:ResultsTest:SummaryWithoutTable', ...
            'Summary persistence without table changed its contract.');
    end
    clear cleanup
end

function assert_mat_variables(pathValue, expectedNames)
    details = whos('-file', pathValue);
    actualNames = string({details.name});
    actualNames = sort(actualNames(:));
    expectedNames = sort(expectedNames(:));
    if ~isequal(actualNames, expectedNames)
        error('OCE:ResultsTest:SummaryVariables', ...
            'Unexpected MAT variables in %s. Expected=%s; actual=%s.', ...
            pathValue, strjoin(expectedNames, ', '), ...
            strjoin(actualNames, ', '));
    end
end

function remove_temporary_root(pathValue)
    if isfolder(pathValue)
        rmdir(pathValue, 's');
    end
end
