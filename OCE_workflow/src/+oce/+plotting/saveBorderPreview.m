function artifacts = saveBorderPreview(reconstructionResult, borderResult, ...
        ~, displayLimitsDb, outputDir, varargin)
%SAVEBORDERPREVIEW Save the common border and intensity-mask previews.
% FilePrefix (default "") starts every file name, e.g. the acquisition
% name: <FilePrefix>_<name>.

    parser = inputParser;
    addParameter(parser, 'FilePrefix', "", @(value) ischar(value) || (isstring(value) && isscalar(value)));
    parse(parser, varargin{:});
    stems = ["BorderPreview_pixels"; "BorderMaskPreview"];
    if strlength(parser.Results.FilePrefix) > 0
        stems = string(parser.Results.FilePrefix) + "_" + stems;
    end

    artifacts = [ ...
        string(fullfile(outputDir, stems(1) + ".fig")); ...
        string(fullfile(outputDir, stems(1) + ".png")); ...
        string(fullfile(outputDir, stems(2) + ".fig")); ...
        string(fullfile(outputDir, stems(2) + ".png"))];
    borderFigure = figure('Name', 'Border preview');
    borderAxes = axes(borderFigure);
    maskFigure = figure('Name', 'Intensity mask preview');
    maskAxes = axes(maskFigure);
    oce.plotting.plotBorderPreview(borderAxes, maskAxes, ...
        reconstructionResult, borderResult, displayLimitsDb);
    oce.plotting.applyPreviewStyle(borderFigure, borderAxes, ...
        'FigureSize', [820 520]);
    oce.plotting.applyPreviewStyle(maskFigure, maskAxes, ...
        'FigureSize', [820 520]);
    saveas(borderFigure, artifacts(1));
    saveas(borderFigure, artifacts(2));
    saveas(maskFigure, artifacts(3));
    saveas(maskFigure, artifacts(4));
end
