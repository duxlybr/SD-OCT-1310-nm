function [outputDirectory, acquisitionName] = resolveOutputDirectory(processingInputs)
%RESOLVEOUTPUTDIRECTORY Resolve the canonical per-acquisition results directory.
% [outputDirectory, acquisitionName] = resolveOutputDirectory(processingInputs)
% Outputs of one acquisition go to <resultsDir>/<acquisitionName>/, where
% acquisitionName is the .bin file name without extension. Savers use the
% same name as FilePrefix so every saved file names its acquisition.

    filename = string(processingInputs.acquisition_row.filename);
    [~, acquisitionName, ~] = fileparts(char(filename));
    outputDirectory = fullfile(processingInputs.resultsDir, acquisitionName);
end
