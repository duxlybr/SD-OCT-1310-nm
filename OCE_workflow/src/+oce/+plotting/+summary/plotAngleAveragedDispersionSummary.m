function [figures, fileNames] = plotAngleAveragedDispersionSummary(experiment)
%PLOTANGLEAVERAGEDDISPERSIONSUMMARY Render angle-averaged dispersion summaries.

    [angleMeanData, angleCi95Data] = get_angle_summary(experiment);
    [dimensionKeys, dimensionValues] = get_experiment_dimensions(experiment);
    sharedYLimit = resolveSummaryPhaseSpeedLimit( ...
        experiment, "dispersion", "angle_averaged");

    angleSize = size(angleMeanData);
    nVars = numel(dimensionKeys) - 1;
    nCond = numel(angleMeanData);
    figures = gobjects(0, 1);
    fileNames = strings(0, 1);

    for p = 1:nCond
        idxCellFull = cell(1, numel(angleSize));
        [idxCellFull{:}] = ind2sub(angleSize, p);
        idxCell = idxCellFull(1:nVars);
        [conditionTitle, fileTitle] = oce.results.formatConditionLabel( ...
            dimensionKeys, dimensionValues, idxCell, 1:nVars);

        meanS = angleMeanData{idxCell{:}};
        ci95S = angleCi95Data{idxCell{:}};
        if isempty(meanS) || isempty(ci95S) || ...
                ~isstruct(meanS) || ~isstruct(ci95S)
            warning('Skipping empty angle summary for condition: %s', ...
                conditionTitle);
            continue;
        end
        if ~has_required_curve_data(meanS, ci95S)
            warning('Skipping incomplete angle dispersion curve: %s', ...
                conditionTitle);
            continue;
        end

        freq = meanS.direction_frequency_axes_hz;
        meanSpeed = meanS.direction_smoothed_phase_speed_m_per_s;
        ci95Speed = ci95S.direction_smoothed_phase_speed_m_per_s;
        meanFFT = meanS.direction_temporal_diagnostic_magnitude;
        ci95FFT = ci95S.direction_temporal_diagnostic_magnitude;
        [isValid, freq, meanSpeed, ci95Speed, meanFFT, ci95FFT] = ...
            validate_curve_vectors(freq, meanSpeed, ci95Speed, ...
            meanFFT, ci95FFT);
        if ~isValid
            warning('Skipping invalid angle dispersion curve: %s', ...
                conditionTitle);
            continue;
        end

        upS = meanSpeed + ci95Speed;
        loS = meanSpeed - ci95Speed;
        upF = meanFFT + ci95FFT;
        loF = meanFFT - ci95FFT;
        normFactor = max(meanFFT, [], 'omitnan');
        if isempty(normFactor) || ~isfinite(normFactor) || normFactor <= 0
            warning('Skipping curve with invalid FFT normalization: %s', ...
                conditionTitle);
            continue;
        end
        meanFFTNorm = meanFFT ./ normFactor;
        upFNorm = upF ./ normFactor;
        loFNorm = loF ./ normFactor;
        freqCut = max(freq, [], 'omitnan');
        if isempty(freqCut) || ~isfinite(freqCut) || freqCut <= 0
            warning('Skipping curve with invalid frequency limit: %s', ...
                conditionTitle);
            continue;
        end

        c1 = [0 0.4470 0.7410];
        c2 = [0.8500 0.3250 0.0980];
        figHandle = figure('MenuBar', 'figure', 'ToolBar', 'figure', ...
            'Color', 'w');
        hold on;

        yyaxis left
        if any(isfinite(ci95Speed))
            fill([freq' fliplr(freq')], [upS' fliplr(loS')], ...
                c1, 'FaceAlpha', 0.2, 'EdgeColor', 'none', ...
                'DisplayName', 'Speed 95% CI');
        end
        plot(freq, meanSpeed, 'Color', c1, 'LineWidth', 2, ...
            'DisplayName', 'Angle-averaged speed');
        ylabel('Speed (m/s)');
        ylim(sharedYLimit);

        yyaxis right
        if any(isfinite(ci95FFT))
            fill([freq' fliplr(freq')], [upFNorm' fliplr(loFNorm')], ...
                c2, 'FaceAlpha', 0.2, 'EdgeColor', 'none', ...
                'DisplayName', 'FFT 95% CI');
        end
        plot(freq, meanFFTNorm, 'Color', c2, 'LineWidth', 2, ...
            'DisplayName', 'Angle-averaged FFT');
        ylabel('Normalized FFT magnitude');
        ylim([0 1.1]);

        xlabel('Frequency (Hz)');
        xlim([0 freqCut]);
        title(sprintf('%s - Angle-averaged', conditionTitle));
        legend('Location', 'best');
        hold off;

        figures(end + 1, 1) = figHandle; %#ok<AGROW>
        fileNames(end + 1, 1) = "AngleDispersion_" + string(fileTitle); %#ok<AGROW>
    end
end

function tf = has_required_curve_data(meanS, ci95S)
    meanFields = {'direction_frequency_axes_hz', ...
        'direction_smoothed_phase_speed_m_per_s', ...
        'direction_temporal_diagnostic_magnitude'};
    ciFields = {'direction_smoothed_phase_speed_m_per_s', ...
        'direction_temporal_diagnostic_magnitude'};
    tf = true;
    for i = 1:numel(meanFields)
        fieldName = meanFields{i};
        if ~isfield(meanS, fieldName) || isempty(meanS.(fieldName))
            tf = false;
            return;
        end
    end
    for i = 1:numel(ciFields)
        fieldName = ciFields{i};
        if ~isfield(ci95S, fieldName) || isempty(ci95S.(fieldName))
            tf = false;
            return;
        end
    end
end

function [isValid, freq, meanSpeed, ci95Speed, meanFFT, ci95FFT] = ...
        validate_curve_vectors(freq, meanSpeed, ci95Speed, meanFFT, ci95FFT)
    isValid = false;
    freq = freq(:);
    meanSpeed = meanSpeed(:);
    ci95Speed = ci95Speed(:);
    meanFFT = meanFFT(:);
    ci95FFT = ci95FFT(:);
    n = min([numel(freq), numel(meanSpeed), numel(ci95Speed), ...
        numel(meanFFT), numel(ci95FFT)]);
    if isempty(n) || n < 2
        return;
    end

    freq = freq(1:n);
    meanSpeed = meanSpeed(1:n);
    ci95Speed = ci95Speed(1:n);
    meanFFT = meanFFT(1:n);
    ci95FFT = ci95FFT(1:n);
    validMask = isfinite(freq) & isfinite(meanSpeed) & isfinite(meanFFT);
    if nnz(validMask) < 2
        return;
    end

    freq = freq(validMask);
    meanSpeed = meanSpeed(validMask);
    ci95Speed = ci95Speed(validMask);
    meanFFT = meanFFT(validMask);
    ci95FFT = ci95FFT(validMask);
    ci95Speed(~isfinite(ci95Speed)) = NaN;
    ci95FFT(~isfinite(ci95FFT)) = NaN;
    if numel(freq) < 2 || max(freq) <= 0
        return;
    end
    isValid = true;
end

function [angleMeanData, angleCi95Data] = get_angle_summary(experiment)
    if isfield(experiment, 'summary') && ...
            isfield(experiment.summary, 'angle_mean_data') && ...
            isfield(experiment.summary, 'angle_ci95_data')
        angleMeanData = experiment.summary.angle_mean_data;
        angleCi95Data = experiment.summary.angle_ci95_data;
    else
        error(['Angle mean/CI95 data not found. Run ' ...
            'oce.results.summarizeAngles first.']);
    end
end

function [dimensionKeys, dimensionValues] = get_experiment_dimensions(experiment)
    if isfield(experiment, 'design') && ...
            isfield(experiment.design, 'dimension_keys') && ...
            isfield(experiment.design, 'dimension_values')
        dimensionKeys = string(experiment.design.dimension_keys);
        dimensionValues = experiment.design.dimension_values;
    else
        error('Experiment dimension information not found.');
    end
end
