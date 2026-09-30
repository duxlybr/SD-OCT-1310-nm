function [figures, details] = plotFilterPreviews(phaseResult, filterResult, ...
        reconstructionResult, geometry, varargin)
%PLOTFILTERPREVIEWS Render temporal-filter diagnostics without saving.
% The time-profile figure compensates FIR group delay for visualization only;
% filtered scientific arrays remain unchanged.

    if ~isstruct(phaseResult) || ~isfield(phaseResult, 'surface')
        error('OCE:Plotting:InvalidPhaseResult', ...
            'phaseResult.surface is required.');
    end
    inputSurfacePhase = phaseResult.surface;
    design = filterResult.design;
    frequencyAxisHz = filterResult.frequency_axis_hz;
    inputLine = design.diagnostic.input_line;
    inputSpectrum = design.diagnostic.input_spectrum;
    cropStartIndex = double( ...
        reconstructionResult.crop.time.start_index_inclusive);
    timeOffsetS = (cropStartIndex - 0.5) * ...
        double(reconstructionResult.geometry.time_sample_interval_s);
    timeAxisMs = (filterResult.time_axis_s + timeOffsetS) * 1e3;
    timeSampleIndices = cropStartIndex + ...
        (0:numel(filterResult.time_axis_s) - 1);
    lineIndex = design.diagnostic.line_index_used;
    outputLine = filterResult.surface.values(lineIndex, :);
    surfaceMap = filterResult.surface_postprocessed.values;

    parser = inputParser;
    addParameter(parser, 'CLimMode', "robust");
    addParameter(parser, 'CLim', []);
    addParameter(parser, 'BmodeMode', "representative");
    parse(parser, varargin{:});

    figures = gobjects(3, 1);

    figures(1) = figure('Name', 'Temporal filter spectrum');
    spectrumAxes = axes(figures(1));
    plot(spectrumAxes, frequencyAxisHz, abs(inputSpectrum), 'LineWidth', 1);
    grid(spectrumAxes, 'on');
    ylabel(spectrumAxes, 'Magnitude (Arb.)');
    xlabel(spectrumAxes, 'Frequency (Hz)');
    title(spectrumAxes, sprintf('Filter spectrum | lateral line %d', lineIndex));
    maxFrequencyHz = min(8000, frequencyAxisHz(end));
    ymax = max(abs(inputSpectrum), [], 'omitnan') * 1.1;
    if isempty(ymax) || ~isfinite(ymax) || ymax <= 0
        ymax = 1;
    end
    axis(spectrumAxes, [0 maxFrequencyHz 0 ymax]);
    hold(spectrumAxes, 'on');
    effective = design.effective_passband_hz;
    rectangle(spectrumAxes, 'Position', ...
        [effective(1), 0, diff(effective), ymax], ...
        'LineWidth', 1.5, 'LineStyle', '--');
    text(spectrumAxes, mean(effective), 0.92 * ymax, ...
        sprintf(' %.0f-%.0f Hz ', effective), ...
        'HorizontalAlignment', 'center', 'BackgroundColor', 'w');
    oce.plotting.applyPreviewStyle(figures(1), spectrumAxes, ...
        'FigureSize', [760 470]);

    figures(2) = figure('Name', 'Temporal filter time profile');
    [plotTimeMs, plotInput, plotOutput, outputLabel, profileAlignment] = ...
        delay_compensated_profile(inputLine, outputLine, timeAxisMs, ...
            design.delay_samples, filterResult.applied);
    plotInput = plotInput - mean(plotInput, 'omitnan');
    plotOutput = plotOutput - mean(plotOutput, 'omitnan');
    profileAxes = axes(figures(2));
    hold(profileAxes, 'on');
    plot(profileAxes, plotTimeMs, plotInput, ...
        'DisplayName', 'Input (demeaned)', ...
        'LineWidth', 1);
    plot(profileAxes, plotTimeMs, plotOutput, 'DisplayName', outputLabel, ...
        'LineWidth', 1);
    grid(profileAxes, 'on');
    ylabel(profileAxes, 'Phase increment (rad)');
    xlabel(profileAxes, 'Time (ms)');
    title(profileAxes, sprintf('FIR profile | lateral line %d', lineIndex));
    legend(profileAxes, 'show', 'Location', 'best');
    oce.plotting.applyPreviewStyle(figures(2), profileAxes, ...
        'FigureSize', [760 470]);

    if ~isequal(size(inputSurfacePhase.values), size(filterResult.surface.values))
        error('OCE:Plotting:InvalidFilterResult', ...
            'Input and output surface phase sizes must match.');
    end
    visualDelay = double(design.delay_samples) * double(filterResult.applied);
    [figures(3), spaceTimeDetails] = oce.plotting.plotBmodeSpaceTime( ...
        surfaceMap, timeAxisMs, filterResult.surface_postprocessed.units, ...
        geometry, "Filtered space-time", ...
        'CLimMode', parser.Results.CLimMode, 'CLim', parser.Results.CLim, ...
        'BmodeMode', parser.Results.BmodeMode, ...
        'DelaySamples', visualDelay, ...
        'TimeSampleIndices', timeSampleIndices);
    details = struct('profile_alignment', profileAlignment, ...
        'space_time', spaceTimeDetails);
end

function [timeMs, inputValues, outputValues, label, alignment] = ...
        delay_compensated_profile(inputLine, outputLine, timeAxisMs, ...
        delaySamples, applied)
    inputLine = inputLine(:)';
    outputLine = outputLine(:)';
    timeAxisMs = timeAxisMs(:)';
    if ~applied
        timeMs = timeAxisMs;
        inputValues = inputLine;
        outputValues = outputLine;
        label = 'Passthrough';
        alignment = alignment_metadata(0, 1:numel(timeAxisMs), ...
            1:numel(timeAxisMs));
        return;
    end
    delaySamples = max(0, round(double(delaySamples)));
    if delaySamples >= numel(timeAxisMs) - 1
        timeMs = timeAxisMs;
        inputValues = inputLine;
        outputValues = outputLine;
        label = 'FIR output';
        alignment = alignment_metadata(0, 1:numel(timeAxisMs), ...
            1:numel(timeAxisMs));
        return;
    end
    if delaySamples == 0
        timeMs = timeAxisMs;
        inputValues = inputLine;
        outputValues = outputLine;
    else
        timeMs = timeAxisMs(1:end-delaySamples);
        inputValues = inputLine(1:end-delaySamples);
        outputValues = outputLine(delaySamples+1:end);
    end
    label = sprintf('FIR output (delay compensated, %d samples)', delaySamples);
    alignment = alignment_metadata(delaySamples, ...
        1:numel(timeMs), delaySamples + 1:delaySamples + numel(timeMs));
end

function value = alignment_metadata(delaySamples, inputIndices, outputIndices)
    value = struct('delay_samples', delaySamples, ...
        'input_indices', inputIndices, 'output_indices', outputIndices);
end
