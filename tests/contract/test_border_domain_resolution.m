function test_border_domain_resolution(context)
%TEST_BORDER_DOMAIN_RESOLUTION Verify border ownership and canonical methods.

    canonical = {
        'oce.borders.buildIntensityMask', ...
            'src/+oce/+borders/buildIntensityMask.m';
        'oce.borders.findSurface', 'src/+oce/+borders/findSurface.m';
        'oce.borders.resolveMethod', 'src/+oce/+borders/resolveMethod.m';
        'oce.borders.methods.findPhantomBorders', ...
            'src/+oce/+borders/+methods/findPhantomBorders.m';
        'oce.borders.methods.findAdaptiveCornealBorders', ...
            'src/+oce/+borders/+methods/findAdaptiveCornealBorders.m';
        'oce.borders.methods.findInVivoCornealBorders', ...
            'src/+oce/+borders/+methods/findInVivoCornealBorders.m'};
    assert_unique_locations(canonical, context.repoRoot, "canonical function");
    assert_absent(["FindBothConrealBorders", ...
        "FindBothCornealBordersAdaptive", "FindBothCornealBordersInVivo", ...
        "oce.borders.legacy.findBothCornealBorders"]);
    assert_files(context.repoRoot, fullfile('src', '+oce', '+borders'), ...
        ["buildIntensityMask.m", "detectAndMask.m", ...
        "findSurface.m", "resolveMethod.m"]);
    assert_files(context.repoRoot, ...
        fullfile('src', '+oce', '+borders', '+methods'), ...
        ["findAdaptiveCornealBorders.m", "findInVivoCornealBorders.m", ...
        "findPhantomBorders.m"]);

    expected = {
        "phantom", @oce.borders.methods.findPhantomBorders;
        "adaptive_corneal", @oce.borders.methods.findAdaptiveCornealBorders;
        "in_vivo_corneal", @oce.borders.methods.findInVivoCornealBorders};
    for index = 1:size(expected, 1)
        actual = oce.borders.resolveMethod(expected{index, 1});
        if ~strcmp(func2str(actual), func2str(expected{index, 2}))
            error('OCE:RegressionBorders:Method', ...
                'Method %s resolved to %s.', expected{index, 1}, func2str(actual));
        end
    end

    retiredIdentifiers = ["legacy", "findbothconrealborders", "adaptive", ...
        "corneal_adaptive", "invivo", "in_vivo", "invivo_corneal"];
    for index = 1:numel(retiredIdentifiers)
        captured = capture_error(@() oce.borders.resolveMethod(retiredIdentifiers(index)));
        if captured.identifier == ""
            error('OCE:RegressionBorders:RetiredIdentifier', ...
                'Retired method identifier still resolves: %s.', retiredIdentifiers(index));
        end
    end

    source = fileread(fullfile(context.repoRoot, ...
        'src', '+oce', '+borders', 'detectAndMask.m'));
    if count(source, 'oce.borders.resolveMethod') ~= 1 || contains(source, 'fprintf(')
        error('OCE:RegressionBorders:Coordinator', ...
            'detectAndMask must use one resolver and remain silent.');
    end
    if ~isempty(which('oce.borders.methods.findLegacyBorders', '-all')) || ...
            isfile(fullfile(context.repoRoot, 'src', '+oce', '+borders', ...
            '+methods', 'findLegacyBorders.m'))
        error('OCE:RegressionBorders:RetiredMethod', ...
            'The retired legacy border method still resolves or exists.');
    end
end

function assert_absent(names)
    for idx = 1:numel(names)
        if ~isempty(which(char(names(idx)), '-all'))
            error('OCE:RegressionBorders:RetiredAdapter', ...
                'Retired border API still resolves: %s.', names(idx));
        end
    end
end

function assert_unique_locations(expected, repoRoot, description)
    for idx = 1:size(expected, 1)
        locations = string(which(expected{idx, 1}, '-all'));
        locations = locations(strlength(locations) > 0);
        if numel(locations) ~= 1
            error('OCE:RegressionBorders:Resolution', ...
                'Expected one %s for %s; actual count=%d.', ...
                description, expected{idx, 1}, numel(locations));
        end
        expectedPath = fullfile(repoRoot, expected{idx, 2});
        if ~strcmpi(normalize_path(locations), normalize_path(expectedPath))
            error('OCE:RegressionBorders:Resolution', ...
                '%s expected at %s; actual=%s.', ...
                expected{idx, 1}, expectedPath, locations);
        end
    end
end

function assert_files(repoRoot, relativeFolder, expected)
    files = dir(fullfile(repoRoot, relativeFolder, '*.m'));
    actual = sort(string({files.name}));
    if ~isequal(actual, sort(expected))
        error('OCE:RegressionBorders:PackageContents', ...
            '%s expected=%s; actual=%s.', relativeFolder, ...
            strjoin(sort(expected), ', '), strjoin(actual, ', '));
    end
end

function captured = capture_error(callback)
    captured = struct('identifier', "", 'message', "");
    try
        callback();
    catch ME
        captured.identifier = string(ME.identifier);
        captured.message = string(ME.message);
    end
end

function value = normalize_path(value)
    value = replace(string(value), ["/", "\"], filesep);
end
