function artifacts = savePhaseSpeedVsFrequencyByScanAxis(experiment, rootdir)
%SAVEPHASESPEEDVSFREQUENCYBYSCANAXIS Render and persist scan-axis summary figures.

    [figures, fileNames] = ...
        oce.plotting.summary.plotPhaseSpeedVsFrequencyByScanAxis(experiment);
    artifacts = saveSummaryFigureSet(figures, fileNames, rootdir);
end
