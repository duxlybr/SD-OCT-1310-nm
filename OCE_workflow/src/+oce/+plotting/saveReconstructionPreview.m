function artifacts = saveReconstructionPreview(reconstructionResult, ...
        displayLimitsDb, outputDir)
%SAVERECONSTRUCTIONPREVIEW Save the log OCT-amplitude preview.

    fig = oce.plotting.plotReconstructionPreview( ...
        reconstructionResult, displayLimitsDb);
    artifacts = [string(fullfile(outputDir, 'ReconstructionPreview.fig')); ...
        string(fullfile(outputDir, 'ReconstructionPreview.png'))];
    saveas(fig, artifacts(1));
    saveas(fig, artifacts(2));
end
