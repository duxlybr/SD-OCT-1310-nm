function artifacts = saveCompleteSpaceTime(phaseResult, filterResult, ...
        reconstructionResult, geometry, outputDirectory, varargin)
%SAVECOMPLETESPACETIME Render and persist the complete B-mode space-time.
% Name-value options other than FilePrefix go to plotCompleteSpaceTime.
% FilePrefix (default "") starts every file name, e.g. the acquisition
% name: <FilePrefix>_<name>.

    parser = inputParser;
    parser.KeepUnmatched = true;
    addParameter(parser, 'FilePrefix', "", @(value) ischar(value) || (isstring(value) && isscalar(value)));
    parse(parser, varargin{:});
    stem = "CompleteSpaceTime";
    if strlength(parser.Results.FilePrefix) > 0
        stem = string(parser.Results.FilePrefix) + "_" + stem;
    end

    if ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end
    rendererOptions = namedargs2cell(parser.Unmatched);
    fig = oce.plotting.plotCompleteSpaceTime(phaseResult, filterResult, ...
        reconstructionResult, geometry, rendererOptions{:});
    artifacts = [ ...
        string(fullfile(outputDirectory, stem + ".fig")); ...
        string(fullfile(outputDirectory, stem + ".png"))];
    drawnow;
    fig.SizeChangedFcn = [];
    savefig(fig, char(artifacts(1)));
    exportgraphics(fig, char(artifacts(2)), 'Resolution', 300);
end
