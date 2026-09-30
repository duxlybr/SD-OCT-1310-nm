function fig = plotReconstructionPreview(reconstructionResult, displayLimitsDb)
%PLOTRECONSTRUCTIONPREVIEW Render the log OCT-amplitude preview without saving.

    logAmplitude = reconstructionResult.log_amplitude.values;
    lateralStorageIndex = reconstructionResult.axes.lateral.values;
    depthAxisMm = reconstructionResult.axes.depth.values;

    fig = figure('Name', 'Reconstruction preview');
    ax = axes(fig);
    imagesc(ax, lateralStorageIndex, depthAxisMm, logAmplitude);
    clim(ax, displayLimitsDb);
    colormap(ax, gray(256));
    ylabel(ax, 'Depth (mm)');
    xlabel(ax, 'Concatenated lateral sample');
    title(ax, 'Reconstruction preview (concatenated meridian storage)');
    axis(ax, [lateralStorageIndex(1) lateralStorageIndex(end) ...
        depthAxisMm(1) depthAxisMm(end)]);
    oce.plotting.applyPreviewStyle(fig, ax, 'FigureSize', [820 520]);
end
