function T = exportScanAxisSummaryTable(experiment, rootdir, varargin)
%EXPORTSCANAXISSUMMARYTABLE Export scan-axis statistics.

    if nargin < 2 || strlength(string(rootdir)) == 0
        error('rootdir is required for experiment-level summary export.');
    end

    parser = inputParser;
    addParameter(parser, 'OutputFolder', "", @(x) ischar(x) || isstring(x));
    addParameter(parser, 'BaseFileName', "experiment_scan_axis_summary", ...
        @(x) ischar(x) || isstring(x));
    addParameter(parser, 'WriteCSV', true, @islogical);
    addParameter(parser, 'WriteXLSX', true, @islogical);
    parse(parser, varargin{:});

    outputFolder = string(parser.Results.OutputFolder);
    if strlength(outputFolder) == 0
        outputFolder = fullfile(string(rootdir), "Summary Tables");
    end
    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    T = oce.results.buildScanAxisSummaryTable(experiment);
    baseFileName = string(parser.Results.BaseFileName);

    if parser.Results.WriteCSV
        csvPath = fullfile(outputFolder, baseFileName + ".csv");
        writetable(T, csvPath);
        fprintf('Saved experiment scan-axis summary CSV:\n%s\n', csvPath);
    end

    if parser.Results.WriteXLSX
        xlsxPath = fullfile(outputFolder, baseFileName + ".xlsx");
        writetable(T, xlsxPath);
        fprintf('Saved experiment scan-axis summary XLSX:\n%s\n', xlsxPath);
    end
end
