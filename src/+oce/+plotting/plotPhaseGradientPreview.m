function [fig, details] = plotPhaseGradientPreview(analysis, scanAxisIndex)
%PLOTPHASEGRADIENTPREVIEW Render preserved spatial phase and fit for left/right.
% Consumes analyzeWindows runtime diagnostics, not a persisted scientific result.
% Disabled estimation returns no figure. Invalid directions show their status
% and any available diagnostic vectors. No projection, unwrap or fit is computed.
% R squared describes the fit; it does not establish single-mode propagation.

    fig = gobjects(0);
    details = struct();
    if ~analysis.phase_gradient.enabled, return; end
    validateattributes(scanAxisIndex, {'numeric'}, ...
        {'scalar', 'integer', 'positive', '<=', analysis.scan_axis_count});
    indices = [2 * scanAxisIndex - 1, 2 * scanAxisIndex];
    directions = analysis.phase_gradient.directions(indices);

    fig = figure('Name', sprintf('Phase gradient - scan axis %02d', scanAxisIndex));
    layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(layout, sprintf('Spatial phase fit | scan axis %02d | f0 = %.4g Hz', ...
        scanAxisIndex, analysis.phase_gradient.target_frequency_hz));
    axesHandles = gobjects(2, 1);
    phaseLines = gobjects(2, 1);
    fitLines = gobjects(2, 1);
    for index = 1:2
        direction = directions(index);
        diagnostic = direction.diagnostic;
        ax = nexttile(layout, index);
        axesHandles(index) = ax;
        hold(ax, 'on');
        if ~isempty(diagnostic.unwrapped_phase_rad)
            phaseLines(index) = plot(ax, diagnostic.x_axis_mm, ...
                diagnostic.unwrapped_phase_rad, '.-', ...
                'DisplayName', 'Unwrapped phase', 'LineWidth', 1.2);
        end
        if ~isempty(diagnostic.fitted_phase_rad)
            fitLines(index) = plot(ax, diagnostic.x_axis_mm, ...
                diagnostic.fitted_phase_rad, '--', ...
                'DisplayName', 'Linear fit', 'LineWidth', 1.4);
        end
        if isgraphics(phaseLines(index)) || isgraphics(fitLines(index))
            legend(ax, 'show', 'Location', 'best');
        else
            text(ax, 0.5, 0.5, 'Spatial phase diagnostic unavailable', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center');
        end
        xlabel(ax, 'x (mm)');
        ylabel(ax, 'Spatial phase (rad)');
        grid(ax, 'on');
        title(ax, {sprintf('%s propagation | status: %s', ...
            analysis.directions(indices(index)).direction, direction.status); ...
            sprintf('c = %.3g m/s | R² = %.3f | RMSE = %.3g rad', ...
                direction.phase_speed_m_per_s, direction.r_squared, ...
                direction.phase_rmse_rad)}, 'Interpreter', 'none');
    end
    oce.plotting.applyPreviewStyle(fig, axesHandles, 'FigureSize', [1080 460]);
    details = struct('axes', axesHandles, ...
        'phase_lines', phaseLines, 'fit_lines', fitLines);
end
