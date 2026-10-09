function test_io_acquisition_resolution(context)
%TEST_IO_ACQUISITION_RESOLUTION Verify I/O and acquisition package ownership.

    canonical = {
        'oce.io.loadExperimentalLog', 'src/+oce/+io/loadExperimentalLog.m';
        'oce.io.loadAcquisitionTable', 'src/+oce/+io/loadAcquisitionTable.m';
        'oce.io.loadSubexperimentParameters', 'src/+oce/+io/loadSubexperimentParameters.m';
        'oce.io.readAcquisitionHeader', 'src/+oce/+io/readAcquisitionHeader.m';
        'oce.io.readRawAcquisition', 'src/+oce/+io/readRawAcquisition.m';
        'oce.io.exportConditionSummaryTable', 'src/+oce/+io/exportConditionSummaryTable.m';
        'oce.io.exportScanAxisSummaryTable', 'src/+oce/+io/exportScanAxisSummaryTable.m';
        'oce.acquisition.estimatePreviewDisplayLimits', 'src/+oce/+acquisition/estimatePreviewDisplayLimits.m';
        'oce.acquisition.prepareAcquisitionParameters', 'src/+oce/+acquisition/prepareAcquisitionParameters.m';
        'oce.acquisition.validateAcquisitionParameters', 'src/+oce/+acquisition/validateAcquisitionParameters.m';
        'oce.acquisition.prepareSpectralSamples', 'src/+oce/+acquisition/prepareSpectralSamples.m';
        'oce.acquisition.loadWaveMotionPlane', 'src/+oce/+acquisition/loadWaveMotionPlane.m';
        'oce.acquisition.buildWaveMotionPlane', 'src/+oce/+acquisition/buildWaveMotionPlane.m';
        'oce.acquisition.finalizeUnwrappedWavePlane', 'src/+oce/+acquisition/finalizeUnwrappedWavePlane.m';
        'oce.acquisition.applyWaveEnfaceOperator', 'src/+oce/+acquisition/applyWaveEnfaceOperator.m';
        'oce.acquisition.selectDepthCropFromPreview', 'src/+oce/+acquisition/selectDepthCropFromPreview.m';
        'oce.acquisition.selectTimeCropFromPhasePreview', 'src/+oce/+acquisition/selectTimeCropFromPhasePreview.m';
        'oce.acquisition.resolveCropOptions', 'src/+oce/+acquisition/resolveCropOptions.m';
        'oce.acquisition.getAcquisitionRow', 'src/+oce/+acquisition/getAcquisitionRow.m';
        'oce.acquisition.prepareProcessingInputs', 'src/+oce/+acquisition/prepareProcessingInputs.m';
        'oce.acquisition.prepareSingleFileInputs', 'src/+oce/+acquisition/prepareSingleFileInputs.m';
        'oce.acquisition.validateAcquisitionFiles', 'src/+oce/+acquisition/validateAcquisitionFiles.m';
        'oce.acquisition.buildAcquisitionGeometry', 'src/+oce/+acquisition/buildAcquisitionGeometry.m';
        'oce.acquisition.buildAcquisitionState', 'src/+oce/+acquisition/buildAcquisitionState.m';
        'oce.acquisition.reconstructComplexVolume', 'src/+oce/+acquisition/reconstructComplexVolume.m';
        'oce.acquisition.computeStructuralEnface', 'src/+oce/+acquisition/computeStructuralEnface.m'};
    assert_unique_locations(canonical, context.repoRoot, "canonical function");
    assert_absent(["load_experimental_log", "load_subexperiment_params", ...
        "generate_oce_params_from_bin", "get_acquisition_row", ...
        "prepare_processing_inputs", "validate_experiment_files", ...
        "oct2_readRawData", "ReadCplx_Volume_BS", ...
        "oce.io.readOct2RawData", "oce.acquisition.readComplexVolume", ...
        "oce.acquisition.buildProcessingState", ...
        "oce.acquisition.normalizeAcquisitionParameters", ...
        "oce.io.exportResultsSummaryTable", ...
        "oce.io.exportExperimentMeridianSummaryTable"]);
    assert_package_contents(context.repoRoot, "io", [ ...
        "exportConditionSummaryTable.m", ...
        "exportScanAxisSummaryTable.m", ...
        "loadAcquisitionTable.m", "loadExperimentalLog.m", ...
        "loadSubexperimentParameters.m", "loadScientificResult.m", ...
        "readAcquisitionHeader.m", "readRawAcquisition.m", ...
        "saveScientificResult.m", "saveResultsSummary.m"]);
    assert_package_contents(context.repoRoot, "acquisition", [ ...
        "applyWaveEnfaceOperator.m", "buildWaveMotionPlane.m", ...
        "buildAcquisitionGeometry.m", "buildAcquisitionState.m", ...
        "computeStructuralEnface.m", "estimatePreviewDisplayLimits.m", ...
        "finalizeUnwrappedWavePlane.m", ...
        "getAcquisitionRow.m", "loadWaveMotionPlane.m", "prepareAcquisitionParameters.m", ...
        "prepareSpectralSamples.m", "prepareProcessingInputs.m", ...
        "prepareSingleFileInputs.m", "reconstructComplexVolume.m", ...
        "resolveCropOptions.m", "selectDepthCropFromPreview.m", ...
        "selectTimeCropFromPhasePreview.m", ...
        "validateAcquisitionFiles.m", "validateAcquisitionParameters.m"]);

    if ~isempty(which('oce.io.processOct2RawData'))
        error('OCE:RegressionIO:UnexpectedMigration', ...
            'oct2_processRawData has no maintained caller and must remain retired.');
    end
    assert_absent(["oce.acquisition.generateParametersFromBinary", ...
        "oce.acquisition.configureAcquisitionFromPreview", ...
        "oce.acquisition.selectAcquisitionTimeRange"]);

    forbidden = '\<(eval|evalin|assignin|cd)\s*\(';
    for idx = 1:size(canonical, 1)
        source = fileread(fullfile(context.repoRoot, canonical{idx, 2}));
        if ~isempty(regexp(source, forbidden, 'once'))
            error('OCE:RegressionIO:ImplicitState', ...
                'Forbidden implicit-state API found in %s.', canonical{idx, 1});
        end
    end
end

function assert_absent(names)
    for idx = 1:numel(names)
        if ~isempty(which(char(names(idx)), '-all'))
            error('OCE:RegressionIO:RetiredAdapter', ...
                'Retired I/O or acquisition adapter still resolves: %s.', names(idx));
        end
    end
end

function assert_unique_locations(expected, repoRoot, description)
    for idx = 1:size(expected, 1)
        name = expected{idx, 1};
        locations = string(which(name, '-all'));
        locations = locations(strlength(locations) > 0);
        if numel(locations) ~= 1
            error('OCE:RegressionIO:Resolution', ...
                'Expected one %s resolution for %s; actual count=%d; values=%s.', ...
                description, name, numel(locations), strjoin(locations, ', '));
        end
        expectedPath = fullfile(repoRoot, expected{idx, 2});
        if ~strcmpi(normalize_path(locations(1)), normalize_path(expectedPath))
            error('OCE:RegressionIO:Resolution', ...
                '%s expected at %s but resolved to %s.', ...
                name, expectedPath, locations(1));
        end
    end
end

function assert_package_contents(repoRoot, packageName, expected)
    files = dir(fullfile(repoRoot, "src", "+oce", "+" + packageName, "*.m"));
    actual = sort(string({files.name}));
    expected = sort(expected);
    if ~isequal(actual, expected)
        error('OCE:RegressionIO:PackageContents', ...
            '%s package expected=%s; actual=%s.', ...
            packageName, strjoin(expected, ', '), strjoin(actual, ', '));
    end
end

function value = normalize_path(value)
    value = replace(string(value), ["/", "\"], filesep);
end
