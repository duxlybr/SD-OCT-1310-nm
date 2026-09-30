function outputPath = saveProcessingConfig(experimentRoot, subExperiment, processing_config, varargin)
%SAVEPROCESSINGCONFIG Save processing_config for a sub-experiment.
% Input: experiment identity and a processing_config contract.
% Output: the persisted MAT path.
% Side effect: writes ProcessingConfig_<subExperiment>.mat without changing
% its variable schema. The config package owns this persistence boundary;
% prepareProcessingInputs is the next consumer.
%
% Expected output:
%
%   <experiment>/Params/<sub-experiment>/ProcessingConfig_<sub-experiment>.mat
%
% Usage:
%
%   outputPath = oce.config.saveProcessingConfig( ...
%       experimentRoot, subExperiment, processing_config)
%   outputPath = oce.config.saveProcessingConfig(..., 'Overwrite', false)
%
% Saved MAT file contains:
%
%   processing_config

    if nargin < 1 || isempty(experimentRoot)
        error('experimentRoot is required.');
    end

    if nargin < 2 || isempty(subExperiment)
        error('subExperiment is required.');
    end

    if nargin < 3 || isempty(processing_config)
        error('processing_config is required.');
    end

    p = inputParser;
    addParameter(p, 'Overwrite', true, @islogical);
    parse(p, varargin{:});

    oce.config.validateProcessingConfig(processing_config);

    experimentRoot = char(experimentRoot);
    subExperiment = char(subExperiment);
    safeSubExperiment = matlab.lang.makeValidName(subExperiment);

    paramsDir = fullfile(experimentRoot, 'Params', subExperiment);
    if ~exist(paramsDir, 'dir')
        mkdir(paramsDir);
    end

    outputPath = fullfile(paramsDir, ['ProcessingConfig_' safeSubExperiment '.mat']);

    if exist(outputPath, 'file') && ~p.Results.Overwrite
        error(['Processing config file already exists:\n%s\n' ...
               'Use oce.config.saveProcessingConfig(..., ''Overwrite'', true) ' ...
               'to replace it.'], outputPath);
    end

    save(outputPath, 'processing_config');
    fprintf('Saved processing_config to:\n%s\n', outputPath);

end
