function [figures, fileNames] = plotRepetitionAveragedDispersionSummary(experiment)
%PLOTREPETITIONAVERAGEDDISPERSIONSUMMARY Render repetition-averaged dispersion summaries.

    [meanData, ci95Data] = get_repetition_summary(experiment);
    [dimensionKeys, dimensionValues] = get_experiment_dimensions(experiment);
    sharedYLimit = resolveSummaryPhaseSpeedLimit( ...
        experiment, "dispersion", "by_angle");

    meanSize = size(meanData);
    nCond = numel(meanData);
    nVars = numel(dimensionKeys) - 1;
    figures = gobjects(0, 1);
    fileNames = strings(0, 1);

    for p = 1:nCond
        idxCellFull = cell(1, numel(meanSize));
        [idxCellFull{:}] = ind2sub(meanSize, p);
        idxCell = idxCellFull(1:nVars);
        [conditionTitle, fileTitle] = oce.results.formatConditionLabel( ...
            dimensionKeys, dimensionValues, idxCell, 1:nVars);

        meanS = meanData{idxCell{:}};
        ci95S = ci95Data{idxCell{:}};
        if isempty(meanS) || isempty(ci95S) || ...
                ~isstruct(meanS) || ~isstruct(ci95S)
            warning('Skipping empty repetition summary for condition: %s', ...
                conditionTitle);
            continue;
        end
        if ~isfield(meanS, 'full_circle_angles_deg') || ...
                isempty(meanS.full_circle_angles_deg)
            warning('Skipping condition without full_circle_angles_deg: %s', ...
                conditionTitle);
            continue;
        end

        nAngles = numel(meanS.full_circle_angles_deg);
        for angle = 1:nAngles
            if ~has_required_angle_data(meanS, ci95S, angle)
                warning(['Skipping incomplete repetition dispersion curve: ' ...
                    '%s | angle %d'], conditionTitle, angle);
                continue;
            end

            freq = meanS.direction_frequency_axes_hz{angle};
            meanSpeed = meanS.direction_smoothed_phase_speed_m_per_s{angle};
            ci95Speed = ci95S.direction_smoothed_phase_speed_m_per_s{angle};
            meanFFT = meanS.direction_temporal_diagnostic_magnitude{angle};
            ci95FFT = ci95S.direction_temporal_diagnostic_magnitude{angle};
            [isValid, freq, meanSpeed, ci95Speed, meanFFT, ci95FFT] = ...
                validate_curve_vectors(freq, meanSpeed, ci95Speed, ...
                meanFFT, ci95FFT);
            if ~isValid
                warning(['Skipping invalid repetition dispersion curve: ' ...
                    '%s | angle %d'], conditionTitle, angle);
                continue;
            end

            upS = meanSpeed + ci95Speed;
            loS = meanSpeed - ci95Speed;
            upF = meanFFT + ci95FFT;
            loF = meanFFT - ci95FFT;
            normFactor = max(meanFFT, [], 'omitnan');
            if isempty(normFactor) || ~isfinite(normFactor) || normFactor <= 0
                warning(['Skipping curve with invalid FFT normalization: ' ...
                    '%s | angle %d'], conditionTitle, angle);
                continue;
            end
            meanFFTNorm = meanFFT ./ normFactor;
            upFNorm = upF ./ normFactor;
            loFNorm = loF ./ normFactor;
            freqCut = max(freq, [], 'omitnan');
            if isempty(freqCut) || ~isfinite(freqCut) || freqCut <= 0
                warning(['Skipping curve with invalid frequency limit: ' ...
                    '%s | angle %d'], conditionTitle, angle);
                continue;
            end

            angleDeg = meanS.full_circle_angles_deg(angle);
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
                'DisplayName', 'Speed mean');
            ylabel('Speed (m/s)');
            ylim(sharedYLimit);

            yyaxis right
            if any(isfinite(ci95FFT))
                fill([freq' fliplr(freq')], ...
                    [upFNorm' fliplr(loFNorm')], c2, ...
                    'FaceAlpha', 0.2, 'EdgeColor', 'none', ...
                    'DisplayName', 'FFT 95% CI');
            end
            plot(freq, meanFFTNorm, 'Color', c2, 'LineWidth', 2, ...
                'DisplayName', 'FFT mean');
            ylabel('Normalized FFT magnitude');
            ylim([0 1.1]);

            xlabel('Frequency (Hz)');
            xlim([0 freqCut]);
            title(sprintf('%s - Angle %.0f°', conditionTitle, angleDeg));
            legend('Location', 'best');
            hold off;

            figures(end + 1, 1) = figHandle; %#ok<AGROW>
            fileNames(end + 1, 1) = sprintf( ...
                'RepetitionDispersion_%s_Angle%.0fdeg', ...
                fileTitle, angleDeg); %#ok<AGROW>
        end
    end
end

function tf = has_required_angle_data(meanS, ci95S, angle)
    requiredFields = {'direction_frequency_axes_hz', ...
        'direction_smoothed_phase_speed_m_per_s', ...
        'direction_temporal_diagnostic_magnitude'};
    tf = true;
    for i = 1:numel(requiredFields)
        fieldName = requiredFields{i};
        if ~isfield(meanS, fieldName) || ...
                numel(meanS.(fieldName)) < angle || ...
                isempty(meanS.(fieldName){angle})
            tf = false;
            return;
        end
    end

    ciFields = {'direction_smoothed_phase_speed_m_per_s', ...
        'direction_temporal_diagnostic_magnitude'};
    for i = 1:numel(ciFields)
        fieldName = ciFields{i};
        if ~isfield(ci95S, fieldName) || ...
                numel(ci95S.(fieldName)) < angle || ...
                isempty(ci95S.(fieldName){angle})
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

function [meanData, ci95Data] = get_repetition_summary(experiment)
    if isfield(experiment, 'summary') && ...
            isfield(experiment.summary, 'repetition_mean_data') && ...
            isfield(experiment.summary, 'repetition_ci95_data')
        meanData = experiment.summary.repetition_mean_data;
        ci95Data = experiment.summary.repetition_ci95_data;
    else
        error(['Repetition mean/CI95 data not found. Run ' ...
            'oce.results.summarizeRepetitions first.']);
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
