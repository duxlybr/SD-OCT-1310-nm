function artifacts = savePhaseSpeedVsFrequencyAngleAveraged(experiment, rootdir)
%SAVEPHASESPEEDVSFREQUENCYANGLEAVERAGED Render and persist angle-averaged phase speed vs frequency.

    [figures, fileNames] = ...
        oce.plotting.summary.plotPhaseSpeedVsFrequencyAngleAveraged(experiment);
    artifacts = saveSummaryFigureSet(figures, fileNames, rootdir);
end
