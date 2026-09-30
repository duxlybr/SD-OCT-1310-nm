function artifacts = saveAngleAveragedDispersionSummary(experiment, rootdir)
%SAVEANGLEAVERAGEDDISPERSIONSUMMARY Render and persist angle-averaged dispersion summaries.

    [figures, fileNames] = ...
        oce.plotting.summary.plotAngleAveragedDispersionSummary(experiment);
    artifacts = saveSummaryFigureSet(figures, fileNames, rootdir);
end
