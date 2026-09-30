function artifacts = saveThicknessPolarSummary(experiment, rootdir)
%SAVETHICKNESSPOLARSUMMARY Render and persist thickness polar summaries.

    [figures, fileNames] = ...
        oce.plotting.summary.plotThicknessPolarSummary(experiment);
    artifacts = saveSummaryFigureSet(figures, fileNames, rootdir);
end
