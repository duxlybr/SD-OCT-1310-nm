function geometry = buildAcquisitionGeometry(rawDescriptor, scanGeometry)
%BUILDACQUISITIONGEOMETRY Interpret neutral raw dimensions as acquisition geometry.
% geometry = buildAcquisitionGeometry(rawDescriptor, scanGeometry)
%
% scanGeometry is one of:
%   "angular_bmodes" - straight B-scans through the scan center: meridians,
%                      linear lines, crosshair X/Y sweeps or a one-line raster;
%   "raster"         - parallel B-scans along x stepping along y;
%   "polar"          - closed polar turns (concentric rings or spiral turns);
%   "automatic"      - resolved from the scan pattern of an OCTOCE header.
% Headers that report their scan pattern must be compatible with the
% requested geometry. Every geometry reports the resolved scan_geometry,
% bmode_axis_angles_deg (B-scan orientation in [0, 180) deg),
% bmode_direction_deg (direction of increasing local A-line index in
% [0, 360) deg, NaN when the header does not define it) and bmode_labels for
% displays. Raster and polar geometries add enface: a sparse operator that
% maps lateral samples onto a Cartesian x/y grid (exact for raster, linear
% interpolation over the Delaunay triangulation of the polar positions).

    scanGeometry = normalize_geometry(scanGeometry);
    validate_descriptor(rawDescriptor);
    pattern = descriptor_pattern(rawDescriptor);
    samplesPerBmode = rawDescriptor.Bframes_in_3Dscan;
    bmodeCount = rawDescriptor.No_3Dscans;
    if scanGeometry == "automatic"
        scanGeometry = automatic_geometry(pattern, bmodeCount);
    end
    validate_pattern(scanGeometry, pattern, bmodeCount);

    switch scanGeometry
        case "angular_bmodes"
            bmodeWidthMm = resolve_angular_width(rawDescriptor);
            bmodeAxisMm = linspace(0, bmodeWidthMm, samplesPerBmode);
            [axisAnglesDeg, directionsDeg] = angular_directions( ...
                rawDescriptor, bmodeCount);
            geometry = base_geometry(rawDescriptor, scanGeometry, ...
                bmodeWidthMm, bmodeAxisMm, axisAnglesDeg, directionsDeg, ...
                compose("%.1f deg", axisAnglesDeg));
        case "raster"
            % One B-mode is one B-scan along x; consecutive B-modes step
            % along y. Positions follow acquisition order from 0 mm.
            [fastLengthMm, slowLengthMm] = resolve_raster_lengths(rawDescriptor);
            bmodeAxisMm = linspace(0, fastLengthMm, samplesPerBmode);
            slowAxisMm = linspace(0, slowLengthMm, bmodeCount);
            if bmodeCount == 1
                slowAxisMm = 0;
            end
            geometry = base_geometry(rawDescriptor, scanGeometry, ...
                fastLengthMm, bmodeAxisMm, zeros(1, bmodeCount), ...
                zeros(1, bmodeCount), compose("y = %.2f mm", slowAxisMm));
            geometry.raster = struct( ...
                'fast_scan_length_mm', fastLengthMm, ...
                'slow_scan_length_mm', slowLengthMm, ...
                'slow_axis_mm', slowAxisMm, ...
                'slow_sample_interval_mm', sample_interval(slowAxisMm));
            geometry.enface = raster_enface(bmodeAxisMm, slowAxisMm);
        case "polar"
            geometry = polar_geometry(rawDescriptor, pattern);
    end
end

function value = normalize_geometry(value)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('OCE:Acquisition:MissingScanGeometry', ...
            'scanGeometry must be a text scalar.');
    end
    value = lower(strtrim(string(value)));
    if ismissing(value) || strlength(value) == 0
        error('OCE:Acquisition:MissingScanGeometry', ...
            'scanGeometry must not be empty.');
    end
    if ~ismember(value, ["angular_bmodes", "raster", "polar", "automatic"])
        error('OCE:Acquisition:UnsupportedScanGeometry', ...
            'Unsupported scan geometry "%s".', value);
    end
end

function pattern = descriptor_pattern(rawDescriptor)
    % Only headers that describe each stored line (OCTOCE) carry a scan
    % pattern; historical headers describe angular B-modes implicitly.
    pattern = "";
    if isfield(rawDescriptor, 'bscan_angle_deg') && isfield(rawDescriptor, 'type')
        pattern = lower(strtrim(string(rawDescriptor.type)));
    end
end

function scanGeometry = automatic_geometry(pattern, bmodeCount)
    switch pattern
        case {"meridians", "linear", "crosshair"}
            scanGeometry = "angular_bmodes";
        case "raster"
            % A one-line raster is a single B-scan through the scan center.
            if bmodeCount == 1
                scanGeometry = "angular_bmodes";
            else
                scanGeometry = "raster";
            end
        case {"rings", "spiral"}
            scanGeometry = "polar";
        otherwise
            error('OCE:Acquisition:MissingScanGeometry', ...
                ['Automatic scan geometry needs a header that reports its ' ...
                 'scan pattern; set scan_geometry explicitly.']);
    end
end

function validate_pattern(scanGeometry, pattern, bmodeCount)
    if strlength(pattern) == 0
        if scanGeometry == "polar"
            error('OCE:Acquisition:InvalidRawDescriptor', ...
                'Polar geometry requires a header that reports rings or spiral.');
        end
        return;
    end
    switch scanGeometry
        case "angular_bmodes"
            compatible = ismember(pattern, ...
                ["meridians", "linear", "crosshair"]) || ...
                (pattern == "raster" && bmodeCount == 1);
        case "raster"
            compatible = pattern == "raster";
        case "polar"
            compatible = ismember(pattern, ["rings", "spiral"]);
    end
    if ~compatible
        error('OCE:Acquisition:UnsupportedScanGeometry', ...
            'Header scan pattern "%s" is not compatible with scan geometry "%s".', ...
            pattern, scanGeometry);
    end
end

function geometry = base_geometry(rawDescriptor, scanGeometry, widthMm, ...
        bmodeAxisMm, axisAnglesDeg, directionsDeg, labels)
    samplesPerBmode = rawDescriptor.Bframes_in_3Dscan;
    bmodeCount = rawDescriptor.No_3Dscans;
    geometry = struct( ...
        'scan_geometry', scanGeometry, ...
        'spectral_sample_count', rawDescriptor.samples_in_Aline, ...
        'temporal_repetition_count', rawDescriptor.Alines_in_Bframe, ...
        'available_depth_sample_count', ...
            floor(rawDescriptor.samples_in_Aline / 2), ...
        'lateral_sample_count', samplesPerBmode * bmodeCount, ...
        'bmode_count', bmodeCount, ...
        'samples_per_bmode', samplesPerBmode, ...
        'bmode_scan_width_mm', widthMm, ...
        'bmode_lateral_axis_mm', bmodeAxisMm, ...
        'lateral_sample_interval_mm', sample_interval(bmodeAxisMm), ...
        'bmode_axis_angles_deg', axisAnglesDeg, ...
        'bmode_direction_deg', directionsDeg, ...
        'bmode_labels', reshape(string(labels), 1, []));
end

function [axisAnglesDeg, directionsDeg] = angular_directions( ...
        rawDescriptor, bmodeCount)
    if ~isfield(rawDescriptor, 'bscan_angle_deg')
        % Historical angular headers: B-mode b (0-based) lies at 180*b/N;
        % their scan directions follow the maintained full-circle ordering.
        axisAnglesDeg = (0:bmodeCount - 1) * (180 / bmodeCount);
        directionsDeg = NaN(1, bmodeCount);
        return;
    end
    directionsDeg = double(rawDescriptor.bscan_angle_deg(:)');
    if numel(directionsDeg) ~= bmodeCount || any(~isfinite(directionsDeg))
        error('OCE:Acquisition:InvalidRawDescriptor', ...
            'rawDescriptor.bscan_angle_deg must hold one finite angle per B-scan.');
    end
    directionsDeg = mod(directionsDeg, 360);
    axisAnglesDeg = mod(directionsDeg, 180);
end

function widthMm = resolve_angular_width(rawDescriptor)
    % Historical headers record the B-mode length as the vertical scan length.
    if ~isfield(rawDescriptor, 'bscan_length_mm')
        widthMm = rawDescriptor.Ver_scan_length_mm;
        return;
    end
    widthMm = uniform_bscan_length(rawDescriptor.bscan_length_mm, ...
        rawDescriptor.No_3Dscans);
end

function [fastLengthMm, slowLengthMm] = resolve_raster_lengths(rawDescriptor)
    if ~isfield(rawDescriptor, 'bscan_length_mm') || ...
            ~isfield(rawDescriptor, 'raster_bidirectional')
        error('OCE:Acquisition:InvalidRawDescriptor', ...
            ['Raster geometry requires bscan_length_mm and ' ...
             'raster_bidirectional in the raw descriptor.']);
    end
    if ~islogical(rawDescriptor.raster_bidirectional) || ...
            ~isscalar(rawDescriptor.raster_bidirectional)
        error('OCE:Acquisition:InvalidRawDescriptor', ...
            'rawDescriptor.raster_bidirectional must be a logical scalar.');
    end
    % Bidirectional rasters are accepted because the raw reader stores every
    % line forward (bscan_storage_reversed); without that marker the odd
    % lines would still run backwards.
    if rawDescriptor.raster_bidirectional && ...
            ~isfield(rawDescriptor, 'bscan_storage_reversed')
        error('OCE:Acquisition:UnsupportedScanGeometry', ...
            'Bidirectional rasters require per-line storage direction metadata.');
    end
    fastLengthMm = uniform_bscan_length(rawDescriptor.bscan_length_mm, ...
        rawDescriptor.No_3Dscans);
    slowLengthMm = rawDescriptor.Ver_scan_length_mm;
    if rawDescriptor.No_3Dscans > 1 && ~(slowLengthMm > 0)
        error('OCE:Acquisition:InvalidRawDescriptor', ...
            'Raster slow-axis scan length must be positive.');
    end
end

function widthMm = uniform_bscan_length(lengths, bmodeCount)
    if ~isnumeric(lengths) || numel(lengths) ~= bmodeCount || ...
            any(~isfinite(lengths)) || any(lengths <= 0)
        error('OCE:Acquisition:InvalidRawDescriptor', ...
            ['rawDescriptor.bscan_length_mm must hold one positive finite ' ...
             'length per B-scan.']);
    end
    % One local lateral axis serves every B-mode, so lengths must agree
    % (meridians of an x/y ellipse or a crosshair with x ~= y are rejected).
    if max(abs(lengths - lengths(1))) > 1e-9 * max(1, lengths(1))
        error('OCE:Acquisition:UnsupportedScanGeometry', ...
            ['B-scans of unequal physical length are not supported; ' ...
             'acquire with equal x and y lengths.']);
    end
    widthMm = double(lengths(1));
end

function geometry = polar_geometry(rawDescriptor, pattern)
    % Positions follow the OCTOCE planner (header polar_geometry): A-line a of
    % turn b sits at x = rho*Lx/2*cos(theta), y = rho*Ly/2*sin(theta) from the
    % scan center. Rings: rho = (b+1)/B, theta = 2*pi*a/A. Spiral: k = b*A+a,
    % rho = k/(A*B-1), theta = 2*pi*k/A. Turns are stored a-fastest.
    samplesPerBmode = rawDescriptor.Bframes_in_3Dscan;
    bmodeCount = rawDescriptor.No_3Dscans;
    xLengthMm = double(rawDescriptor.Hor_scan_length_mm);
    yLengthMm = double(rawDescriptor.Ver_scan_length_mm);
    if ~(xLengthMm > 0 && yLengthMm > 0)
        error('OCE:Acquisition:InvalidRawDescriptor', ...
            'Polar scans require positive x and y scan lengths.');
    end
    alineIndex = 0:samplesPerBmode - 1;
    turnIndex = (0:bmodeCount - 1)';
    if pattern == "rings"
        rho = repmat((turnIndex + 1) / bmodeCount, 1, samplesPerBmode);
        theta = repmat(2 * pi * alineIndex / samplesPerBmode, bmodeCount, 1);
        labels = compose("r = %.2f mm", ...
            (turnIndex' + 1) / bmodeCount * mean([xLengthMm yLengthMm]) / 2);
    else
        k = turnIndex * samplesPerBmode + alineIndex;
        rho = k / max(1, samplesPerBmode * bmodeCount - 1);
        theta = 2 * pi * k / samplesPerBmode;
        labels = compose("turn %d", 1:bmodeCount);
    end
    x = rho .* (xLengthMm / 2) .* cos(theta);
    y = rho .* (yLengthMm / 2) .* sin(theta);
    positionsMm = [reshape(x.', [], 1), reshape(y.', [], 1)];

    % B-mode displays share one local axis: arc length on the outer turn.
    outerRadiusMm = mean([xLengthMm yLengthMm]) / 2;
    bmodeAxisMm = outerRadiusMm * 2 * pi * alineIndex / samplesPerBmode;
    geometry = base_geometry(rawDescriptor, "polar", bmodeAxisMm(end), ...
        bmodeAxisMm, NaN(1, bmodeCount), NaN(1, bmodeCount), labels);
    geometry.polar = struct( ...
        'pattern', pattern, ...
        'x_scan_length_mm', xLengthMm, ...
        'y_scan_length_mm', yLengthMm, ...
        'positions_mm', positionsMm, ...
        'radius_fraction', reshape(rho.', [], 1), ...
        'angle_rad', reshape(theta.', [], 1), ...
        'bmode_axis_quantity', "outer_turn_arc_length");
    geometry.enface = polar_enface(positionsMm, xLengthMm, yLengthMm, ...
        samplesPerBmode, bmodeCount);
end

function enface = raster_enface(xAxisMm, yAxisMm)
    % Exact placement: grid pixel (y_i, x_j) is lateral sample j of line i.
    columnCount = numel(xAxisMm);
    rowCount = numel(yAxisMm);
    [rows, columns] = ndgrid(1:rowCount, 1:columnCount);
    gridIndex = rows(:) + (columns(:) - 1) * rowCount;
    lateralIndex = columns(:) + (rows(:) - 1) * columnCount;
    enface = struct( ...
        'method', "acquired_grid", ...
        'x_axis_mm', double(xAxisMm(:)'), ...
        'y_axis_mm', double(yAxisMm(:)'), ...
        'operator', sparse(gridIndex, lateralIndex, 1, ...
            rowCount * columnCount, rowCount * columnCount), ...
        'coverage', true(rowCount, columnCount));
end

function enface = polar_enface(positionsMm, xLengthMm, yLengthMm, ...
        samplesPerBmode, bmodeCount)
    % Grid step: the finer of the radial turn spacing and the outer-turn
    % A-line spacing, capped at 801 pixels per axis.
    radialStepMm = min(xLengthMm, yLengthMm) / (2 * bmodeCount);
    arcStepMm = pi * min(xLengthMm, yLengthMm) / samplesPerBmode;
    stepMm = min(radialStepMm, arcStepMm);
    xCount = min(801, 2 * ceil(xLengthMm / (2 * stepMm)) + 1);
    yCount = min(801, 2 * ceil(yLengthMm / (2 * stepMm)) + 1);
    xAxisMm = linspace(-xLengthMm / 2, xLengthMm / 2, xCount);
    yAxisMm = linspace(-yLengthMm / 2, yLengthMm / 2, yCount);
    [gridX, gridY] = meshgrid(xAxisMm, yAxisMm);

    triangulation = delaunayTriangulation(positionsMm);
    [triangle, weights] = pointLocation(triangulation, [gridX(:), gridY(:)]);
    inside = ~isnan(triangle);
    vertices = triangulation.ConnectivityList(triangle(inside), :);
    gridIndex = repmat(find(inside), 1, 3);
    enface = struct( ...
        'method', "linear_triangulation", ...
        'x_axis_mm', xAxisMm, ...
        'y_axis_mm', yAxisMm, ...
        'operator', sparse(gridIndex(:), vertices(:), ...
            reshape(weights(inside, :), [], 1), ...
            yCount * xCount, size(positionsMm, 1)), ...
        'coverage', reshape(inside, yCount, xCount));
end

function validate_descriptor(value)
    required = ["samples_in_Aline"; "Alines_in_Bframe"; ...
        "Bframes_in_3Dscan"; "No_3Dscans"; "Ver_scan_length_mm"];
    if ~isstruct(value) || ~isscalar(value)
        error('OCE:Acquisition:InvalidRawDescriptor', ...
            'rawDescriptor must be a scalar struct.');
    end
    for index = 1:numel(required)
        name = required(index);
        if ~isfield(value, name)
            error('OCE:Acquisition:InvalidRawDescriptor', ...
                'rawDescriptor is missing required field %s.', name);
        end
    end
    positiveIntegers = ["samples_in_Aline"; "Alines_in_Bframe"; ...
        "Bframes_in_3Dscan"; "No_3Dscans"];
    for index = 1:numel(positiveIntegers)
        name = positiveIntegers(index);
        item = value.(name);
        if ~isnumeric(item) || ~isscalar(item) || ~isfinite(item) || ...
                item <= 0 || item ~= round(item)
            error('OCE:Acquisition:InvalidRawDescriptor', ...
                'rawDescriptor.%s must be a positive integer.', name);
        end
    end
    width = value.Ver_scan_length_mm;
    if ~isnumeric(width) || ~isscalar(width) || ~isfinite(width) || width < 0
        error('OCE:Acquisition:InvalidRawDescriptor', ...
            'rawDescriptor.Ver_scan_length_mm must be finite and nonnegative.');
    end
end

function interval = sample_interval(axisValues)
    if numel(axisValues) < 2
        interval = NaN;
    else
        interval = axisValues(2) - axisValues(1);
    end
end
