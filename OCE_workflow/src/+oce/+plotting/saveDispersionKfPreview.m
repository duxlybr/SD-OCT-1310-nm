function artifacts = saveDispersionKfPreview(analysis, scanAxisIndex, outputDir)
%SAVEDISPERSIONKFPREVIEW Save one preserved k-f magnitude/ridge diagnostic.

    if ~isfolder(outputDir)
        mkdir(outputDir);
    end
    angleDeg = analysis.scan_axis_angles_deg(scanAxisIndex);
    fig = oce.plotting.plotDispersionKfPreview(analysis, scanAxisIndex);
    artifacts = [string(fullfile(outputDir, sprintf( ...
        'DispersionKf_scanAxis%02d_%0.1fdeg.fig', ...
        scanAxisIndex, angleDeg))); ...
        string(fullfile(outputDir, sprintf( ...
        'DispersionKf_scanAxis%02d_%0.1fdeg.png', ...
        scanAxisIndex, angleDeg)))];
    saveas(fig, artifacts(1));
    saveas(fig, artifacts(2));
end
