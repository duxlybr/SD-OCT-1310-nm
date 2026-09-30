function validation = validateAcquisitionFiles( ...
        experimentRoot, subExperiment, acquisition_table)
%VALIDATEACQUISITIONFILES Compare canonical log filenames with Data/*.bin.
% Matching is case-insensitive and nonrecursive by design.

    if nargin < 1 || isempty(experimentRoot)
        error('experimentRoot is required.');
    end
    if nargin < 2 || isempty(subExperiment)
        error('subExperiment is required.');
    end
    if nargin < 3 || isempty(acquisition_table)
        error('acquisition_table is required.');
    end

    experimentRoot = char(experimentRoot);
    subExperiment = char(subExperiment);

    if ~istable(acquisition_table)
        error('acquisition_table must be a MATLAB table.');
    end
    if ~ismember('filename', acquisition_table.Properties.VariableNames)
        error('Column "filename" was not found in acquisition_table.');
    end

    dataDir = fullfile(experimentRoot, 'Data', subExperiment);
    if ~exist(dataDir, 'dir')
        error('Data folder not found: %s', dataDir);
    end

    logFilenamesRaw = strtrim(string(acquisition_table.filename));
    emptyIdx = ismissing(logFilenamesRaw) | strlength(logFilenamesRaw) == 0;
    emptyFilenames = find(emptyIdx);
    logFilenames = logFilenamesRaw(~emptyIdx);

    dataFiles = dir(fullfile(dataDir, '*.bin'));
    dataFilenames = strtrim(string({dataFiles.name})');

    logCompare = lower(logFilenames);
    dataCompare = lower(dataFilenames);

    duplicateMask = false(size(logCompare));
    [uniqueLog, ~, groupIdx] = unique(logCompare, 'stable');
    counts = accumarray(groupIdx, 1);
    duplicatedKeys = uniqueLog(counts > 1);
    for index = 1:numel(duplicatedKeys)
        duplicateMask = duplicateMask | logCompare == duplicatedKeys(index);
    end
    duplicateInLog = logFilenames(duplicateMask);

    missingInData = logFilenames(~ismember(logCompare, dataCompare));
    notListedInLog = dataFilenames(~ismember(dataCompare, logCompare));

    validation = struct();
    validation.isValid = isempty(missingInData) && isempty(notListedInLog) && ...
        isempty(duplicateInLog) && isempty(emptyFilenames);
    validation.experimentRoot = experimentRoot;
    validation.subExperiment = subExperiment;
    validation.dataDir = dataDir;
    validation.filenameColumn = 'filename';
    validation.nLogFiles = numel(logFilenames);
    validation.nDataFiles = numel(dataFilenames);
    validation.missingInData = missingInData;
    validation.notListedInLog = notListedInLog;
    validation.duplicateInLog = duplicateInLog;
    validation.emptyFilenames = emptyFilenames;
    validation.logFilenames = logFilenames;
    validation.dataFilenames = dataFilenames;
end
