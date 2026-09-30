function batchOutput = process_acquisition_batch(experimentRoot, subExperiment, acquisitionKeys, varargin)
%PROCESS_ACQUISITION_BATCH Human-facing function for sequential acquisition processing.
% Example: process_acquisition_batch(root, "Ojopaciente_propagacion", ["R004" "R005"])

    initialize_repository();
    batchOutput = oce.pipeline.runBatchProcessing( ...
        experimentRoot, subExperiment, acquisitionKeys, varargin{:});
end
