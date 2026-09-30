function test_startup_contract(context)
%TEST_STARTUP_CONTRACT Validate clean and idempotent path initialization.

    originalPath = path;
    originalDirectory = pwd;
    figuresBefore = findall(groot, 'Type', 'figure');
    cleanup = onCleanup(@() restore_state(originalPath, originalDirectory));

    restoredefaultpath;
    addpath(context.repoRoot);
    cd(context.repoRoot);
    startup;
    startup;

    expectedPaths = [ ...
        string(fullfile(context.repoRoot, 'src')); ...
        string(fullfile(context.repoRoot, 'third_party', 'MIMT')); ...
        string(fullfile(context.repoRoot, 'third_party', 'fireice'))];
    entries = string(strsplit(path, pathsep));
    for index = 1:numel(expectedPaths)
        count = sum(strcmpi(entries, expectedPaths(index)));
        if count ~= 1
            error('OCE:Startup:Idempotence', ...
                'Expected one path entry for %s; actual=%d.', ...
                expectedPaths(index), count);
        end
    end

    source = fileread(fullfile(context.repoRoot, 'startup.m'));
    assert_startup_source(source);
    assert_excluded_paths(entries, context.repoRoot);
    assert_mimt_resolution(context.repoRoot);
    assert_fireice_resolution(context.repoRoot);
    assert_workflows(context.repoRoot, [ ...
        "process_single_acquisition.m"; ...
        "process_acquisition_batch.m"; ...
        "summarize_subexperiment_results.m"; ...
        "summarize_experiment_results.m"; ...
        "run_acquisition_stepwise.m"; ...
        "run_raster_enface_stepwise.m"]);
    addpath(fullfile(context.repoRoot, 'workflows'));
    assert_workflow_resolution(context.repoRoot, [ ...
        "process_single_acquisition"; ...
        "process_acquisition_batch"; ...
        "summarize_subexperiment_results"; ...
        "summarize_experiment_results"; ...
        "run_acquisition_stepwise"; ...
        "run_raster_enface_stepwise"]);
    if isempty(which('oce.pipeline.runSingleAcquisition'))
        error('OCE:Startup:CanonicalResolution', ...
            'Canonical single-acquisition pipeline did not resolve.');
    end
    if ~strcmpi(pwd, context.repoRoot)
        error('OCE:Startup:WorkingDirectory', ...
            'startup changed the working directory.');
    end
    figuresAfter = findall(groot, 'Type', 'figure');
    if numel(setdiff(figuresAfter, figuresBefore)) ~= 0
        error('OCE:Startup:Figures', 'startup created a figure.');
    end

    detected = false;
    try
        assert_workflows(context.repoRoot, "missing_workflow.m");
    catch ME
        detected = strcmp(ME.identifier, 'OCE:Startup:WorkflowMissing');
    end
    if ~detected
        error('OCE:Startup:NegativeControl', ...
            'Missing-workflow negative control was not detected.');
    end
    detectedLegacyPath = false;
    try
        assert_startup_source("addpath(fullfile(repoRoot, 'Codes'));");
    catch ME
        detectedLegacyPath = strcmp(ME.identifier, 'OCE:Startup:LegacyPath');
    end
    if ~detectedLegacyPath
        error('OCE:Startup:NegativeControl', ...
            'Legacy-startup-path negative control was not detected.');
    end
    clear cleanup
    restore_state(originalPath, originalDirectory);
end

function assert_fireice_resolution(repoRoot)
    locations = which('fireice', '-all');
    if ischar(locations), locations = {locations}; end
    expected = fullfile(repoRoot, 'third_party', 'fireice', 'fireice.m');
    if numel(locations) ~= 1 || ~strcmpi(string(locations{1}), expected)
        error('OCE:Startup:FireiceResolution', ...
            'Expected one fireice resolution at %s.', expected);
    end
end

function assert_startup_source(source)
    if contains(source, 'genpath') || contains(source, "'Processing'") || ...
            contains(source, "'Codes'") || contains(source, "'inherited'")
        error('OCE:Startup:LegacyPath', ...
            'startup.m added a broad or non-required legacy path.');
    end
end

function assert_excluded_paths(entries, repoRoot)
    excluded = [string(fullfile(repoRoot, 'Codes')); ...
        string(fullfile(repoRoot, 'Processing')); ...
        string(fullfile(repoRoot, 'inherited')); ...
        string(fullfile(repoRoot, 'third_party', 'MIMT', 'demo scripts')); ...
        string(fullfile(repoRoot, 'third_party', 'MIMT', 'FEX_dependencies'))];
    for index = 1:numel(excluded)
        if any(strcmpi(entries, excluded(index)))
            error('OCE:Startup:LegacyPath', ...
                'Excluded path was added by startup: %s.', excluded(index));
        end
    end
end

function assert_mimt_resolution(repoRoot)
    names = ["immodify1", "imcast", "imtweak", "imadjustFB", "stretchlimFB"];
    for index = 1:numel(names)
        locations = which(char(names(index)), '-all');
        if ischar(locations), locations = {locations}; end
        expected = fullfile(repoRoot, 'third_party', 'MIMT', names(index) + ".m");
        if numel(locations) ~= 1 || ~strcmpi(string(locations{1}), expected)
            error('OCE:Startup:MimtResolution', ...
                'Expected one MIMT resolution for %s at %s.', names(index), expected);
        end
    end
end

function assert_workflows(repoRoot, names)
    for index = 1:numel(names)
        filePath = fullfile(repoRoot, 'workflows', names(index));
        if ~isfile(filePath)
            error('OCE:Startup:WorkflowMissing', ...
                'Required workflow is missing: %s.', filePath);
        end
    end
end

function assert_workflow_resolution(repoRoot, names)
    for index = 1:numel(names)
        expected = fullfile(repoRoot, 'workflows', names(index) + ".m");
        locations = which(char(names(index)), '-all');
        if ischar(locations), locations = {locations}; end
        if numel(locations) ~= 1 || ~strcmpi(string(locations{1}), expected)
            error('OCE:Startup:WorkflowResolution', ...
                'Expected one workflow resolution for %s at %s.', ...
                names(index), expected);
        end
    end
end

function restore_state(originalPath, originalDirectory)
    path(originalPath);
    if isfolder(originalDirectory), cd(originalDirectory); end
end
