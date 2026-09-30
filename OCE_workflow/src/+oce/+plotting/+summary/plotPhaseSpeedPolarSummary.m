function [figures, fileNames] = plotPhaseSpeedPolarSummary( ...
        experiment, varargin)
%PLOTPHASESPEEDPOLARSUMMARY Render phase-speed polar summaries.

    parser = inputParser;
    addParameter(parser, 'OverlayDimension', "", ...
        @(x) ischar(x) || isstring(x));
    parse(parser, varargin{:});

    overlayDimension = strtrim(string(parser.Results.OverlayDimension));
    if isfield(experiment, 'summary') && ...
            isfield(experiment.summary, 'dispersion_sampling')
        [dimensionKeys, dimensionValues] = get_experiment_dimensions(experiment);
        [figures, fileNames] = plot_sampled_dispersion( ...
            experiment, dimensionKeys, dimensionValues, overlayDimension);
        return;
    end

    [meanData, ci95Data] = get_repetition_summary(experiment);
    [dimensionKeys, dimensionValues] = get_experiment_dimensions(experiment);
    sharedRadialLimit = resolveSummaryPhaseSpeedLimit( ...
        experiment, "target", "by_angle");
    sharedRadialLimit = extend_radial_limit(sharedRadialLimit, meanData, ci95Data);

    if strlength(overlayDimension) > 0
        [figures, fileNames] = plot_overlay_dimension( ...
            meanData, dimensionKeys, dimensionValues, overlayDimension, ...
            sharedRadialLimit);
        return;
    end

    meanSize = size(meanData);
    nVars = numel(dimensionKeys) - 1;
    nCond = numel(meanData);
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
        if isempty(meanS)
            continue;
        end
        theta = meanS.full_circle_angles_deg(:) * pi / 180;
        kfMean = meanS.angular_phase_speed_m_per_s(:);
        kfCi95 = ci95S.angular_phase_speed_m_per_s(:);
        [gradientMean, gradientCi95] = gradient_values(meanS, ci95S, numel(theta));

        figHandle = comparison_figure();
        kfAxes = polaraxes('Parent', figHandle, ...
            'Position', [0.05 0.14 0.40 0.72]);
        gradientAxes = polaraxes('Parent', figHandle, ...
            'Position', [0.55 0.14 0.40 0.72]);
        render_polar(kfAxes, theta, kfMean, kfCi95, ...
            "k-f - " + conditionTitle, sharedRadialLimit, true);
        render_polar(gradientAxes, theta, gradientMean, gradientCi95, ...
            "Phase gradient - " + conditionTitle, sharedRadialLimit, true);

        figures(end + 1, 1) = figHandle; %#ok<AGROW>
        fileNames(end + 1, 1) = "PhaseSpeedPolar_" + string(fileTitle); %#ok<AGROW>
    end
end

function [figures, fileNames] = plot_overlay_dimension( ...
        meanData, dimensionKeys, dimensionValues, overlayDimension, ...
        sharedRadialLimit)
    nConditionDims = numel(dimensionKeys) - 1;
    conditionKeys = dimensionKeys(1:nConditionDims);
    overlayDim = find(conditionKeys == overlayDimension);
    if numel(overlayDim) ~= 1
        error('OCE:Plotting:SummaryOverlayDimension', ...
            'OverlayDimension must identify exactly one condition dimension: %s.', ...
            overlayDimension);
    end

    facetDims = setdiff(1:nConditionDims, overlayDim, 'stable');
    facetSizes = cellfun(@numel, dimensionValues(facetDims));
    if isempty(facetDims)
        nFacetGroups = 1;
    else
        nFacetGroups = prod(facetSizes);
    end

    overlayValues = dimensionValues{overlayDim};
    figures = gobjects(0, 1);
    fileNames = strings(0, 1);

    for facetIndex = 1:nFacetGroups
        idxBase = cell(1, nConditionDims);
        if numel(facetDims) == 1
            idxBase{facetDims} = facetIndex;
        elseif numel(facetDims) > 1
            facetSubscripts = cell(1, numel(facetDims));
            [facetSubscripts{:}] = ind2sub(facetSizes, facetIndex);
            for index = 1:numel(facetDims)
                idxBase{facetDims(index)} = facetSubscripts{index};
            end
        end

        [conditionTitle, conditionFile] = oce.results.formatConditionLabel( ...
            dimensionKeys, dimensionValues, idxBase, facetDims);
        figHandle = comparison_figure();
        kfAxes = polaraxes('Parent', figHandle, ...
            'Position', [0.05 0.14 0.40 0.72]);
        gradientAxes = polaraxes('Parent', figHandle, ...
            'Position', [0.55 0.14 0.40 0.72]);
        hold(kfAxes, 'on');
        hold(gradientAxes, 'on');

        referenceAnglesDeg = [];
        nCurves = 0;
        for overlayIndex = 1:numel(overlayValues)
            idxCell = idxBase;
            idxCell{overlayDim} = overlayIndex;
            meanS = meanData{idxCell{:}};
            if isempty(meanS)
                continue;
            end

            anglesDeg = meanS.full_circle_angles_deg(:);
            if isempty(referenceAnglesDeg)
                referenceAnglesDeg = anglesDeg;
            elseif ~isequal(referenceAnglesDeg, anglesDeg)
                error('OCE:Plotting:SummaryOverlayAngles', ...
                    'Angular coordinates must match across overlaid conditions.');
            end
            [curveTitle, ~] = oce.results.formatConditionLabel( ...
                dimensionKeys, dimensionValues, idxCell, overlayDim);
            theta = anglesDeg * pi / 180;
            kfValues = meanS.angular_phase_speed_m_per_s(:);
            gradientValues = NaN(size(kfValues));
            if isfield(meanS, 'angular_phase_gradient_speed_m_per_s')
                gradientValues = meanS.angular_phase_gradient_speed_m_per_s(:);
            end
            polarplot(kfAxes, [theta; theta(1)], [kfValues; kfValues(1)], ...
                '-o', 'LineWidth', 1.5, 'MarkerSize', 5, ...
                'DisplayName', char(curveTitle));
            if any(isfinite(gradientValues))
                polarplot(gradientAxes, [theta; theta(1)], ...
                    [gradientValues; gradientValues(1)], '-o', ...
                    'LineWidth', 1.5, 'MarkerSize', 5, ...
                    'DisplayName', char(curveTitle));
            end
            nCurves = nCurves + 1;
        end

        if nCurves == 0
            close(figHandle);
            continue;
        end
        format_polar_axes(kfAxes, "k-f - " + conditionTitle, sharedRadialLimit);
        format_polar_axes(gradientAxes, ...
            "Phase gradient - " + conditionTitle, sharedRadialLimit);
        legend(kfAxes, 'show', 'Location', 'southoutside', ...
            'Orientation', 'horizontal');
        if ~isempty(gradientAxes.Children)
            legend(gradientAxes, 'show', 'Location', 'southoutside', ...
                'Orientation', 'horizontal');
        end

        figures(end + 1, 1) = figHandle; %#ok<AGROW>
        fileNames(end + 1, 1) = "PhaseSpeedPolar_" + ...
            string(conditionFile) + "_By_" + overlayDimension; %#ok<AGROW>
    end
end

function [figures, fileNames] = plot_sampled_dispersion( ...
        experiment, dimensionKeys, dimensionValues, overlayDimension)
    sampling = experiment.summary.dispersion_sampling;
    required = {'requested_frequency_hz', 'selected_frequency_hz', ...
        'mean_data', 'ci95_data'};
    if any(~isfield(sampling, required))
        error('OCE:Plotting:DispersionSampling', ...
            'Dispersion sampling summary is incomplete.');
    end

    sharedRadialLimit = resolveSummaryPhaseSpeedLimit( ...
        experiment, "dispersion", "by_angle");
    sharedRadialLimit = extend_sampled_radial_limit( ...
        sharedRadialLimit, sampling.mean_data, sampling.ci95_data);

    if strlength(overlayDimension) > 0
        [figures, fileNames] = plot_sampled_overlay_dimension( ...
            sampling, dimensionKeys, dimensionValues, overlayDimension, ...
            sharedRadialLimit);
    else
        [figures, fileNames] = plot_sampled_conditions( ...
            sampling, dimensionKeys, dimensionValues, sharedRadialLimit);
    end
end

function [figures, fileNames] = plot_sampled_conditions( ...
        sampling, dimensionKeys, dimensionValues, sharedRadialLimit)
    meanData = sampling.mean_data;
    ci95Data = sampling.ci95_data;
    meanSize = size(meanData);
    nVars = numel(dimensionKeys) - 1;
    figures = gobjects(0, 1);
    fileNames = strings(0, 1);

    for conditionIndex = 1:numel(meanData)
        meanS = meanData{conditionIndex};
        ci95S = ci95Data{conditionIndex};
        if isempty(meanS) || isempty(ci95S)
            continue;
        end

        idxFull = cell(1, numel(meanSize));
        [idxFull{:}] = ind2sub(meanSize, conditionIndex);
        idxCell = idxFull(1:nVars);
        [conditionTitle, fileTitle] = oce.results.formatConditionLabel( ...
            dimensionKeys, dimensionValues, idxCell, 1:nVars);
        theta = meanS.full_circle_angles_deg(:) * pi / 180;

        for frequencyIndex = 1:numel(sampling.requested_frequency_hz)
            meanValues = meanS.phase_speed_m_per_s(:, frequencyIndex);
            ci95Values = ci95S.phase_speed_m_per_s(:, frequencyIndex);
            requested = sampling.requested_frequency_hz(frequencyIndex);
            selected = sampling.selected_frequency_hz(frequencyIndex);

            figHandle = figure('MenuBar', 'figure', 'ToolBar', 'figure', ...
                'Color', 'w');
            ax = polaraxes('Parent', figHandle);
            render_polar(ax, theta, meanValues, ci95Values, ...
                sprintf('k-f sampled @ %g Hz (bin %g Hz) - %s', ...
                requested, selected, conditionTitle), sharedRadialLimit, true);

            figures(end + 1, 1) = figHandle; %#ok<AGROW>
            fileNames(end + 1, 1) = "PhaseSpeedPolar_Sampled_" + ...
                string(sprintf('%gHz_', requested)) + string(fileTitle); %#ok<AGROW>
        end
    end
end

function [figures, fileNames] = plot_sampled_overlay_dimension( ...
        sampling, dimensionKeys, dimensionValues, overlayDimension, ...
        sharedRadialLimit)
    nConditionDims = numel(dimensionKeys) - 1;
    conditionKeys = dimensionKeys(1:nConditionDims);
    overlayDim = find(conditionKeys == overlayDimension);
    if numel(overlayDim) ~= 1
        error('OCE:Plotting:SummaryOverlayDimension', ...
            'OverlayDimension must identify exactly one condition dimension: %s.', ...
            overlayDimension);
    end

    facetDims = setdiff(1:nConditionDims, overlayDim, 'stable');
    facetSizes = cellfun(@numel, dimensionValues(facetDims));
    if isempty(facetDims)
        nFacetGroups = 1;
    else
        nFacetGroups = prod(facetSizes);
    end

    overlayValues = dimensionValues{overlayDim};
    figures = gobjects(0, 1);
    fileNames = strings(0, 1);

    for frequencyIndex = 1:numel(sampling.requested_frequency_hz)
        requested = sampling.requested_frequency_hz(frequencyIndex);
        selected = sampling.selected_frequency_hz(frequencyIndex);

        for facetIndex = 1:nFacetGroups
            idxBase = cell(1, nConditionDims);
            if numel(facetDims) == 1
                idxBase{facetDims} = facetIndex;
            elseif numel(facetDims) > 1
                facetSubscripts = cell(1, numel(facetDims));
                [facetSubscripts{:}] = ind2sub(facetSizes, facetIndex);
                for index = 1:numel(facetDims)
                    idxBase{facetDims(index)} = facetSubscripts{index};
                end
            end

            [conditionTitle, conditionFile] = oce.results.formatConditionLabel( ...
                dimensionKeys, dimensionValues, idxBase, facetDims);
            figHandle = figure('MenuBar', 'figure', 'ToolBar', 'figure', ...
                'Color', 'w');
            ax = polaraxes('Parent', figHandle);
            hold(ax, 'on');

            referenceAnglesDeg = [];
            nCurves = 0;
            for overlayIndex = 1:numel(overlayValues)
                idxCell = idxBase;
                idxCell{overlayDim} = overlayIndex;
                meanS = sampling.mean_data{idxCell{:}};
                if isempty(meanS)
                    continue;
                end

                anglesDeg = meanS.full_circle_angles_deg(:);
                if isempty(referenceAnglesDeg)
                    referenceAnglesDeg = anglesDeg;
                elseif ~isequal(referenceAnglesDeg, anglesDeg)
                    error('OCE:Plotting:SummaryOverlayAngles', ...
                        'Angular coordinates must match across overlaid conditions.');
                end
                [curveTitle, ~] = oce.results.formatConditionLabel( ...
                    dimensionKeys, dimensionValues, idxCell, overlayDim);
                theta = anglesDeg * pi / 180;
                values = meanS.phase_speed_m_per_s(:, frequencyIndex);
                polarplot(ax, [theta; theta(1)], [values; values(1)], ...
                    '-o', 'LineWidth', 1.5, 'MarkerSize', 5, ...
                    'DisplayName', char(curveTitle));
                nCurves = nCurves + 1;
            end

            if nCurves == 0
                close(figHandle);
                continue;
            end
            format_polar_axes(ax, sprintf( ...
                'k-f sampled @ %g Hz (bin %g Hz) - %s', ...
                requested, selected, conditionTitle), sharedRadialLimit);
            legend(ax, 'show', 'Location', 'southoutside', ...
                'Orientation', 'horizontal');

            figures(end + 1, 1) = figHandle; %#ok<AGROW>
            fileNames(end + 1, 1) = "PhaseSpeedPolar_Sampled_" + ...
                string(sprintf('%gHz_', requested)) + string(conditionFile) + ...
                "_By_" + overlayDimension; %#ok<AGROW>
        end
    end
end

function fig = comparison_figure()
    fig = figure('MenuBar', 'figure', 'ToolBar', 'figure', 'Color', 'w');
    set(fig, 'Position', [10, 10, 1000, 430]);
end

function render_polar(ax, theta, meanValues, ci95Values, titleText, ...
        radialLimit, showCi)
    hold(ax, 'on');
    if any(isfinite(meanValues))
        polarplot(ax, [theta; theta(1)], [meanValues; meanValues(1)], ...
            '-o', 'LineWidth', 1.5, 'MarkerSize', 5, ...
            'DisplayName', 'Mean');
        if showCi
            for k = 1:numel(theta)
                if ~isfinite(ci95Values(k)) || ~isfinite(meanValues(k))
                    continue;
                end
                visibility = 'off';
                if k == 1
                    visibility = 'on';
                end
                polarplot(ax, [theta(k) theta(k)], ...
                    [meanValues(k) - ci95Values(k), meanValues(k) + ci95Values(k)], ...
                    '-', 'LineWidth', 1.2, 'DisplayName', '95% CI', ...
                    'HandleVisibility', visibility);
            end
        end
        legend(ax, 'show', 'Location', 'southoutside', ...
            'Orientation', 'horizontal');
    end
    format_polar_axes(ax, titleText, radialLimit);
end

function format_polar_axes(ax, titleText, radialLimit)
    title(ax, titleText);
    rlim(ax, radialLimit);
    grid(ax, 'on');
    hold(ax, 'off');
end

function [gradientMean, gradientCi95] = gradient_values(meanS, ci95S, count)
    gradientMean = NaN(count, 1);
    gradientCi95 = NaN(count, 1);
    if isfield(meanS, 'angular_phase_gradient_speed_m_per_s')
        gradientMean = meanS.angular_phase_gradient_speed_m_per_s(:);
        gradientCi95 = ci95S.angular_phase_gradient_speed_m_per_s(:);
    end
end

function limit = extend_radial_limit(limit, meanData, ci95Data)
    upper = limit(2);
    for index = 1:numel(meanData)
        meanS = meanData{index};
        ci95S = ci95Data{index};
        if isempty(meanS) || ...
                ~isfield(meanS, 'angular_phase_gradient_speed_m_per_s')
            continue;
        end
        values = meanS.angular_phase_gradient_speed_m_per_s(:);
        ci95 = ci95S.angular_phase_gradient_speed_m_per_s(:);
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

function limit = extend_sampled_radial_limit(limit, meanData, ci95Data)
    upper = limit(2);
    for index = 1:numel(meanData)
        meanS = meanData{index};
        ci95S = ci95Data{index};
        if isempty(meanS) || isempty(ci95S)
            continue;
        end
        values = meanS.phase_speed_m_per_s;
        ci95 = ci95S.phase_speed_m_per_s;
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
