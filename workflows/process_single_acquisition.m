function runOutput = process_single_acquisition(experimentRoot, subExperiment, acquisitionKey, varargin)
%PROCESS_SINGLE_ACQUISITION Human-facing function for one complete acquisition.
% Example: process_single_acquisition(root, "Ojopaciente_propagacion", "R004")

    initialize_repository();
    runOutput = oce.pipeline.runSingleAcquisition( ...
        experimentRoot, subExperiment, acquisitionKey, varargin{:});
end
