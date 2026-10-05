function [acquisition_parameters, outputMatPath, measurement] = prepareAcquisitionParameters(filename, filepath, varargin)
%PREPAREACQUISITIONPARAMETERS Create a resolved acquisition artifact.
% Persistence is disabled unless SaveParameters=true is explicit.
% The optional third output reuses the raw measurement already read here.
% ScanGeometry "automatic" takes the geometry from the header scan pattern;
% the artifact records the resolved geometry. Previews use the header A-line
% rate when the header records one.

    if nargin < 1 || isempty(filename)
        error('filename is required.');
    end
    if nargin < 2 || isempty(filepath)
        error('filepath is required.');
    end

    p = inputParser;
    addParameter(p, 'AcquisitionMode', "mb_mode", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(p, 'ScanGeometry', "angular_bmodes", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(p, 'TimeSizingN', 3, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'OCTSystemOptions', ...
        oce.config.getOCTSystemOptions("swept_source_1300"), @isstruct);
    addParameter(p, 'CropOptions', default_crop_options(), @isstruct);
    addParameter(p, 'SaveParameters', false, @islogical);
    addParameter(p, 'Overwrite', false, @islogical);
    addParameter(p, 'CloseFigures', true, @islogical);
    addParameter(p, 'OutputMatPath', '', @(x) ischar(x) || isstring(x));
    addParameter(p, 'Interaction', struct(), @isstruct);
    parse(p, varargin{:});

    figuresBefore = findall(0, 'Type', 'figure');
    cleanupObj = onCleanup(@() close_generated_figures( ...
        figuresBefore, p.Results.CloseFigures));

    filename = char(filename);
    filepath = char(filepath);
    acquisitionMode = normalize_mode(p.Results.AcquisitionMode);
    scanGeometry = normalize_geometry(p.Results.ScanGeometry);
    measurement = oce.io.readRawAcquisition(filename, filepath);
    rawDescriptor = measurement.raw_descriptor;
    geometry = oce.acquisition.buildAcquisitionGeometry( ...
        rawDescriptor, scanGeometry);
    % "automatic" resolves from the header scan pattern; persist the result.
    scanGeometry = geometry.scan_geometry;

    octSystem = oce.config.resolveOCTSystemOptions( ...
        p.Results.OCTSystemOptions, "", rawDescriptor);
    spectralContext = oce.acquisition.prepareSpectralSamples( ...
        measurement.rawdata, octSystem);

    cropOptions = resolve_crop_options(p.Results.CropOptions, geometry);
    previewInteraction = get_interaction(p.Results.Interaction, 'preview');
    timeInteraction = get_interaction(p.Results.Interaction, 'timeRange');
    depthSelection = oce.acquisition.selectDepthCropFromPreview( ...
        measurement, octSystem, geometry, cropOptions.depth, ...
        previewInteraction, spectralContext);
    timeSelection = oce.acquisition.selectTimeCropFromPhasePreview( ...
        measurement, octSystem, geometry, depthSelection, ...
        depthSelection.bmode_intensity_limits_db, cropOptions.time, ...
        p.Results.TimeSizingN, timeInteraction, spectralContext);

    acquisition_parameters = build_artifact(filename, acquisitionMode, ...
        scanGeometry, rawDescriptor, depthSelection, timeSelection, ...
        octSystem.profile);
    oce.acquisition.validateAcquisitionParameters(acquisition_parameters);

    outputMatPath = char(p.Results.OutputMatPath);
    if ~p.Results.SaveParameters
        if ~isempty(outputMatPath)
            error('OCE:Acquisition:UnexpectedOutputPath', ...
                'OutputMatPath requires SaveParameters=true.');
        end
        outputMatPath = '';
        clear cleanupObj
        return;
    end

    if isempty(outputMatPath)
        outputMatPath = infer_output_mat_path(filepath);
    end
    outputDir = fileparts(outputMatPath);
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end
    if exist(outputMatPath, 'file') && ~p.Results.Overwrite
        error(['Output MAT file already exists:\n%s\n' ...
            'Use oce.acquisition.prepareAcquisitionParameters(..., ' ...
            '''Overwrite'', true) to replace it.'], outputMatPath);
    end

    save(outputMatPath, 'acquisition_parameters');
    fprintf('Saved acquisition parameters to:\n%s\n', outputMatPath);
    clear cleanupObj
end

function options = default_crop_options()
    options = struct();
    options.depth = struct( ...
        'selection', "interactive", ...
        'start_index_inclusive', [], ...
        'end_index_inclusive', [], ...
        'bmode_intensity_limits_db', []);
    options.time = struct( ...
        'selection', "interactive", ...
        'start_index_inclusive', [], ...
        'end_index_inclusive', []);
end

function options = resolve_crop_options(options, geometry)
    if ~isfield(options, 'depth') || ~isstruct(options.depth) || ...
            ~isfield(options, 'time') || ~isstruct(options.time)
        error('OCE:Acquisition:InvalidParameterSchema', ...
            'CropOptions must contain scalar depth and time structs.');
    end
    options.depth.depth_limit = geometry.available_depth_sample_count;
end

function artifact = build_artifact(filename, acquisitionMode, ...
        scanGeometry, rawDescriptor, depth, time, octSystemProfile)
    artifact = struct();
    artifact.schema_version = 4;
    artifact.acquisition_mode = acquisitionMode;
    artifact.scan_geometry = scanGeometry;
    artifact.source = struct( ...
        'filename', string(filename), ...
        'header', header_snapshot(rawDescriptor), ...
        'oct_system_profile', string(octSystemProfile));
    artifact.crop = struct( ...
        'depth', struct( ...
            'selection', depth.selection, ...
            'start_index_inclusive', depth.start_index_inclusive, ...
            'end_index_inclusive', depth.end_index_inclusive), ...
        'time', struct( ...
            'selection', time.selection, ...
            'start_index_inclusive', time.start_index_inclusive, ...
            'end_index_inclusive', time.end_index_inclusive));
    artifact.preview_display = struct( ...
        'bmode_intensity_limits_db', ...
        depth.bmode_intensity_limits_db(:).');
end

function snapshot = header_snapshot(rawDescriptor)
    snapshot = struct( ...
        'samples_in_Aline', rawDescriptor.samples_in_Aline, ...
        'Alines_in_Bframe', rawDescriptor.Alines_in_Bframe, ...
        'Bframes_in_3Dscan', rawDescriptor.Bframes_in_3Dscan, ...
        'No_3Dscans', rawDescriptor.No_3Dscans, ...
        'Hor_scan_length_mm', rawDescriptor.Hor_scan_length_mm, ...
        'Ver_scan_length_mm', rawDescriptor.Ver_scan_length_mm, ...
        'type', string(rawDescriptor.type), ...
        'pattern_control', string(rawDescriptor.pattern_control));
end

function mode = normalize_mode(value)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('OCE:Acquisition:AcquisitionModeMismatch', ...
            'Preparation acquisition mode must be a text scalar.');
    end
    mode = lower(strtrim(string(value)));
    if mode ~= "mb_mode"
        error('OCE:Acquisition:AcquisitionModeMismatch', ...
            'Preparation supports only acquisition mode "mb_mode".');
    end
end

function geometry = normalize_geometry(value)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('OCE:Acquisition:ScanGeometryMismatch', ...
            'Preparation scan geometry must be a text scalar.');
    end
    geometry = lower(strtrim(string(value)));
    if ~ismember(geometry, ["automatic", "angular_bmodes", "raster", "polar"])
        error('OCE:Acquisition:ScanGeometryMismatch', ...
            'Preparation received unsupported scan geometry "%s".', geometry);
    end
end

function value = get_interaction(interaction, fieldName)
    value = struct();
    if isfield(interaction, fieldName)
        value = interaction.(fieldName);
    end
end

function outputMatPath = infer_output_mat_path(filepath)
    normalized = strrep(filepath, '\', '/');
    token = '/Data/';
    tokenIdx = strfind(normalized, token);
    if isempty(tokenIdx)
        error(['Could not infer experiment root from filepath:\n%s\n' ...
               'Expected a path containing /Data/.'], filepath);
    end
    dataIdx = tokenIdx(end);
    experimentRoot = normalized(1:dataIdx-1);
    relative = normalized(dataIdx + length(token):end);
    relative = regexprep(relative, '/+$', '');
    [~, subExperiment] = fileparts(relative);
    if isempty(subExperiment)
        error('Could not infer sub-experiment from filepath: %s', filepath);
    end
    paramsDir = fullfile(experimentRoot, 'Params', subExperiment);
    safeSubExperiment = matlab.lang.makeValidName(subExperiment);
    outputMatPath = fullfile(paramsDir, ['Params_' safeSubExperiment '.mat']);
end

function close_generated_figures(figuresBefore, closeFigures)
    if ~closeFigures
        return;
    end
    figuresAfter = findall(0, 'Type', 'figure');
    generated = setdiff(figuresAfter, figuresBefore);
    if ~isempty(generated)
        close(generated);
    end
end
