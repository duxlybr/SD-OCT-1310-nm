function test_border_domain_contract(~)
%TEST_BORDER_DOMAIN_CONTRACT Validate maintained border outputs and side effects.

    fixture = create_border_fixture();
    methods = { ...
        "phantom", @oce.borders.methods.findPhantomBorders, ...
            fixture.explicitPhantomOptions; ...
        "adaptive", @oce.borders.methods.findAdaptiveCornealBorders, ...
            fixture.explicitAdaptiveOptions; ...
        "in_vivo", @oce.borders.methods.findInVivoCornealBorders, ...
            fixture.explicitInVivoOptions};

    for index = 1:size(methods, 1)
        figuresBefore = findall(groot, 'Type', 'figure');
        workDir = tempname;
        mkdir(workDir);
        oldDir = pwd;
        cleanup = onCleanup(@() cleanup_workdir(oldDir, workDir));
        cd(workDir);

        [thickness, border, anterior, posterior] = methods{index, 2}( ...
            fixture.Xaxis, fixture.localAxisMm, fixture.Bmode, ...
            fixture.geometry, fixture.Zaxis, methods{index, 3});

        assert_border_contract(thickness, border, anterior, posterior, fixture);
        % Use an independent affine reference, including fractional fit indices.
        dz = fixture.geometry.depth_sample_interval_mm;
        assert(max(abs(anterior(:,2) - (border.Idx_Up(:)-1)*dz), [], 'omitnan') < 1e-12);
        assert(max(abs(posterior(:,2) - (border.Idx_Down(:)-1)*dz), [], 'omitnan') < 1e-12);
        assert(~isfield(border, 'DepthPos'), 'Physical depth is owned by reconstruction.');
        shiftedAxis = fixture.Zaxis + 0.25;
        [shiftedThickness, shiftedIndices, shiftedAnterior, shiftedPosterior] = ...
            methods{index, 2}(fixture.Xaxis, fixture.localAxisMm, fixture.Bmode, ...
                fixture.geometry, shiftedAxis, methods{index, 3});
        assert(isequaln(border, shiftedIndices));
        assert(isequal(isnan(anterior), isnan(shiftedAnterior)));
        assert(max(abs(shiftedAnterior(:,2)-anterior(:,2)-0.25), [], 'omitnan') < 1e-12);
        assert(max(abs(shiftedPosterior(:,2)-posterior(:,2)-0.25), [], 'omitnan') < 1e-12);
        assert(max(abs(shiftedThickness-thickness), [], 'omitnan') < 1e-12);
        if numel(findall(groot, 'Type', 'figure')) ~= numel(figuresBefore)
            error('OCE:BordersTest:UnexpectedFigure', ...
                'Border detector created a figure.');
        end
        if ~isempty(dir('BmodeBorder.*'))
            error('OCE:BordersTest:UnexpectedFile', ...
                'Border detector wrote preview files.');
        end
        clear cleanup
    end

    reconstruction = make_reconstruction_result( ...
        fixture.Bmode, fixture.Xaxis, fixture.Zaxis, 0);
    state = struct( ...
        'geometry', fixture.geometry, ...
        'reconstruction', reconstruction);
    base = oce.config.getDefaultProcessingConfig("phantom").BorderOptions;
    base.selection = "manual";
    base.method = "in_vivo_corneal";
    options = oce.config.resolveBorderOptions(base, table(), ...
        struct('depth', struct( ...
            'sample_count', size(fixture.Bmode, 1))));
    result = oce.borders.detectAndMask(state, options);
    expectedFields = ["surface_mode"; "thickness"; "indices"; ...
        "anteriorSurface"; "posteriorSurface"; "intensityMask"];
    if ~isequal(string(fieldnames(result)), expectedFields) || ...
            result.surface_mode ~= "anterior_posterior"
        error('OCE:BordersTest:ResultFields', ...
            'Unexpected border result fields or surface mode.');
    end
    if ~islogical(result.intensityMask) || ...
            ~isequal(size(result.intensityMask), size(fixture.Bmode))
        error('OCE:BordersTest:Mask', ...
            'Intensity mask contract is invalid.');
    end
    logValues = reconstruction.log_amplitude.values;
    lowerMask = oce.borders.buildIntensityMask( ...
        reconstruction, min(logValues, [], 'all') - 1);
    higherMask = oce.borders.buildIntensityMask( ...
        reconstruction, max(logValues, [], 'all') + 1);
    if any(higherMask(:) & ~lowerMask(:)) || isequal(lowerMask, higherMask)
        error('OCE:BordersTest:MaskThreshold', ...
            'Mask threshold did not independently control intensityMask.');
    end
    retainedBorders = rmfield(result, 'intensityMask');
    result.intensityMask = higherMask;
    if ~isequaln(rmfield(result, 'intensityMask'), retainedBorders)
        error('OCE:BordersTest:MaskGeometry', ...
            'Updating intensityMask changed border geometry.');
    end

    assert_anterior_only_contract(state, fixture);
    assert_first_depth_sample();

    compare_identifier("OCE:Borders:InvalidResolvedOptions", @() ...
        oce.borders.detectAndMask(state, base));
    invalid = options;
    invalid.method = "legacy";
    compare_identifier("OCE:Borders:UnsupportedMethod", @() ...
        oce.borders.detectAndMask(state, invalid));
    compare_identifier("OCE:Borders:InvalidMaskThreshold", @() ...
        oce.borders.buildIntensityMask(reconstruction, NaN));
end

function assert_first_depth_sample()
    fixture = create_border_fixture();
    bmode = ones(40, 12);
    bmode(19:21,:) = 100;
    geometry = fixture.geometry;
    geometry.lateral_sample_count = 12;
    geometry.samples_per_bmode = 12;
    geometry.depth_sample_count = 40;
    options = fixture.explicitPhantomOptions;
    options.surface_mode = "anterior_only";
    options.top_search_offset = 9;
    options.top_index_offset = 19;
    options.top_peak_multiplier = 1;
    options.peak_window_size = 5;
    options.max_depth_index = 40;
    axisMm = 0.12 + (0:39)' * 0.003;
    [~, indices, anterior] = oce.borders.methods.findPhantomBorders( ...
        1:12, linspace(0,1,12), bmode, geometry, axisMm, options);
    assert(all(indices.Idx_Up == 1));
    assert(all(anterior(:,2) == axisMm(1)), ...
        'MATLAB index one must use the first reconstruction depth coordinate.');
end

function assert_anterior_only_contract(state, fixture)
    crop = struct('depth', struct('sample_count', size(fixture.Bmode, 1)));
    base = oce.config.getDefaultProcessingConfig("phantom").BorderOptions;
    base.selection = "manual";
    base.method = "phantom";

    fullOptions = oce.config.resolveBorderOptions(base, table(), crop);
    fullResult = oce.borders.detectAndMask(state, fullOptions);

    anteriorOnly = base;
    anteriorOnly.methods.phantom.surface_mode = "anterior_only";
    resolved = oce.config.resolveBorderOptions(anteriorOnly, table(), crop);
    result = oce.borders.detectAndMask(state, resolved);

    if resolved.surface_mode ~= "anterior_only" || ...
            result.surface_mode ~= "anterior_only" || ...
            ~isequaln(result.indices.anterior, fullResult.indices.anterior) || ...
            ~isequaln(result.anteriorSurface, fullResult.anteriorSurface) || ...
            ~all(isnan(result.indices.posterior)) || ...
            ~all(isnan(result.posteriorSurface(:, 2))) || ...
            ~all(isnan(result.thickness)) || ...
            ~isequal(result.intensityMask, fullResult.intensityMask)
        error('OCE:BordersTest:AnteriorOnlyContract', ...
            ['Anterior-only phantom mode must preserve anterior detection and ' ...
             'leave posterior geometry and thickness unavailable.']);
    end

    previousConfig = base;
    previousConfig.methods.phantom = rmfield( ...
        previousConfig.methods.phantom, 'surface_mode');
    previousResolved = oce.config.resolveBorderOptions( ...
        previousConfig, table(), crop);
    if previousResolved.surface_mode ~= "anterior_posterior" || ...
            previousResolved.parameters.surface_mode ~= "anterior_posterior"
        error('OCE:BordersTest:SurfaceModeDefault', ...
            'Missing phantom surface_mode did not resolve to the maintained default.');
    end

    invalid = base;
    invalid.methods.phantom.surface_mode = "unsupported";
    compare_identifier("OCE:Config:InvalidBorderSurfaceMode", @() ...
        oce.config.resolveBorderOptions(invalid, table(), crop));
end

function assert_border_contract(thickness, border, anterior, posterior, fixture)
    count = fixture.geometry.lateral_sample_count;
    if ~isequal(size(thickness), [count 1]) || ...
            ~isequal(size(anterior), [count 2]) || ...
            ~isequal(size(posterior), [count 2])
        error('OCE:BordersTest:Dimensions', ...
            'Border output dimensions are invalid.');
    end
    required = ["Idx"; "Idx_Up"; "Idx_Down"];
    for index = 1:numel(required)
        if ~isfield(border, required(index)) || ...
                numel(border.(required(index))) ~= count
            error('OCE:BordersTest:Indices', ...
                'Border index contract is missing %s.', required(index));
        end
    end

    finiteThickness = thickness(isfinite(thickness));
    if isempty(finiteThickness) || any(finiteThickness < 0)
        error('OCE:BordersTest:Thickness', ...
            'Finite thickness values must exist and be nonnegative.');
    end
end

function compare_identifier(expectedIdentifier, callback)
    actualIdentifier = "";
    try
        callback();
    catch ME
        actualIdentifier = string(ME.identifier);
    end
    if actualIdentifier ~= expectedIdentifier
        error('OCE:BordersTest:ErrorIdentifier', ...
            'Expected identifier=%s; actual=%s.', ...
            expectedIdentifier, actualIdentifier);
    end
end

function cleanup_workdir(oldDir, workDir)
    cd(oldDir);
    if isfolder(workDir)
        rmdir(workDir, 's');
    end
end
