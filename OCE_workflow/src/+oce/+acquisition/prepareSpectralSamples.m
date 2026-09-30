function output = prepareSpectralSamples(rawData, octSystem, varargin)
%PREPARESPECTRALSAMPLES Own system-specific preparation before OCT FFT.
% context = prepareSpectralSamples(rawData, octSystem)
% samples = prepareSpectralSamples(rawData, octSystem, timeIndices, ...
%     lateralIndex, context, purpose)

    validate_common(rawData, octSystem);
    if isempty(varargin)
        output = build_context(rawData, octSystem);
        return;
    end
    if numel(varargin) ~= 4
        error('OCE:Acquisition:InvalidSpectralPreparation', ...
            ['Applying spectral preparation requires timeIndices, ' ...
             'lateralIndex, context, and purpose.']);
    end
    output = apply_preparation(rawData, octSystem, varargin{:});
end

function context = build_context(rawData, octSystem)
    context = struct( ...
        'profile', string(octSystem.profile), ...
        'background_spectrum', [], ...
        'source_coordinate', [], ...
        'target_coordinate', []);

    backgroundMethod = string( ...
        octSystem.spectral_preprocessing.background_method);
    switch backgroundMethod
        case "none"
        case "sample_derived_global_median"
            sampleCount = size(rawData, 1);
            lateralCount = size(rawData, 3);
            lateralMedians = zeros(sampleCount, lateralCount);
            for position = 1:lateralCount
                lateralMedians(:, position) = median( ...
                    double(rawData(:, :, position)), 2);
            end
            context.background_spectrum = median(lateralMedians, 2);
        otherwise
            error('OCE:Acquisition:UnsupportedSpectralBackground', ...
                'Unsupported spectral background method "%s".', ...
                backgroundMethod);
    end

    samplingMethod = string(octSystem.spectral_sampling.method);
    switch samplingMethod
        case "fft_ready_uniform_k"
            return;
        case "linear_wavelength_endpoints"
            sampleCount = size(rawData, 1);
            sampling = octSystem.spectral_sampling;
            lambdaNm = linspace(sampling.lambda_start_nm, ...
                sampling.lambda_end_nm, sampleCount)';
            sigmaCm = 1e7 ./ lambdaNm;
            sourceCoordinate = (sigmaCm - sigmaCm(1)) ./ ...
                (sigmaCm(end) - sigmaCm(1)) * (sampleCount - 1);
            targetCoordinate = (0:sampleCount - 1)';
            if any(diff(sourceCoordinate) <= 0) || ...
                    targetCoordinate(1) < sourceCoordinate(1) || ...
                    targetCoordinate(end) > sourceCoordinate(end)
                error('OCE:Acquisition:InvalidSpectralSampling', ...
                    'Wavelength endpoints do not produce a complete monotonic grid.');
            end
            context.source_coordinate = sourceCoordinate;
            context.target_coordinate = targetCoordinate;
        otherwise
            error('OCE:Acquisition:UnsupportedSpectralSampling', ...
                'Unsupported spectral sampling method "%s".', samplingMethod);
    end
end

function samples = apply_preparation(rawData, octSystem, timeIndices, ...
        lateralIndex, context, purpose)
    validate_selection(rawData, timeIndices, lateralIndex, context, ...
        octSystem);
    purpose = normalize_purpose(purpose);
    % Raw digitizer counts may be stored as uint16; double conversion is exact.
    fringes = double(rawData(:, timeIndices, lateralIndex));

    samples = prepare_input_samples( ...
        fringes, octSystem.spectral_sampling.method, purpose);
    samples = apply_background( ...
        samples, octSystem.spectral_preprocessing.background_method, context);
    samples = apply_resampling( ...
        samples, octSystem.spectral_preprocessing, context);
end

function samples = prepare_input_samples(fringes, samplingMethod, purpose)
    samplingMethod = string(samplingMethod);
    switch samplingMethod
        case "fft_ready_uniform_k"
            samples = prepare_historical_preview(fringes, purpose);
        case "linear_wavelength_endpoints"
            samples = double(fringes);
        otherwise
            error('OCE:Acquisition:UnsupportedSpectralSampling', ...
                'Unsupported spectral sampling method "%s".', samplingMethod);
    end
end

function samples = apply_background(samples, method, context)
    method = string(method);
    switch method
        case "none"
            return;
        case "sample_derived_global_median"
            if isempty(context.background_spectrum)
                error('OCE:Acquisition:InvalidSpectralPreparation', ...
                    ['Sample-derived global-median background subtraction ' ...
                     'requires a background spectrum in the preparation context.']);
            end
            samples = samples - context.background_spectrum;
        otherwise
            error('OCE:Acquisition:UnsupportedSpectralBackground', ...
                'Unsupported spectral background method "%s".', method);
    end
end

function samples = apply_resampling(samples, preprocessing, context)
    method = string(preprocessing.resampling_method);
    switch method
        case "none"
            return;
        case "uniform_inverse_wavelength"
            if isempty(context.source_coordinate) || ...
                    isempty(context.target_coordinate)
                error('OCE:Acquisition:InvalidSpectralPreparation', ...
                    ['Uniform inverse-wavelength resampling requires ' ...
                     'spectral coordinates in the preparation context.']);
            end
            interpolationMethod = string(preprocessing.interpolation_method);
            if interpolationMethod ~= "pchip" || preprocessing.extrapolation
                error('OCE:Acquisition:UnsupportedSpectralResampling', ...
                    ['Uniform inverse-wavelength resampling supports ' ...
                     'pchip interpolation without extrapolation.']);
            end
            samples = interp1(context.source_coordinate, samples, ...
                context.target_coordinate, char(interpolationMethod));
            if any(~isfinite(samples), 'all')
                error('OCE:Acquisition:SpectralInterpolationFailure', ...
                    'Spectral interpolation produced nonfinite samples.');
            end
        otherwise
            error('OCE:Acquisition:UnsupportedSpectralResampling', ...
                'Unsupported spectral resampling method "%s".', method);
    end
end

function samples = prepare_historical_preview(fringes, purpose)
    repeatCount = size(fringes, 2);
    switch purpose
        case "reconstruction"
            samples = double(fringes);
        case "depth_preview"
            samples = double(fringes - repmat( ...
                median(fringes, 2), 1, repeatCount));
        case "time_preview"
            samples = double(fringes - repmat( ...
                smooth(mean(fringes, 2), 0.05, 'lowess'), ...
                1, repeatCount));
    end
end

function purpose = normalize_purpose(value)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('OCE:Acquisition:InvalidSpectralPreparation', ...
            'Spectral preparation purpose must be a text scalar.');
    end
    purpose = lower(strtrim(string(value)));
    if ~ismember(purpose, ...
            ["reconstruction", "depth_preview", "time_preview"])
        error('OCE:Acquisition:InvalidSpectralPreparation', ...
            'Unsupported spectral preparation purpose "%s".', purpose);
    end
end

function validate_common(rawData, octSystem)
    if ~isnumeric(rawData) || ndims(rawData) > 3 || isempty(rawData)
        error('OCE:Acquisition:InvalidRawMeasurement', ...
            'rawData must be a nonempty numeric spectral-time-lateral array.');
    end
    required = ["profile"; "spectral_sampling"; ...
        "spectral_preprocessing"];
    if ~isstruct(octSystem) || ~isscalar(octSystem)
        error('OCE:Acquisition:InvalidSystemParameter', ...
            'octSystem must be a scalar struct.');
    end
    for index = 1:numel(required)
        if ~isfield(octSystem, required(index))
            error('OCE:Acquisition:MissingSystemParameter', ...
                'octSystem is missing %s.', required(index));
        end
    end
end

function validate_selection(rawData, timeIndices, lateralIndex, context, ...
        octSystem)
    if ~isnumeric(timeIndices) || isempty(timeIndices) || ...
            any(~isfinite(timeIndices)) || any(timeIndices < 1) || ...
            any(timeIndices ~= round(timeIndices)) || ...
            any(timeIndices > size(rawData, 2))
        error('OCE:Acquisition:InvalidSpectralPreparation', ...
            'timeIndices must be valid positive integer indices.');
    end
    if ~isnumeric(lateralIndex) || ~isscalar(lateralIndex) || ...
            ~isfinite(lateralIndex) || lateralIndex < 1 || ...
            lateralIndex ~= round(lateralIndex) || ...
            lateralIndex > size(rawData, 3)
        error('OCE:Acquisition:InvalidSpectralPreparation', ...
            'lateralIndex must select one valid lateral position.');
    end
    if ~isstruct(context) || ~isscalar(context) || ...
            ~isfield(context, 'profile') || ...
            string(context.profile) ~= string(octSystem.profile)
        error('OCE:Acquisition:InvalidSpectralPreparation', ...
            'Spectral preparation context does not match the OCT profile.');
    end
end
