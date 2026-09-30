function test_motion_domain_resolution(context)
%TEST_MOTION_DOMAIN_RESOLUTION Verify phase-estimation ownership and callers.

    canonical = {
        'oce.motion.computeDepthResolvedPhase', ...
            'src/+oce/+motion/computeDepthResolvedPhase.m';
        'oce.motion.computeSurfacePhase', ...
            'src/+oce/+motion/computeSurfacePhase.m';
        'oce.motion.estimateLoupasPhaseIncrement', ...
            'src/+oce/+motion/estimateLoupasPhaseIncrement.m';
        'oce.config.resolvePhaseEstimationOptions', ...
            'src/+oce/+config/resolvePhaseEstimationOptions.m'};
    assert_unique_locations(canonical, context.repoRoot);
    assert_absent(["oce.motion.computeMotion"; ...
        "oce.motion.computeBorderMotion"; ...
        "oce.motion.computeLoupasPhaseDifference"; ...
        "oce.config.resolveMotionOptions"; ...
        "MotionAnalysis"; "MotionAnalysisBorder"]);
    assert_package_contents(context.repoRoot, ...
        ["computeDepthResolvedPhase.m", "computeSurfacePhase.m", ...
        "estimateLoupasPhaseIncrement.m"]);

    caller = fileread(fullfile(context.repoRoot, 'src', '+oce', ...
        '+pipeline', 'processPreparedAcquisition.m'));
    required = ["oce.motion.computeDepthResolvedPhase"; ...
        "oce.motion.computeSurfacePhase"];
    for index = 1:numel(required)
        assert(count(caller, required(index)) == 1, ...
            'Maintained pipeline must call %s exactly once.', required(index));
    end
    retired = ["computeMotion"; "computeBorderMotion"; ...
        "loaded_phases"; "loaded_phases_Border"];
    assert(~any(contains(caller, retired)), ...
        'Maintained pipeline retains a retired phase contract.');

    roots = [fullfile(context.repoRoot, 'src'); ...
        fullfile(context.repoRoot, 'workflows')];
    forbiddenTokens = ["LineOrFrame"; "MotionType"; "LoupasAxialWin"; ...
        "SmoothingWinPer"; "BorderMotionType"; "BorderDelta"; ...
        "BorderLoupasAxialWin"; "BorderSmoothingWinPer"];
    for rootIndex = 1:numel(roots)
        files = dir(fullfile(roots(rootIndex), '**', '*.m'));
        for fileIndex = 1:numel(files)
            source = string(fileread(fullfile(files(fileIndex).folder, ...
                files(fileIndex).name)));
            assert(~any(contains(source, forbiddenTokens)), ...
                'Retired phase option remains in %s.', files(fileIndex).name);
        end
    end
end

function assert_absent(names)
    for index = 1:numel(names)
        assert(isempty(which(char(names(index)), '-all')), ...
            'Retired phase API still resolves: %s.', names(index));
    end
end

function assert_unique_locations(expected, repoRoot)
    for index = 1:size(expected, 1)
        locations = string(which(expected{index, 1}, '-all'));
        locations = locations(strlength(locations) > 0);
        assert(isscalar(locations), ...
            'Expected one resolution for %s.', expected{index, 1});
        expectedPath = fullfile(repoRoot, expected{index, 2});
        assert(strcmpi(normalize_path(locations), normalize_path(expectedPath)), ...
            '%s resolved at an unexpected path.', expected{index, 1});
    end
end

function assert_package_contents(repoRoot, expected)
    files = dir(fullfile(repoRoot, 'src', '+oce', '+motion', '*.m'));
    actual = sort(string({files.name}));
    assert(isequal(actual, sort(expected)), ...
        'The motion package contains unexpected files.');
end

function value = normalize_path(value)
    value = replace(string(value), ["/", "\"], filesep);
end
