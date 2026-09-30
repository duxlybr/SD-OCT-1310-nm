function test_interactive_acquisition_architecture(context)
%TEST_INTERACTIVE_ACQUISITION_ARCHITECTURE Validate canonical interaction ownership.

    canonical = ["oce.acquisition.selectDepthCropFromPreview"; ...
        "oce.acquisition.selectTimeCropFromPhasePreview"; ...
        "oce.acquisition.estimatePreviewDisplayLimits"; ...
        "oce.interaction.tuneBorderDetection"; ...
        "oce.interaction.tuneDispersionWindows"];
    for index = 1:numel(canonical)
        locations = which(char(canonical(index)), '-all');
        if ischar(locations), locations = {locations}; end
        if numel(locations) ~= 1
            error('OCE:InteractiveArchitecture:Resolution', ...
                'Expected one resolution for %s; actual=%d.', ...
                canonical(index), numel(locations));
        end
    end

    assert(isfolder(fullfile(context.repoRoot, 'inherited')));
    assert(isfolder(fullfile(context.repoRoot, 'inherited', 'Codes')));
    assert(isfolder(fullfile(context.repoRoot, 'inherited', 'Processing')));
    assert(~isfile(fullfile(context.repoRoot, 'Codes', 'Resize_Adjust_Fix_Parameters.m')));
    assert(~isfile(fullfile(context.repoRoot, 'Codes', 'SizeTime.m')));
    assert(isfolder(fullfile(context.repoRoot, 'third_party', 'MIMT')));
    assert(~isfolder(fullfile(context.repoRoot, 'Codes', 'MIMT')));

    source = fileread(fullfile(context.repoRoot, 'src', '+oce', ...
        '+acquisition', 'prepareAcquisitionParameters.m'));
    requiredCalls = ["oce.acquisition.selectDepthCropFromPreview"; ...
        "oce.acquisition.selectTimeCropFromPhasePreview"];
    for index = 1:numel(requiredCalls)
        if ~contains(source, requiredCalls(index))
            error('OCE:InteractiveArchitecture:Caller', ...
                'Canonical generator does not call %s.', requiredCalls(index));
        end
    end

    assert_automatic_limits();
    assert_preview_dependency_boundary(context.repoRoot);
    assert_border_tuning_boundary(context.repoRoot);
    assert_dispersion_tuning_boundary(context.repoRoot);

    assert_no_flat_calls(context.repoRoot);
    retired = ["oce.acquisition.generateParametersFromBinary"; ...
        "oce.acquisition.configureAcquisitionFromPreview"; ...
        "oce.acquisition.selectAcquisitionTimeRange"];
    for index = 1:numel(retired)
        assert(isempty(which(char(retired(index)), '-all')));
    end
    assert_mimt_tree(context.repoRoot);
    assert_negative_controls();
end

function assert_border_tuning_boundary(repoRoot)
    tunerPath = fullfile(repoRoot, 'src', '+oce', '+interaction', ...
        'tuneBorderDetection.m');
    uiPath = fullfile(repoRoot, 'src', '+oce', '+interaction', 'private', ...
        'createBorderTunerUI.m');
    source = fileread(tunerPath);
    uiSource = fileread(uiPath);
    required = ["oce.config.resolveBorderOptions"; ...
        "oce.borders.detectAndMask"; "oce.borders.buildIntensityMask"; ...
        "oce.plotting.plotBorderPreview"; "createBorderTunerUI"; ...
        "workingOptions.selection = ""manual"""];
    if any(~contains(source, required)) || ...
            ~contains(uiSource, 'Accept borders')
        error('OCE:InteractiveArchitecture:BorderTuner', ...
            'Border tuner does not converge through maintained contracts.');
    end
    scientificTokens = ["oce.config.resolveBorderOptions"; ...
        "oce.borders.detectAndMask"; "oce.borders.buildIntensityMask"; ...
        "oce.plotting.plotBorderPreview"];
    if any(contains(uiSource, scientificTokens))
        error('OCE:InteractiveArchitecture:BorderTunerUIOwnership', ...
            'Border tuner UI helper contains scientific processing.');
    end
    maskStart = strfind(source, 'function mask_threshold_changed');
    renderStart = strfind(source, 'function render_preview');
    if isempty(maskStart) || isempty(renderStart) || ...
            maskStart(1) >= renderStart(1) || ...
            contains(source(maskStart(1):renderStart(1) - 1), ...
                'detectAndMask')
        error('OCE:InteractiveArchitecture:MaskRecomputation', ...
            'Mask-only updates must not rerun border detection.');
    end
    batchSource = fileread(fullfile(repoRoot, 'src', '+oce', ...
        '+pipeline', 'runBatchProcessing.m'));
    if contains(batchSource, 'oce.interaction') || contains(batchSource, 'uifigure')
        error('OCE:InteractiveArchitecture:BatchDependency', ...
            'Batch processing depends on interactive border tuning.');
    end
end

function assert_dispersion_tuning_boundary(repoRoot)
    tunerPath = fullfile(repoRoot, 'src', '+oce', '+interaction', ...
        'tuneDispersionWindows.m');
    uiPath = fullfile(repoRoot, 'src', '+oce', '+interaction', 'private', ...
        'createDispersionWindowTunerUI.m');
    source = fileread(tunerPath);
    uiSource = fileread(uiPath);
    required = ["oce.config.resolveDispersionWindowOptions"; ...
        "oce.dispersion.buildWindows"; ...
        "oce.plotting.plotDispersionWindowContext"; ...
        "createDispersionWindowTunerUI"; ...
        "middle"; "manual_local_index"; "max_rms_phase_increment"; ...
        "max_mirrored_correlation"; "fraction_of_bmode"; ...
        "manual_interval_count"; "cycle_count"; "to_end"; ...
        "currentResult.resolved_options.center.local_indices"];
    uiRequired = ["Center method"; "Spatial method"; "Temporal method"; ...
        "Accept dispersion windows"];
    if any(~contains(source, required)) || any(~contains(uiSource, uiRequired))
        error('OCE:InteractiveArchitecture:DispersionTuner', ...
            'Dispersion tuner does not expose maintained strategy contracts.');
    end
    scientificTokens = ["oce.config.resolveDispersionWindowOptions"; ...
        "oce.dispersion.buildWindows"; ...
        "oce.plotting.plotDispersionWindowContext"];
    if any(contains(uiSource, scientificTokens))
        error('OCE:InteractiveArchitecture:DispersionTunerUIOwnership', ...
            'Dispersion tuner UI helper contains scientific processing.');
    end
    forbidden = ["drawrectangle"; "drawpolygon"; "imrect"; "imagesc("; ...
        "options.center.method = ""manual_local_index"";"; ...
        "options.spatial.method = ""fraction_of_bmode"";"; ...
        "options.temporal.method = ""cycle_count"";"];
    if any(contains(source, forbidden)) || any(contains(uiSource, forbidden))
        error('OCE:InteractiveArchitecture:DispersionTunerOwnership', ...
            ['Numeric/method controls must own editable intent; the tuner ' ...
             'must not force one strategy or implement an alternate ROI.']);
    end
end

function assert_automatic_limits()
    image = reshape(linspace(-40, 20, 1000), 20, 50);
    image(1) = NaN;
    limits = oce.acquisition.estimatePreviewDisplayLimits(image);
    assert(isequal(size(limits), [1 2]));
    assert(all(isfinite(limits)) && limits(1) < limits(2));

    finiteImage = image(isfinite(image));
    dataRange = max(finiteImage) - min(finiteImage);
    normalized = (finiteImage - min(finiteImage)) / dataRange;
    reference = min(finiteImage) + ...
        stretchlimFB(normalized, 0.001).' * dataRange;
    tolerance = dataRange / 255;
    assert(all(abs(limits - reference) <= tolerance));
end

function assert_preview_dependency_boundary(repoRoot)
    maintainedFiles = [dir(fullfile(repoRoot, 'src', '**', '*.m')); ...
        dir(fullfile(repoRoot, 'workflows', '**', '*.m'))];
    forbidden = ["immodify1"; "akzoom"; "FEX_dependencies"];
    for fileIndex = 1:numel(maintainedFiles)
        filePath = fullfile(maintainedFiles(fileIndex).folder, ...
            maintainedFiles(fileIndex).name);
        source = fileread(filePath);
        for tokenIndex = 1:numel(forbidden)
            if contains(source, forbidden(tokenIndex))
                error('OCE:InteractiveArchitecture:PreviewDependency', ...
                    'Maintained source %s contains forbidden token %s.', ...
                    filePath, forbidden(tokenIndex));
            end
        end
    end
end

function assert_no_flat_calls(repoRoot)
    roots = [string(fullfile(repoRoot, 'src')); string(fullfile(repoRoot, 'workflows'))];
    expression = '(?<![\.\w])(Resize_Adjust_Fix_Parameters|SizeTime)\s*\(';
    for rootIndex = 1:numel(roots)
        files = dir(fullfile(roots(rootIndex), '**', '*.m'));
        for fileIndex = 1:numel(files)
            filePath = fullfile(files(fileIndex).folder, files(fileIndex).name);
            if ~isempty(regexp(fileread(filePath), expression, 'once'))
                error('OCE:InteractiveArchitecture:FlatCall', ...
                    'Flat interactive-helper call remains in %s.', filePath);
            end
        end
    end
end

function assert_mimt_tree(repoRoot)
    root = fullfile(repoRoot, 'third_party', 'MIMT');
    files = dir(fullfile(root, '**', '*'));
    files = files(~[files.isdir]);
    if numel(files) ~= 151
        error('OCE:InteractiveArchitecture:MimtCount', ...
            'Expected 151 preserved MIMT files; actual=%d.', numel(files));
    end
    required = ["immodify1.m", "imcast.m", "imtweak.m", ...
        "imadjustFB.m", "stretchlimFB.m", "LABLUT.mat"];
    for index = 1:numel(required)
        if ~isfile(fullfile(root, required(index)))
            error('OCE:InteractiveArchitecture:MimtFile', ...
                'Required MIMT file is missing: %s.', required(index));
        end
    end
end

function assert_negative_controls()
    detected = false;
    try
        assert_unique_path(["a"; "a"], "a");
    catch ME
        detected = strcmp(ME.identifier, 'OCE:InteractiveArchitecture:DuplicatePath');
    end
    if ~detected
        error('OCE:InteractiveArchitecture:NegativeControl', ...
            'Duplicate-path negative control was not detected.');
    end
end

function assert_unique_path(entries, expected)
    if sum(strcmpi(entries, expected)) ~= 1
        error('OCE:InteractiveArchitecture:DuplicatePath', ...
            'Expected exactly one path entry for %s.', expected);
    end
end
