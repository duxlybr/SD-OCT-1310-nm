function measurement = readRawAcquisition(filename, filepath, selection)
%READRAWACQUISITION Read one OCT/OCE binary acquisition without geometry intent.
% Binary-family storage is normalized to spectral_time_lateral. Samples keep
% their native uint16 digitizer counts; spectral preparation converts them to
% double exactly. Lines the header marks as stored backwards
% (bscan_storage_reversed) are put back in forward A-line order, so every
% stored line runs along its bscan_angle_deg. Experimental acquisition mode
% and scan geometry are resolved outside the I/O boundary.
% Optional selection.bmode_indices and selection.lateral_indices select
% canonical forward positions without loading the other payload. The raw
% descriptor always describes the complete file; raw_selection records the
% retained positions. This is the bounded-memory I/O boundary for rasters.

    if nargin < 1 || isempty(filename)
        error('filename is required.');
    end
    if nargin < 2 || isempty(filepath)
        error('filepath is required.');
    end
    if nargin < 3
        selection = [];
    end

    fullPath = fullfile(char(filepath), char(filename));
    rawDescriptor = oce.io.readAcquisitionHeader(filename, filepath);
    fileInfo = dir(fullPath);
    if isempty(fileInfo)
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Failed to inspect acquisition file: %s', fullPath);
    end

    samplesPerBmode = rawDescriptor.Bframes_in_3Dscan;
    temporalCount = rawDescriptor.Alines_in_Bframe;
    bmodeCount = rawDescriptor.No_3Dscans;
    spectralCount = rawDescriptor.samples_in_Aline;
    dimensions = [spectralCount, temporalCount, samplesPerBmode, bmodeCount];
    expectedCount = prod(dimensions);
    payloadOffset = rawDescriptor.binary_format.payload_offset_bytes;
    expectedFileBytes = payloadOffset + 2 * expectedCount;
    actualFileBytes = double(fileInfo.bytes);
    if actualFileBytes < expectedFileBytes
        actualPayloadCount = max(0, floor((actualFileBytes - ...
            payloadOffset) / 2));
        error('OCE:IO:IncompleteAcquisition', ...
            ['Incomplete binary acquisition: expected %d uint16 samples, ' ...
             'found %d in %s.'], expectedCount, actualPayloadCount, fullPath);
    end
    if actualFileBytes > expectedFileBytes
        trailingBytes = actualFileBytes - expectedFileBytes;
        acceptedHistoricalBoundary = ...
            rawDescriptor.binary_format.family == "historical_full" && ...
            rawDescriptor.binary_format.trailing_payload_classification == ...
                "historical_declared_dimensions_boundary";
        if ~acceptedHistoricalBoundary
            error('OCE:IO:UnexpectedAcquisitionData', ...
                ['Binary acquisition contains %d unexplained trailing ' ...
                 'byte(s) after %d expected uint16 samples in %s.'], ...
                trailingBytes, expectedCount, fullPath);
        end
    end

    fileID = fopen(fullPath, 'r');
    if fileID == -1
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Failed to open acquisition file: %s', fullPath);
    end
    cleanup = onCleanup(@() fclose(fileID));
    if ~isempty(selection)
        [rawData, retained] = read_selection(fileID, rawDescriptor, ...
            selection, fullPath);
        measurement = struct('raw_descriptor', rawDescriptor, ...
            'rawdata', rawData, 'raw_selection', retained);
        clear cleanup
        return;
    end
    if fseek(fileID, payloadOffset, 'bof') ~= 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Failed to seek to raw acquisition samples in: %s', fullPath);
    end

    [rawData, actualCount] = fread(fileID, expectedCount, 'uint16=>uint16');
    if actualCount ~= expectedCount
        error('OCE:IO:IncompleteAcquisition', ...
            ['Incomplete binary acquisition: expected %d uint16 samples, ' ...
             'read %d from %s.'], expectedCount, actualCount, fullPath);
    end
    rawData = normalize_layout(rawData, rawDescriptor, dimensions, fullPath);
    rawData = normalize_line_direction(rawData, rawDescriptor, ...
        samplesPerBmode);
    measurement = struct( ...
        'raw_descriptor', rawDescriptor, ...
        'rawdata', rawData);

    clear cleanup
end

function [rawData, retained] = read_selection(fileID, descriptor, selection, fullPath)
    if ~isstruct(selection) || ~isscalar(selection) || ...
            any(~ismember(fieldnames(selection), ...
                {'bmode_indices', 'lateral_indices'}))
        error('OCE:IO:InvalidRawSelection', ...
            'Selection accepts only bmode_indices and lateral_indices.');
    end
    bmode = selection_indices(selection, 'bmode_indices', descriptor.No_3Dscans);
    local = selection_indices(selection, 'lateral_indices', descriptor.Bframes_in_3Dscan);
    [localGrid, bmodeGrid] = ndgrid(local, bmode);
    canonical = localGrid(:)' + ...
        (bmodeGrid(:)' - 1) * descriptor.Bframes_in_3Dscan;
    storageLocal = localGrid;
    if isfield(descriptor, 'bscan_storage_reversed')
        reversed = descriptor.bscan_storage_reversed(bmodeGrid);
        storageLocal(reversed) = descriptor.Bframes_in_3Dscan + 1 - storageLocal(reversed);
    end
    switch string(descriptor.binary_format.source_layout)
        case "spectral_time_local_lateral_bmode"
            stored = storageLocal(:)' + ...
                (bmodeGrid(:)' - 1) * descriptor.Bframes_in_3Dscan;
        case "spectral_time_bmode_local_lateral"
            stored = bmodeGrid(:)' + ...
                (storageLocal(:)' - 1) * descriptor.No_3Dscans;
        otherwise
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'Unsupported binary source layout in: %s', fullPath);
    end
    samplesPerPosition = descriptor.samples_in_Aline * descriptor.Alines_in_Bframe;
    rawData = zeros(descriptor.samples_in_Aline, descriptor.Alines_in_Bframe, ...
        numel(stored), 'uint16');
    % Coalesce adjacent payload positions while preserving the caller's
    % canonical order, including backwards stored MB lines.
    first = 1;
    while first <= numel(stored)
        last = first;
        while last < numel(stored) && stored(last + 1) == stored(last) + 1
            last = last + 1;
        end
        offset = descriptor.binary_format.payload_offset_bytes + ...
            2 * samplesPerPosition * (stored(first) - 1);
        if fseek(fileID, offset, 'bof') ~= 0
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'Failed to seek to selected raw samples in: %s', fullPath);
        end
        expected = samplesPerPosition * (last - first + 1);
        [samples, count] = fread(fileID, expected, 'uint16=>uint16');
        if count ~= expected
            error('OCE:IO:IncompleteAcquisition', ...
                'Selected payload is truncated in: %s', fullPath);
        end
        rawData(:, :, first:last) = reshape(samples, descriptor.samples_in_Aline, ...
            descriptor.Alines_in_Bframe, last - first + 1);
        first = last + 1;
    end
    retained = struct('bmode_indices', bmode, 'lateral_indices', local, ...
        'global_lateral_indices', canonical, 'stored_position_indices', stored);
end

function indices = selection_indices(selection, name, count)
    indices = 1:count;
    if isfield(selection, name)
        indices = selection.(name);
    end
    if ~isnumeric(indices) || ~isvector(indices) || isempty(indices) || ...
            any(~isfinite(indices)) || any(indices ~= round(indices)) || ...
            any(indices < 1 | indices > count) || any(diff(indices) <= 0)
        error('OCE:IO:InvalidRawSelection', ...
            '%s must contain increasing distinct indices within the file.', name);
    end
    indices = double(indices(:)');
end

function rawData = normalize_line_direction(rawData, rawDescriptor, ...
        samplesPerBmode)
    % MB storage keeps positions in acquisition order; only the position
    % order of a backwards line is flipped, never its M time samples.
    if ~isfield(rawDescriptor, 'bscan_storage_reversed')
        return;
    end
    for bmodeIndex = find(rawDescriptor.bscan_storage_reversed)
        columns = (bmodeIndex - 1) * samplesPerBmode + (1:samplesPerBmode);
        rawData(:, :, columns) = rawData(:, :, flip(columns));
    end
end

function rawData = normalize_layout(rawData, rawDescriptor, dimensions, fullPath)
    spectralCount = dimensions(1);
    temporalCount = dimensions(2);
    samplesPerBmode = dimensions(3);
    bmodeCount = dimensions(4);
    sourceLayout = string(rawDescriptor.binary_format.source_layout);
    switch sourceLayout
        case "spectral_time_local_lateral_bmode"
            rawData = reshape(rawData, spectralCount, temporalCount, ...
                samplesPerBmode * bmodeCount);
        case "spectral_time_bmode_local_lateral"
            rawData = reshape(rawData, spectralCount, temporalCount, ...
                bmodeCount, samplesPerBmode);
            rawData = permute(rawData, [1 2 4 3]);
            rawData = reshape(rawData, spectralCount, temporalCount, ...
                samplesPerBmode * bmodeCount);
        otherwise
            error('OCE:IO:InvalidAcquisitionHeader', ...
                'Unsupported binary source layout "%s" in: %s', ...
                sourceLayout, fullPath);
    end
end
