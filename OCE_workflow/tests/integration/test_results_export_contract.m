function test_results_export_contract(~)
%TEST_RESULTS_EXPORT_CONTRACT Verify table, CSV, and executable XLSX output.

    temporaryRoot = tempname;
    fixture = create_results_fixture(temporaryRoot);
    cleanup = onCleanup(@() remove_temporary_root(temporaryRoot));

    experiment = oce.results.buildSubexperimentResultSet( ...
        fixture.experimentRoot, fixture.subExperiment, ...
        "frequency_Hz", "rep_id");
    experiment = oce.results.alignDispersionFrequencies(experiment);
    experiment = oce.results.summarizeRepetitions(experiment);
    experiment = oce.results.summarizeAngles(experiment);
    T = oce.io.exportConditionSummaryTable(experiment, fixture.summaryRoot);

    csvPath = fullfile(fixture.outputFolder, 'results_summary_table.csv');
    xlsxPath = fullfile(fixture.outputFolder, 'results_summary_table.xlsx');
    if ~isfile(csvPath) || ~isfile(xlsxPath)
        error('OCE:ResultsTest:ExportMissing', ...
            'Expected CSV and XLSX summary exports were not created.');
    end

    csvTable = readtable(csvPath, 'TextType', 'string');
    xlsxTable = readtable(xlsxPath, 'TextType', 'string');
    assert_export_matches(T, csvTable, 'CSV');
    assert_export_matches(T, xlsxTable, 'XLSX');

    sheets = string(sheetnames(xlsxPath));
    if isempty(sheets)
        error('OCE:ResultsTest:XLSX', ...
            'XLSX export does not contain a readable worksheet.');
    end
    clear cleanup
end

function assert_export_matches(expected, actual, formatName)
    if height(actual) ~= height(expected) || ...
            ~isequal(string(actual.Properties.VariableNames), ...
                string(expected.Properties.VariableNames))
        error('OCE:ResultsTest:ExportSchema', ...
            '%s export changed the summary-table schema.', formatName);
    end

    required = ["frequency_Hz", "phase_speed_mean_mps", "phase_speed_n"];
    if any(~ismember(required, string(actual.Properties.VariableNames)))
        error('OCE:ResultsTest:ExportSchema', ...
            '%s export is missing required summary columns.', formatName);
    end
    if ~isequal(string(actual.frequency_Hz), string(expected.frequency_Hz)) || ...
            ~isequaln(actual.phase_speed_mean_mps, expected.phase_speed_mean_mps) || ...
            ~isequaln(actual.phase_speed_n, expected.phase_speed_n)
        error('OCE:ResultsTest:ExportValues', ...
            '%s export changed maintained summary values.', formatName);
    end
end

function remove_temporary_root(pathValue)
    if isfolder(pathValue)
        rmdir(pathValue, 's');
    end
end
