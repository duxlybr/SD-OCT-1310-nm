function border_test = run_border_detection_test(processing_inputs, config_for_run, varargin)
%RUN_BORDER_DETECTION_TEST Run only Phase 1 and Phase 2 border detection.
%
% This function is intended for safely tuning BorderOptions without running
% motion analysis, temporal filtering, or dispersion analysis.
%
% Usage:
%   border_test = run_border_detection_test(run_info.processing_inputs, run_info.config_for_run);
%
% Optional name-value inputs:
%   "AssignToBase"      default: true
%   "CloseFigures"      default: false
%   "SaveBmodePreview"  default: true
%   "SaveBorderPreview" default: true
%
% Output:
%   border_test.measurement
%   border_test.OCT_system
%   border_test.OCE_system
%   border_test.Cplx_Matrix
%   border_test.Xaxis
%   border_test.Zaxis
%   border_test.Bmode
%   border_test.Bmode_IntLog
%   border_test.BorderOptions
%   border_test.DistBorder
%   border_test.Border
%   border_test.TopBorder
%   border_test.BottomBorder
%   border_test.Bmode_Mask
%   border_test.outputDir

    if nargin < 1 || isempty(processing_inputs)
        if evalin('base', 'exist(''processing_inputs'', ''var'')')
            processing_inputs = evalin('base', 'processing_inputs');
        else
            error('processing_inputs was not provided and does not exist in the base workspace.');
        end
    end

    if nargin < 2 || isempty(config_for_run)
        if evalin('base', 'exist(''config_for_run'', ''var'')')
            config_for_run = evalin('base', 'config_for_run');
        else
            error('config_for_run was not provided and does not exist in the base workspace.');
        end
    end

    p = inputParser;
    addParameter(p, 'AssignToBase', true, @islogical);
    addParameter(p, 'CloseFigures', false, @islogical);
    addParameter(p, 'SaveBmodePreview', true, @islogical);
    addParameter(p, 'SaveBorderPreview', true, @islogical);
    parse(p, varargin{:});

    validate_inputs(processing_inputs, config_for_run);

    figuresBefore = findall(0, 'Type', 'figure');
    cleanupObj = onCleanup(@() close_generated_figures(figuresBefore, p.Results.CloseFigures));

    fprintf('\nrun_border_detection_test\n');
    fprintf('-------------------------\n');
    fprintf('File: %s\n', processing_inputs.fullfile);
    fprintf('Results folder: %s\n', processing_inputs.resultsDir);

    outputDir = get_output_dir(processing_inputs);
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    oldFolder = pwd;
    cd(outputDir);
    cdCleanup = onCleanup(@() cd(oldFolder));

    filename = processing_inputs.filename;
    filepath = processing_inputs.filepath;
    OCE_system1 = processing_inputs.OCE_system1;

    OCE_AcqType = 1;
    measurement = oce.io.readOct2RawData(filename, filepath, OCE_AcqType);

    OCT_system = build_oct_system(measurement, config_for_run);
    OCE_system = build_oce_system(measurement, OCT_system, OCE_system1);

    Cplx_Matrix = oce.acquisition.readComplexVolume( ...
        measurement, OCT_system, OCE_system);

    Xaxis = linspace(0, OCT_system.x_scan_width * OCT_system.NumAngles, OCE_system.NumLateralPos);
    Zaxis = (0:1:OCE_system.NewDepthSize-1)' * OCT_system.axial_pixel_res * 1e-3;
    Zaxis = Zaxis / OCT_system.IDXrefrac;

    Bmode = mean(abs(Cplx_Matrix(:,:,:)), 3)';
    Bmode_IntLog = real(20 * log10(Bmode));

    if p.Results.SaveBmodePreview
        save_bmode_preview(Bmode_IntLog, Xaxis, Zaxis, OCE_system);
    end

    BorderOptions = get_border_options(config_for_run);
    print_border_options_summary(BorderOptions);

    [DistBorder, Border, TopBorder, BottomBorder] = run_border_detection( ...
        Xaxis, Zaxis, Bmode, OCE_system, OCT_system, BorderOptions);

    maskThreshold = get_default_value(BorderOptions, 'mask_threshold', 90);
    Bmode_Mask = Bmode_IntLog > maskThreshold;

    if p.Results.SaveBorderPreview
        save_border_preview(Bmode_IntLog, Bmode_Mask, Xaxis, Zaxis, OCE_system, OCT_system, Border, TopBorder, BottomBorder);
    end

    border_test = struct();
    border_test.measurement = measurement;
    border_test.OCT_system = OCT_system;
    border_test.OCE_system = OCE_system;
    border_test.Cplx_Matrix = Cplx_Matrix;
    border_test.Xaxis = Xaxis;
    border_test.Zaxis = Zaxis;
    border_test.Bmode = Bmode;
    border_test.Bmode_IntLog = Bmode_IntLog;
    border_test.BorderOptions = BorderOptions;
    border_test.DistBorder = DistBorder;
    border_test.Border = Border;
    border_test.TopBorder = TopBorder;
    border_test.BottomBorder = BottomBorder;
    border_test.Bmode_Mask = Bmode_Mask;
    border_test.outputDir = outputDir;

    fprintf('Border detection test completed. Processing stopped after Phase 2.\n');
    fprintf('Output folder:\n%s\n', outputDir);

    if p.Results.AssignToBase
        assignin('base', 'border_test', border_test);
        assignin('base', 'measurement', measurement);
        assignin('base', 'OCT_system', OCT_system);
        assignin('base', 'OCE_system', OCE_system);
        assignin('base', 'Cplx_Matrix', Cplx_Matrix);
        assignin('base', 'Xaxis', Xaxis);
        assignin('base', 'Zaxis', Zaxis);
        assignin('base', 'Bmode', Bmode);
        assignin('base', 'Bmode_IntLog', Bmode_IntLog);
        assignin('base', 'BorderOptions', BorderOptions);
        assignin('base', 'DistBorder', DistBorder);
        assignin('base', 'Border', Border);
        assignin('base', 'TopBorder', TopBorder);
        assignin('base', 'BottomBorder', BottomBorder);
        assignin('base', 'Bmode_Mask', Bmode_Mask);
        fprintf('border_test and Phase 1/2 variables assigned to base workspace.\n');
    end

    clear cdCleanup cleanupObj
end

function validate_inputs(processing_inputs, config_for_run)
    requiredInputFields = ["filename"; "filepath"; "fullfile"; "resultsDir"; "OCE_system1"];

    for i = 1:numel(requiredInputFields)
        fieldName = char(requiredInputFields(i));
        if ~isfield(processing_inputs, fieldName)
            error('processing_inputs is missing required field: %s', fieldName);
        end
    end

    if ~isfile(processing_inputs.fullfile)
        error('Input .bin file not found: %s', processing_inputs.fullfile);
    end

    if ~isfield(config_for_run, 'OCT_defaults')
        error('config_for_run is missing OCT_defaults.');
    end
end

function OCT_system = build_oct_system(measurement, config_for_run)
    OCT_defaults = config_for_run.OCT_defaults;

    OCT_system = struct();
    OCT_system.NumAngles = measurement.ScanInfo.No_3Dscans;
    OCT_system.center_wavelength = get_default_value(OCT_defaults, 'center_wavelength', 1.300);
    OCT_system.a_scan_rate = get_default_value(OCT_defaults, 'a_scan_rate', 200);
    OCT_system.axial_pixel_res = get_default_value(OCT_defaults, 'axial_pixel_res', 7.1);
    OCT_system.x_scan_width = measurement.ScanInfo.Ver_scan_length_mm;
    OCT_system.IDXrefrac = get_default_value(OCT_defaults, 'IDXrefrac', 1.4);
    OCT_system.spec_len = measurement.ScanInfo.samples_in_Aline;
    OCT_system.NumBscanSingle = measurement.ScanInfo.Bframes_in_3Dscan;
end

function OCE_system = build_oce_system(measurement, OCT_system, OCE_system1)
    OCE_system = struct();
    OCE_system.NumLateralPos = measurement.ScanInfo.Bframes_in_3Dscan * OCT_system.NumAngles;
    OCE_system.NumMrept = measurement.ScanInfo.Alines_in_Bframe;
    OCE_system.DepthSize = measurement.ScanInfo.samples_in_Aline / 2;

    requiredOCEFields = [ ...
        "Jump_Lat_pos"; ...
        "NewDepthSize"; ...
        "Cut_Depth_ini"; ...
        "Cut_Depth_end"; ...
        "i_thresh_low"; ...
        "i_thresh_high"; ...
        "Cut_Time_ini"; ...
        "Cut_Time_end"; ...
        "NewTimeSize"];

    for i = 1:numel(requiredOCEFields)
        fieldName = char(requiredOCEFields(i));
        if ~isfield(OCE_system1, fieldName)
            error('OCE_system1 is missing required field: %s', fieldName);
        end
        OCE_system.(fieldName) = OCE_system1.(fieldName);
    end
end

function BorderOptions = get_border_options(config_for_run)
    if isfield(config_for_run, 'BorderOptions')
        BorderOptions = config_for_run.BorderOptions;
    else
        BorderOptions = struct();
    end
end

function [DistBorder, Border, TopBorder, BottomBorder] = run_border_detection(Xaxis, Zaxis, Bmode, OCE_system, OCT_system, BorderOptions)
    method = lower(string(get_default_value(BorderOptions, 'method', "legacy")));
    detector = oce.borders.resolveMethod(method);
    fprintf('Border detection method: %s\n', method);
    [DistBorder, Border, TopBorder, BottomBorder] = detector( ...
        Xaxis, Zaxis, Bmode, OCE_system, OCT_system, BorderOptions);
end

function save_bmode_preview(Bmode_IntLog, Xaxis, Zaxis, OCE_system)
    fig = figure;
    imagesc(Xaxis, Zaxis, Bmode_IntLog);
    clim([OCE_system.i_thresh_low OCE_system.i_thresh_high]);
    colormap(gray);
    ylabel('z-axis (mm)');
    xlabel('x-axis (mm)');
    title('B-mode image - border test');
    axis([0 Xaxis(end) 0 Zaxis(end)]);
    set(gca, 'FontSize', 14);
    saveas(fig, 'BorderTest_BmodePreview.fig');
    saveas(fig, 'BorderTest_BmodePreview.tif');
end

function save_border_preview(Bmode_IntLog, Bmode_Mask, Xaxis, Zaxis, OCE_system, OCT_system, Border, TopBorder, BottomBorder)
    fig = figure;
    imagesc(Bmode_IntLog);
    hold on;
    plot(TopBorder / OCT_system.axial_pixel_res * OCT_system.IDXrefrac, 'g', 'LineWidth', 1.2);
    plot(BottomBorder / OCT_system.axial_pixel_res * OCT_system.IDXrefrac, 'r', 'LineWidth', 1.2);
    if isfield(Border, 'Idx_Up')
        plot(Border.Idx_Up, 'c--', 'LineWidth', 1.0);
    end
    if isfield(Border, 'Idx_Down')
        plot(Border.Idx_Down, 'm--', 'LineWidth', 1.0);
    end
    clim([OCE_system.i_thresh_low OCE_system.i_thresh_high]);
    colormap(gray);
    title('Border detection test - pixels');
    set(gca, 'FontSize', 14);
    saveas(fig, 'BorderTest_BorderPreview_pixels.fig');
    saveas(fig, 'BorderTest_BorderPreview_pixels.tif');

    fig = figure;
    imagesc(Xaxis, Zaxis, Bmode_IntLog .* Bmode_Mask);
    clim([OCE_system.i_thresh_low OCE_system.i_thresh_high]);
    colormap(gray);
    hold on;
    plot(TopBorder(:, 1), TopBorder(:, 2), 'g', 'LineWidth', 1.5);
    plot(BottomBorder(:, 1), BottomBorder(:, 2), 'r', 'LineWidth', 1.5);
    ylabel('z-axis (mm)');
    xlabel('x-axis (mm)');
    title('Border detection test - physical coordinates');
    axis([0 Xaxis(end) 0 Zaxis(end)]);
    set(gca, 'FontSize', 14);
    saveas(fig, 'BorderTest_BorderPreview_mm.fig');
    saveas(fig, 'BorderTest_BorderPreview_mm.tif');
end

function outputDir = get_output_dir(processing_inputs)
    runName = get_run_output_name(processing_inputs);
    outputDir = fullfile(processing_inputs.resultsDir, runName);
end

function runName = get_run_output_name(processing_inputs)
    runName = "";

    if isfield(processing_inputs, 'acquisition_row') && ...
            istable(processing_inputs.acquisition_row) && ...
            ismember('run_id', processing_inputs.acquisition_row.Properties.VariableNames)
        runID = string(processing_inputs.acquisition_row.run_id);
        if ~ismissing(runID) && strlength(strtrim(runID)) > 0
            runName = runID;
        end
    end

    if strlength(runName) == 0
        [~, fileBase, ~] = fileparts(processing_inputs.filename);
        runName = string(fileBase);
    end

    runName = matlab.lang.makeValidName(char(runName));
end

function print_border_options_summary(BorderOptions)
    fprintf('Border method: %s\n', string(get_default_value(BorderOptions, 'method', "legacy")));

    if isfield(BorderOptions, 'adaptive_threshold_k')
        fprintf('adaptive_threshold_k: %g\n', BorderOptions.adaptive_threshold_k);
    end

    if isfield(BorderOptions, 'bottom_search_offset_px')
        fprintf('bottom_search_offset_px: %g\n', BorderOptions.bottom_search_offset_px);
    end

    if isfield(BorderOptions, 'fit_type')
        fprintf('fit_type: %s\n', string(BorderOptions.fit_type));
    end

    if isfield(BorderOptions, 'thickness_range_mm')
        fprintf('thickness_range_mm: [%g %g]\n', BorderOptions.thickness_range_mm(1), BorderOptions.thickness_range_mm(2));
    end

    if isfield(BorderOptions, 'smooth_method')
        fprintf('smooth_method: %s\n', string(BorderOptions.smooth_method));
    end
end

function value = get_default_value(S, fieldName, fallbackValue)
    if isfield(S, fieldName) && ~isempty(S.(fieldName))
        value = S.(fieldName);
    else
        value = fallbackValue;
    end
end

function close_generated_figures(figuresBefore, closeFigures)
    if ~closeFigures
        return;
    end

    figuresAfter = findall(0, 'Type', 'figure');
    generatedFigures = setdiff(figuresAfter, figuresBefore);

    for i = 1:numel(generatedFigures)
        if isvalid(generatedFigures(i))
            close(generatedFigures(i));
        end
    end
end
