function artifacts = saveDispersionWindowContext(windowResult, filterResult, ...
        localLateralAxisMm, bmodeIndex, outputDirectory, varargin)
%SAVEDISPERSIONWINDOWCONTEXT Save one resolved space-time ROI context figure.
% Name-value options other than FilePrefix go to plotDispersionWindowContext.
% FilePrefix (default "") starts every file name, e.g. the acquisition
% name: <FilePrefix>_<name>.

    parser = inputParser;
    parser.KeepUnmatched = true;
    addParameter(parser, 'FilePrefix', "", @(value) ischar(value) || (isstring(value) && isscalar(value)));
    parse(parser, varargin{:});
    stem = string(sprintf('DispersionWindowContext_bmode%02d', bmodeIndex));
    if strlength(parser.Results.FilePrefix) > 0
        stem = string(parser.Results.FilePrefix) + "_" + stem;
    end

    if ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end
    rendererOptions = namedargs2cell(parser.Unmatched);
    fig = oce.plotting.plotDispersionWindowContext( ...
        windowResult, filterResult, localLateralAxisMm, bmodeIndex, ...
        rendererOptions{:});
    artifacts = [string(fullfile(outputDirectory, stem + ".fig")); ...
        string(fullfile(outputDirectory, stem + ".png"))];
    drawnow;
    fig.SizeChangedFcn = [];
    saveas(fig, artifacts(1));
    saveas(fig, artifacts(2));
end
