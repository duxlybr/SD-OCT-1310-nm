function test_border_multibmode_contract(~)
%TEST_BORDER_MULTIBMODE_CONTRACT Enforce independent border B-modes.

    fixture = create_multibmode_fixture();
    methods = { ...
        "phantom", @oce.borders.methods.findPhantomBorders, ...
            fixture.phantomOptions; ...
        "adaptive_corneal", @oce.borders.methods.findAdaptiveCornealBorders, ...
            fixture.adaptiveOptions; ...
        "in_vivo_corneal", @oce.borders.methods.findInVivoCornealBorders, ...
            fixture.inVivoOptions};

    for methodIndex = 1:size(methods, 1)
        method = methods{methodIndex, 2};
        options = methods{methodIndex, 3};
        combined = run_detector(method, fixture, fixture.Bmode, options);
        singles = run_each_bmode(method, fixture, fixture.Bmode, options);
        assert_concatenated_equivalence( ...
            combined, singles, methods{methodIndex, 1});

        modifiedBmode = fixture.Bmode;
        middle = bmode_range(fixture.geometry, 2);
        modifiedBmode(:, middle) = flipud(modifiedBmode(:, middle));
        modified = run_detector(method, fixture, modifiedBmode, options);
        assert_untouched_bmodes(combined, modified, ...
            fixture.geometry, methods{methodIndex, 1});
        assert_middle_bmode_changed(combined, modified, middle, ...
            methods{methodIndex, 1});
    end

    assert_anterior_only_multibmode_contract(fixture);
    assert_edge_exclusion_contract(fixture);
    assert_small_bmode_protection(fixture);
    assert_edge_exclusion_validation();
end

function fixture = create_multibmode_fixture()
    base = create_border_fixture();
    samplesPerBmode = base.geometry.samples_per_bmode;
    bmodeCount = 3;

    first = base.Bmode;
    second = base.Bmode;
    third = base.Bmode;
    second(170:190, :) = second(170:190, :) + 12;
    third(260:280, :) = third(260:280, :) + 8;
    first(:, end) = first(:, end) * 40;
    second(:, 1) = second(:, 1) * 0.02;
    second(:, end) = second(:, end) * 0.03;
    third(:, 1) = third(:, 1) * 35;

    fixture = struct();
    fixture.Bmode = [first second third];
    fixture.storageAxis = 1:(samplesPerBmode * bmodeCount);
    fixture.localAxisMm = base.localAxisMm;
    fixture.geometry = base.geometry;
    fixture.geometry.bmode_count = bmodeCount;
    fixture.geometry.lateral_sample_count = samplesPerBmode * bmodeCount;
    fixture.Zaxis = base.Zaxis;
    fixture.sampleOptics = base.sample_optics;
    fixture.phantomOptions = base.explicitPhantomOptions;
    fixture.adaptiveOptions = base.explicitAdaptiveOptions;
    fixture.inVivoOptions = base.explicitInVivoOptions;
end

function result = run_detector(method, fixture, Bmode, options)
    [result.thickness, result.border, result.anterior, result.posterior] = ...
        method(fixture.storageAxis, fixture.localAxisMm, Bmode, ...
            fixture.geometry, fixture.Zaxis, options);
end

function singles = run_each_bmode(method, fixture, Bmode, options)
    bmodeCount = fixture.geometry.bmode_count;
    samplesPerBmode = fixture.geometry.samples_per_bmode;
    singles = repmat(struct('thickness', [], 'border', struct(), ...
        'anterior', [], 'posterior', []), bmodeCount, 1);
    for bmode = 1:bmodeCount
        range = bmode_range(fixture.geometry, bmode);
        geometry = fixture.geometry;
        geometry.bmode_count = 1;
        geometry.lateral_sample_count = samplesPerBmode;
        [singles(bmode).thickness, singles(bmode).border, ...
            singles(bmode).anterior, singles(bmode).posterior] = ...
            method(fixture.storageAxis(range), fixture.localAxisMm, ...
                Bmode(:, range), geometry, fixture.Zaxis, options);
    end
end

function assert_anterior_only_multibmode_contract(fixture)
    method = @oce.borders.methods.findPhantomBorders;
    options = fixture.phantomOptions;
    options.surface_mode = "anterior_only";

    combined = run_detector(method, fixture, fixture.Bmode, options);
    singles = run_each_bmode(method, fixture, fixture.Bmode, options);
    assert_concatenated_equivalence( ...
        combined, singles, "phantom_anterior_only");
    if ~all(isnan(combined.border.Idx_Down)) || ...
            ~all(isnan(combined.posterior(:, 2))) || ...
            ~all(isnan(combined.thickness)) || ...
            ~any(isfinite(combined.border.Idx_Up))
        error('OCE:BordersTest:AnteriorOnlyMultibmode', ...
            ['Anterior-only phantom mode must retain one anterior surface per ' ...
             'B-mode without producing posterior geometry or thickness.']);
    end

    modifiedBmode = fixture.Bmode;
    middle = bmode_range(fixture.geometry, 2);
    modifiedBmode(:, middle) = flipud(modifiedBmode(:, middle));
    modified = run_detector(method, fixture, modifiedBmode, options);
    assert_untouched_bmodes(combined, modified, fixture.geometry, ...
        "phantom_anterior_only");
    assert_middle_bmode_changed(combined, modified, middle, ...
        "phantom_anterior_only");
end

function assert_concatenated_equivalence(combined, singles, methodName)
    assert_exact(combined.thickness, vertcat(singles.thickness), ...
        methodName + ".thickness concatenation");
    assert_exact(combined.anterior, vertcat(singles.anterior), ...
        methodName + ".anterior concatenation");
    assert_exact(combined.posterior, vertcat(singles.posterior), ...
        methodName + ".posterior concatenation");

    names = string(fieldnames(combined.border));
    for name = names'
        expected = concatenate_diagnostic(singles, name);
        assert_exact(combined.border.(name), expected, ...
            methodName + "." + name + " concatenation");
    end
end

function expected = concatenate_diagnostic(singles, name)
    switch name
        case {"TopSearchRange", "BottomSearchRange", "CornealBand"}
            values = arrayfun(@(item) item.border.(name), singles, ...
                'UniformOutput', false);
            expected = vertcat(values{:});
        case "ThicknessRangePx"
            expected = singles(1).border.(name);
            for index = 2:numel(singles)
                assert_exact(expected, singles(index).border.(name), ...
                    name + " per-B-mode parameter");
            end
        otherwise
            values = arrayfun(@(item) item.border.(name), singles, ...
                'UniformOutput', false);
            expected = horzcat(values{:});
    end
end

function assert_untouched_bmodes(baseline, modified, geometry, methodName)
    untouched = [bmode_range(geometry, 1), bmode_range(geometry, 3)];
    assert_exact(baseline.border.Idx(untouched), ...
        modified.border.Idx(untouched), methodName + ".raw independence");
    assert_exact(baseline.border.Idx_Up(untouched), ...
        modified.border.Idx_Up(untouched), methodName + ".anterior independence");
    assert_exact(baseline.border.Idx_Down(untouched), ...
        modified.border.Idx_Down(untouched), methodName + ".posterior independence");
    assert_exact(baseline.thickness(untouched), ...
        modified.thickness(untouched), methodName + ".thickness independence");

    if isfield(baseline.border, 'BadColumns')
        assert_exact(baseline.border.BadColumns(untouched), ...
            modified.border.BadColumns(untouched), ...
            methodName + ".bad-column independence");
        rows = [1 3];
        diagnosticNames = ["TopSearchRange", "BottomSearchRange", "CornealBand"];
        for name = diagnosticNames
            assert_exact(baseline.border.(name)(rows, :), ...
                modified.border.(name)(rows, :), ...
                methodName + "." + name + " independence");
        end
    end
end

function assert_middle_bmode_changed(baseline, modified, middle, methodName)
    changed = ~isequaln(baseline.border.Idx_Up(middle), ...
        modified.border.Idx_Up(middle)) || ...
        ~isequaln(baseline.border.Idx_Down(middle), ...
            modified.border.Idx_Down(middle)) || ...
        ~isequaln(baseline.thickness(middle), modified.thickness(middle));
    if ~changed
        error('OCE:BordersTest:VacuousBmodePerturbation', ...
            'Middle-B-mode perturbation did not affect %s.', methodName);
    end
end

function assert_edge_exclusion_contract(fixture)
    state = make_state(fixture, fixture.Bmode);
    base = oce.config.getDefaultProcessingConfig("in_vivo_eye").BorderOptions;
    base.selection = "manual";
    base.method = "in_vivo_corneal";
    crop = struct('depth', struct('sample_count', size(fixture.Bmode, 1)));

    disabled = oce.config.resolveBorderOptions(base, table(), crop);
    disabledResult = oce.borders.detectAndMask(state, disabled);

    zero = base;
    zero.lateral_edge_exclusion.enabled = true;
    zero.lateral_edge_exclusion.fraction_per_side = 0;
    zeroResult = oce.borders.detectAndMask( ...
        state, oce.config.resolveBorderOptions(zero, table(), crop));
    assert_exact(disabledResult, zeroResult, ...
        "zero-fraction edge exclusion");

    enabled = base;
    enabled.lateral_edge_exclusion.enabled = true;
    enabled.lateral_edge_exclusion.fraction_per_side = 0.10;
    enabledResult = oce.borders.detectAndMask( ...
        state, oce.config.resolveBorderOptions(enabled, table(), crop));

    excluded = expected_excluded( ...
        fixture.geometry, enabled.lateral_edge_exclusion.fraction_per_side);
    retained = ~excluded;
    assert_exact(disabledResult.indices.raw, enabledResult.indices.raw, ...
        "edge exclusion raw candidates");
    assert_exact(disabledResult.indices.BadColumns, ...
        enabledResult.indices.BadColumns, "edge exclusion diagnostics");
    assert_exact(disabledResult.indices.TopSearchRange, ...
        enabledResult.indices.TopSearchRange, "edge exclusion search ranges");
    assert_exact(disabledResult.indices.anterior(retained), ...
        enabledResult.indices.anterior(retained), "retained anterior");
    assert_exact(disabledResult.indices.posterior(retained), ...
        enabledResult.indices.posterior(retained), "retained posterior");
    assert_exact(disabledResult.thickness(retained), ...
        enabledResult.thickness(retained), "retained thickness");
    assert_exact(disabledResult.intensityMask, enabledResult.intensityMask, ...
        "edge exclusion intensity mask");

    if ~all(isnan(enabledResult.indices.anterior(excluded))) || ...
            ~all(isnan(enabledResult.indices.posterior(excluded))) || ...
            ~all(isnan(enabledResult.anteriorSurface(excluded, 2))) || ...
            ~all(isnan(enabledResult.posteriorSurface(excluded, 2))) || ...
            ~all(isnan(enabledResult.thickness(excluded)))
        error('OCE:BordersTest:InconsistentEdgeExclusion', ...
            'Common edge exclusion did not invalidate all final products.');
    end
end

function assert_small_bmode_protection(fixture)
    samplesPerBmode = 5;
    bmodeCount = 3;
    columns = 1:samplesPerBmode;
    small = fixture;
    small.Bmode = repmat(fixture.Bmode(:, columns), 1, bmodeCount);
    small.storageAxis = 1:(samplesPerBmode * bmodeCount);
    small.localAxisMm = linspace(0, 1, samplesPerBmode);
    small.geometry.samples_per_bmode = samplesPerBmode;
    small.geometry.bmode_count = bmodeCount;
    small.geometry.lateral_sample_count = samplesPerBmode * bmodeCount;
    small.geometry.bmode_lateral_axis_mm = small.localAxisMm;
    state = make_state(small, small.Bmode);

    base = oce.config.getDefaultProcessingConfig("in_vivo_eye").BorderOptions;
    base.selection = "manual";
    base.method = "in_vivo_corneal";
    base.lateral_edge_exclusion.enabled = true;
    base.lateral_edge_exclusion.fraction_per_side = 0.49;
    crop = struct('depth', struct('sample_count', size(small.Bmode, 1)));
    result = oce.borders.detectAndMask( ...
        state, oce.config.resolveBorderOptions(base, table(), crop));

    for bmode = 1:bmodeCount
        center = bmode_range(small.geometry, bmode);
        center = center(ceil(end / 2));
        if isnan(result.indices.anterior(center)) && ...
                isnan(result.indices.posterior(center)) && ...
                isnan(result.thickness(center))
            error('OCE:BordersTest:SmallBmodeFullyExcluded', ...
                'Edge exclusion invalidated the only retained sample.');
        end
    end
end

function assert_edge_exclusion_validation()
    base = oce.config.getDefaultProcessingConfig("phantom").BorderOptions;
    base.selection = "manual";
    base.method = "phantom";
    crop = struct('depth', struct('sample_count', 1000));

    oldConfig = rmfield(base, 'lateral_edge_exclusion');
    resolvedOld = oce.config.resolveBorderOptions(oldConfig, table(), crop);
    if resolvedOld.lateral_edge_exclusion.enabled || ...
            resolvedOld.lateral_edge_exclusion.fraction_per_side ~= 0.02
        error('OCE:BordersTest:LegacyEdgeDefault', ...
            'Missing edge policy did not resolve to the maintained default.');
    end

    base.methods.phantom.edge_margin = 20;
    resolved = oce.config.resolveBorderOptions(base, table(), crop);
    if isfield(resolved.parameters, 'edge_margin')
        error('OCE:BordersTest:LegacyPhantomEdgePolicy', ...
            'Legacy phantom edge_margin remains active at runtime.');
    end

    invalidFractions = {-0.01, 0.5, NaN, Inf, 0.1 + 0.2i};
    for index = 1:numel(invalidFractions)
        invalid = base;
        invalid.lateral_edge_exclusion.fraction_per_side = ...
            invalidFractions{index};
        assert_identifier('OCE:Config:InvalidBorderEdgeExclusion', @() ...
            oce.config.resolveBorderOptions(invalid, table(), crop));
    end
    invalid = base;
    invalid.lateral_edge_exclusion.enabled = 1;
    assert_identifier('OCE:Config:InvalidBorderEdgeExclusion', @() ...
        oce.config.resolveBorderOptions(invalid, table(), crop));
end

function state = make_state(fixture, Bmode)
    zAxis = fixture.Zaxis;
    reconstruction = make_reconstruction_result( ...
        Bmode, fixture.storageAxis, zAxis, 0);
    state = struct( ...
        'geometry', fixture.geometry, ...
        'reconstruction', reconstruction);
end

function excluded = expected_excluded(geometry, fraction)
    samplesPerBmode = geometry.samples_per_bmode;
    margin = max(1, round(fraction * samplesPerBmode));
    margin = min(margin, floor((samplesPerBmode - 1) / 2));
    excluded = false(1, geometry.lateral_sample_count);
    for bmode = 1:geometry.bmode_count
        range = bmode_range(geometry, bmode);
        excluded(range([1:margin, end - margin + 1:end])) = true;
    end
end

function range = bmode_range(geometry, bmode)
    range = (bmode - 1) * geometry.samples_per_bmode + ...
        (1:geometry.samples_per_bmode);
end

function assert_exact(expected, actual, label)
    if ~isequaln(expected, actual)
        error('OCE:BordersTest:BmodeDifference', ...
            '%s differs.', label);
    end
end

function assert_identifier(expected, callback)
    try
        callback();
    catch ME
        if string(ME.identifier) == string(expected)
            return;
        end
        error('OCE:BordersTest:WrongIdentifier', ...
            'Expected %s; actual=%s.', expected, ME.identifier);
    end
    error('OCE:BordersTest:MissingError', ...
        'Expected error %s was not raised.', expected);
end
