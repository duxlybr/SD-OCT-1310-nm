function [acquisition_parameters, acquisition_table, paramsInfo] = loadSubexperimentParameters( ...
        experimentRoot, subExperiment, varargin)
%LOADSUBEXPERIMENTPARAMETERS Load prepared parameters for one sub-experiment.

    if nargin < 1 || isempty(experimentRoot)
        error('experimentRoot is required.');
    end
    if nargin < 2 || isempty(subExperiment)
        error('subExperiment is required.');
    end

    p = inputParser;
    addParameter(p, 'ParamsFile', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'AcqFile', '', @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});

    experimentRoot = char(experimentRoot);
    subExperiment = char(subExperiment);
    paramsDir = fullfile(experimentRoot, 'Params', subExperiment);
    safeSubExperiment = matlab.lang.makeValidName(subExperiment);

    paramsFile = char(p.Results.ParamsFile);
    if isempty(paramsFile)
        paramsFile = fullfile(paramsDir, ['Params_' safeSubExperiment '.mat']);
    end
    if ~isfile(paramsFile)
        error(['OCE system params file not found:\n%s\n\n' ...
            'Generate it first with ' ...
            'oce.acquisition.prepareAcquisitionParameters().'], paramsFile);
    end

    variableInfo = whos('-file', paramsFile);
    fileVariables = string({variableInfo.name});
    if ~isequal(fileVariables, "acquisition_parameters")
        error('OCE:Acquisition:InvalidParameterSchema', ...
            ['Params file must contain only acquisition_parameters. ' ...
             'Found: %s. File: %s'], strjoin(fileVariables, ', '), paramsFile);
    end

    systemData = load(paramsFile, 'acquisition_parameters');
    acquisition_parameters = systemData.acquisition_parameters;
    oce.acquisition.validateAcquisitionParameters(acquisition_parameters);

    [acquisition_table, acqFile] = oce.io.loadAcquisitionTable( ...
        experimentRoot, subExperiment, 'AcqFile', p.Results.AcqFile);

    paramsInfo = struct( ...
        'experimentRoot', experimentRoot, ...
        'subExperiment', subExperiment, ...
        'paramsDir', paramsDir, ...
        'paramsFile', paramsFile, ...
        'acquisitionParamsFile', acqFile, ...
        'numAcquisitions', height(acquisition_table));
end
