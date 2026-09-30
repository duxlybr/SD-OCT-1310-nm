function [figures, polarResults] = plotPolarPhaseResults(oceResult, varargin)
%PLOTPOLARPHASERESULTS Render phase-speed and thickness polar results.
% This renderer is display-only. File persistence belongs to
% oce.plotting.savePolarPhaseResults.

    p = inputParser;
    addParameter(p, 'UseTemplate', false, @islogical);
    addParameter(p, 'TemplateFile', "", ...
        @(x) ischar(x) || isstring(x));
    addParameter(p, 'CentralFrequencyHz', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x)));
    addParameter(p, 'ComparePhaseGradient', true, @islogical);
    parse(p, varargin{:});

    anglesDeg = oceResult.angular.full_circle_angles_deg(:);
    phaseSpeed = oceResult.angular.phase_speed_m_per_s(:);
    thicknessMm = oceResult.angular.mean_thickness_mm(:);
    gradientSpeed = phase_gradient_speed(oceResult);
    compareGradient = p.Results.ComparePhaseGradient && any(isfinite(gradientSpeed));

    centralFrequencyHz = p.Results.CentralFrequencyHz;
    if isempty(centralFrequencyHz)
        centralFrequencyHz = ...
            oceResult.dispersion.target_frequency.requested_hz;
    end

    thicknessStats = oceResult.statistics.thickness;
    phaseSpeedStats = oceResult.statistics.phase_speed;
    templateFile = string(p.Results.TemplateFile);

    thicknessFigure = create_polar_figure( ...
        p.Results.UseTemplate, templateFile, "Polar thickness");
    clf(thicknessFigure);
    if all(isnan(thicknessMm))
        ax = axes(thicknessFigure);
        axis(ax, 'off');
        text(ax, 0.5, 0.5, 'Thickness unavailable', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontSize', 14);
        title(ax, 'Thickness unavailable');
    else
        render_polar_with_box(thicknessFigure, anglesDeg, ...
            thicknessMm * 1e3, "Thickness (um)", ...
            sprintf('Mean %.2f um\nSTD %.3f um', ...
                thicknessStats.mean_um, ...
                thicknessStats.standard_deviation_um));
    end

    phaseFigure = create_polar_figure( ...
        p.Results.UseTemplate, templateFile, "Polar phase speed");
    clf(phaseFigure);
    if ~isfinite(centralFrequencyHz) || all(isnan(phaseSpeed))
        ax = axes(phaseFigure);
        axis(ax, 'off');
        text(ax, 0.5, 0.5, 'Phase speed unavailable', ...
            'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', 'FontSize', 14);
        title(ax, 'Target frequency unavailable');
    elseif compareGradient
        render_phase_speed_comparison(phaseFigure, anglesDeg, ...
            phaseSpeed, gradientSpeed, centralFrequencyHz);
    else
        render_polar_with_box(phaseFigure, anglesDeg, phaseSpeed, ...
            sprintf('Phase speed (m/s) @ %.0f Hz', centralFrequencyHz), ...
            sprintf('Mean %.2f m/s\nSTD %.3f m/s', ...
                phaseSpeedStats.mean_m_per_s, ...
                phaseSpeedStats.standard_deviation_m_per_s));
    end

    figures = [thicknessFigure; phaseFigure];
    polarResults = struct( ...
        'mean_thickness_um', thicknessStats.mean_um, ...
        'std_thickness_um', thicknessStats.standard_deviation_um, ...
        'range_thickness_um', thicknessStats.range_um, ...
        'mean_phase_speed_m_per_s', phaseSpeedStats.mean_m_per_s, ...
        'std_phase_speed_m_per_s', ...
            phaseSpeedStats.standard_deviation_m_per_s, ...
        'range_phase_speed_m_per_s', phaseSpeedStats.range_m_per_s, ...
        'central_frequency_hz', centralFrequencyHz);
end

function values = phase_gradient_speed(oceResult)
    values = NaN(size(oceResult.angular.full_circle_angles_deg(:)));
    gradient = oceResult.dispersion.estimators.phase_gradient;
    if ~gradient.enabled || isempty(gradient.directions)
        return;
    end
    sourceIndices = double(oceResult.angular.source_direction_indices(:));
    directionValues = arrayfun( ...
        @(item) double(item.phase_speed_m_per_s), gradient.directions(:));
    if numel(sourceIndices) == numel(values) && ...
            all(sourceIndices >= 1 & sourceIndices <= numel(directionValues))
        values = directionValues(sourceIndices);
    end
end

function render_phase_speed_comparison(fig, anglesDeg, kfValues, ...
        gradientValues, frequencyHz)
    figure(fig);
    fig.Color = 'w';
    fig.GraphicsSmoothing = 'on';
    fig.Position(3:4) = [960 520];

    polarAx = polaraxes('Parent', fig, ...
        'Position', [0.06 0.08 0.65 0.76]);
    theta = anglesDeg / 180 * pi;
    hold(polarAx, 'on');
    polarplot(polarAx, [theta; theta(1)], [kfValues; kfValues(1)], ...
        '-s', 'LineWidth', 1.2, 'MarkerSize', 6, 'DisplayName', 'k-f');
    polarplot(polarAx, [theta; theta(1)], ...
        [gradientValues; gradientValues(1)], '--o', ...
        'LineWidth', 1.2, 'MarkerSize', 6, 'DisplayName', 'Phase gradient');
    polarAx.ThetaZeroLocation = 'right';
    polarAx.ThetaDir = 'counterclockwise';
    polarAx.ThetaTick = 0:45:315;
    polarAx.FontSize = 12;
    polarAx.GridAlpha = 0.35;
    title(polarAx, sprintf('Phase speed (m/s) @ %.0f Hz', frequencyHz), ...
        'FontWeight', 'bold');
    legend(polarAx, 'show', 'Location', 'best');
    apply_radial_limit(polarAx, [kfValues; gradientValues]);

    boxAx = axes(fig, 'Position', [0.77 0.20 0.19 0.60]);
    combined = [kfValues; gradientValues];
    groups = [ones(numel(kfValues), 1); 2 * ones(numel(gradientValues), 1)];
    boxplot(boxAx, combined, groups, 'Whisker', 1, 'Widths', 0.45, ...
        'Labels', {'k-f', 'Phase gradient'});
    grid(boxAx, 'on');
    boxAx.FontSize = 10;
    kfMean = mean(kfValues, 'omitnan');
    kfStd = std(kfValues, 0, 'omitnan');
    pgMean = mean(gradientValues, 'omitnan');
    pgStd = std(gradientValues, 0, 'omitnan');
    title(boxAx, sprintf(['k-f: %.2f +/- %.3f m/s\n' ...
        'Phase gradient: %.2f +/- %.3f m/s'], ...
        kfMean, kfStd, pgMean, pgStd), ...
        'FontSize', 9, 'FontWeight', 'normal');
end

function render_polar_with_box(fig, anglesDeg, values, polarTitle, statsTitle)
    figure(fig);
    fig.Color = 'w';
    fig.GraphicsSmoothing = 'on';
    fig.Position(3:4) = [900 520];

    polarAx = polaraxes('Parent', fig, ...
        'Position', [0.07 0.08 0.66 0.76]);
    polarplot(polarAx, [anglesDeg / 180 * pi; 0], ...
        [values; values(1)], '-bs', 'LineWidth', 1, 'MarkerSize', 7);
    polarAx.ThetaZeroLocation = 'right';
    polarAx.ThetaDir = 'counterclockwise';
    polarAx.ThetaTick = 0:45:315;
    polarAx.FontSize = 12;
    polarAx.GridAlpha = 0.35;
    title(polarAx, polarTitle, 'FontWeight', 'bold');
    apply_radial_limit(polarAx, values);

    boxAx = axes(fig, 'Position', [0.80 0.20 0.12 0.60]);
    boxplot(boxAx, values, 'Whisker', 1, 'Widths', 0.45);
    grid(boxAx, 'on');
    boxAx.XTick = [];
    boxAx.FontSize = 11;
    title(boxAx, statsTitle, 'FontSize', 10, 'FontWeight', 'normal');
end

function apply_radial_limit(polarAx, values)
    finiteValues = values(isfinite(values));
    if isempty(finiteValues)
        return;
    end
    upper = max(finiteValues);
    if upper <= 0
        return;
    end
    span = upper - min(finiteValues);
    if span <= 0
        span = max(abs(upper) * 0.1, 1);
    end
    rlim(polarAx, [0 upper + 0.15 * span]);
end

function figureHandle = create_polar_figure(useTemplate, templateFile, name)
    if useTemplate && strlength(templateFile) > 0 && isfile(templateFile)
        figureHandle = openfig(char(templateFile), 'new', 'visible');
    else
        figureHandle = figure('Name', char(name));
    end
end
