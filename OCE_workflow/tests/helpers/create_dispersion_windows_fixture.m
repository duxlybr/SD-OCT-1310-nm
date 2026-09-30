function fixture = create_dispersion_windows_fixture()
%CREATE_DISPERSION_WINDOWS_FIXTURE Build deterministic window-contract inputs.

    samplesPerBmode = 31;
    bmodeCount = 3;
    sampleCount = 121;
    time = linspace(-1, 1, sampleCount);
    values = zeros(samplesPerBmode * bmodeCount, sampleCount);
    centers = [9 16 23];
    for bmodeIndex = 1:bmodeCount
        x = (1:samplesPerBmode)';
        spatial = exp(-((x - centers(bmodeIndex)) / 3).^2);
        temporal = sin(2*pi*(2 + bmodeIndex)*time) + ...
            0.07*cos(2*pi*11*time + 0.2*bmodeIndex);
        block = spatial * temporal;
        block = block + 0.15*exp(-abs(x - 16)/5) * cos(2*pi*5*time);
        rows = (bmodeIndex - 1)*samplesPerBmode + (1:samplesPerBmode);
        values(rows, :) = block;
    end
    values(4, 19) = NaN;
    values(samplesPerBmode + 7, 37) = NaN;

    options = oce.config.getDefaultProcessingConfig("phantom"). ...
        DispersionWindowOptions;
    options.center.method = "middle";
    options.center.search_range_fraction = [0.20 0.80];
    options.center.max_mirrored_correlation.minimum_half_width_samples = 4;
    options.temporal.start_index_inclusive = 10;
    options.temporal.method = "manual_interval_count";
    options.temporal.manual_interval_count = 50;
    frequencyHz = 1000;
    sampleIntervalS = 5e-5;

    fixture.values = values;
    fixture.x_axis_mm = (0:samplesPerBmode-1) * 0.1;
    fixture.geometry = struct('samples_per_bmode', samplesPerBmode, ...
        'bmode_count', bmodeCount);
    fixture.resolved_filter = struct( ...
        'sample_interval_s', sampleIntervalS, ...
        'frequency', struct('center_hz', frequencyHz));
    fixture.filter_result = struct( ...
        'enabled', true, 'applied', true, ...
        'design', struct('applied', true, 'delay_samples', 3), ...
        'surface_postprocessed', struct('values', values, ...
            'quantity', "phase_increment", 'units', "rad", ...
            'layout', "lateral_time"), ...
        'time_axis_s', (0:sampleCount-1) * sampleIntervalS);
    fixture.baseOptions = options;
    fixture.expectedRmsCenters = centers(:);

    fixture.cases = struct();
    fixture.cases.middle = make_config(options);
    manual = options;
    manual.center.method = "manual_local_index";
    manual.center.manual_local_index = 3;
    fixture.cases.manualScalar = make_config(manual);
    manual.center.manual_local_index = [1 16 31];
    fixture.cases.manualByBmode = make_config(manual);
    rmsOptions = options;
    rmsOptions.center.method = "max_rms_phase_increment";
    fixture.cases.maxRmsPhaseIncrement = make_config(rmsOptions);
    mirrorOptions = options;
    mirrorOptions.center.method = "max_mirrored_correlation";
    mirrorOptions.center.search_range_fraction = [0.35 0.65];
    fixture.cases.maxMirroredCorrelation = make_config(mirrorOptions);
    spatialManual = options;
    spatialManual.spatial.method = "manual_interval_count";
    spatialManual.spatial.manual_interval_count = 6;
    fixture.cases.manualSpatial = make_config(spatialManual);
    cycles = options;
    cycles.temporal.method = "cycle_count";
    cycles.temporal.manual_interval_count = [];
    cycles.temporal.cycle_count = 0.2;
    fixture.cases.cycleDuration = make_config(cycles);
    toEnd = options;
    toEnd.temporal.method = "to_end";
    fixture.cases.toEnd = make_config(toEnd);
    shifted = options;
    shifted.center.method = "manual_local_index";
    shifted.center.manual_local_index = [1 16 31];
    fixture.cases.shiftToFit = make_config(shifted);

    fixture.invalid = struct();
    fixture.invalid.missingOptions = rmfield( ...
        make_config(options), 'DispersionWindowOptions');

    fixture.invalidOptions = struct();
    invalid = options;
    invalid.center.method = "unsupported";
    fixture.invalidOptions.unsupportedCenter = invalid;
    invalid = options;
    invalid.center.method = "manual_local_index";
    invalid.center.manual_local_index = [];
    fixture.invalidOptions.manualCenterMissing = invalid;
end

function config = make_config(options)
    options = oce.config.resolveDispersionWindowOptions(options);
    config = struct('DispersionWindowOptions', options, ...
        'DispersionAnalysisOptions', struct( ...
            'method', "windowed_fft_ridge"), ...
        'resolved_crop', struct('time', struct( ...
            'start_index_inclusive', 1, ...
            'end_index_inclusive', 122)));
end
