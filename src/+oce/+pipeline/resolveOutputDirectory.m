function outputDirectory = resolveOutputDirectory(processingInputs)
%RESOLVEOUTPUTDIRECTORY Resolve the canonical per-acquisition results directory.

    filename = string(processingInputs.acquisition_row.filename);
    [~, acquisitionName, ~] = fileparts(char(filename));
    outputDirectory = fullfile(processingInputs.resultsDir, acquisitionName);
end
