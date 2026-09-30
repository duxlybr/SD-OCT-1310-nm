function [fig, details] = plotDispersionKfPreview(analysis, scanAxisIndex)
%PLOTDISPERSIONKFPREVIEW Plot preserved k-f magnitude and ridge diagnostics.
% This function consumes analysis output and performs no FFT or ridge search.

    indices = [scanAxisIndex * 2 - 1, scanAxisIndex * 2];
    if ~isstruct(analysis) || ~isfield(analysis, 'directions') || ...
            any(indices > numel(analysis.directions))
        error('OCE:Plotting:InvalidDispersionAnalysis', ...
            'Analysis does not contain the requested scan-axis directions.');
    end
    directions = analysis.directions(indices);
    displayedMagnitude = cell(2, 1);
    for index = 1:2
        magnitude = double(directions(index).spectrum.magnitude);
        scale = max(magnitude, [], 'all', 'omitnan');
        if ~isfinite(scale) || scale <= 0, scale = 1; end
        displayedMagnitude{index} = max(-60, ...
            20 * log10(max(magnitude / scale, eps)));
    end

    fig = figure('Name', sprintf('k-f diagnostic - scan axis %02d', ...
        scanAxisIndex));
    layout = tiledlayout(fig, 4, 2, ...
        'TileSpacing', 'compact', 'Padding', 'compact');
    axesHandles = gobjects(2, 1);
    profileAxes = gobjects(2, 1);
    imageHandles = gobjects(2, 1);
    ridgeHandles = gobjects(2, 1);
    targetLines = gobjects(2, 1);
    selectedPoints = gobjects(2, 1);
    profileLines = gobjects(2, 1);
    profilePeakLines = gobjects(2, 1);
    profileFrequencyHz = NaN(2, 1);

    for index = 1:2
        direction = directions(index);
        frequencyHz = direction.spectrum.frequency_axis_hz;
        frequencyKhz = frequencyHz / 1e3;
        wavenumber = direction.spectrum.wavenumber_axis_per_m;
        ax = nexttile(layout, index, [3 1]);
        axesHandles(index) = ax;
        imageHandles(index) = imagesc(ax, frequencyKhz, wavenumber, ...
            displayedMagnitude{index});
        axis(ax, 'xy');
        hold(ax, 'on');
        ridgeHandles(index) = plot(ax, frequencyKhz, ...
            direction.ridge.wavenumber_per_m, 'w-', 'LineWidth', 1.4, ...
            'DisplayName', 'Detected ridge');

        targetAvailable = isfinite( ...
            direction.target_selection.requested_frequency_hz) && ...
            isfinite(direction.target_selection.selected_bin_index);
        if targetAvailable
            requestedKhz = ...
                direction.target_selection.requested_frequency_hz / 1e3;
            targetLines(index) = xline(ax, requestedKhz, '--', ...
                'Excitation', 'Color', [0.95 0.80 0.15], 'LineWidth', 1.1);
            selectedPoints(index) = scatter(ax, ...
                direction.target_selection.selected_frequency_hz / 1e3, ...
                direction.target_selection.selected_wavenumber_per_m, ...
                28, [0.95 0.80 0.15], 'filled', ...
                'DisplayName', 'Selected bin');
        end
        xlabel(ax, 'Frequency (kHz)');
        ylabel(ax, 'Wavenumber (cycles/m)');
        title(ax, sprintf('%s propagation | cropped k-f', ...
            char(direction.direction)));

        profileAx = nexttile(layout, 6 + index);
        profileAxes(index) = profileAx;
        if targetAvailable
            selectedIndex = double( ...
                direction.target_selection.selected_bin_index);
            profileFrequencyHz(index) = frequencyHz(selectedIndex);
            profileMagnitude = double( ...
                direction.spectrum.magnitude(:, selectedIndex));
            profileLines(index) = plot(profileAx, wavenumber, ...
                profileMagnitude, 'LineWidth', 1.2);
            hold(profileAx, 'on');
            profilePeakLines(index) = xline(profileAx, ...
                direction.target_selection.selected_wavenumber_per_m, '--', ...
                'LineWidth', 1.0);
            grid(profileAx, 'on');
            xlim(profileAx, [wavenumber(1) wavenumber(end)]);
            xlabel(profileAx, 'Wavenumber (cycles/m)');
            ylabel(profileAx, 'Magnitude (arb.)');
            title(profileAx, sprintf('k profile @ %.3f kHz', ...
                profileFrequencyHz(index) / 1e3), 'FontSize', 9);
        else
            axis(profileAx, 'off');
            text(profileAx, 0.5, 0.5, 'Target-frequency k profile unavailable', ...
                'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', 'FontSize', 10);
        end
    end

    colormap(fig, parula(256));
    for index = 1:numel(axesHandles)
        clim(axesHandles(index), [-60 0]);
    end
    colorbarHandle = colorbar(axesHandles(end));
    colorbarHandle.Layout.Tile = 'south';
    colorbarHandle.Label.String = 'Magnitude (dB rel.)';
    oce.plotting.applyPreviewStyle(fig, [axesHandles; profileAxes], ...
        'FigureSize', [1080 720]);

    details = struct('scan_axis_index', scanAxisIndex, ...
        'directions', string({directions.direction}), ...
        'axes', axesHandles, 'images', imageHandles, ...
        'ridge_lines', ridgeHandles, 'target_lines', targetLines, ...
        'selected_points', selectedPoints, 'profile_axes', profileAxes, ...
        'profile_lines', profileLines, 'profile_peak_lines', profilePeakLines, ...
        'profile_frequency_hz', profileFrequencyHz, ...
        'colorbar', colorbarHandle, ...
        'source', "analysis.directions.spectrum_and_ridge");
end
