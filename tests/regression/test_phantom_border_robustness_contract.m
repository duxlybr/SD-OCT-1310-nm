function test_phantom_border_robustness_contract(~)
%TEST_PHANTOM_BORDER_ROBUSTNESS_CONTRACT Lock phantom local robustness semantics.

    fixture = create_border_fixture();
    options = fixture.explicitPhantomOptions;
    nCols = fixture.geometry.samples_per_bmode;

    top = 120 * ones(1, nCols);
    bottom = 320 * ones(1, nCols);
    baselineBmode = make_phantom_bmode( ...
        fixture.geometry.depth_sample_count, top, bottom);
    baseline = run_phantom(fixture, baselineBmode, options);
    assert_offset_geometry(fixture, baselineBmode, options, baseline);
    baselineAnterior = median(baseline.border.Idx_Up, 'omitnan');

    if ~isfinite(baseline.border.Idx(end))
        error('OCE:BordersTest:PhantomLastCandidate', ...
            'The final local anterior candidate was discarded unconditionally.');
    end

    rightTop = top;
    rightTop(end - 2:end) = 200;
    right = run_phantom(fixture, ...
        make_phantom_bmode(fixture.geometry.depth_sample_count, ...
            rightTop, bottom), options);
    assert_all_nan(right.border.Idx(end - 2:end), ...
        'right-edge short anterior excursion');
    assert_finite(right.border.Idx(end - 3), ...
        'right-edge retained anterior anchor');
    assert_stable_final_anterior(right.border.Idx_Up(end - 2:end), ...
        baselineAnterior, options.max_lateral_jump, ...
        'right-edge short anterior excursion');

    leftTop = top;
    leftTop(1:3) = 200;
    left = run_phantom(fixture, ...
        make_phantom_bmode(fixture.geometry.depth_sample_count, ...
            leftTop, bottom), options);
    assert_all_nan(left.border.Idx(1:3), ...
        'left-edge short anterior excursion');
    assert_finite(left.border.Idx(4), ...
        'left-edge retained anterior anchor');
    assert_stable_final_anterior(left.border.Idx_Up(1:3), ...
        baselineAnterior, options.max_lateral_jump, ...
        'left-edge short anterior excursion');

    interiorTop = top;
    interiorTop(59:61) = 200;
    interior = run_phantom(fixture, ...
        make_phantom_bmode(fixture.geometry.depth_sample_count, ...
            interiorTop, bottom), options);
    assert_all_nan(interior.border.Idx(59:61), ...
        'interior short anterior excursion');
    assert_finite(interior.border.Idx(58), ...
        'interior left retained anterior anchor');
    assert_finite(interior.border.Idx(62), ...
        'interior right retained anterior anchor');

    longTop = top;
    longTop(end - 4:end) = 200;
    longEdge = run_phantom(fixture, ...
        make_phantom_bmode(fixture.geometry.depth_sample_count, ...
            longTop, bottom), options);
    if all(isnan(longEdge.border.Idx(end - 4:end)))
        error('OCE:BordersTest:PhantomLongEdgeExcursion', ...
            ['An edge excursion longer than max_jump_gap was rejected as ' ...
             'though it were a short excursion.']);
    end

    % A short false branch followed by loss of surface detection must remain a
    % short supported excursion. Missing edge columns do not add evidence that
    % the false branch is physically long.
    unsupportedBmode = baselineBmode;
    unsupportedBmode(:, end - 10:end) = 1;
    falseColumn = make_phantom_bmode( ...
        fixture.geometry.depth_sample_count, 200, 320);
    unsupportedBmode(:, end - 10) = falseColumn;
    unsupported = run_phantom(fixture, unsupportedBmode, options);
    assert_all_nan(unsupported.border.Idx(end - 10:end), ...
        'unsupported right-edge anterior branch');
    assert_stable_final_anterior(unsupported.border.Idx_Up(end - 10:end), ...
        baselineAnterior, options.max_lateral_jump, ...
        'unsupported right-edge anterior branch');

    posteriorBottom = bottom;
    posteriorBottom(end - 2:end) = 360;
    posterior = run_phantom(fixture, ...
        make_phantom_bmode(fixture.geometry.depth_sample_count, ...
            top, posteriorBottom), options);
    referencePosterior = median( ...
        posterior.border.Idx_Down(1:end - 3), 'omitnan');
    edgePosterior = posterior.border.Idx_Down(end - 2:end);
    finiteEdge = edgePosterior(isfinite(edgePosterior));
    if isempty(finiteEdge) || ...
            any(abs(finiteEdge - referencePosterior) > options.max_lateral_jump)
        error('OCE:BordersTest:PhantomPosteriorExcursion', ...
            ['Posterior-only short edge excursion was not rejected before ' ...
             'posterior smoothing.']);
    end

    contaminated = baselineBmode;
    contaminated(50:100, 10:30) = 12;
    contaminatedResult = run_phantom(fixture, contaminated, options);
    assert_exact(baseline.border.Idx_Down, ...
        contaminatedResult.border.Idx_Down, ...
        'fixed-window intensity contamination posterior');
    assert_exact(baseline.thickness, contaminatedResult.thickness, ...
        'fixed-window intensity contamination thickness');

    shallowTop = 24 * ones(1, nCols);
    shallowBottom = 224 * ones(1, nCols);
    shallow = run_phantom(fixture, ...
        make_phantom_bmode(fixture.geometry.depth_sample_count, ...
            shallowTop, shallowBottom), options);
    finiteAnterior = shallow.border.Idx_Up(isfinite(shallow.border.Idx_Up));
    if isempty(finiteAnterior) || median(finiteAnterior) >= 30
        error('OCE:BordersTest:PhantomShallowSurface', ...
            ['A valid shallow anterior surface was suppressed by an ' ...
             'additional phantom depth prior.']);
    end

    assert_legacy_phantom_resolution();
end

function assert_offset_geometry(fixture, Bmode, options, historical)
    % The flat interfaces isolate index offsets from nearest-neighbor geometry:
    % changing 4/4 to 2/0 reduces thickness by exactly six physical depth bins.
    currentOptions = options;
    currentOptions.top_search_offset = 0;
    currentOptions.top_index_offset = 2;
    currentOptions.bottom_index_offset = 0;
    current = run_phantom(fixture, Bmode, currentOptions);
    assert_exact(historical.border.Idx_Up + 2, current.border.Idx_Up, ...
        'anterior offset shift');
    assert_exact(historical.border.Idx_Down - 4, current.border.Idx_Down, ...
        'posterior offset shift');
    dz = 7.1 / 1.4 * 1e-3;
    assert(all(abs(historical.thickness - current.thickness - 6 * dz) < 1e-12), ...
        'Flat-interface thickness must decrease by six depth bins.');

    currentOptions.top_search_offset = 9;
    shiftedSearch = run_phantom(fixture, Bmode, currentOptions);
    assert(isequaln(current, shiftedSearch), ...
        'Search starts before these interfaces must preserve the result.');
end

function result = run_phantom(fixture, Bmode, options)
    [result.thickness, result.border, result.anterior, result.posterior] = ...
        oce.borders.methods.findPhantomBorders( ...
            fixture.Xaxis, fixture.localAxisMm, Bmode, fixture.geometry, ...
            fixture.Zaxis, options);
end

function Bmode = make_phantom_bmode(nDepth, topIdx, bottomIdx)
    nCols = numel(topIdx);
    Bmode = ones(nDepth, nCols);
    for column = 1:nCols
        top = round(topIdx(column));
        bottom = round(bottomIdx(column));
        Bmode(top:bottom, column) = 6;
        Bmode(top - 2:top + 2, column) = 101;
        Bmode(bottom - 2:bottom + 2, column) = 81;
    end
end

function assert_legacy_phantom_resolution()
    base = oce.config.getDefaultProcessingConfig("phantom").BorderOptions;
    if isfield(base.methods.phantom, 'min_depth_index')
        error('OCE:BordersTest:PhantomMinimumDepthDefault', ...
            'Canonical phantom defaults still expose min_depth_index.');
    end

    base.selection = "manual";
    base.method = "phantom";
    base.methods.phantom = rmfield( ...
        base.methods.phantom, 'background_percentile');
    base.methods.phantom.background_depth_range = [50 100];
    base.methods.phantom.background_lateral_range = [10 30];
    base.methods.phantom.min_depth_index = 30;
    crop = struct('depth', struct('sample_count', 1000));

    resolved = oce.config.resolveBorderOptions(base, table(), crop);
    if isfield(resolved.parameters, 'background_depth_range') || ...
            isfield(resolved.parameters, 'background_lateral_range') || ...
            isfield(resolved.parameters, 'min_depth_index') || ...
            ~isfield(resolved.parameters, 'background_percentile') || ...
            resolved.parameters.background_percentile ~= 10
        error('OCE:BordersTest:PhantomOptionMigration', ...
            'Legacy phantom options did not resolve to the canonical contract.');
    end

    invalid = base;
    invalid.methods.phantom.background_percentile = 75;
    assert_identifier('OCE:Config:InvalidBorderSelection', @() ...
        oce.config.resolveBorderOptions(invalid, table(), crop));
end

function assert_all_nan(value, label)
    if ~all(isnan(value))
        error('OCE:BordersTest:PhantomShortExcursion', ...
            '%s was not fully rejected.', label);
    end
end

function assert_finite(value, label)
    if ~isfinite(value)
        error('OCE:BordersTest:PhantomRetainedAnchor', ...
            '%s was invalidated.', label);
    end
end

function assert_stable_final_anterior(value, reference, limit, label)
    finite = value(isfinite(value));
    if isempty(finite) || any(abs(finite - reference) > limit)
        error('OCE:BordersTest:PhantomFinalAnterior', ...
            '%s produced an unstable final anterior border.', label);
    end
end

function assert_exact(expected, actual, label)
    if ~isequaln(expected, actual)
        delta = abs(double(expected) - double(actual));
        error('OCE:BordersTest:PhantomRobustnessDifference', ...
            '%s differs; maxabs=%g.', ...
            label, max(delta(:), [], 'omitnan'));
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
