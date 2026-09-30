function [acquisitionTable, acquisitionParamsFile] = loadAcquisitionTable( ...
        experimentRoot, subExperiment, varargin)
%LOADACQUISITIONTABLE Load one canonical persisted acquisition_table.

    if nargin < 1 || isempty(experimentRoot)
        error('experimentRoot is required.');
    end
    if nargin < 2 || isempty(subExperiment)
        error('subExperiment is required.');
    end

    p = inputParser;
    addParameter(p, 'AcqFile', '', @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});

    experimentRoot = char(experimentRoot);
    subExperiment = char(subExperiment);
    acquisitionParamsFile = char(p.Results.AcqFile);
    if isempty(acquisitionParamsFile)
        safeSubExperiment = matlab.lang.makeValidName(subExperiment);
        acquisitionParamsFile = fullfile(experimentRoot, 'Params', ...
            subExperiment, ['AcquisitionParams_' safeSubExperiment '.mat']);
    end
    if ~isfile(acquisitionParamsFile)
        error('OCE:IO:AcquisitionTableNotFound', ...
            'Acquisition params file not found:\n%s', acquisitionParamsFile);
    end

    variableInfo = whos('-file', acquisitionParamsFile);
    fileVariables = string({variableInfo.name});
    if ~isequal(fileVariables, "acquisition_table")
        error('OCE:IO:InvalidAcquisitionTable', ...
            ['Acquisition params file must contain only acquisition_table. ' ...
             'Found: %s. File: %s'], ...
            strjoin(fileVariables, ', '), acquisitionParamsFile);
    end

    data = load(acquisitionParamsFile, 'acquisition_table');
    acquisitionTable = validateAcquisitionTable( ...
        data.acquisition_table, "persisted acquisition_table");
    if any(acquisitionTable.sub_experiment ~= string(subExperiment))
        error('OCE:IO:AcquisitionTableSubexperimentMismatch', ...
            ['Persisted acquisition_table contains rows outside requested ' ...
             'sub_experiment "%s".'], subExperiment);
    end
end
