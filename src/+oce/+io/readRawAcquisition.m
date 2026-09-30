function measurement = readRawAcquisition(filename, filepath)
%READRAWACQUISITION Read one OCT/OCE binary acquisition without geometry intent.
% Binary-family storage is normalized to spectral_time_lateral. Experimental
% acquisition mode and scan geometry are resolved outside the I/O boundary.

    if nargin < 1 || isempty(filename)
        error('filename is required.');
    end
    if nargin < 2 || isempty(filepath)
        error('filepath is required.');
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
    if fseek(fileID, payloadOffset, 'bof') ~= 0
        error('OCE:IO:InvalidAcquisitionHeader', ...
            'Failed to seek to raw acquisition samples in: %s', fullPath);
    end

    [rawData, actualCount] = fread(fileID, expectedCount, 'uint16');
    if actualCount ~= expectedCount
        error('OCE:IO:IncompleteAcquisition', ...
            ['Incomplete binary acquisition: expected %d uint16 samples, ' ...
             'read %d from %s.'], expectedCount, actualCount, fullPath);
    end
    rawData = normalize_layout(rawData, rawDescriptor, dimensions, fullPath);
    measurement = struct( ...
        'raw_descriptor', rawDescriptor, ...
        'rawdata', rawData);

    clear cleanup
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
