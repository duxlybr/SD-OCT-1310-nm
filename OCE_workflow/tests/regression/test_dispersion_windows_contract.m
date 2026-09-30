function test_dispersion_windows_contract(~)
%TEST_DISPERSION_WINDOWS_CONTRACT Verify explicit extraction and provenance.

    fixture = create_dispersion_windows_fixture();
    captured = capture_dispersion_windows_contract( ...
        @oce.dispersion.buildWindows, fixture);
    assert_all_silent(captured.outputs);

    middle = captured.outputs.middle.result;
    assert_source(middle, fixture);
    assert(isequal([middle.bmodes.center], [middle.bmodes.center]));
    centers = arrayfun(@(m) m.center.local_lateral_index, middle.bmodes);
    assert_equal(centers, [16 16 16], 'middle centers');
    assert_equal(middle.resolved_options.spatial.interval_count, 9, ...
        'fractional spatial interval count');
    assert_equal(middle.resolved_options.temporal.interval_count, 50, ...
        'manual temporal interval count');
    assert_equal(middle.bmodes(1).left.local_lateral_indices, 4:13, ...
        'left inclusive indices');
    assert_equal(middle.bmodes(1).right.local_lateral_indices, 19:28, ...
        'right inclusive indices');
    assert_equal(middle.bmodes(1).left.time_indices, 10:60, ...
        'inclusive time indices');
    assert_equal(size(middle.bmodes(1).left.values), [10 51], ...
        'interval versus sample count');
    expectedFiltered = fixture.values(4:13, 13:63);
    assert_equal(middle.bmodes(1).left.values, expectedFiltered, ...
        'delay-aligned extraction values');
    for index = 1:numel(middle.bmodes)
        range = middle.bmodes(index).global_lateral_range;
        assert(all(middle.bmodes(index).left.global_lateral_indices >= range(1) & ...
            middle.bmodes(index).left.global_lateral_indices <= range(2)));
        assert(all(middle.bmodes(index).right.global_lateral_indices >= range(1) & ...
            middle.bmodes(index).right.global_lateral_indices <= range(2)));
    end

    manual = captured.outputs.manualByBmode.result;
    centers = arrayfun(@(m) m.center.local_lateral_index, manual.bmodes);
    assert_equal(centers, [1 16 31], 'manual centers');
    assert(manual.bmodes(1).left.spatial_boundary.applied);
    assert(manual.bmodes(3).right.spatial_boundary.applied);
    assert_equal(manual.bmodes(1).left.local_lateral_indices, 1:10, ...
        'left shift-to-fit');
    assert_equal(manual.bmodes(3).right.local_lateral_indices, 22:31, ...
        'right shift-to-fit');

    rmsResult = captured.outputs.maxRmsPhaseIncrement.result;
    rmsCenters = arrayfun(@(m) m.center.local_lateral_index, ...
        rmsResult.bmodes)';
    assert_equal(rmsCenters, fixture.expectedRmsCenters, 'RMS centers');
    assert_equal(captured.outputs.manualSpatial.result. ...
        resolved_options.spatial.interval_count, 6, 'manual spatial interval');
    assert_equal(captured.outputs.cycleDuration.result. ...
        resolved_options.temporal.interval_count, 4, 'cycle duration intervals');
    toEnd = captured.outputs.toEnd.result;
    assert_equal(toEnd.resolved_options.temporal.interval_count, 108, ...
        'to-end effective intervals');
    assert_equal(toEnd.resolved_options.temporal_boundary. ...
        requested_end_index_inclusive, 122, 'to-end requested crop end');
    assert_equal(toEnd.resolved_options.temporal_boundary. ...
        effective_end_index_inclusive, 118, 'to-end aligned end');
    assert_equal(toEnd.bmodes(1).left.time_indices, 10:118, ...
        'to-end absolute indices');
    cycles = oce.dispersion.windowdurations.cycleCount( ...
        struct('cycle_count', 3), 3500, 5e-6, [], 1000);
    assert_equal(cycles.interval_count, 171, 'R004 cycle intervals');
    assert_equal(cycles.sample_count, 172, 'R004 cycle samples');
    assert_equal(cycles.represented_cycle_count, 2.9925, ...
        'R004 represented cycles');

    clippedConfig = fixture.cases.cycleDuration;
    clippedConfig.DispersionWindowOptions.temporal.cycle_count = 6;
    lastwarn('');
    evalc('clipped = run(clippedConfig, fixture.filter_result, fixture);');
    [~, warningId] = lastwarn;
    assert_equal(string(warningId), ...
        "OCE:DispersionWindows:CycleCountTruncated", ...
        'cycle-count truncation warning');
    assert_equal(clipped.resolved_options.temporal.interval_count, 108, ...
        'cycle-count effective intervals');
    assert_equal(clipped.resolved_options.temporal.requested_duration_s, ...
        0.006, 'cycle-count requested duration');
    assert_equal(clipped.resolved_options.temporal.effective_duration_s, ...
        0.0054, 'cycle-count effective duration');
    assert_equal(clipped.bmodes(1).left.time_indices, 10:118, ...
        'cycle-count clipped absolute indices');
    passthrough = fixture.filter_result;
    passthrough.enabled = false;
    passthrough.applied = false;
    passthroughResult = run(fixture.cases.middle, passthrough, fixture);
    assert(~passthroughResult.source.filter_enabled && ...
        ~passthroughResult.source.filter_applied);
    expectedPassthrough = fixture.values(4:13, 10:60);
    assert_equal(passthroughResult.bmodes(1).left.values, expectedPassthrough, ...
        'filter passthrough extraction');

    assert_error(captured.errors.missingOptions, ...
        'OCE:DispersionWindows:MissingOptions');
    assert_identifier(@() oce.config.resolveDispersionWindowOptions( ...
        fixture.invalidOptions.unsupportedCenter), ...
        'OCE:Config:InvalidDispersionWindowOptions');
    assert_identifier(@() oce.config.resolveDispersionWindowOptions( ...
        fixture.invalidOptions.manualCenterMissing), ...
        'OCE:Config:InvalidDispersionWindowOptions');
    assert_input_failures(fixture);
    assert_first_max_tie(fixture);
end

function assert_source(result, fixture)
    assert_equal(result.source.quantity, "phase_increment", 'quantity');
    assert_equal(result.source.units, "rad", 'units');
    assert_equal(result.source.layout, "lateral_time", 'layout');
    assert(result.source.filter_enabled && result.source.filter_applied);
    assert_equal(result.source.signal_size, size(fixture.values), 'signal size');
end

function assert_input_failures(fixture)
    config = fixture.cases.middle;
    bad = fixture.filter_result;
    bad.surface_postprocessed.values = fixture.values(1:end-1, :);
    assert_identifier(@() run(config, bad, fixture), ...
        'OCE:DispersionWindows:SpaceAngleMismatch');
    mismatch = fixture.resolved_filter;
    mismatch.frequency.center_hz = 1001;
    resolved = oce.dispersion.buildWindows(config, ...
        fixture.filter_result, fixture.x_axis_mm, mismatch, ...
        fixture.geometry);
    assert_equal(resolved.frequency.center_hz, 1001, ...
        'resolved filter frequency authority');
    late = config;
    late.DispersionWindowOptions.temporal.start_index_inclusive = 999;
    assert_identifier(@() run(late, fixture.filter_result, fixture), ...
        'OCE:DispersionWindows:TemporalStartOutsideDomain');
    raster = fixture;
    raster.geometry.raster = struct('slow_axis_mm', [0 1]);
    assert_identifier(@() run(config, fixture.filter_result, raster), ...
        'OCE:DispersionWindows:UnsupportedScanGeometry');
end

function assert_first_max_tie(fixture)
    tied = fixture;
    tied.values(:) = 0;
    tied.filter_result.surface_postprocessed.values = tied.values;
    config = tied.cases.maxRmsPhaseIncrement;
    result = run(config, tied.filter_result, tied);
    searchStart = round(config.DispersionWindowOptions.center. ...
        search_range_fraction(1) * tied.geometry.samples_per_bmode);
    centers = arrayfun(@(m) m.center.local_lateral_index, result.bmodes);
    assert_equal(centers, repmat(searchStart, 1, 3), ...
        'first maximum tie policy');
end

function result = run(config, filterResult, fixture)
    result = oce.dispersion.buildWindows(config, filterResult, ...
        fixture.x_axis_mm, fixture.resolved_filter, fixture.geometry);
end

function assert_all_silent(outputs)
    names = fieldnames(outputs);
    for index = 1:numel(names)
        if strlength(outputs.(names{index}).transcript) ~= 0
            error('OCE:DispersionWindows:UnexpectedConsoleOutput', ...
                'Normal window resolution must be silent.');
        end
    end
end

function assert_identifier(callback, identifier)
    try
        callback();
    catch ME
        if strcmp(ME.identifier, identifier), return; end
        error('OCE:DispersionWindows:ExpectedError', ...
            'Expected %s; received %s.', identifier, ME.identifier);
    end
    error('OCE:DispersionWindows:ExpectedError', ...
        'Expected error %s was not raised.', identifier);
end

function assert_error(captured, identifier)
    if captured.identifier ~= identifier
        error('OCE:DispersionWindows:ExpectedError', ...
            'Expected %s; received %s.', identifier, captured.identifier);
    end
end

function assert_equal(actual, expected, label)
    if ~isequaln(actual, expected)
        error('OCE:DispersionWindows:Contract', ...
            '%s differs from the explicit contract.', label);
    end
end
