function T = exportConditionSummaryTable(experiment, rootdir, varargin)
%EXPORTCONDITIONSUMMARYTABLE Export the canonical condition summary table.

    if nargin < 2 || strlength(string(rootdir)) == 0
        if isfield(experiment, 'metadata') && isfield(experiment.metadata, 'resultsRoot')
            rootdir = experiment.metadata.resultsRoot;
        else
            error('rootdir is required when experiment.metadata.resultsRoot is unavailable.');
        end
    end

    p = inputParser;
    addParameter(p, 'OutputFolder', "", @(x) ischar(x) || isstring(x));
    addParameter(p, 'BaseFileName', "results_summary_table", @(x) ischar(x) || isstring(x));
    addParameter(p, 'WriteCSV', true, @islogical);
    addParameter(p, 'WriteXLSX', true, @islogical);
    parse(p, varargin{:});

    outputFolder = string(p.Results.OutputFolder);
    if strlength(outputFolder) == 0
        outputFolder = fullfile(string(rootdir), "Summary Tables");
    end

    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    T = oce.results.buildConditionSummaryTable(experiment);
    baseFileName = string(p.Results.BaseFileName);

    if p.Results.WriteCSV
        csvPath = fullfile(outputFolder, baseFileName + ".csv");
        writetable(T, csvPath);
        fprintf('Saved summary CSV:\n%s\n', csvPath);
    end

    if p.Results.WriteXLSX
        xlsxPath = fullfile(outputFolder, baseFileName + ".xlsx");
        writetable(T, xlsxPath);
        fprintf('Saved summary XLSX:\n%s\n', xlsxPath);
    end
end
