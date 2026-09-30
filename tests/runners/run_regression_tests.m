function summary = run_regression_tests(varargin)
%RUN_REGRESSION_TESTS Canonical self-contained repository regression runner.
%
% summary = run_regression_tests()
% summary = run_regression_tests("UpdateBaseline", true)

    p = inputParser;
    addParameter(p, 'UpdateBaseline', false, @islogical);
    addParameter(p, 'ThrowOnFailure', true, @islogical);
    parse(p, varargin{:});

    runnerFile = mfilename('fullpath');
    repoRoot = string(fileparts(fileparts(fileparts(runnerFile))));
    add_explicit_paths(repoRoot);

    context = struct();
    context.repoRoot = repoRoot;
    context.goldenManifest = synthetic_scientific_golden_manifest(repoRoot);
    context.syntheticGolden = struct( ...
        'executed', false, 'actual', struct(), 'errorMessage', "");

    try
        context.syntheticGolden.actual = ...
            create_synthetic_scientific_golden_snapshot();
        context.syntheticGolden.executed = true;
    catch ME
        context.syntheticGolden.errorMessage = ...
            string(getReport(ME, 'extended'));
    end

    if p.Results.UpdateBaseline
        if ~context.syntheticGolden.executed
            error('OCE:Regression:SyntheticGoldenGenerationFailed', ...
                'Cannot update synthetic golden: %s', ...
                context.syntheticGolden.errorMessage);
        end
        baseline = context.syntheticGolden.actual;
        assert_baseline_is_safe(baseline);
        save(context.goldenManifest.goldenFile, 'baseline', '-v7');
        fprintf('Updated synthetic scientific golden: %s\n', ...
            context.goldenManifest.goldenFile);
    end

    fprintf('\nOCE repository regression suite\n');
    fprintf('===============================\n');
    fprintf('Repository: %s\n', repoRoot);
    fprintf('Synthetic golden available: %d\n', ...
        isfile(context.goldenManifest.goldenFile));

    groups = repository_test_catalog();
    validate_test_catalog(repoRoot, groups);
    testCount = sum(arrayfun(@(group) numel(group.tests), groups));
    results = repmat(struct('name', "", 'status', "", 'message', ""), ...
        testCount, 1);

    resultIndex = 0;
    for groupIndex = 1:numel(groups)
        fprintf('\n[%s]\n', groups(groupIndex).name);
        for testIndex = 1:numel(groups(groupIndex).tests)
            resultIndex = resultIndex + 1;
            testFunction = groups(groupIndex).tests{testIndex};
            results(resultIndex).name = string(func2str(testFunction));
            try
                testFunction(context);
                results(resultIndex).status = "PASS";
                results(resultIndex).message = "";
            catch ME
                results(resultIndex).status = "FAIL";
                results(resultIndex).message = string(getReport(ME, 'basic'));
            end
            fprintf('%-8s %s', results(resultIndex).status, ...
                results(resultIndex).name);
            if strlength(results(resultIndex).message) > 0
                fprintf(' - %s', results(resultIndex).message);
            end
            fprintf('\n');
        end
    end

    statuses = string({results.status});
    summary = struct();
    summary.results = results;
    summary.passed = sum(statuses == "PASS");
    summary.failed = sum(statuses == "FAIL");
    summary.skipped = 0;
    summary.goldenAvailable = isfile(context.goldenManifest.goldenFile);

    fprintf('-----------------------------\n');
    fprintf('PASS=%d FAIL=%d SKIPPED=%d\n', ...
        summary.passed, summary.failed, summary.skipped);

    if p.Results.ThrowOnFailure && summary.failed > 0
        error('OCE:Regression:Failed', ...
            '%d repository regression test(s) failed.', summary.failed);
    end
end

function add_explicit_paths(repoRoot)
    relativePaths = [ ...
        "src"; "third_party/MIMT"; "third_party/fireice"; ...
        "tests/helpers"; "tests/fixtures"; "tests/unit"; ...
        "tests/contract"; "tests/integration"; ...
        "tests/regression"; "tests/runners"];
    for idx = 1:numel(relativePaths)
        pathToAdd = fullfile(repoRoot, relativePaths(idx));
        if ~isfolder(pathToAdd)
            error('OCE:Regression:Path', ...
                'Required path does not exist: %s.', pathToAdd);
        end
        addpath(pathToAdd, '-end');
    end
end

function validate_test_catalog(repoRoot, groups)
    testFolders = ["contract"; "unit"; "integration"; "regression"];
    discovered = strings(0, 1);
    for folderIndex = 1:numel(testFolders)
        files = dir(fullfile(repoRoot, 'tests', testFolders(folderIndex), ...
            'test_*.m'));
        names = erase(string({files.name})', ".m");
        discovered = [discovered; names]; %#ok<AGROW>
    end

    catalog = strings(0, 1);
    for groupIndex = 1:numel(groups)
        names = string(cellfun(@func2str, groups(groupIndex).tests, ...
            'UniformOutput', false))';
        catalog = [catalog; names]; %#ok<AGROW>
    end

    if numel(unique(catalog)) ~= numel(catalog)
        error('OCE:Regression:DuplicateTestCatalogEntry', ...
            'The canonical test catalog contains duplicate function names.');
    end

    missing = setdiff(discovered, catalog);
    unknown = setdiff(catalog, discovered);
    if ~isempty(missing) || ~isempty(unknown)
        error('OCE:Regression:TestCatalogMismatch', ...
            ['Canonical test inventory mismatch. Uncatalogued=%s; ' ...
             'missing files=%s.'], ...
            strjoin(missing, ', '), strjoin(unknown, ', '));
    end
end

function assert_baseline_is_safe(baseline)
    if ~isstruct(baseline) || ~isscalar(baseline) || ...
            ~isfield(baseline, 'schema') || ...
            baseline.schema.name ~= "oce_synthetic_scientific_golden" || ...
            baseline.schema.version ~= 3 || ...
            ~isfield(baseline, 'border_result') || ...
            ~isfield(baseline, 'scientific_result')
        error('OCE:Regression:UnsafeBaseline', ...
            'Synthetic baseline root contract is invalid.');
    end
    oce.results.validateScientificResult(baseline.scientific_result);
    assert_no_absolute_paths(baseline, "baseline");
    details = whos('baseline');
    maxBytes = 512 * 1024;
    if details.bytes > maxBytes
        error('OCE:Regression:UnsafeBaseline', ...
            'Synthetic baseline exceeds %d bytes; actual=%d bytes.', ...
            maxBytes, details.bytes);
    end
end

function assert_no_absolute_paths(value, fieldPath)
    if isstruct(value)
        names = fieldnames(value);
        for idx = 1:numel(value)
            for f = 1:numel(names)
                name = names{f};
                assert_no_absolute_paths(value(idx).(name), ...
                    fieldPath + "." + name);
            end
        end
        return;
    end
    if istable(value)
        names = value.Properties.VariableNames;
        for f = 1:numel(names)
            assert_no_absolute_paths(value.(names{f}), ...
                fieldPath + "." + names{f});
        end
        return;
    end
    if iscell(value)
        for idx = 1:numel(value)
            assert_no_absolute_paths(value{idx}, fieldPath + "{" + idx + "}");
        end
        return;
    end
    if ischar(value) || isstring(value)
        values = string(value);
        for idx = 1:numel(values)
            text = char(values(idx));
            isDrivePath = ~isempty(regexp(text, '^[A-Za-z]:[\\/]', 'once'));
            isUncPath = startsWith(text, '\\');
            isUnixPath = startsWith(text, '/');
            if isDrivePath || isUncPath || isUnixPath
                error('OCE:Regression:UnsafeBaseline', ...
                    'Absolute path found at %s: %s.', fieldPath, text);
            end
        end
    end
end
