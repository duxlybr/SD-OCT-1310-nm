function artifacts = saveSpeedDispersionPreview(analysis, scanAxisIndex, ...
        outputDir, varargin)
%SAVESPEEDDISPERSIONPREVIEW Save one directional-pair dispersion preview.
% FilePrefix (default "") starts every file name, e.g. the acquisition
% name: <FilePrefix>_<name>.

    parser = inputParser;
    addParameter(parser, 'FilePrefix', "", @(value) ischar(value) || (isstring(value) && isscalar(value)));
    parse(parser, varargin{:});
    angleDeg = analysis.scan_axis_angles_deg(scanAxisIndex);
    stem = string(sprintf('SpeedDispersion_scanAxis%02d_%0.1fdeg', ...
        scanAxisIndex, angleDeg));
    if strlength(parser.Results.FilePrefix) > 0
        stem = string(parser.Results.FilePrefix) + "_" + stem;
    end
    figHandle = oce.plotting.plotSpeedDispersionPreview(analysis, scanAxisIndex);
    artifacts = [string(fullfile(outputDir, stem + ".fig")); ...
        string(fullfile(outputDir, stem + ".png"))];
    saveas(figHandle, artifacts(1));
    saveas(figHandle, artifacts(2));
end
