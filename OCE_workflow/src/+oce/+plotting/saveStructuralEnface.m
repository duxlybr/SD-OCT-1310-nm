function artifacts = saveStructuralEnface(enface, outputDirectory, varargin)
%SAVESTRUCTURALENFACE Render and persist the structural en-face map.
% artifacts = saveStructuralEnface(enface, outputDirectory, Name, Value)
% writes StructuralEnface.fig/.png by reusing plotStructuralEnface;
% DisplayLimitsDb is forwarded to the renderer.
% FilePrefix (default "") starts every file name, e.g. the acquisition
% name: <FilePrefix>_<name>.

    parser = inputParser;
    addParameter(parser, 'FilePrefix', "", @(value) ischar(value) || (isstring(value) && isscalar(value)));
    addParameter(parser, 'DisplayLimitsDb', []);
    parse(parser, varargin{:});
    stem = "StructuralEnface";
    if strlength(parser.Results.FilePrefix) > 0
        stem = string(parser.Results.FilePrefix) + "_" + stem;
    end

    if ~isfolder(outputDirectory)
        mkdir(outputDirectory);
    end
    fig = oce.plotting.plotStructuralEnface(enface, ...
        'DisplayLimitsDb', parser.Results.DisplayLimitsDb);
    artifacts = [ ...
        string(fullfile(outputDirectory, stem + ".fig")); ...
        string(fullfile(outputDirectory, stem + ".png"))];
    saveas(fig, artifacts(1));
    saveas(fig, artifacts(2));
end
