function saveResultsSummary(summaryPath, experiment, T, includeTable)
%SAVERESULTSSUMMARY Persist summary.mat variables using an explicit path.

    if nargin < 4
        includeTable = true;
    end

    summaryPath = string(summaryPath);
    outputFolder = string(fileparts(summaryPath));
    if strlength(outputFolder) > 0 && ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    if includeTable
        save(summaryPath, 'experiment', 'T');
    else
        save(summaryPath, 'experiment');
    end
end
