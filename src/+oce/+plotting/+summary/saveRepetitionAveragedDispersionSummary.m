function artifacts = saveRepetitionAveragedDispersionSummary(experiment, rootdir)
%SAVEREPETITIONAVERAGEDDISPERSIONSUMMARY Render and persist repetition dispersion summaries.

    [figures, fileNames] = ...
        oce.plotting.summary.plotRepetitionAveragedDispersionSummary(experiment);
    artifacts = saveSummaryFigureSet(figures, fileNames, rootdir);
end
