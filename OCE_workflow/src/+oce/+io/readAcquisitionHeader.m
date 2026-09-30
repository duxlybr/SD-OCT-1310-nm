function scanInfo = readAcquisitionHeader(filename, filepath)
%READACQUISITIONHEADER Read and normalize one OCT/OCE binary header.
% Supported binary families converge on the same canonical acquisition
% dimensions. Raw samples are not loaded.

    if nargin < 1 || isempty(filename)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'filename is required.');
    end
    if nargin < 2 || isempty(filepath)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'filepath is required.');
    end

    fullPath = fullfile(char(filepath), char(filename));
    fileID = fopen(fullPath, 'r');
    if fileID == -1
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Failed to open acquisition file: %s', fullPath);
    end
    cleanup = onCleanup(@() fclose(fileID));

    magic = fread(fileID, 8, '*uint8')';
    if isequal(magic, octoce_raw_v1_magic())
        scanInfo = build_octoce_raw_v1_scan_info(fileID, fullPath);
    else
        if fseek(fileID, 0, 'bof') ~= 0
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'Failed to rewind the binary header in: %s', fullPath);
        end
        headerLength = fread(fileID, 1, 'uint16');
        if isempty(headerLength) || ~isfinite(headerLength) || ...
                headerLength <= 0 || headerLength ~= round(headerLength)
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'Invalid binary header length in: %s', fullPath);
        end

        if fseek(fileID, 4, 'bof') ~= 0
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'Failed to seek to the binary header in: %s', fullPath);
        end

        headerText = fread(fileID, headerLength, '*char')';
        if numel(headerText) ~= headerLength
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'Incomplete binary header in: %s', fullPath);
        end

        [payloadOffset, payloadBytes] = payload_details( ...
            fileID, headerLength, fullPath);
        fields = parse_header_fields(headerText, fullPath);
        family = detect_header_family(fields, fullPath);
        switch family
            case "historical_full"
                scanInfo = build_historical_scan_info( ...
                    fields, payloadOffset, payloadBytes, fullPath);
            case "compact"
                scanInfo = build_compact_scan_info( ...
                    fields, payloadOffset, payloadBytes, fullPath);
        end
    end
    scanInfo = apply_scan_type_dimensions(scanInfo);
    scanInfo = classify_payload_remainder(scanInfo);
    validate_scan_info(scanInfo, fullPath);
    clear cleanup
end

function magic = octoce_raw_v1_magic()
    magic = uint8(['OCTOCE1' char(0)]);
end

function scanInfo = build_octoce_raw_v1_scan_info(fileID, fullPath)
    jsonOffset = 64;
    jsonLength = read_uint32_le(fileID, 20, ...
        'JSON header length', fullPath);
    payloadOffset = read_uint32_le(fileID, 28, ...
        'payload offset', fullPath);
    fileBytes = acquisition_file_size(fileID, fullPath);

    if jsonLength <= 0 || jsonLength ~= round(jsonLength) || ...
            payloadOffset < jsonOffset + jsonLength || ...
            payloadOffset > fileBytes
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Invalid OCTOCE raw v1 header boundaries in: %s', fullPath);
    end
    if fseek(fileID, jsonOffset, 'bof') ~= 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Failed to seek to the OCTOCE JSON header in: %s', fullPath);
    end
    jsonBytes = fread(fileID, jsonLength, '*uint8')';
    if numel(jsonBytes) ~= jsonLength
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Incomplete OCTOCE JSON header in: %s', fullPath);
    end
    try
        source = jsondecode(native2unicode(jsonBytes, 'UTF-8'));
    catch exception
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Invalid OCTOCE JSON header in %s: %s', ...
            fullPath, exception.message);
    end
    validate_octoce_raw_v1_source(source, payloadOffset, fullPath);

    scan = source.scan;
    hardware = source.hardware;
    spectralCount = json_positive_integer( ...
        hardware, 'spectral_samples', 'hardware.spectral_samples', fullPath);
    temporalCount = json_positive_integer( ...
        scan, 'm_repetitions', 'scan.m_repetitions', fullPath);
    samplesPerBmode = json_positive_integer( ...
        scan, 'alines', 'scan.alines', fullPath);
    bmodeCount = json_positive_integer( ...
        scan, 'bscans', 'scan.bscans', fullPath);
    xWidthMm = json_nonnegative_scalar( ...
        scan, 'x_length_mm', 'scan.x_length_mm', fullPath);
    yWidthMm = json_nonnegative_scalar( ...
        scan, 'y_length_mm', 'scan.y_length_mm', fullPath);
    pattern = json_text_scalar(scan, 'pattern', 'scan.pattern', fullPath);
    createdUtc = json_text_scalar( ...
        source, 'created_utc', 'created_utc', fullPath);

    plannedShape = source.planned_shape;
    if ~isnumeric(plannedShape) || numel(plannedShape) ~= 4 || ...
            any(~isfinite(plannedShape), 'all')
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE planned_shape must contain four finite values in: %s', ...
            fullPath);
    end
    plannedShape = double(plannedShape(:).');
    expectedShape = [bmodeCount, samplesPerBmode, temporalCount, spectralCount];
    if ~isequal(plannedShape, expectedShape)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            ['OCTOCE planned_shape does not match scan/hardware metadata ' ...
             'in: %s'], fullPath);
    end

    payloadBytes = fileBytes - payloadOffset;
    if payloadBytes < 0 || mod(payloadBytes, 2) ~= 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE payload is not an exact uint16 array in: %s', fullPath);
    end
    binaryFormat = binary_format("octoce_raw_v1", ...
        "spectral_time_local_lateral_bmode", payloadOffset, payloadBytes, ...
        spectralCount, temporalCount, samplesPerBmode, bmodeCount, "header");
    binaryFormat.format_version = string(source.format_version);
    binaryFormat.json_header_offset_bytes = jsonOffset;
    binaryFormat.json_header_length_bytes = jsonLength;
    binaryFormat.payload_dtype = string(source.dtype);
    binaryFormat.axis_order = reshape(string(source.axis_order), 1, []);
    binaryFormat.storage_layout = string(source.raw_storage.layout);

    scanInfo = struct( ...
        'acquisition_datetime', char(createdUtc), ...
        'samples_in_Aline', spectralCount, ...
        'pattern_control', char(pattern), ...
        'type', char(pattern), ...
        'Alines_in_Bframe', temporalCount, ...
        'Bframes_in_3Dscan', samplesPerBmode, ...
        'No_3Dscans', bmodeCount, ...
        'Hor_scan_length_mm', xWidthMm, ...
        'Ver_scan_length_mm', yWidthMm, ...
        'binary_format', binaryFormat);

    scanInfo.bscan_length_mm = octoce_bscan_lengths( ...
        scan, pattern, bmodeCount, xWidthMm, yWidthMm, fullPath);
    if isfield(scan, 'raster_bidirectional')
        bidirectional = scan.raster_bidirectional;
        if ~islogical(bidirectional) || ~isscalar(bidirectional)
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'OCTOCE field scan.raster_bidirectional must be boolean in: %s', ...
                fullPath);
        end
        scanInfo.raster_bidirectional = bidirectional;
    end
end

function lengths = octoce_bscan_lengths(scan, pattern, bmodeCount, ...
        xWidthMm, yWidthMm, fullPath)
    % Physical length of each stored B-scan under the OCTOCE scan planner:
    % raster lines run along x; linear lines follow their orientation;
    % meridian b spans the ellipse diameter at theta = pi*b/bscans.
    switch lower(pattern)
        case "raster"
            lengths = repmat(xWidthMm, 1, bmodeCount);
        case "linear"
            orientation = lower(json_text_scalar( ...
                scan, 'orientation', 'scan.orientation', fullPath));
            switch orientation
                case "horizontal"
                    lengths = repmat(xWidthMm, 1, bmodeCount);
                case "vertical"
                    lengths = repmat(yWidthMm, 1, bmodeCount);
                otherwise
                    error('OCE:IO:InvalidAcquisitionHeader', ...
                        'Unsupported OCTOCE scan.orientation "%s" in: %s', ...
                        orientation, fullPath);
            end
        case "meridians"
            theta = pi * (0:bmodeCount - 1) / bmodeCount;
            lengths = hypot(xWidthMm * cos(theta), yWidthMm * sin(theta));
        otherwise
            % No single-line length is defined (e.g. crosshair sweeps).
            lengths = NaN(1, bmodeCount);
    end
end

function validate_octoce_raw_v1_source(source, payloadOffset, fullPath)
    required = {'axis_order', 'created_utc', 'dtype', 'format', ...
        'format_version', 'hardware', 'planned_shape', 'raw_storage', 'scan'};
    require_json_fields(source, required, 'OCTOCE root', fullPath);
    if json_text_scalar(source, 'format', 'format', fullPath) ~= ...
            "OCT/OCE raw acquisition" || ...
            json_text_scalar(source, 'format_version', ...
                'format_version', fullPath) ~= "1.0" || ...
            json_text_scalar(source, 'dtype', 'dtype', fullPath) ~= "<u2"
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Unsupported OCTOCE raw acquisition format in: %s', fullPath);
    end

    axisOrder = reshape(string(source.axis_order), 1, []);
    expectedAxisOrder = ["bscan", "aline", "m_repetition", "pixel"];
    if ~isequal(axisOrder, expectedAxisOrder)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Unsupported OCTOCE axis_order in: %s', fullPath);
    end

    require_json_fields(source.raw_storage, ...
        {'data_offset_bytes', 'layout'}, 'raw_storage', fullPath);
    dataOffset = json_positive_integer(source.raw_storage, ...
        'data_offset_bytes', 'raw_storage.data_offset_bytes', fullPath);
    storageLayout = json_text_scalar(source.raw_storage, ...
        'layout', 'raw_storage.layout', fullPath);
    if dataOffset ~= payloadOffset || ...
            storageLayout ~= "C-order, contiguous, no sync samples"
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Unsupported OCTOCE raw storage contract in: %s', fullPath);
    end

    require_json_fields(source.hardware, {'spectral_samples'}, ...
        'hardware', fullPath);
    require_json_fields(source.scan, ...
        {'alines', 'bscans', 'm_repetitions', 'pattern', ...
         'x_length_mm', 'y_length_mm'}, 'scan', fullPath);
end

function value = read_uint32_le(fileID, offset, label, fullPath)
    if fseek(fileID, offset, 'bof') ~= 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Failed to seek to OCTOCE %s in: %s', label, fullPath);
    end
    value = fread(fileID, 1, 'uint32=>double', 0, 'ieee-le');
    if isempty(value) || ~isfinite(value)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Missing OCTOCE %s in: %s', label, fullPath);
    end
end

function fileBytes = acquisition_file_size(fileID, fullPath)
    if fseek(fileID, 0, 'eof') ~= 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Failed to inspect acquisition size in: %s', fullPath);
    end
    fileBytes = ftell(fileID);
    if fileBytes < 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Failed to inspect acquisition size in: %s', fullPath);
    end
    fileBytes = double(fileBytes);
end

function require_json_fields(source, names, label, fullPath)
    if ~isstruct(source) || ~isscalar(source)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE %s must be a scalar object in: %s', label, fullPath);
    end
    missing = names(~isfield(source, names));
    if ~isempty(missing)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE %s is missing field(s) %s in: %s', ...
            label, strjoin(missing, ', '), fullPath);
    end
end

function value = json_text_scalar(source, name, label, fullPath)
    if ~isstruct(source) || ~isscalar(source) || ~isfield(source, name)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE field %s is missing in: %s', label, fullPath);
    end
    raw = source.(name);
    if ~(ischar(raw) || (isstring(raw) && isscalar(raw)))
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE field %s must be text in: %s', label, fullPath);
    end
    value = strtrim(string(raw));
    if ismissing(value) || strlength(value) == 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE field %s must not be empty in: %s', label, fullPath);
    end
end

function value = json_positive_integer(source, name, label, fullPath)
    value = json_numeric_scalar(source, name, label, fullPath);
    if value <= 0 || value ~= round(value)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE field %s must be a positive integer in: %s', ...
            label, fullPath);
    end
end

function value = json_nonnegative_scalar(source, name, label, fullPath)
    value = json_numeric_scalar(source, name, label, fullPath);
    if value < 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE field %s must be nonnegative in: %s', label, fullPath);
    end
end

function value = json_numeric_scalar(source, name, label, fullPath)
    if ~isstruct(source) || ~isscalar(source) || ~isfield(source, name)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE field %s is missing in: %s', label, fullPath);
    end
    value = source.(name);
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'OCTOCE field %s must be a finite numeric scalar in: %s', ...
            label, fullPath);
    end
    value = double(value);
end

function [payloadOffset, payloadBytes] = payload_details( ...
        fileID, headerLength, fullPath)
    payloadOffset = 4 + double(headerLength);
    fileBytes = acquisition_file_size(fileID, fullPath);
    payloadBytes = fileBytes - payloadOffset;
    if payloadBytes < 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Binary header exceeds the acquisition file size in: %s', ...
            fullPath);
    end
end

function fields = parse_header_fields(headerText, fullPath)
    records = regexp(headerText, '\r\n|\r|\n', 'split');
    fields = struct();
    for index = 1:numel(records)
        record = strtrim(records{index});
        if isempty(record)
            continue;
        end
        delimiter = strfind(record, ':');
        if isempty(delimiter)
            continue;
        end
        delimiter = delimiter(1);
        label = strtrim(record(1:delimiter - 1));
        value = strtrim(record(delimiter + 1:end));
        if endsWith(value, ';')
            value = strtrim(value(1:end - 1));
        end
        name = canonical_field_name(label);
        if isempty(name)
            continue;
        end
        if isfield(fields, name)
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'Duplicate binary header field %s in: %s', label, fullPath);
        end
        fields.(name) = value;
    end
end

function name = canonical_field_name(label)
    switch label
        case {'Date/Time scan acquisition start', 'acquisition_datetime'}
            name = 'acquisition_datetime';
        case {'Sample trigger source', 'sample_trigger_source'}
            name = 'sample_trigger_source';
        case {'Sample Rate (MHz)', 'sample_rate_MHz'}
            name = 'sample_rate_MHz';
        case {'# spectral samples per A-line', 'samples_in_Aline'}
            name = 'samples_in_Aline';
        case {'# pre-trigger samples', 'pre_trigger_samples'}
            name = 'pre_trigger_samples';
        case {'Scan pattern control', 'pattern_control'}
            name = 'pattern_control';
        case {'Scan type', 'type'}
            name = 'type';
        case {'A-lines per B-frame', 'Alines_in_Bframe'}
            name = 'Alines_in_Bframe';
        case {'Flyback duration in # A-lines', 'Flyback_Aline_No'}
            name = 'Flyback_Aline_No';
        case {'B-frame trigger delay in # A-lines', ...
                'Bframe_trigger_Aline_delay'}
            name = 'Bframe_trigger_Aline_delay';
        case {'# of B-frames in 3D scan', 'Bframes_in_3Dscan'}
            name = 'Bframes_in_3Dscan';
        case {'# of 3D repeated scans', 'No_3Dscans'}
            name = 'No_3Dscans';
        case {'Horizontal scan length (mm)', 'Hor_scan_length_mm'}
            name = 'Hor_scan_length_mm';
        case {'Vertical scan length (mm)', 'Ver_scan_length_mm'}
            name = 'Ver_scan_length_mm';
        case {'Background subtraction', 'use_background_scan'}
            name = 'use_background_scan';
        case {'Concurrent reference MZI', 'use_reference_MZI_scan'}
            name = 'use_reference_MZI_scan';
        case {'Dual edge k-clock sampling (if used)', ...
                'use_dual_edge_sampling_if_external'}
            name = 'use_dual_edge_sampling_if_external';
        case {'Max A-lines per buffer', 'Max_Alines_in_buffer'}
            name = 'Max_Alines_in_buffer';
        case {'Is calibration scan ON', 'Is_Calib_on'}
            name = 'Is_Calib_on';
        case {'Number of calibration steps', 'No_calib_scan'}
            name = 'No_calib_scan';
        otherwise
            name = '';
    end
end

function family = detect_header_family(fields, fullPath)
    fullOnly = {'sample_rate_MHz', 'pattern_control', ...
        'use_reference_MZI_scan', ...
        'use_dual_edge_sampling_if_external', ...
        'Max_Alines_in_buffer', 'Is_Calib_on', 'No_calib_scan'};
    if any(isfield(fields, fullOnly))
        family = "historical_full";
        return;
    end
    compactSignature = {'acquisition_datetime', ...
        'sample_trigger_source', 'samples_in_Aline'};
    if all(isfield(fields, compactSignature))
        family = "compact";
        return;
    end
    error('OCE:IO:InvalidAcquisitionHeader', ...
        'Unrecognized binary header family in: %s', fullPath);
end

function scanInfo = build_historical_scan_info( ...
        fields, payloadOffset, payloadBytes, fullPath)
    required = {'acquisition_datetime', 'sample_trigger_source', ...
        'sample_rate_MHz', 'samples_in_Aline', 'pre_trigger_samples', ...
        'pattern_control', 'type', 'Alines_in_Bframe', ...
        'Flyback_Aline_No', 'Bframe_trigger_Aline_delay', ...
        'Bframes_in_3Dscan', 'No_3Dscans', 'Hor_scan_length_mm', ...
        'Ver_scan_length_mm', 'use_background_scan', ...
        'use_reference_MZI_scan', ...
        'use_dual_edge_sampling_if_external', ...
        'Max_Alines_in_buffer', 'Is_Calib_on', 'No_calib_scan'};
    require_fields(fields, required, "historical_full", fullPath);

    reportedSamples = numeric_field(fields, 'samples_in_Aline');
    reportedBframes = numeric_field(fields, 'Bframes_in_3Dscan');
    reportedScans = numeric_field(fields, 'No_3Dscans');
    binaryFormat = binary_format("historical_full", ...
        "spectral_time_local_lateral_bmode", payloadOffset, payloadBytes, ...
        reportedSamples, numeric_field(fields, 'Alines_in_Bframe'), ...
        reportedBframes, reportedScans, "header");
    scanInfo = struct( ...
        'acquisition_datetime', fields.acquisition_datetime, ...
        'sample_trigger_source', fields.sample_trigger_source, ...
        'sample_rate_MHz', numeric_field(fields, 'sample_rate_MHz'), ...
        'samples_in_Aline', reportedSamples, ...
        'pre_trigger_samples', numeric_field(fields, 'pre_trigger_samples'), ...
        'pattern_control', fields.pattern_control, ...
        'type', fields.type, ...
        'Alines_in_Bframe', numeric_field(fields, 'Alines_in_Bframe'), ...
        'Flyback_Aline_No', numeric_field(fields, 'Flyback_Aline_No'), ...
        'Bframe_trigger_Aline_delay', ...
            numeric_field(fields, 'Bframe_trigger_Aline_delay'), ...
        'Bframes_in_3Dscan', reportedBframes, ...
        'No_3Dscans', reportedScans, ...
        'Hor_scan_length_mm', numeric_field(fields, 'Hor_scan_length_mm'), ...
        'Ver_scan_length_mm', numeric_field(fields, 'Ver_scan_length_mm'), ...
        'use_background_scan', ...
            numeric_field(fields, 'use_background_scan'), ...
        'use_reference_MZI_scan', ...
            numeric_field(fields, 'use_reference_MZI_scan'), ...
        'use_dual_edge_sampling_if_external', ...
            numeric_field(fields, 'use_dual_edge_sampling_if_external'), ...
        'Max_Alines_in_buffer', ...
            numeric_field(fields, 'Max_Alines_in_buffer'), ...
        'Is_Calib_on', numeric_field(fields, 'Is_Calib_on'), ...
        'No_calib_scan', numeric_field(fields, 'No_calib_scan'), ...
        'binary_format', binaryFormat);
end

function scanInfo = build_compact_scan_info( ...
        fields, payloadOffset, payloadBytes, fullPath)
    required = {'acquisition_datetime', 'sample_trigger_source', ...
        'samples_in_Aline', 'pre_trigger_samples', 'type', ...
        'Alines_in_Bframe', 'Flyback_Aline_No', ...
        'Bframe_trigger_Aline_delay', 'Bframes_in_3Dscan', ...
        'No_3Dscans', 'Hor_scan_length_mm', 'Ver_scan_length_mm', ...
        'use_background_scan'};
    require_fields(fields, required, "compact", fullPath);

    temporalCount = numeric_field(fields, 'Alines_in_Bframe');
    reportedBmodeCount = numeric_field(fields, 'Bframes_in_3Dscan');
    reportedSamplesPerBmode = numeric_field(fields, 'No_3Dscans');
    validate_positive_integers([temporalCount, reportedBmodeCount, ...
        reportedSamplesPerBmode], {'Alines_in_Bframe', 'Bframes_in_3Dscan', ...
        'No_3Dscans'}, fullPath);
    reportedSamples = numeric_field(fields, 'samples_in_Aline');
    [effectiveSamples, sampleSource] = resolve_compact_samples( ...
        reportedSamples, temporalCount, reportedBmodeCount, ...
        reportedSamplesPerBmode, payloadBytes, fullPath);
    binaryFormat = binary_format("compact", ...
        "spectral_time_local_lateral_bmode", payloadOffset, payloadBytes, ...
        reportedSamples, temporalCount, reportedBmodeCount, ...
        reportedSamplesPerBmode, sampleSource);

    scanInfo = struct( ...
        'acquisition_datetime', fields.acquisition_datetime, ...
        'sample_trigger_source', fields.sample_trigger_source, ...
        'samples_in_Aline', effectiveSamples, ...
        'pre_trigger_samples', numeric_field(fields, 'pre_trigger_samples'), ...
        'pattern_control', '', ...
        'type', fields.type, ...
        'Alines_in_Bframe', temporalCount, ...
        'Flyback_Aline_No', numeric_field(fields, 'Flyback_Aline_No'), ...
        'Bframe_trigger_Aline_delay', ...
            numeric_field(fields, 'Bframe_trigger_Aline_delay'), ...
        'Bframes_in_3Dscan', reportedSamplesPerBmode, ...
        'No_3Dscans', reportedBmodeCount, ...
        'Hor_scan_length_mm', numeric_field(fields, 'Hor_scan_length_mm'), ...
        'Ver_scan_length_mm', numeric_field(fields, 'Ver_scan_length_mm'), ...
        'use_background_scan', ...
            numeric_field(fields, 'use_background_scan'), ...
        'binary_format', binaryFormat);
end

function [samples, source] = resolve_compact_samples( ...
        reported, temporalCount, bmodeCount, samplesPerBmode, ...
        payloadBytes, fullPath)
    if payloadBytes < 0 || mod(payloadBytes, 2) ~= 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Compact acquisition payload is not an exact uint16 array: %s', ...
            fullPath);
    end
    payloadCount = payloadBytes / 2;
    nonSpectralCount = temporalCount * bmodeCount * samplesPerBmode;
    reportedIsValid = is_positive_integer(reported);
    if reportedIsValid && reported * nonSpectralCount == payloadCount
        samples = reported;
        source = "header";
        return;
    end

    inferred = payloadCount / nonSpectralCount;
    if ~is_positive_integer(inferred)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            ['Compact spectral length cannot be inferred exactly from the ' ...
             'payload and reported dimensions in: %s'], fullPath);
    end
    samples = inferred;
    source = "payload_size";
end

function value = binary_format(family, sourceLayout, payloadOffset, ...
        payloadBytes, reportedSamples, reportedTemporal, ...
        reportedBframes, reportedScans, sampleSource)
    value = struct( ...
        'family', family, ...
        'source_layout', sourceLayout, ...
        'payload_offset_bytes', payloadOffset, ...
        'payload_uint16_count', payloadBytes / 2, ...
        'reported_dimensions', struct( ...
            'samples_in_Aline', reportedSamples, ...
            'Alines_in_Bframe', reportedTemporal, ...
            'Bframes_in_3Dscan', reportedBframes, ...
            'No_3Dscans', reportedScans), ...
        'samples_in_Aline_source', sampleSource);
end

function scanInfo = apply_scan_type_dimensions(scanInfo)
    switch scanInfo.type
        case 'Crosshair'
            scanInfo.Alines_in_Bframe = scanInfo.Alines_in_Bframe * 2;
        case {'3_lines', '3_lines_lowAcc'}
            scanInfo.Alines_in_Bframe = scanInfo.Alines_in_Bframe * 3;
    end
end

function scanInfo = classify_payload_remainder(scanInfo)
    expectedCount = scanInfo.samples_in_Aline * ...
        scanInfo.Alines_in_Bframe * scanInfo.Bframes_in_3Dscan * ...
        scanInfo.No_3Dscans;
    actualCount = scanInfo.binary_format.payload_uint16_count;
    trailingCount = actualCount - expectedCount;
    classification = "unexpected";
    if trailingCount < 0
        classification = "truncated";
    elseif trailingCount == 0
        classification = "none";
    elseif scanInfo.binary_format.family == "historical_full"
        % Historical reading has always stopped at the dimensions declared
        % by the full header. Preserve that accepted boundary while making
        % any unconsumed payload explicit instead of silently discarding it.
        classification = "historical_declared_dimensions_boundary";
    end
    scanInfo.binary_format.expected_payload_uint16_count = expectedCount;
    scanInfo.binary_format.trailing_payload_uint16_count = trailingCount;
    scanInfo.binary_format.trailing_payload_classification = classification;
end

function require_fields(fields, names, family, fullPath)
    missing = names(~isfield(fields, names));
    if ~isempty(missing)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            '%s binary header is missing required fields %s in: %s', ...
            family, strjoin(missing, ', '), fullPath);
    end
end

function value = numeric_field(fields, name)
    value = str2double(fields.(name));
end

function validate_positive_integers(values, names, fullPath)
    for index = 1:numel(values)
        if ~is_positive_integer(values(index))
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'Header field %s must be a positive integer in: %s', ...
                names{index}, fullPath);
        end
    end
end

function valid = is_positive_integer(value)
    valid = isnumeric(value) && isscalar(value) && isfinite(value) && ...
        value > 0 && value == round(value);
end

function validate_scan_info(scanInfo, fullPath)
    dimensionFields = { ...
        'No_3Dscans', ...
        'Bframes_in_3Dscan', ...
        'Alines_in_Bframe', ...
        'samples_in_Aline'};
    values = zeros(1, numel(dimensionFields));
    for index = 1:numel(dimensionFields)
        values(index) = scanInfo.(dimensionFields{index});
    end
    validate_positive_integers(values, dimensionFields, fullPath);

    if isempty(strtrim(scanInfo.type))
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Header type must be nonempty in: %s', fullPath);
    end
    if ~(ischar(scanInfo.pattern_control) || ...
            (isstring(scanInfo.pattern_control) && ...
             isscalar(scanInfo.pattern_control)))
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Header pattern_control must be text when reported in: %s', ...
            fullPath);
    end
end