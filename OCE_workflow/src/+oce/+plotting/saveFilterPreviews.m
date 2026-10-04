function artifacts = saveFilterPreviews(phaseResult, filterResult, ...
        reconstructionResult, geometry, outputDir, varargin)
%SAVEFILTERPREVIEWS Save temporal-filter diagnostics and filtered space-time.
% Saved filter previews default to all B-modes; callers may request the
% representative diagnostic layout explicitly.
% FilePrefix (default "") starts every file name, e.g. the acquisition
% name: <FilePrefix>_<name>.

    parser = inputParser;
    addParameter(parser, 'CLimMode', "robust");
    addParameter(parser, 'CLim', []);
    addParameter(parser, 'BmodeMode', "all");
    addParameter(parser, 'FilePrefix', "", @(value) ischar(value) || (isstring(value) && isscalar(value)));
    parse(parser, varargin{:});
    stems = ["TemporalFilterSpectrum"; "TemporalFilterTimeProfile"; ...
        "FilteredSpaceTime"];
    if strlength(parser.Results.FilePrefix) > 0
        stems = string(parser.Results.FilePrefix) + "_" + stems;
    end

    figures = oce.plotting.plotFilterPreviews( ...
        phaseResult, filterResult, reconstructionResult, geometry, ...
        'CLimMode', parser.Results.CLimMode, ...
        'CLim', parser.Results.CLim, ...
        'BmodeMode', parser.Results.BmodeMode);
    artifacts = reshape([fullfile(string(outputDir), stems + ".fig"), ...
        fullfile(string(outputDir), stems + ".png")].', [], 1);

    for figureIndex = 1:numel(figures)
        artifactIndex = 2 * figureIndex - 1;
        drawnow;
        figures(figureIndex).SizeChangedFcn = [];
        saveas(figures(figureIndex), artifacts(artifactIndex));
        saveas(figures(figureIndex), artifacts(artifactIndex + 1));
    end
end
