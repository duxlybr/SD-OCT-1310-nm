function artifacts = saveStructuralEnface(enface, outputDirectory, varargin)
%SAVESTRUCTURALENFACE Render and persist the structural en-face map.
% artifacts = saveStructuralEnface(enface, outputDirectory, Name, Value)
% writes StructuralEnface.fig/.png (FileStem overrides the name) by reusing
% plotStructuralEnface; DisplayLimitsDb is forwarded to the renderer.

    parser = inputParser;
    addParameter(parser, 'FileStem', "StructuralEnface", ...
        @(value) (ischar(value) || (isstring(value) && isscalar(value))) && ...
        strlength(string(value)) > 0);
    addParameter(parser, 'DisplayLimitsDb', []);
    parse(parser, varargin{:});

    if ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end
    fig = oce.plotting.plotStructuralEnface(enface, ...
        'DisplayLimitsDb', parser.Results.DisplayLimitsDb);
    stem = string(parser.Results.FileStem);
    artifacts = [ ...
        string(fullfile(outputDirectory, stem + ".fig")); ...
        string(fullfile(outputDirectory, stem + ".png"))];
    saveas(fig, artifacts(1));
    saveas(fig, artifacts(2));
end
