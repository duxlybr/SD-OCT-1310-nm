function artifacts = saveCompleteSpaceTime(phaseResult, filterResult, ...
        reconstructionResult, geometry, outputDirectory, varargin)
%SAVECOMPLETESPACETIME Render and persist the complete B-mode space-time.

    if ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end
    fig = oce.plotting.plotCompleteSpaceTime(phaseResult, filterResult, ...
        reconstructionResult, geometry, varargin{:});
    artifacts = [ ...
        string(fullfile(outputDirectory, 'CompleteSpaceTime.fig')); ...
        string(fullfile(outputDirectory, 'CompleteSpaceTime.png'))];
    drawnow;
    fig.SizeChangedFcn = [];
    savefig(fig, char(artifacts(1)));
    exportgraphics(fig, char(artifacts(2)), 'Resolution', 300);
end
