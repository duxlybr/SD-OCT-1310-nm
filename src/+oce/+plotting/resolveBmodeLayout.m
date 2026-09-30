function selection = resolveBmodeLayout(geometry, lateralSampleCount, mode)
%RESOLVEBMODELAYOUT Resolve stable preview or complete B-mode mosaics.

    required = {'bmode_count', 'samples_per_bmode', 'bmode_scan_width_mm'};
    if ~isstruct(geometry) || any(~isfield(geometry, required))
        error('OCE:Plotting:InvalidPreviewGeometry', ...
            'Canonical acquisition geometry is incomplete.');
    end
    bmodeCount = validate_positive_integer( ...
        geometry.bmode_count, 'bmode_count');
    samplesPerBmode = validate_positive_integer( ...
        geometry.samples_per_bmode, 'samples_per_bmode');
    if ~isnumeric(lateralSampleCount) || ~isscalar(lateralSampleCount) || ...
            lateralSampleCount ~= samplesPerBmode * bmodeCount
        error('OCE:Plotting:InvalidPreviewGeometry', ...
            ['Lateral sample count does not match bmode_count * ' ...
             'samples_per_bmode.']);
    end
    if ~isnumeric(geometry.bmode_scan_width_mm) || ...
            ~isscalar(geometry.bmode_scan_width_mm) || ...
            ~isfinite(geometry.bmode_scan_width_mm) || ...
            geometry.bmode_scan_width_mm <= 0
        error('OCE:Plotting:InvalidPreviewGeometry', ...
            'geometry.bmode_scan_width_mm must be positive and finite.');
    end
    if ~(ischar(mode) || (isstring(mode) && isscalar(mode)))
        error('OCE:Plotting:InvalidBmodeMode', ...
            'BmodeMode must be "representative" or "all".');
    end
    mode = lower(string(mode));
    anglesDeg = (0:bmodeCount - 1) * (180 / bmodeCount);
    switch mode
        case "representative"
            selectedIndices = representative_indices(anglesDeg);
            rowCount = 1;
            columnCount = numel(selectedIndices);
        case "all"
            selectedIndices = 1:bmodeCount;
            columnCount = min(4, bmodeCount);
            rowCount = ceil(bmodeCount / columnCount);
        otherwise
            error('OCE:Plotting:InvalidBmodeMode', ...
                'BmodeMode must be "representative" or "all".');
    end

    ranges = zeros(numel(selectedIndices), 2);
    for index = 1:numel(selectedIndices)
        first = (selectedIndices(index) - 1) * samplesPerBmode + 1;
        ranges(index, :) = [first, first + samplesPerBmode - 1];
    end

    selection = struct( ...
        'mode', mode, ...
        'indices', selectedIndices, ...
        'angles_deg', anglesDeg(selectedIndices), ...
        'global_lateral_ranges', ranges, ...
        'samples_per_bmode', samplesPerBmode, ...
        'local_lateral_axis_mm', linspace(0, ...
            double(geometry.bmode_scan_width_mm), ...
            samplesPerBmode), ...
        'row_count', rowCount, ...
        'column_count', columnCount);
end

function indices = representative_indices(anglesDeg)
    bmodeCount = numel(anglesDeg);
    targetCount = min(2, bmodeCount);
    targetsDeg = [0 90];
    indices = zeros(1, targetCount);
    for targetIndex = 1:targetCount
        [~, indices(targetIndex)] = min(abs( ...
            anglesDeg - targetsDeg(targetIndex)));
    end
    if targetCount == 2 && indices(2) == indices(1)
        alternatives = setdiff(1:bmodeCount, indices(1), 'stable');
        [~, localIndex] = min(abs(anglesDeg(alternatives) - 90));
        indices(2) = alternatives(localIndex);
    end
end

function value = validate_positive_integer(value, label)
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
            value < 1 || value ~= round(value)
        error('OCE:Plotting:InvalidPreviewGeometry', ...
            '%s must be a positive finite integer.', label);
    end
    value = double(value);
end
