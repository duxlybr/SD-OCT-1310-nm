function artifacts = saveDispersionKfPreview(analysis, scanAxisIndex, ...
        outputDir, varargin)
%SAVEDISPERSIONKFPREVIEW Save one preserved k-f magnitude/ridge diagnostic.
% FilePrefix (default "") starts every file name, e.g. the acquisition
% name: <FilePrefix>_<name>.

    parser = inputParser;
    addParameter(parser, 'FilePrefix', "", @(value) ischar(value) || (isstring(value) && isscalar(value)));
    parse(parser, varargin{:});
    if ~isfolder(outputDir)
        mkdir(outputDir);
    end
    angleDeg = analysis.scan_axis_angles_deg(scanAxisIndex);
    stem = string(sprintf('DispersionKf_scanAxis%02d_%0.1fdeg', ...
        scanAxisIndex, angleDeg));
    if strlength(parser.Results.FilePrefix) > 0
        stem = string(parser.Results.FilePrefix) + "_" + stem;
    end
    fig = oce.plotting.plotDispersionKfPreview(analysis, scanAxisIndex);
    artifacts = [string(fullfile(outputDir, stem + ".fig")); ...
        string(fullfile(outputDir, stem + ".png"))];
    saveas(fig, artifacts(1));
    saveas(fig, artifacts(2));
end
