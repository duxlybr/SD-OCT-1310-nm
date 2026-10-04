function enface = computeStructuralEnface(reconstructionResult, geometry, varargin)
%COMPUTESTRUCTURALENFACE Depth-averaged structural en-face map of an area scan.
% enface = computeStructuralEnface(reconstructionResult, geometry, Name, Value)
%
% Inputs are the reconstruction (complex volume, layout lateral_depth_time)
% and a raster or polar acquisition geometry. Name-value options:
%   AScanAverageCount - N M-repetitions averaged per A-scan (default: all
%                       retained repetitions from FirstMRepetition).
%   FirstMRepetition  - absolute acquisition M-repetition index of the first
%                       averaged A-scan (default: first retained repetition).
%   DepthRangeIndices - [first last] crop-local depth indices averaged
%                       (default: the complete reconstructed depth crop).
% Each position first averages the OCT amplitude |A| of N repetitions
% (incoherent A-scan averaging, insensitive to motion-induced phase), then
% takes the linear mean over depth. Positions are then mapped onto the
% geometry.enface grid (exact for raster, linear interpolation for polar
% scans, NaN outside the scanned area). Output layout is y_x with Cartesian
% x/y axes in mm; log_values is 20*log10 of the linear map. No side effects.

    parser = inputParser;
    addParameter(parser, 'AScanAverageCount', [], @valid_optional_integer);
    addParameter(parser, 'FirstMRepetition', [], @valid_optional_integer);
    addParameter(parser, 'DepthRangeIndices', [], @valid_optional_range);
    parse(parser, varargin{:});

    complexValues = validate_inputs(reconstructionResult, geometry);
    [lateralCount, depthCount, timeCount] = size(complexValues);
    cropStart = double(reconstructionResult.crop.time.start_index_inclusive);

    firstRepetition = parser.Results.FirstMRepetition;
    if isempty(firstRepetition)
        firstRepetition = cropStart;
    end
    firstLocal = double(firstRepetition) - cropStart + 1;
    averageCount = parser.Results.AScanAverageCount;
    if isempty(averageCount)
        averageCount = timeCount - firstLocal + 1;
    end
    if firstLocal < 1 || firstLocal + averageCount - 1 > timeCount
        error('OCE:Acquisition:InvalidEnfaceAveraging', ...
            ['M-repetitions %d:%d fall outside the reconstructed range ' ...
             '%d:%d.'], firstRepetition, firstRepetition + averageCount - 1, ...
            cropStart, cropStart + timeCount - 1);
    end
    timeIndices = firstLocal:(firstLocal + averageCount - 1);

    depthRange = parser.Results.DepthRangeIndices;
    if isempty(depthRange)
        depthRange = [1 depthCount];
    end
    depthRange = double(depthRange(:)');
    if depthRange(2) > depthCount
        error('OCE:Acquisition:InvalidEnfaceDepthRange', ...
            'DepthRangeIndices must lie within the depth crop 1:%d.', depthCount);
    end
    depthIndices = depthRange(1):depthRange(2);

    % Per-position loop avoids an N-repetition abs() copy of the volume.
    depthAveraged = zeros(lateralCount, 1);
    for position = 1:lateralCount
        aScans = reshape(complexValues(position, depthIndices, timeIndices), ...
            numel(depthIndices), numel(timeIndices));
        depthAveraged(position) = mean(mean(abs(aScans), 2));
    end

    enfaceGrid = geometry.enface;
    values = reshape(full(enfaceGrid.operator * depthAveraged), ...
        size(enfaceGrid.coverage));
    values(~enfaceGrid.coverage) = NaN;
    depthAxisMm = double(reconstructionResult.axes.depth.values(:));
    enface = struct( ...
        'values', values, ...
        'log_values', real(20 * log10(values)), ...
        'quantity', "depth_averaged_oct_amplitude", ...
        'units', "arbitrary_amplitude", ...
        'log_units', "dB_relative", ...
        'layout', "y_x", ...
        'x_axis_mm', double(enfaceGrid.x_axis_mm(:)'), ...
        'y_axis_mm', double(enfaceGrid.y_axis_mm(:)'), ...
        'grid_method', string(enfaceGrid.method), ...
        'a_scan_average', struct( ...
            'count', averageCount, ...
            'first_m_repetition', double(firstRepetition), ...
            'last_m_repetition', double(firstRepetition) + averageCount - 1, ...
            'method', "mean_amplitude_over_m_repetitions"), ...
        'depth_average', struct( ...
            'crop_indices', depthRange, ...
            'range_mm', depthAxisMm(depthRange)', ...
            'method', "linear_mean_over_depth"));
end

function complexValues = validate_inputs(reconstructionResult, geometry)
    if ~isstruct(reconstructionResult) || ...
            ~isfield(reconstructionResult, 'complex_volume') || ...
            ~isfield(reconstructionResult.complex_volume, 'values') || ...
            ~isfield(reconstructionResult, 'crop') || ...
            ~isfield(reconstructionResult, 'axes')
        error('OCE:Acquisition:InvalidReconstructionResult', ...
            'A reconstruction_result with its complex volume is required.');
    end
    if string(reconstructionResult.complex_volume.layout) ~= "lateral_depth_time"
        error('OCE:Acquisition:InvalidReconstructionResult', ...
            'The complex volume layout must be lateral_depth_time.');
    end
    if ~isstruct(geometry) || ~isfield(geometry, 'enface')
        error('OCE:Acquisition:InvalidEnfaceGeometry', ...
            'A structural en-face map requires a raster or polar geometry.');
    end
    complexValues = reconstructionResult.complex_volume.values;
    if size(complexValues, 1) ~= size(geometry.enface.operator, 2)
        error('OCE:Acquisition:InvalidEnfaceGeometry', ...
            'Lateral positions must equal the en-face lateral sample count.');
    end
end

function tf = valid_optional_integer(value)
    tf = isempty(value) || (isnumeric(value) && isscalar(value) && ...
        isfinite(value) && value >= 1 && value == round(value));
end

function tf = valid_optional_range(value)
    tf = isempty(value) || (isnumeric(value) && numel(value) == 2 && ...
        all(isfinite(value)) && all(value >= 1) && ...
        all(value == round(value)) && value(1) <= value(2));
end
