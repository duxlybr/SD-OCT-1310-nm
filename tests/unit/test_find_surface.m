function test_find_surface(context) %#ok<INUSD>
%TEST_FIND_SURFACE Permanent contract for oce.borders.findSurface.

    base = ones(40, 4);
    geometry = struct('PeakThresMult', 1, ...
        'PeakThresWinSize', 5, 'lateral_sample_count', 4);

    singlePeak = base;
    singlePeak(19:21, :) = 100;
    transcript = evalc(['singleResult = oce.borders.findSurface(' ...
        'singlePeak, geometry);']);
    assert(isempty(transcript), ...
        'FindSurface must remain silent during domain calculation.');
    assert(isequal(fieldnames(singleResult), {'Idx'; 'Inten'}), ...
        'FindSurface field names or order changed.');
    assertExactNumericContract([20 20 20 20], singleResult.Idx, ...
        'FindSurface.single.Idx');
    assertExactNumericContract(40 * ones(1, 4), singleResult.Inten, ...
        'FindSurface.single.Inten');

    multiplePeaks = base;
    multiplePeaks(15:17, :) = 50;
    multiplePeaks(27:29, :) = 100;
    multipleResult = call_surface(multiplePeaks, geometry);
    assertExactNumericContract([16 16 16 16], multipleResult.Idx, ...
        'FindSurface.multiple.Idx');
    assertExactNumericContract(33.979400086720375 * ones(1, 4), ...
        multipleResult.Inten, 'FindSurface.multiple.Inten');

    assert_all_nan(call_surface(base, geometry), ...
        'FindSurface.noPeak');
    assert_all_nan(call_surface(5 * base, geometry), ...
        'FindSurface.flat');
    assert_all_nan(call_surface(NaN(size(base)), geometry), ...
        'FindSurface.allNaN');
    assert_all_nan(call_surface(zeros(size(base)), geometry), ...
        'FindSurface.allNegativeInf');

    rng(1101, 'twister');
    noisy = base + 0.02 * rand(size(base));
    noisy(19:21, :) = 100;
    noisyResult = call_surface(noisy, geometry);
    assertExactNumericContract([20 20 20 20], noisyResult.Idx, ...
        'FindSurface.noise.Idx');

    localizedNaN = singlePeak;
    localizedNaN(20, 2) = NaN;
    nanResult = call_surface(localizedNaN, geometry);
    assertExactNumericContract([NaN NaN NaN 20], nanResult.Idx, ...
        'FindSurface.localizedNaN.Idx');

    lowerPeak = base;
    lowerPeak(10:12, :) = 100;
    assert_all_nan(call_surface(lowerPeak, geometry), ...
        'FindSurface.lowerBoundary');
    upperPeak = base;
    upperPeak(37:39, :) = 100;
    upperResult = call_surface(upperPeak, geometry);
    assertExactNumericContract([38 38 38 38], upperResult.Idx, ...
        'FindSurface.upperBoundary.Idx');

    highThreshold = geometry;
    highThreshold.PeakThresMult = 1000;
    warningStateBefore = warning;
    lastwarn('sentinel', 'OCE:FindSurfaceTest:Sentinel');
    thresholdResult = call_surface(singlePeak, highThreshold);
    [warningMessage, warningIdentifier] = lastwarn;
    assert(strcmp(warningMessage, 'sentinel') && ...
        strcmp(warningIdentifier, 'OCE:FindSurfaceTest:Sentinel'), ...
        'FindSurface high threshold must not issue a warning.');
    warningStateAfter = warning;
    assert(isequal(warningStateAfter, warningStateBefore), ...
        'FindSurface must not change warning state.');
    assert_all_nan(thresholdResult, 'FindSurface.highThreshold');

    singleResultFromSingle = call_surface(single(singlePeak), ...
        geometry);
    assert(isa(singleResultFromSingle.Idx, 'double'), ...
        'FindSurface single-input output class changed.');

    infInput = singlePeak;
    infInput(20, 2) = Inf;
    infResult = call_surface(infInput, geometry);
    assertExactNumericContract([40 Inf 40 40], infResult.Inten, ...
        'FindSurface.Inf.Inten');

    assert_error(@() oce.borders.findSurface(singlePeak, ...
        rmfield(geometry, 'PeakThresMult')), ...
        'MATLAB:nonExistentField');
    assert_error(@() oce.borders.findSurface( ...
        repmat(singlePeak, 1, 1, 2), geometry), ...
        'MATLAB:medfilt2:expected2D');
    assert_error(@() oce.borders.findSurface(ones(9, 4), ...
        geometry), 'MATLAB:badsubscript');

    intentional = singleResult.Idx;
    intentional(1) = intentional(1) + 1;
    assert_difference_detected(singleResult.Idx, intentional, ...
        'FindSurface.intentional.Idx');
end

function result = call_surface(Bmode, geometry) %#ok<INUSD>
    result = [];
    evalc('result = oce.borders.findSurface(Bmode, geometry);');
end

function assert_all_nan(result, path)
    assert(all(isnan(result.Idx)), '%s Idx must be all NaN.', path);
    assert(all(isnan(result.Inten)), '%s Inten must be all NaN.', path);
end

function assert_error(callback, expectedIdentifier)
    try
        callback();
    catch ME
        assert(strcmp(ME.identifier, expectedIdentifier), ...
            'Expected error %s; actual=%s.', expectedIdentifier, ME.identifier);
        return;
    end
    error('OCE:FindSurfaceTest:MissingError', ...
        'Expected error %s was not raised.', expectedIdentifier);
end

function assert_difference_detected(expected, actual, path)
    try
        assertExactNumericContract(expected, actual, path);
    catch ME
        assert(strcmp(ME.identifier, 'OCE:Contract:Difference'), ...
            'Unexpected negative-control error: %s.', ME.identifier);
        assert(contains(ME.message, 'absolute tolerance=0'), ...
            'Negative-control diagnostics omitted the tolerance.');
        return;
    end
    error('OCE:FindSurfaceTest:NegativeControl', ...
        'Intentional FindSurface difference was not detected.');
end
