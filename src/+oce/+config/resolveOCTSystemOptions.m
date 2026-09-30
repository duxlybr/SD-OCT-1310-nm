function resolved = resolveOCTSystemOptions(options, preparedProfile)
%RESOLVEOCTSYSTEMOPTIONS Validate and resolve editable OCT-system parameters.
% Binary format is deliberately not an input to this resolver.

    if nargin < 2
        preparedProfile = "";
    end

    validate_options(options);
    profile = normalize_required_profile(options.profile);
    systemType = system_type_for_profile(profile);

    centerWavelength = positive_scalar( ...
        options.center_wavelength, 'center_wavelength');
    centerSource = text_scalar( ...
        options.center_wavelength_source, 'center_wavelength_source');
    aScanRate = positive_scalar(options.a_scan_rate, 'a_scan_rate');
    aScanRateSource = text_scalar( ...
        options.a_scan_rate_source, 'a_scan_rate_source');
    depthCalibration = validate_depth_calibration(options.depth_sampling_calibration);
    spectralSampling = validate_spectral_sampling(options.spectral_sampling);
    spectralPreprocessing = validate_spectral_preprocessing( ...
        options.spectral_preprocessing, spectralSampling.method);

    resolved = struct( ...
        'profile', profile, ...
        'system_type', systemType, ...
        'center_wavelength', centerWavelength, ...
        'center_wavelength_source', centerSource, ...
        'a_scan_rate', aScanRate, ...
        'a_scan_rate_source', aScanRateSource, ...
        'depth_sampling_calibration', depthCalibration, ...
        'spectral_sampling', spectralSampling, ...
        'spectral_preprocessing', spectralPreprocessing, ...
        'selection_source', "explicit_profile");

    preparedProfile = normalize_optional_profile(preparedProfile);
    if strlength(preparedProfile) > 0 && preparedProfile ~= resolved.profile
        error('OCE:Config:OCTSystemProfileMismatch', ...
            ['Acquisition previews were prepared with OCT profile "%s", ' ...
             'but processing selected "%s". Reprepare the acquisition ' ...
             'parameters with the selected profile.'], ...
            preparedProfile, resolved.profile);
    end
end

function validate_options(options)
    if isstruct(options) && any(isfield(options, ...
            {'axial_pixel_res', 'axial_pixel_res_source'}))
        error('OCE:Config:RetiredAxialSampling', ...
            ['axial_pixel_res is retired. Rebuild OCTSystemOptions with ' ...
             'getOCTSystemOptions and explicitly review custom air-depth ' ...
             'calibration in depth_sampling_calibration before saving.']);
    end
    expected = ["profile"; "center_wavelength"; ...
        "center_wavelength_source"; "a_scan_rate"; ...
        "a_scan_rate_source"; "depth_sampling_calibration"; "spectral_sampling"; ...
        "spectral_preprocessing"];
    require_exact_fields(options, expected, 'OCTSystemOptions');
end

function calibration = validate_depth_calibration(value)
% Calibration evidence is in air, never sample-corrected depth or optical FWHM.
    if ~isstruct(value) || ~isscalar(value) || ~isfield(value, 'method')
        invalid('depth_sampling_calibration must specify a method.');
    end
    method = text_scalar(value.method, 'depth_sampling_calibration.method');
    expected = ["method"; "interval_um"; "source"];
    switch method
        case "native_fft_interval"
        case "reference_fft_interval"
            expected = [expected; "spectral_sample_count"; ...
                "reference_fft_sample_count"];
        otherwise
            invalid('Unsupported depth sampling calibration method "%s".', method);
    end
    require_exact_fields(value, expected, 'depth_sampling_calibration');
    calibration = struct('method', method, ...
        'interval_um', positive_scalar(value.interval_um, ...
            'depth_sampling_calibration.interval_um'), ...
        'source', text_scalar(value.source, 'depth_sampling_calibration.source'));
    if method == "reference_fft_interval"
        for name = ["spectral_sample_count", "reference_fft_sample_count"]
            count = positive_scalar(value.(name), ...
                'depth_sampling_calibration.' + name);
            if count ~= round(count) || count < 2
                invalid('depth_sampling_calibration.%s must be an integer >= 2.', name);
            end
            calibration.(name) = count;
        end
        if calibration.reference_fft_sample_count < calibration.spectral_sample_count
            invalid('Reference FFT must not truncate the calibrated spectrum.');
        end
    end
end

function systemType = system_type_for_profile(profile)
    switch profile
        case "swept_source_1300"
            systemType = "swept_source";
        case "spectral_domain_1040"
            systemType = "spectral_domain";
        case "spectral_domain_1310"
            systemType = "spectral_domain";
        otherwise
            error('OCE:Config:UnknownOCTSystemProfile', ...
                ['Unsupported OCT system profile "%s". Supported profiles ' ...
                 'are "swept_source_1300", "spectral_domain_1040", and ' ...
                 '"spectral_domain_1310".'], profile);
    end
end

function sampling = validate_spectral_sampling(value)
    expected = ["method"; "lambda_start_nm"; "lambda_end_nm"; ...
        "parameter_source"];
    require_exact_fields(value, expected, ...
        'OCTSystemOptions.spectral_sampling');

    method = text_scalar(value.method, 'spectral_sampling.method');
    source = text_scalar( ...
        value.parameter_source, 'spectral_sampling.parameter_source');

    switch method
        case "fft_ready_uniform_k"
            if ~isempty(value.lambda_start_nm) || ~isempty(value.lambda_end_nm)
                invalid(['spectral_sampling wavelength endpoints must be ' ...
                    'empty for fft_ready_uniform_k.']);
            end
            lambdaStart = [];
            lambdaEnd = [];

        case "linear_wavelength_endpoints"
            lambdaStart = positive_scalar( ...
                value.lambda_start_nm, 'spectral_sampling.lambda_start_nm');
            lambdaEnd = positive_scalar( ...
                value.lambda_end_nm, 'spectral_sampling.lambda_end_nm');
            if lambdaStart == lambdaEnd
                invalid('spectral_sampling wavelength endpoints must differ.');
            end

        otherwise
            invalid('Unsupported spectral_sampling.method "%s".', method);
    end

    sampling = struct( ...
        'method', method, ...
        'lambda_start_nm', lambdaStart, ...
        'lambda_end_nm', lambdaEnd, ...
        'parameter_source', source);
end

function preprocessing = validate_spectral_preprocessing(value, samplingMethod)
    expected = ["background_method"; "resampling_method"; ...
        "interpolation_method"; "extrapolation"];
    require_exact_fields(value, expected, ...
        'OCTSystemOptions.spectral_preprocessing');

    backgroundMethod = text_scalar( ...
        value.background_method, 'spectral_preprocessing.background_method');
    resamplingMethod = text_scalar( ...
        value.resampling_method, 'spectral_preprocessing.resampling_method');
    interpolationMethod = text_scalar( ...
        value.interpolation_method, ...
        'spectral_preprocessing.interpolation_method');
    extrapolation = value.extrapolation;

    if ~ismember(backgroundMethod, ["none", "sample_derived_global_median"])
        invalid('Unsupported spectral background method "%s".', ...
            backgroundMethod);
    end
    if ~ismember(resamplingMethod, ["none", "uniform_inverse_wavelength"])
        invalid('Unsupported spectral resampling method "%s".', ...
            resamplingMethod);
    end
    if ~ismember(interpolationMethod, ["none", "pchip"])
        invalid('Unsupported spectral interpolation method "%s".', ...
            interpolationMethod);
    end
    if ~islogical(extrapolation) || ~isscalar(extrapolation)
        invalid('spectral_preprocessing.extrapolation must be a logical scalar.');
    end

    switch samplingMethod
        case "fft_ready_uniform_k"
            if resamplingMethod ~= "none" || interpolationMethod ~= "none" || ...
                    extrapolation
                invalid(['fft_ready_uniform_k requires resampling_method="none", ' ...
                    'interpolation_method="none", and extrapolation=false.']);
            end

        case "linear_wavelength_endpoints"
            if resamplingMethod ~= "uniform_inverse_wavelength" || ...
                    interpolationMethod ~= "pchip" || extrapolation
                invalid(['linear_wavelength_endpoints requires ' ...
                    'uniform_inverse_wavelength PCHIP resampling without ' ...
                    'extrapolation.']);
            end
    end

    preprocessing = struct( ...
        'background_method', backgroundMethod, ...
        'resampling_method', resamplingMethod, ...
        'interpolation_method', interpolationMethod, ...
        'extrapolation', extrapolation);
end

function require_exact_fields(value, expected, label)
    if ~isstruct(value) || ~isscalar(value)
        invalid('%s must be a scalar struct.', label);
    end
    actual = string(fieldnames(value));
    if numel(actual) ~= numel(expected) || ...
            any(~ismember(expected, actual)) || any(~ismember(actual, expected))
        invalid('%s fields are invalid.', label);
    end
end

function value = positive_scalar(value, label)
    if ~isnumeric(value) || ~isscalar(value) || ...
            ~isfinite(value) || value <= 0
        invalid('%s must be a positive finite numeric scalar.', label);
    end
    value = double(value);
end

function value = text_scalar(value, label)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        invalid('%s must be a text scalar.', label);
    end
    value = strtrim(string(value));
    if ismissing(value) || strlength(value) == 0
        invalid('%s must not be empty.', label);
    end
end

function profile = normalize_required_profile(value)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('OCE:Config:InvalidOCTSystemProfile', ...
            'OCT system profile must be a text scalar.');
    end
    profile = lower(strtrim(string(value)));
    if ismissing(profile) || strlength(profile) == 0
        error('OCE:Config:InvalidOCTSystemProfile', ...
            'OCT system profile must not be empty.');
    end
end

function profile = normalize_optional_profile(value)
    if isempty(value) || ...
            ((ischar(value) || (isstring(value) && isscalar(value))) && ...
             (ismissing(string(value)) || ...
              strlength(strtrim(string(value))) == 0))
        profile = "";
        return;
    end
    profile = normalize_required_profile(value);
end

function invalid(message, varargin)
    error('OCE:Config:InvalidOCTSystemOptions', message, varargin{:});
end
