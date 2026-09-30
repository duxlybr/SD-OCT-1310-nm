function [figures, fileNames] = plotThicknessPolarSummary(experiment)
%PLOTTHICKNESSPOLARSUMMARY Render polar thickness summaries.

    [meanData, ci95Data] = get_repetition_summary(experiment);
    [dimensionKeys, dimensionValues] = get_experiment_dimensions(experiment);

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
        theta = meanS.full_circle_angles_deg(:) * pi / 180;
        meanThickness = meanS.angular_mean_thickness_mm(:) * 1000;
        ci95Thickness = ci95S.angular_mean_thickness_mm(:) * 1000;

        figHandle = figure('MenuBar', 'figure', 'ToolBar', 'figure', ...
            'Color', 'w');
        set(figHandle, 'Position', [10, 10, 550, 400]);
        if all(isnan(meanThickness))
            ax = axes(figHandle);
            axis(ax, 'off');
            text(ax, 0.5, 0.5, 'Thickness unavailable', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'middle', 'FontSize', 14);
            title(ax, sprintf('Thickness unavailable - %s', conditionTitle));
        else
            upR = meanThickness + ci95Thickness;
            loR = meanThickness - ci95Thickness;
            thetaClosed = [theta; theta(1)];
            thicknessClosed = [meanThickness; meanThickness(1)];

            pax = polaraxes(figHandle);
            hold(pax, 'on');
            polarplot(pax, thetaClosed, thicknessClosed, '-o', ...
                'LineWidth', 1.5, 'MarkerSize', 5, ...
                'DisplayName', 'Thickness mean (µm)');

            for k = 1:numel(theta)
                if isnan(ci95Thickness(k))
                    continue;
                end
                visibility = 'off';
                if k == 1
                    visibility = 'on';
                end
                polarplot(pax, [theta(k) theta(k)], [loR(k) upR(k)], '-', ...
                    'LineWidth', 1.2, 'DisplayName', '95% CI', ...
                    'HandleVisibility', visibility);
            end

            title(pax, sprintf('Thickness (µm) - %s', conditionTitle));
            legend(pax, 'show', 'Location', 'southoutside', ...
                'Orientation', 'horizontal');
            grid(pax, 'on');
            hold(pax, 'off');
        end

        figures(end + 1, 1) = figHandle; %#ok<AGROW>
        fileNames(end + 1, 1) = "ThicknessPolar_" + string(fileTitle); %#ok<AGROW>
    end
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
