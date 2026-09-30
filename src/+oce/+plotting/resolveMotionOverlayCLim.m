function limits = resolveMotionOverlayCLim(panels, mode, configured, varargin)
%RESOLVEMOTIONOVERLAYCLIM Resolve CLim from the displayed motion signal.
% Motion overlays remove each spatial pixel's temporal mean. Optional spatial
% median denoising is visualization-only and is included before robust/auto
% limits are resolved so the scale matches the frames that are actually shown.

    parser = inputParser;
    addParameter(parser, 'MedianWindow', [], @valid_median_window);
    parse(parser, varargin{:});
    medianWindow = parser.Results.MedianWindow;

    mode = lower(strtrim(string(mode)));
    if mode == "manual"
        limits = oce.plotting.resolvePhasePreviewCLim( ...
            0, mode, configured);
        return;
    end

    if ~isstruct(panels)
        error('OCE:Plotting:InvalidMotionPanels', ...
            'Motion overlay panels must be a struct array.');
    end

    values = cell(numel(panels), 1);
    for panelIndex = 1:numel(panels)
        if ~isfield(panels(panelIndex), 'phase_values') || ...
                ~isfield(panels(panelIndex), 'visualization_mask')
            error('OCE:Plotting:InvalidMotionPanels', ...
                ['Every motion overlay panel must contain phase_values and ' ...
                 'visualization_mask.']);
        end
        current = double(panels(panelIndex).phase_values);
        mask = panels(panelIndex).visualization_mask;
        spatialSize = [size(current, 1), size(current, 2)];
        if ~islogical(mask) || ~isequal(size(mask), spatialSize)
            error('OCE:Plotting:InvalidMotionPanels', ...
                'visualization_mask must match the motion panel spatial size.');
        end
        current = current - mean(current, 3, 'omitnan');
        if ~isempty(medianWindow)
            for timeIndex = 1:size(current, 3)
                current(:, :, timeIndex) = ...
                    oce.plotting.postprocessMotionOverlayFrame( ...
                        current(:, :, timeIndex), medianWindow);
            end
        end
        excluded = repmat(~mask, 1, 1, size(current, 3));
        current(excluded) = NaN;
        values{panelIndex} = reshape(current, [], size(current, 3));
    end

    limits = oce.plotting.resolvePhasePreviewCLim(values, mode, configured);
    if ~isempty(limits)
        return;
    end

    minimumValue = Inf;
    maximumValue = -Inf;
    for index = 1:numel(values)
        finiteValues = values{index}(isfinite(values{index}));
        if ~isempty(finiteValues)
            minimumValue = min(minimumValue, min(finiteValues));
            maximumValue = max(maximumValue, max(finiteValues));
        end
    end

    if ~isfinite(minimumValue) || ~isfinite(maximumValue)
        limits = [-0.05 0.05];
        return;
    end

    limits = [minimumValue maximumValue];
    if limits(1) == limits(2)
        delta = eps(max(1, abs(limits(1))));
        limits = limits + [-delta delta];
    end
end

function tf = valid_median_window(value)
    tf = isempty(value) || (isnumeric(value) && isvector(value) && ...
        numel(value) == 2 && all(isfinite(value)) && ...
        all(value >= 1) && all(value == round(value)));
end
