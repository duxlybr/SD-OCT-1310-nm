function test_final_architecture_contract(context)
%TEST_FINAL_ARCHITECTURE_CONTRACT Validate canonical package ownership.

    assert_repository_layout(context.repoRoot);
    assert_documentation_surface(context.repoRoot);
    assert_single_permanent_runner(context.repoRoot);
    assert_no_historical_dependencies(context.repoRoot);

    sourceRoot = fullfile(context.repoRoot, 'src', '+oce');
    files = dir(fullfile(sourceRoot, '**', '*.m'));
    forbidden = '\<(cd|assignin|eval|evalin|global|addpath|genpath)\s*\(';

    for index = 1:numel(files)
        filePath = fullfile(files(index).folder, files(index).name);
        if ~is_private_source(filePath, sourceRoot)
            qualifiedName = package_name(filePath, context.repoRoot);
            locations = normalize_locations(which(char(qualifiedName), '-all'));
            assert_unique_resolution(qualifiedName, locations, filePath);
        end

        source = fileread(filePath);
        primaryName = primary_function_name(source);
        [~, expectedName] = fileparts(filePath);
        if primaryName ~= string(expectedName)
            error('OCE:Architecture:PrimaryName', ...
                'Primary function mismatch in %s: expected=%s actual=%s.', ...
                filePath, expectedName, primaryName);
        end
        if ~isempty(regexp(source, forbidden, 'once'))
            error('OCE:Architecture:ForbiddenApi', ...
                'Forbidden package API found in %s.', filePath);
        end
    end

    expectedFileChecks = [ ...
        "src/+oce/+borders/+methods/findAdaptiveCornealBorders.m"; ...
        "src/+oce/+acquisition/prepareAcquisitionParameters.m"; ...
        "src/+oce/+io/loadExperimentalLog.m"; ...
        "src/+oce/+config/saveProcessingConfig.m"];
    actualFileChecks = find_file_existence_checks(context.repoRoot);
    if ~isequal(sort(expectedFileChecks), sort(actualFileChecks))
        error('OCE:Architecture:PathFallbackInventory', ...
            'exist(...,''file'') inventory changed. Expected=%s Actual=%s.', ...
            strjoin(expectedFileChecks, ', '), strjoin(actualFileChecks, ', '));
    end

    detected = false;
    try
        assert_unique_resolution("oce.fake.duplicate", {"a.m", "b.m"}, "a.m");
    catch ME
        detected = strcmp(ME.identifier, 'OCE:Architecture:Resolution');
    end
    if ~detected
        error('OCE:Architecture:NegativeControl', ...
            'Duplicate-resolution negative control was not detected.');
    end

    assert_closure_negative_controls(context.repoRoot);
end

function assert_repository_layout(repoRoot)
    absent = ["Codes", "Processing"];
    for index = 1:numel(absent)
        if isfolder(fullfile(repoRoot, absent(index)))
            error('OCE:Architecture:RetiredRoot', ...
                'Retired root was reintroduced: %s.', absent(index));
        end
    end
    required = ["inherited/Codes", "inherited/Processing", ...
        "third_party/MIMT", "third_party/fireice"];
    for index = 1:numel(required)
        pathValue = fullfile(repoRoot, replace(required(index), '/', filesep));
        if ~isfolder(pathValue)
            error('OCE:Architecture:RequiredRoot', ...
                'Required architecture root is missing: %s.', required(index));
        end
    end
end

function assert_documentation_surface(repoRoot)
    required = ["AGENTS.md"; "README.md"; ...
        "docs/repository/final_architecture.md"; ...
        "docs/repository/validation_status.md"; ...
        "docs/project/scientific_audit.md"];
    for index = 1:numel(required)
        pathValue = fullfile(repoRoot, replace(required(index), '/', filesep));
        if ~isfile(pathValue)
            error('OCE:Architecture:DocumentationSurface', ...
                'Required maintained document is missing: %s.', required(index));
        end
    end
end

function assert_single_permanent_runner(repoRoot)
    runners = dir(fullfile(repoRoot, 'tests', 'runners', '*.m'));
    names = string({runners.name});
    if ~isequal(names, "run_regression_tests.m")
        error('OCE:Architecture:RunnerInventory', ...
            'Expected only run_regression_tests.m; actual=%s.', ...
            strjoin(names, ', '));
    end
end

function assert_no_historical_dependencies(repoRoot)
    roots = [fullfile(repoRoot, 'src'); fullfile(repoRoot, 'workflows')];
    backslash = string(char(92));
    forbidden = ["inherited/", "inherited" + backslash, ...
        "Codes/", "Codes" + backslash, ...
        "Processing/", "Processing" + backslash];
    for rootIndex = 1:numel(roots)
        files = dir(fullfile(roots(rootIndex), '**', '*.m'));
        for fileIndex = 1:numel(files)
            pathValue = fullfile(files(fileIndex).folder, files(fileIndex).name);
            source = fileread(pathValue);
            for tokenIndex = 1:numel(forbidden)
                if contains(source, forbidden(tokenIndex))
                    error('OCE:Architecture:HistoricalDependency', ...
                        'Historical token %s found in %s.', ...
                        forbidden(tokenIndex), pathValue);
                end
            end
        end
    end
end

function assert_closure_negative_controls(repoRoot)
    detectedRunner = false;
    try
        injected = ["run_regression_tests.m", ...
            "run_migration_regression_tests.m"];
        if ~isequal(injected, "run_regression_tests.m")
            error('OCE:Architecture:RunnerInventory', 'Injected second runner.');
        end
    catch ME
        detectedRunner = strcmp(ME.identifier, ...
            'OCE:Architecture:RunnerInventory');
    end
    detectedRoot = false;
    try
        injected = fullfile(repoRoot, 'Codes');
        if endsWith(injected, 'Codes')
            error('OCE:Architecture:RetiredRoot', 'Injected retired root.');
        end
    catch ME
        detectedRoot = strcmp(ME.identifier, 'OCE:Architecture:RetiredRoot');
    end
    if ~(detectedRunner && detectedRoot)
        error('OCE:Architecture:NegativeControl', ...
            'Closure negative controls did not all detect differences.');
    end
end

function tf = is_private_source(filePath, sourceRoot)
    relative = erase(string(filePath), string(sourceRoot) + filesep);
    parts = split(relative, filesep);
    tf = any(parts(1:end-1) == "private");
end

function qualifiedName = package_name(filePath, repoRoot)
    relative = erase(string(filePath), string(fullfile(repoRoot, 'src')) + filesep);
    parts = split(relative, filesep);
    [~, functionName] = fileparts(parts(end));
    packages = erase(parts(1:end-1), "+");
    qualifiedName = strjoin([packages; string(functionName)], '.');
end

function locations = normalize_locations(value)
    if isempty(value)
        locations = {};
    elseif ischar(value)
        locations = {value};
    else
        locations = value;
    end
end

function assert_unique_resolution(name, locations, expectedPath)
    if numel(locations) ~= 1 || ~strcmpi(string(locations{1}), string(expectedPath))
        error('OCE:Architecture:Resolution', ...
            'Expected one resolution for %s at %s; actual=%s.', ...
            name, expectedPath, strjoin(string(locations), ', '));
    end
end

function name = primary_function_name(source)
    line = regexp(source, '(?m)^\s*function[^\r\n]*', 'match', 'once');
    token = regexp(line, '([A-Za-z]\w*)\s*\(', 'tokens', 'once');
    if isempty(token)
        error('OCE:Architecture:PrimaryName', ...
            'No primary function declaration was found.');
    end
    name = string(token{1});
end

function paths = find_file_existence_checks(repoRoot)
    files = dir(fullfile(repoRoot, 'src', '+oce', '**', '*.m'));
    paths = strings(0, 1);
    for index = 1:numel(files)
        filePath = fullfile(files(index).folder, files(index).name);
        source = fileread(filePath);
        if ~isempty(regexp(source, 'exist\s*\([^\r\n]*[''\"]file[''\"]', 'once'))
            relative = erase(string(filePath), string(repoRoot) + filesep);
            paths(end + 1, 1) = replace(relative, filesep, '/'); %#ok<AGROW>
        end
    end
end
