function geometry = buildAcquisitionGeometry(rawDescriptor, scanGeometry)
%BUILDACQUISITIONGEOMETRY Interpret neutral raw dimensions as acquisition geometry.

    scanGeometry = normalize_geometry(scanGeometry);
    validate_descriptor(rawDescriptor);

    switch scanGeometry
        case "angular_bmodes"
            samplesPerBmode = rawDescriptor.Bframes_in_3Dscan;
            bmodeCount = rawDescriptor.No_3Dscans;
            bmodeWidthMm = rawDescriptor.Ver_scan_length_mm;
            bmodeAxisMm = linspace(0, bmodeWidthMm, samplesPerBmode);
            geometry = struct( ...
                'spectral_sample_count', rawDescriptor.samples_in_Aline, ...
                'temporal_repetition_count', rawDescriptor.Alines_in_Bframe, ...
                'available_depth_sample_count', ...
                    floor(rawDescriptor.samples_in_Aline / 2), ...
                'lateral_sample_count', samplesPerBmode * bmodeCount, ...
                'bmode_count', bmodeCount, ...
                'samples_per_bmode', samplesPerBmode, ...
                'bmode_scan_width_mm', bmodeWidthMm, ...
                'bmode_lateral_axis_mm', bmodeAxisMm, ...
                'lateral_sample_interval_mm', sample_interval(bmodeAxisMm));
        case "raster"
            error('OCE:Acquisition:UnsupportedScanGeometry', ...
                ['Scan geometry "raster" is recognized by the acquisition ' ...
                 'metadata schema but its geometry builder is not implemented.']);
        otherwise
            error('OCE:Acquisition:UnsupportedScanGeometry', ...
                'Unsupported scan geometry "%s".', scanGeometry);
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
