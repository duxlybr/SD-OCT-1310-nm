function [figures, fileNames] = plotPhaseSpeedVsFrequencyByScanAxis(experiment)
%PLOTPHASESPEEDVSFREQUENCYBYSCANAXIS Render experiment-level scan-axis curves.
%
% One figure is produced per scan axis. Quasi-harmonic summaries use the
% experimental frequency dimension. Aligned broadband summaries use the paired
% scan-axis dispersion curves. All figures share one robust display limit.

    validate_input(experiment);

    if has_scan_axis_dispersion(experiment)
        [figures, fileNames] = plot_dispersion_summary(experiment);
        return;
    end

    groupKeys = string(experiment.design.group_keys);
    dimensionValues = experiment.design.dimension_values;
    nGroupDims = numel(groupKeys);
    frequencyDim = require_dimension(groupKeys, "frequency_Hz");
    strainDim = require_dimension(groupKeys, "strain_percent");
    otherDims = setdiff(1:nGroupDims, [frequencyDim strainDim], 'stable');

    frequencyValues = numeric_values(dimensionValues{frequencyDim}, 'frequency_Hz');
    strainValues = numeric_values(dimensionValues{strainDim}, 'strain_percent');
    [frequencyPlot, frequencyOrder] = sort(frequencyValues);

    scanAxisSummary = experiment.summary.scan_axis;
    meanData = scanAxisSummary.mean_data;
    ci95Data = scanAxisSummary.ci95_data;
    scanAxisIndices = scanAxisSummary.indices(:);
    sharedYLimit = resolveSummaryPhaseSpeedLimit( ...
        experiment, "target", "scan_axis");

    otherSizes = cellfun(@numel, dimensionValues(otherDims));
    if isempty(otherDims)
        nOtherGroups = 1;
    else
        nOtherGroups = prod(otherSizes);
    end

    figures = gobjects(0, 1);
    fileNames = strings(0, 1);

    for groupIndex = 1:nOtherGroups
        idxBase = cell(1, nGroupDims);
        if ~isempty(otherDims)
            otherIndex = cell(1, numel(otherDims));
            [otherIndex{:}] = ind2sub(otherSizes, groupIndex);
            for index = 1:numel(otherDims)
                idxBase{otherDims(index)} = otherIndex{index};
            end
        end

        [conditionTitle, conditionFile] = oce.results.formatConditionLabel( ...
            groupKeys, dimensionValues(1:nGroupDims), idxBase, otherDims);

        for scanAxisPosition = 1:numel(scanAxisIndices)
            scanAxis = scanAxisIndices(scanAxisPosition);
            meanMatrix = NaN(numel(frequencyValues), numel(strainValues));
            ci95Matrix = NaN(size(meanMatrix));

            for strainIndex = 1:numel(strainValues)
                for frequencyIndex = 1:numel(frequencyValues)
                    idxCell = idxBase;
                    idxCell{strainDim} = strainIndex;
                    idxCell{frequencyDim} = frequencyIndex;
                    meanS = meanData{idxCell{:}};
                    ci95S = ci95Data{idxCell{:}};
                    if isempty(meanS)
                        continue;
                    end
                    meanMatrix(frequencyIndex, strainIndex) = ...
                        meanS.phase_speed_m_per_s(scanAxisPosition);
                    ci95Matrix(frequencyIndex, strainIndex) = ...
                        ci95S.phase_speed_m_per_s(scanAxisPosition);
                end
            end

            meanMatrix = meanMatrix(frequencyOrder, :);
            ci95Matrix = ci95Matrix(frequencyOrder, :);

            figHandle = figure('MenuBar', 'figure', 'ToolBar', 'figure', ...
                'Color', 'w');
            hold on;
            for strainIndex = 1:numel(strainValues)
                errorbar(frequencyPlot, meanMatrix(:, strainIndex), ...
                    ci95Matrix(:, strainIndex), '-o', ...
                    'LineWidth', 1.5, 'MarkerSize', 5, ...
                    'DisplayName', sprintf('Strain %g%%', ...
                        strainValues(strainIndex)));
            end

            xlabel('Frequency (Hz)');
            ylabel('Phase speed (m/s)');
            ylim(sharedYLimit);
            grid on;
            legend('Location', 'best');

            titleText = sprintf('Scan axis %d - Phase speed vs frequency - 95%% CI', ...
                scanAxis);
            fileText = "PhaseSpeedVsFrequency_ScanAxis" + string(scanAxis);
            if ~isempty(otherDims) && conditionTitle ~= "All conditions"
                titleText = sprintf('%s - %s', conditionTitle, titleText);
                fileText = fileText + "_" + conditionFile;
            end
            title(titleText);
            hold off;

            figures(end + 1, 1) = figHandle; %#ok<AGROW>
            fileNames(end + 1, 1) = fileText; %#ok<AGROW>
        end
    end
end

function tf = has_scan_axis_dispersion(experiment)
    tf = isfield(experiment.summary.scan_axis, 'dispersion_frequency_axis_hz');
end

function [figures, fileNames] = plot_dispersion_summary(experiment)
    groupKeys = string(experiment.design.group_keys);
    dimensionValues = experiment.design.dimension_values;
    nGroupDims = numel(groupKeys);
    scanAxisSummary = experiment.summary.scan_axis;
    frequencyHz = double(scanAxisSummary.dispersion_frequency_axis_hz(:));
    meanData = scanAxisSummary.mean_data;
    ci95Data = scanAxisSummary.ci95_data;
    scanAxisIndices = scanAxisSummary.indices(:);
    sharedYLimit = resolveSummaryPhaseSpeedLimit( ...
        experiment, "dispersion", "scan_axis");

    [frequencyPlot, frequencyOrder] = sort(frequencyHz);
    meanSize = size(meanData);
    figures = gobjects(0, 1);
    fileNames = strings(0, 1);

    for scanAxisPosition = 1:numel(scanAxisIndices)
        figHandle = figure('MenuBar', 'figure', 'ToolBar', 'figure', ...
            'Color', 'w');
        ax = axes(figHandle);
        hold(ax, 'on');
        colors = colororder(ax);
        curveCount = 0;

        for conditionIndex = 1:numel(meanData)
            meanS = meanData{conditionIndex};
            ci95S = ci95Data{conditionIndex};
            if isempty(meanS) || isempty(ci95S) || ...
                    ~isfield(meanS, 'dispersion_phase_speed_m_per_s') || ...
                    ~isfield(ci95S, 'dispersion_phase_speed_m_per_s')
                continue;
            end

            idxFull = cell(1, numel(meanSize));
            [idxFull{:}] = ind2sub(meanSize, conditionIndex);
            idxCell = idxFull(1:nGroupDims);
            [curveTitle, ~] = oce.results.formatConditionLabel( ...
                groupKeys, dimensionValues(1:nGroupDims), idxCell, 1:nGroupDims);

            meanCurve = meanS.dispersion_phase_speed_m_per_s( ...
                scanAxisPosition, frequencyOrder)';
            ci95Curve = ci95S.dispersion_phase_speed_m_per_s( ...
                scanAxisPosition, frequencyOrder)';
            curveCount = curveCount + 1;
            color = colors(mod(curveCount - 1, size(colors, 1)) + 1, :);
            validCi = isfinite(meanCurve) & isfinite(ci95Curve);
            if nnz(validCi) >= 2
                upper = meanCurve(validCi) + ci95Curve(validCi);
                lower = meanCurve(validCi) - ci95Curve(validCi);
                fill(ax, [frequencyPlot(validCi); flipud(frequencyPlot(validCi))], ...
                    [upper; flipud(lower)], color, ...
                    'FaceAlpha', 0.15, 'EdgeColor', 'none', ...
                    'HandleVisibility', 'off');
            end
            plot(ax, frequencyPlot, meanCurve, 'LineWidth', 1.6, ...
                'Color', color, 'DisplayName', char(curveTitle));
        end

        if curveCount == 0
            close(figHandle);
            continue;
        end

        xlabel(ax, 'Frequency (Hz)');
        ylabel(ax, 'Phase speed (m/s)');
        ylim(ax, sharedYLimit);
        grid(ax, 'on');
        legend(ax, 'show', 'Location', 'best');
        scanAxis = scanAxisIndices(scanAxisPosition);
        title(ax, sprintf('Scan axis %d - Phase speed vs frequency - 95%% CI', ...
            scanAxis));
        hold(ax, 'off');

        figures(end + 1, 1) = figHandle; %#ok<AGROW>
        fileNames(end + 1, 1) = ...
            "PhaseSpeedVsFrequency_ScanAxis" + string(scanAxis); %#ok<AGROW>
    end
end

function validate_input(experiment)
    if ~isfield(experiment, 'design') || ...
            ~isfield(experiment.design, 'group_keys') || ...
            ~isfield(experiment.design, 'dimension_values')
        error('Experiment design metadata is incomplete.');
    end
    if ~isfield(experiment, 'summary') || ...
            ~isfield(experiment.summary, 'scan_axis') || ...
            ~isfield(experiment.summary.scan_axis, 'mean_data') || ...
            ~isfield(experiment.summary.scan_axis, 'ci95_data')
        error(['Scan-axis summary not found. Run ' ...
            'oce.results.summarizeScanAxes first.']);
    end
end

function index = require_dimension(groupKeys, key)
    index = find(groupKeys == key, 1);
    if isempty(index)
        error('Required experiment-summary dimension not found: %s.', key);
    end
end

function values = numeric_values(rawValues, key)
    values = NaN(numel(rawValues), 1);
    for index = 1:numel(rawValues)
        values(index) = str2double(string(rawValues{index}));
        if ~isfinite(values(index))
            error('%s must contain numeric values for plotting.', key);
        end
    end
end
