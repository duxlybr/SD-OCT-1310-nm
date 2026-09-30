function test_prepare_acquisition_parameters_contract(context) %#ok<INUSD>
%TEST_PREPARE_ACQUISITION_PARAMETERS_CONTRACT Exercise crop preparation.

    temporaryRoot = tempname;
    dataFolder = fullfile(temporaryRoot, 'Data', 'synthetic');
    mkdir(dataFolder);
    cleanup = onCleanup(@() remove_tree(temporaryRoot));
    filename = 'synthetic.bin';
    write_oct2_file(fullfile(dataFolder, filename));

    preview = struct();
    preview.createFigure = @() figure('Visible', 'off');
    preview.selectRectangle = @(axesHandle, initialPosition) ...
        return_rectangle([1 1 2 5], axesHandle, initialPosition);
    points = [2 2 1; 3 2 1];
    timeRange = struct();
    timeRange.createFigure = @() figure('Visible', 'off');
    timeRange.selectPoint = make_point_selector(points);
    timeRange.selectRectangle = @(axesHandle, initialPosition) ...
        return_rectangle([20 0 40 1], axesHandle, initialPosition);
    interaction = struct('preview', preview, 'timeRange', timeRange);

    outputPath = fullfile(temporaryRoot, 'Params', 'synthetic', ...
        'Params_synthetic.mat');
    directoryBefore = pwd;
    figuresBefore = findall(groot, 'Type', 'figure');
    [parameters, actualPath] = ...
        oce.acquisition.prepareAcquisitionParameters( ...
        filename, dataFolder, 'AcquisitionMode', "mb_mode", ...
        'ScanGeometry', "angular_bmodes", ...
        'TimeSizingN', 2, 'Interaction', interaction, ...
        'SaveParameters', true, 'OutputMatPath', outputPath, ...
        'Overwrite', true, 'CloseFigures', true);
    assert(strcmp(actualPath, outputPath));
    assert(isfile(outputPath));
    persisted = load(outputPath, 'acquisition_parameters');
    assert(isequaln(parameters, persisted.acquisition_parameters));
    assert(parameters.schema_version == 4);
    assert_exact_schema(parameters);
    assert(parameters.acquisition_mode == "mb_mode");
    assert(parameters.scan_geometry == "angular_bmodes");
    assert(parameters.source.filename == "synthetic.bin");
    assert(parameters.source.oct_system_profile == ...
        "swept_source_1300");
    assert(parameters.crop.depth.selection == "interactive");
    assert(parameters.crop.depth.start_index_inclusive == 1);
    assert(parameters.crop.depth.end_index_inclusive == 6);
    assert(parameters.crop.time.selection == "interactive");
    assert(parameters.crop.time.start_index_inclusive == 20);
    assert(parameters.crop.time.end_index_inclusive == 60);
    displayLimits = ...
        parameters.preview_display.bmode_intensity_limits_db;
    assert(isequal(displayLimits, displayLimits(:).'));
    assert_schema_has_no_retired_fields(parameters);
    assert(strcmp(pwd, directoryBefore));
    assert(isempty(setdiff(findall(groot, 'Type', 'figure'), figuresBefore)));

    manualOptions = struct( ...
        'depth', struct('selection', "manual_indices", ...
            'start_index_inclusive', 2, 'end_index_inclusive', 7, ...
            'bmode_intensity_limits_db', [10 80]), ...
        'time', struct('selection', "manual_indices", ...
            'start_index_inclusive', 5, 'end_index_inclusive', 90));
    forbidden = struct( ...
        'preview', forbidden_interaction(), ...
        'timeRange', forbidden_interaction());
    figuresBeforeManual = findall(groot, 'Type', 'figure');
    [manual, manualPath] = ...
        oce.acquisition.prepareAcquisitionParameters( ...
        filename, dataFolder, 'AcquisitionMode', "mb_mode", ...
        'ScanGeometry', "angular_bmodes", ...
        'CropOptions', manualOptions, 'Interaction', forbidden, ...
        'CloseFigures', true);
    assert(isempty(manualPath));
    assert(manual.crop.depth.selection == "manual_indices");
    assert(manual.crop.depth.start_index_inclusive == 2);
    assert(manual.crop.depth.end_index_inclusive == 7);
    assert(manual.crop.time.start_index_inclusive == 5);
    assert(manual.crop.time.end_index_inclusive == 90);
    assert(isequal(manual.preview_display.bmode_intensity_limits_db, ...
        [10 80]));
    assert(isempty(setdiff( ...
        findall(groot, 'Type', 'figure'), figuresBeforeManual)));

    compactFixture = create_io_acquisition_fixture();
    compactCrop = struct( ...
        'depth', struct('selection', "manual_indices", ...
            'start_index_inclusive', 1, 'end_index_inclusive', 3, ...
            'bmode_intensity_limits_db', [0 100]), ...
        'time', struct('selection', "manual_indices", ...
            'start_index_inclusive', 1, 'end_index_inclusive', 3));
    [compact, compactPath] = oce.acquisition.prepareAcquisitionParameters( ...
        compactFixture.compactFilename, compactFixture.rawDir, ...
        'AcquisitionMode', "mb_mode", ...
        'ScanGeometry', "angular_bmodes", ...
        'CropOptions', compactCrop, ...
        'Interaction', forbidden, 'CloseFigures', true);
    compactHeader = compact.source.header;
    assert(isempty(compactPath));
    assert(compactHeader.samples_in_Aline == 8);
    assert(compactHeader.Alines_in_Bframe == 100);
    assert(compactHeader.Bframes_in_3Dscan == 4);
    assert(compactHeader.No_3Dscans == 2);
    assert(compactHeader.type == "Raster");
    assert(compactHeader.pattern_control == "");
    assert(compact.source.oct_system_profile == ...
        "swept_source_1300");
    clear compactFixture
    clear cleanup
end

function interaction = forbidden_interaction()
    interaction = struct( ...
        'createFigure', @() forbidden_call(), ...
        'selectRectangle', @(varargin) forbidden_call(varargin{:}), ...
        'selectPoint', @() forbidden_call());
end

function assert_exact_schema(parameters)
    assert(isequal(string(fieldnames(parameters)), ...
        ["schema_version"; "acquisition_mode"; "scan_geometry"; ...
         "source"; "crop"; "preview_display"]));
    assert(isequal(string(fieldnames(parameters.preview_display)), ...
        "bmode_intensity_limits_db"));
end

function varargout = forbidden_call(varargin)
    varargout = cell(1, nargout); %#ok<NASGU>
    error('OCE:Test:UnexpectedInteraction', ...
        'Manual crop preparation invoked an interactive callback.');
end

function assert_schema_has_no_retired_fields(parameters) %#ok<INUSD>
    text = evalc('disp(parameters)');
    retired = ["NumLateralPos"; "NumMrept"; "DepthSize"; ...
        "NewDepthSize"; "NewTimeSize"; "Bmode"; "Jump_Lat_pos"; ...
        "Cut_Depth_ini"; "Cut_Depth_end"; "Cut_Time_ini"; ...
        "Cut_Time_end"; "i_thresh_low"; "i_thresh_high"];
    for index = 1:numel(retired)
        assert(~contains(text, retired(index)));
    end
end

function selector = make_point_selector(points)
    currentIndex = 0;
    selector = @next_point;
    function [x, y, button] = next_point
        currentIndex = currentIndex + 1;
        selection = points(currentIndex, :);
        x = selection(1); y = selection(2); button = selection(3);
    end
end

function rectangle = return_rectangle(rectangle, axesHandle, initialPosition) %#ok<INUSD>
end

function write_oct2_file(filePath)
    labels = ["header", "acquisition_datetime", "sample_trigger_source", ...
        "sample_rate_MHz", "samples_in_Aline", "pre_trigger_samples", ...
        "pattern_control", "type", "Alines_in_Bframe", "Flyback_Aline_No", ...
        "Bframe_trigger_Aline_delay", "Bframes_in_3Dscan", "No_3Dscans", ...
        "Hor_scan_length_mm", "Ver_scan_length_mm", "use_background_scan", ...
        "use_reference_MZI_scan", "use_dual_edge_sampling_if_external", ...
        "Max_Alines_in_buffer", "Is_Calib_on", "No_calib_scan"];
    values = ["ignored", "2026-01-01T00:00:00", "internal", "100", "16", ...
        "0", "raster", "Raster", "100", "0", "0", "4", "1", "1.5", ...
        "2.5", "0", "0", "0", "100", "0", "0"];
    header = '';
    for index = 1:numel(labels)
        header = [header char(labels(index)) ': ' char(values(index)) ...
            '  ' char(13) newline]; %#ok<AGROW>
    end
    fileIdentifier = fopen(filePath, 'w');
    assert(fileIdentifier >= 0, 'Could not create synthetic OCT2 fixture.');
    cleanup = onCleanup(@() fclose(fileIdentifier));
    fwrite(fileIdentifier, uint16(numel(header)), 'uint16');
    fwrite(fileIdentifier, uint16(0), 'uint16');
    fwrite(fileIdentifier, uint8(header), 'uint8');
    sampleCount = 16 * 100 * 4;
    values = uint16(mod(0:(sampleCount - 1), 4096));
    fwrite(fileIdentifier, values, 'uint16');
    clear cleanup
end

function remove_tree(folder)
    close all force
    if isfolder(folder), rmdir(folder, 's'); end
end
