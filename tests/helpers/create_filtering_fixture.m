function fixture = create_filtering_fixture()
%CREATE_FILTERING_FIXTURE Build deterministic temporal-filter inputs.

    fixture.OCT_system = struct('a_scan_rate', 20);
    fixture.standardOCE = struct( ...
        'time_sample_count', 129, 'samples_per_bmode', 3);
    fixture.oddOCE = struct( ...
        'time_sample_count', 130, 'samples_per_bmode', 3);
    fixture.shortOCE = struct( ...
        'time_sample_count', 10, 'samples_per_bmode', 3);

    config = oce.config.getDefaultProcessingConfig("phantom");
    config.FilterOptions.frequency.selection_source = "manual_configuration";
    config.FilterOptions.frequency.center_hz = 1000;
    config.FilterOptions.frequency.bandwidth.mode = "absolute_hz";
    config.FilterOptions.frequency.bandwidth.hz = 400;
    config.FilterOptions.order = 20;
    config.FilterOptions.diagnostic.fft_length = 256;
    config.FilterOptions.diagnostic.line_index = [];
    fixture.config_for_run = struct( ...
        'FilterOptions', config.FilterOptions, ...
        'acquisition_row', table());

    fs = fixture.OCT_system.a_scan_rate * 1000;
    tEven = (0:127) / fs;
    tOdd = (0:128) / fs;
    tShort = (0:8) / fs;
    fixture.surfaceEven = build_surface_signals(tEven);
    fixture.surfaceOdd = build_surface_signals(tOdd);
    fixture.surfaceShort = build_surface_signals(tShort);
    fixture.depthEven = build_depth_volume(tEven);
    fixture.depthOdd = build_depth_volume(tOdd);
    fixture.depthShort = build_depth_volume(tShort);

    fixture.surfaceNaN = fixture.surfaceEven;
    fixture.surfaceNaN(2, 23) = NaN;
    fixture.depthNaN = fixture.depthEven;
    fixture.depthNaN(3, 2, 31) = NaN;
    fixture.surfaceAllNaN = NaN(size(fixture.surfaceEven));
    fixture.depthResultEven = phase_result( ...
        fixture.depthEven, "lateral_depth_time");
    fixture.surfaceResultEven = phase_result( ...
        fixture.surfaceEven, "lateral_time");
    fixture.numAngles = 2;
    fixture.positionsPerAngle = 3;
end

function result = phase_result(values, layout)
    result = struct( ...
        'values', values, ...
        'quantity', "phase_increment", ...
        'units', "rad", ...
        'layout', layout);
end

function signals = build_surface_signals(t)
    fs = 20000;
    impulse = zeros(size(t));
    impulse(max(1, round(numel(t) / 3))) = 1;
    deterministicNoise = 0.01 * sin(2 * pi * 1733 * t + 0.37);
    signals = [ ...
        ones(size(t)); ...
        sin(2 * pi * 1000 * t); ...
        sin(2 * pi * 3000 * t); ...
        sin(2 * pi * 1000 * t) + 0.4 * sin(2 * pi * 3000 * t); ...
        impulse; ...
        0.2 * sin(2 * pi * (fs / 20) * t + 0.2) + deterministicNoise];
end

function volume = build_depth_volume(t)
    nSpace = 6;
    nDepth = 4;
    volume = zeros(nSpace, nDepth, numel(t));
    for spaceIndex = 1:nSpace
        for depthIndex = 1:nDepth
            signal = 0.01 * spaceIndex + 0.02 * depthIndex + ...
                sin(2 * pi * 1000 * t + 0.1 * spaceIndex) + ...
                0.25 * sin(2 * pi * 3000 * t + 0.2 * depthIndex);
            volume(spaceIndex, depthIndex, :) = signal;
        end
    end
end
