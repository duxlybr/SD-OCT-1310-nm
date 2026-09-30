function selection = selectDepthCropFromPreview( ...
        measurement, octSystem, geometry, cropOptions, interaction, ...
        spectralContext)
%SELECTDEPTHCROPFROMPREVIEW Select depth indices and preview display limits.
%
% An optional interaction struct may provide createFigure and selectRectangle
% function handles. Preview display limits are estimated automatically when
% cropOptions.bmode_intensity_limits_db is empty.

    if nargin < 5
        interaction = struct();
    end
    if nargin < 6
        spectralContext = oce.acquisition.prepareSpectralSamples( ...
            measurement.rawdata, octSystem);
    end
    cropOptions = validate_options(cropOptions);

    fprintf('Building B-mode preview for depth selection...\n');
    N = 100;
    hann_rep_mat = double(repmat(hann(geometry.spectral_sample_count), 1, N));
    Intensity_Matrix = double(zeros(geometry.available_depth_sample_count, ...
        geometry.lateral_sample_count));

    for pos = 1:geometry.lateral_sample_count
        linear_k_fringes = oce.acquisition.prepareSpectralSamples( ...
            measurement.rawdata, octSystem, 1:N, pos, ...
            spectralContext, "depth_preview");
        fft_1 = fft(hann_rep_mat .* linear_k_fringes);
        Intensity_Matrix(:, pos) = mean( ...
            abs(fft_1(1:geometry.available_depth_sample_count, :)), 2);
    end

    logAmplitudeDb = 20 * log10(Intensity_Matrix);
    displayLimits = resolve_display_limits( ...
        cropOptions.bmode_intensity_limits_db, logAmplitudeDb);
    fprintf('B-mode preview ready.\n');
    if cropOptions.selection == "manual_indices"
        selection = manual_selection( ...
            cropOptions, logAmplitudeDb, displayLimits);
        return;
    end

    interaction = resolve_interaction(interaction);
    interaction.createFigure();
    imagesc(logAmplitudeDb);
    clim(displayLimits)
    title('Select depth crop (axial ROI)')
    xlabel('Lateral position index')
    ylabel('Depth sample index (pixel)')
    colormap(gray)

    initialPosition = [-geometry.lateral_sample_count / 2, 100, ...
        2 * geometry.lateral_sample_count, ...
        geometry.available_depth_sample_count - 200];
    PosDepth = interaction.selectRectangle(gca, initialPosition);

    [startIndex, endIndex] = clip_interactive_range( ...
        round(PosDepth(2)), round(PosDepth(2)) + round(PosDepth(4)), ...
        geometry.available_depth_sample_count, ...
        'OCE:Acquisition:InvalidDepthCrop', 'Depth');
    croppedPreview = logAmplitudeDb(startIndex:endIndex, :);

    selection = struct( ...
        'selection', "interactive", ...
        'start_index_inclusive', startIndex, ...
        'end_index_inclusive', endIndex, ...
        'bmode_intensity_limits_db', displayLimits, ...
        'cropped_preview_db', croppedPreview);
end

function options = validate_options(options)
    if ~isstruct(options) || ~isscalar(options) || ...
            ~isfield(options, 'selection')
        error('OCE:Acquisition:UnsupportedCropSelection', ...
            'Depth CropOptions must contain selection.');
    end
    if ~(ischar(options.selection) || ...
            (isstring(options.selection) && isscalar(options.selection)))
        error('OCE:Acquisition:UnsupportedCropSelection', ...
            'Depth crop selection must be a text scalar.');
    end
    options.selection = lower(strtrim(string(options.selection)));
    if ~ismember(options.selection, ["interactive", "manual_indices"])
        error('OCE:Acquisition:UnsupportedCropSelection', ...
            'Unsupported depth crop selection "%s".', options.selection);
    end
    if ~isfield(options, 'bmode_intensity_limits_db')
        options.bmode_intensity_limits_db = [];
    end
    if ~isempty(options.bmode_intensity_limits_db)
        validate_display_limits(options.bmode_intensity_limits_db);
    end
end

function selection = manual_selection(options, bmodeLog, displayLimits)
    required = ["start_index_inclusive"; "end_index_inclusive"; ...
        "bmode_intensity_limits_db"; "depth_limit"];
    for index = 1:numel(required)
        if ~isfield(options, required(index))
            error('OCE:Acquisition:InvalidDepthCrop', ...
                'Manual depth CropOptions is missing %s.', required(index));
        end
    end
    validate_range(options.start_index_inclusive, ...
        options.end_index_inclusive, options.depth_limit);
    croppedPreview = bmodeLog(options.start_index_inclusive: ...
        options.end_index_inclusive, :);
    selection = struct( ...
        'selection', "manual_indices", ...
        'start_index_inclusive', options.start_index_inclusive, ...
        'end_index_inclusive', options.end_index_inclusive, ...
        'bmode_intensity_limits_db', displayLimits, ...
        'cropped_preview_db', croppedPreview);
end

function [startIndex, endIndex] = clip_interactive_range( ...
        firstIndex, lastIndex, limit, identifier, label)
    if ~isnumeric([firstIndex lastIndex]) || ...
            any(~isfinite([firstIndex lastIndex]))
        error(identifier, '%s crop ROI must contain finite coordinates.', label);
    end
    lower = min(firstIndex, lastIndex);
    upper = max(firstIndex, lastIndex);
    startIndex = max(1, lower);
    endIndex = min(limit, upper);
    if startIndex > endIndex
        error(identifier, ...
            '%s crop ROI does not overlap the available data.', label);
    end
end

function displayLimits = resolve_display_limits(configuredLimits, bmodeLog)
    if isempty(configuredLimits)
        displayLimits = ...
            oce.acquisition.estimatePreviewDisplayLimits(bmodeLog);
    else
        validate_display_limits(configuredLimits);
        displayLimits = configuredLimits(:).';
    end
end

function validate_range(startIndex, endIndex, limit)
    values = [startIndex endIndex];
    if ~isnumeric(values) || numel(values) ~= 2 || ...
            any(~isfinite(values)) || any(values < 1) || ...
            any(values ~= round(values)) || startIndex > endIndex || ...
            endIndex > limit
        error('OCE:Acquisition:InvalidDepthCrop', ...
            ['Depth crop must use positive integer inclusive indices with ' ...
             '1 <= start <= end <= %d.'], limit);
    end
end

function validate_display_limits(limits)
    if ~isnumeric(limits) || ~isvector(limits) || numel(limits) ~= 2 || ...
            any(~isfinite(limits)) || limits(1) >= limits(2)
        error('OCE:Acquisition:InvalidDisplayLimits', ...
            ['bmode_intensity_limits_db must be a finite numeric ' ...
             'two-element vector with low < high.']);
    end
end

function interaction = resolve_interaction(interaction)
    if ~isstruct(interaction)
        error('OCE:Acquisition:InvalidInteraction', ...
            'interaction must be a struct.');
    end
    if ~isfield(interaction, 'createFigure')
        interaction.createFigure = @() figure;
    end
    if ~isfield(interaction, 'selectRectangle')
        interaction.selectRectangle = @select_rectangle;
    end
end

function position = select_rectangle(axesHandle, initialPosition)
    rectangle = imrect(axesHandle, initialPosition); %#ok<IMRECT>
    setColor(rectangle, 'r');
    position = wait(rectangle);
end
