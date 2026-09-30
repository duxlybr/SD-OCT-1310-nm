function artifacts = savePhaseSpeedVsFrequencyByAngle(experiment, rootdir)
%SAVEPHASESPEEDVSFREQUENCYBYANGLE Render and persist phase speed vs frequency by angle.

    [figures, fileNames] = ...
        oce.plotting.summary.plotPhaseSpeedVsFrequencyByAngle(experiment);
    artifacts = saveSummaryFigureSet(figures, fileNames, rootdir);
end
