function [figures, fileNames] = plotPhaseSpeedVsFrequencyAngleAveraged(experiment)
%PLOTPHASESPEEDVSFREQUENCYANGLEAVERAGED Render angle-averaged phase speed vs frequency.

    [angleMeanData, angleCi95Data] = get_angle_summary(experiment);
    [dimensionKeys, dimensionValues, dimensionUnits] = ...
        get_experiment_dimensions(experiment);
    sharedYLimit = resolveSummaryPhaseSpeedLimit( ...
        experiment, "target", "angle_averaged");
    sharedYLimit = extend_y_limit( ...
        sharedYLimit, angleMeanData, angleCi95Data);

    angleSize = size(angleMeanData);
    nVars = numel(dimensionKeys) - 1;
    freqDim = find_frequency_dimension(dimensionKeys);
    [xValues, xLabel] = get_frequency_values( ...
        dimensionValues{freqDim}, dimensionUnits(freqDim));
    otherDims = setdiff(1:nVars, freqDim);
    otherSizes = angleSize(otherDims);
    if isempty(otherDims)
        nGroups = 1;
    else
        nGroups = prod(otherSizes);
    end

    figures = gobjects(0, 1);
    fileNames = strings(0, 1);
    for g = 1:nGroups
        idxBase = cell(1, nVars);
        if ~isempty(otherDims)
            otherIdx = cell(1, numel(otherDims));
            [otherIdx{:}] = ind2sub(otherSizes, g);
            for d = 1:numel(otherDims)
                idxBase{otherDims(d)} = otherIdx{d};
            end
        end

        [conditionTitle, fileTitle] = oce.results.formatConditionLabel( ...
            dimensionKeys, dimensionValues, idxBase, otherDims);
        kfMean = NaN(numel(xValues), 1);
        kfCi95 = NaN(numel(xValues), 1);
        gradientMean = NaN(numel(xValues), 1);
        gradientCi95 = NaN(numel(xValues), 1);
        for iX = 1:numel(xValues)
            idxCell = idxBase;
            idxCell{freqDim} = iX;
            meanS = angleMeanData{idxCell{:}};
            ci95S = angleCi95Data{idxCell{:}};
            kfMean(iX) = meanS.angular_phase_speed_m_per_s;
            kfCi95(iX) = ci95S.angular_phase_speed_m_per_s;
            if isfield(meanS, 'angular_phase_gradient_speed_m_per_s')
                gradientMean(iX) = meanS.angular_phase_gradient_speed_m_per_s;
                gradientCi95(iX) = ...
                    ci95S.angular_phase_gradient_speed_m_per_s;
            end
        end

        [xPlot, sortIdx] = sort(xValues);
        kfMean = kfMean(sortIdx);
        kfCi95 = kfCi95(sortIdx);
        gradientMean = gradientMean(sortIdx);
        gradientCi95 = gradientCi95(sortIdx);

        figHandle = figure('MenuBar', 'figure', 'ToolBar', 'figure', ...
            'Color', 'w');
        hold on;
        errorbar(xPlot, kfMean, kfCi95, '-o', 'LineWidth', 1.8, ...
            'MarkerSize', 6, 'DisplayName', 'k-f');
        if any(isfinite(gradientMean))
            errorbar(xPlot, gradientMean, gradientCi95, '--s', ...
                'LineWidth', 1.8, 'MarkerSize', 6, ...
                'DisplayName', 'Phase gradient');
        end
        xlabel(xLabel);
        ylabel('Phase speed (m/s)');
        ylim(sharedYLimit);

        if strlength(conditionTitle) == 0 || conditionTitle == "All conditions"
            fileTitle = "AllConditions";
            title('Angle-averaged phase speed vs frequency - 95% CI');
        else
            title(sprintf(['%s - Angle-averaged phase speed vs frequency ' ...
                '- 95%% CI'], conditionTitle));
        end
        legend('Location', 'best');
        grid on;
        hold off;

        figures(end + 1, 1) = figHandle; %#ok<AGROW>
        fileNames(end + 1, 1) = ...
            "PhaseSpeedVsFrequency_AngleAveraged_" + string(fileTitle); %#ok<AGROW>
    end
end

function limit = extend_y_limit(limit, meanData, ci95Data)
    upper = limit(2);
    for index = 1:numel(meanData)
        meanS = meanData{index};
        ci95S = ci95Data{index};
        if isempty(meanS) || ...
                ~isfield(meanS, 'angular_phase_gradient_speed_m_per_s')
            continue;
        end
        values = meanS.angular_phase_gradient_speed_m_per_s;
        ci95 = ci95S.angular_phase_gradient_speed_m_per_s;
        candidate = values + ci95;
        candidate = candidate(isfinite(candidate));
        if isempty(candidate)
            candidate = values(isfinite(values));
        end
        if ~isempty(candidate)
            upper = max(upper, 1.1 * max(candidate));
        end
    end
    limit(2) = upper;
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

function [dimensionKeys, dimensionValues, dimensionUnits] = ...
        get_experiment_dimensions(experiment)
    if isfield(experiment, 'design') && ...
            isfield(experiment.design, 'dimension_keys') && ...
            isfield(experiment.design, 'dimension_values')
        dimensionKeys = string(experiment.design.dimension_keys);
        dimensionValues = experiment.design.dimension_values;
        if isfield(experiment.design, 'dimension_units')
            dimensionUnits = string(experiment.design.dimension_units);
        else
            dimensionUnits = strings(size(dimensionKeys));
        end
    else
        error('Experiment dimension information not found.');
    end
end

function freqDim = find_frequency_dimension(dimensionKeys)
    freqDim = find(strcmp(dimensionKeys, 'frequency_Hz'), 1);
    if isempty(freqDim)
        error(['No frequency_Hz dimension found. ' ...
            'plotPhaseSpeedVsFrequencyAngleAveraged requires experiments ' ...
            'acquired at multiple fixed frequencies.']);
    end
end

function [freqValues, xLabel] = get_frequency_values(varValues, unitLabel)
    n = numel(varValues);
    freqValues = NaN(n, 1);
    for i = 1:n
        rawLabel = string(varValues{i});
        numericValue = str2double(rawLabel);
        if isnan(numericValue)
            numericValue = str2double(regexp( ...
                rawLabel, '[\d.]+', 'match', 'once'));
        end
        if isnan(numericValue)
            error(['Unsupported frequency value: %s. Expected numeric ' ...
                'values in frequency_Hz.'], rawLabel);
        end
        if strcmpi(unitLabel, 'kHz')
            freqValues(i) = numericValue * 1e3;
        else
            freqValues(i) = numericValue;
        end
    end
    xLabel = 'Frequency (Hz)';
end
