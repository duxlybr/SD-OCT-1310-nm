function artifacts = saveReconstructionPreview(reconstructionResult, ...
        displayLimitsDb, outputDir, varargin)
%SAVERECONSTRUCTIONPREVIEW Save the log OCT-amplitude preview.
% FilePrefix (default "") starts every file name, e.g. the acquisition
% name: <FilePrefix>_<name>.

    parser = inputParser;
    addParameter(parser, 'FilePrefix', "", @(value) ischar(value) || (isstring(value) && isscalar(value)));
    parse(parser, varargin{:});
    stem = "ReconstructionPreview";
    if strlength(parser.Results.FilePrefix) > 0
        stem = string(parser.Results.FilePrefix) + "_" + stem;
    end

    fig = oce.plotting.plotReconstructionPreview( ...
        reconstructionResult, displayLimitsDb);
    artifacts = [string(fullfile(outputDir, stem + ".fig")); ...
        string(fullfile(outputDir, stem + ".png"))];
    saveas(fig, artifacts(1));
    saveas(fig, artifacts(2));
end
