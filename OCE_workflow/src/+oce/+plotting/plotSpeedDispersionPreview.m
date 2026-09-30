function figHandle = plotSpeedDispersionPreview(analysis, scanAxisIndex)
%PLOTSPEEDDISPERSIONPREVIEW Render one directional-pair dispersion preview.

    left = analysis.directions(scanAxisIndex * 2 - 1);
    right = analysis.directions(scanAxisIndex * 2);
    frequencyLimit = analysis.options.spectrum.crop.maximum_frequency_hz;
    speedYLimit = oce.plotting.resolveSpeedPreviewYLimit( ...
        analysis, scanAxisIndex);
    targetAvailable = isfinite(left.target_selection.selected_frequency_hz) && ...
        isfinite(right.target_selection.selected_frequency_hz);

    figHandle = figure('Name', sprintf( ...
        'Speed dispersion - scan axis %02d', scanAxisIndex));
    ax = axes(figHandle);
    yyaxis(ax, 'left');
    plot(ax, left.phase_speed_curve.frequency_hz, ...
        left.phase_speed_curve.smoothed_phase_speed_m_per_s, ...
        'DisplayName', 'Left prop. - Speed');
    hold(ax, 'on');
    if targetAvailable
        plot(ax, left.target_selection.selected_frequency_hz, ...
            left.target_selection.selected_phase_speed_m_per_s, 'o', ...
            'DisplayName', 'Left target', 'MarkerFaceColor', 'auto');
    end
    ylim(ax, speedYLimit); ylabel(ax, 'Speed (m/s)');
    yyaxis(ax, 'right');
    plot(ax, left.phase_speed_curve.frequency_hz, ...
        normalize_for_display(left.spectrum.temporal_magnitude_mean), ...
        'DisplayName', 'Left prop. - Spectrum');
    ylabel(ax, 'Magnitude FFT (Arb.)'); xlabel(ax, 'Frequency (Hz)');
    xlim(ax, [0 frequencyLimit]); hold(ax, 'on');
    yyaxis(ax, 'left');
    plot(ax, right.phase_speed_curve.frequency_hz, ...
        right.phase_speed_curve.smoothed_phase_speed_m_per_s, ...
        'DisplayName', 'Right prop. - Speed');
    if targetAvailable
        plot(ax, right.target_selection.selected_frequency_hz, ...
            right.target_selection.selected_phase_speed_m_per_s, 'o', ...
            'DisplayName', 'Right target', 'MarkerFaceColor', 'auto');
    end
    ylim(ax, speedYLimit); ylabel(ax, 'Speed (m/s)');
    yyaxis(ax, 'right');
    plot(ax, right.phase_speed_curve.frequency_hz, ...
        normalize_for_display(right.spectrum.temporal_magnitude_mean), ...
        'DisplayName', 'Right prop. - Spectrum');
    ylabel(ax, 'Magnitude FFT (Arb.)'); xlabel(ax, 'Frequency (Hz)');
    xlim(ax, [0 frequencyLimit]);
    legend(ax, 'show', 'Location', 'northeast');
    grid(ax, 'on')
    titleText = thickness_title(left.mean_thickness_mm, right.mean_thickness_mm);
    if ~targetAvailable
        titleText = {titleText; 'Target frequency unavailable'};
    end
    title(ax, titleText);
    oce.plotting.applyPreviewStyle(figHandle, ax, ...
        'FigureSize', [860 520]);
end

function titleText = thickness_title(leftThicknessMm, rightThicknessMm)
    if isnan(leftThicknessMm) && isnan(rightThicknessMm)
        titleText = 'Thickness unavailable';
        return;
    end
    titleText = ['Thickness | left: ', ...
        num2str(round(leftThicknessMm * 1e3, 1)), ...
        ' um | right: ', ...
        num2str(round(rightThicknessMm * 1e3, 1)), ' um'];
end

function normalized = normalize_for_display(values)
    values = values(:);
    scale = max(values);
    if isempty(scale) || scale == 0 || isnan(scale)
        normalized = values;
    else
        normalized = values / scale;
    end
end
