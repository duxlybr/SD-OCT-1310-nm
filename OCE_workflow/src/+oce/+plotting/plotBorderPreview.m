function graphics = plotBorderPreview(borderAxes, maskAxes, ...
        reconstructionResult, borderResult, displayLimitsDb)
%PLOTBORDERPREVIEW Render the common border and intensity-mask views.

    validate_axes(borderAxes, maskAxes);
    surfaceMode = resolve_surface_mode(borderResult);
    validate_border_result(borderResult, reconstructionResult);
    if ~isnumeric(displayLimitsDb) || ~isequal(size(displayLimitsDb), [1 2]) || ...
            any(~isfinite(displayLimitsDb)) || displayLimitsDb(1) >= displayLimitsDb(2)
        error('OCE:Plotting:InvalidDisplayLimits', ...
            'displayLimitsDb must be a finite increasing two-element row vector.');
    end

    logAmplitude = reconstructionResult.log_amplitude.values;
    lateralStorageIndex = reconstructionResult.axes.lateral.values;
    depthAxisMm = reconstructionResult.axes.depth.values;

    cla(borderAxes);
    graphics.borderImage = imagesc(borderAxes, lateralStorageIndex, depthAxisMm, ...
        logAmplitude);
    hold(borderAxes, 'on');
    graphics.anteriorLine = plot(borderAxes, ...
        borderResult.anteriorSurface(:, 1), borderResult.anteriorSurface(:, 2), ...
        'r-', 'LineWidth', 1.5, 'DisplayName', 'Anterior');
    graphics.posteriorLine = gobjects(0);
    if surfaceMode == "anterior_posterior"
        graphics.posteriorLine = plot(borderAxes, ...
            borderResult.posteriorSurface(:, 1), ...
            borderResult.posteriorSurface(:, 2), ...
            'c-', 'LineWidth', 1.5, 'DisplayName', 'Posterior');
    end
    hold(borderAxes, 'off');
    clim(borderAxes, displayLimitsDb);
    colormap(borderAxes, gray(256));
    axis(borderAxes, 'tight');
    xlabel(borderAxes, 'Concatenated lateral sample');
    ylabel(borderAxes, 'Depth (mm)');
    if surfaceMode == "anterior_only"
        title(borderAxes, 'Border preview - anterior only');
        legend(borderAxes, graphics.anteriorLine, ...
            'Location', 'southeast', 'FontSize', 9);
    else
        title(borderAxes, 'Border preview');
        legend(borderAxes, [graphics.anteriorLine graphics.posteriorLine], ...
            'Location', 'southeast', 'FontSize', 9);
    end

    cla(maskAxes);
    graphics.maskImage = imagesc(maskAxes, lateralStorageIndex, depthAxisMm, ...
        logAmplitude .* borderResult.intensityMask);
    clim(maskAxes, displayLimitsDb);
    colormap(maskAxes, gray(256));
    axis(maskAxes, 'tight');
    xlabel(maskAxes, 'Concatenated lateral sample');
    ylabel(maskAxes, 'Depth (mm)');
    title(maskAxes, 'Intensity mask preview');
    oce.plotting.applyPreviewStyle([], [borderAxes; maskAxes]);
end

function validate_axes(borderAxes, maskAxes)
    if ~isscalar(borderAxes) || ~isgraphics(borderAxes, 'axes') || ...
            ~isscalar(maskAxes) || ~isgraphics(maskAxes, 'axes')
        error('OCE:Plotting:InvalidAxes', ...
            'plotBorderPreview requires two valid scalar axes handles.');
    end
end

function mode = resolve_surface_mode(result)
    mode = "anterior_posterior";
    if isstruct(result) && isscalar(result) && isfield(result, 'surface_mode')
        mode = string(result.surface_mode);
    end
    if ~isscalar(mode) || ismissing(mode) || ...
            ~any(mode == ["anterior_posterior", "anterior_only"])
        error('OCE:Plotting:InvalidBorderResult', ...
            'borderResult.surface_mode is invalid.');
    end
end

function validate_border_result(result, reconstruction)
    required = ["indices"; "intensityMask"; "anteriorSurface"; ...
        "posteriorSurface"];
    lateralCount = size(reconstruction.log_amplitude.values, 2);
    if ~isstruct(result) || ~isscalar(result) || ...
            any(~isfield(result, required)) || ...
            ~isstruct(result.indices) || ...
            any(~isfield(result.indices, ["anterior"; "posterior"])) || ...
            numel(result.indices.anterior) ~= lateralCount || ...
            numel(result.indices.posterior) ~= lateralCount || ...
            ~isnumeric(result.anteriorSurface) || ...
            ~isequal(size(result.anteriorSurface), [lateralCount 2]) || ...
            ~isnumeric(result.posteriorSurface) || ...
            ~isequal(size(result.posteriorSurface), [lateralCount 2]) || ...
            ~islogical(result.intensityMask) || ...
            ~isequal(size(result.intensityMask), ...
                size(reconstruction.log_amplitude.values))
        error('OCE:Plotting:InvalidBorderResult', ...
            'borderResult does not satisfy the common preview contract.');
    end
end
