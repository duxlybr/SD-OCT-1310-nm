function selection = selectTimeCropFromPhasePreview( ...
        measurement, octSystem, geometry, depthSelection, ...
        displayLimitsDb, cropOptions, N, interaction, spectralContext)
%SELECTTIMECROPFROMPHASEPREVIEW Select retained time indices.
%
% An optional interaction struct may provide createFigure, selectPoint, and
% selectRectangle function handles. Omitting it preserves the historical
% ginput/imrect interaction.

    if nargin < 8
        interaction = struct();
    end
    cropOptions = validate_options(cropOptions);
    if cropOptions.selection == "manual_indices"
        validate_range(cropOptions.start_index_inclusive, ...
            cropOptions.end_index_inclusive, ...
            geometry.temporal_repetition_count);
        selection = struct( ...
            'selection', "manual_indices", ...
            'start_index_inclusive', cropOptions.start_index_inclusive, ...
            'end_index_inclusive', cropOptions.end_index_inclusive);
        return;
    end
    if nargin < 9
        spectralContext = oce.acquisition.prepareSpectralSamples( ...
            measurement.rawdata, octSystem);
    end

    if isempty(depthSelection.cropped_preview_db)
        error('OCE:Acquisition:InvalidDepthCrop', ...
            ['Interactive time selection requires an interactive depth ' ...
             'preview from the same preparation run.']);
    end
    interaction = resolve_interaction(interaction);
    hann_rep_mat = double(repmat(hann(geometry.spectral_sample_count), 1, ...
        geometry.temporal_repetition_count));
    Min_angle = 0;
    Max_angle = 0;

    fprintf('Preparing temporal phase preview. Select %d spatial points.\n', N);
    interaction.createFigure();
    subplot(2, 1, 1);
    imagesc(depthSelection.cropped_preview_db);
    clim(displayLimitsDb)
    colormap(gray)
    title('Select motion-preview points')
    xlabel('Lateral position index')
    ylabel('Depth sample index (pixel)')

    for ii = 1:N
        [x, y, button] = interaction.selectPoint(); %#ok<ASGLU>
        X_pos = round(x);
        Y_pos = round(y);

        subplot(2, 1, 1);
        hold on
        scatter(X_pos, Y_pos, 'filled', 'red');
        hold off

        fprintf('Computing phase preview for point %d of %d...\n', ii, N);
        linear_k_fringes = oce.acquisition.prepareSpectralSamples( ...
            measurement.rawdata, octSystem, ...
            1:geometry.temporal_repetition_count, ...
            X_pos, spectralContext, "time_preview");
        fft_1 = fft(hann_rep_mat .* linear_k_fringes);
        fft_1 = fft_1(1:geometry.available_depth_sample_count, :);
        fft_2 = fft_1(depthSelection.start_index_inclusive: ...
            depthSelection.end_index_inclusive, :);

        raw_phases = angle(fft_2(Y_pos, :));
        loaded_phases = unwrap(raw_phases);

        if min(loaded_phases) < Min_angle
            Min_angle = min(loaded_phases);
        end
        if max(loaded_phases) > Max_angle
            Max_angle = max(loaded_phases);
        end

        subplot(2, 1, 2);
        hold on
        plot(loaded_phases);
        axis([1 geometry.temporal_repetition_count Min_angle Max_angle])
        xlabel('M-repetition index')
        ylabel('Phase (rad)')
        title('Select time crop')
        hold off
    end
    fprintf('Temporal phase preview ready.\n');

    initialPosition = [round(geometry.temporal_repetition_count / 3), ...
        -1000, round(geometry.temporal_repetition_count / 3), 2000];
    PosTime = interaction.selectRectangle(gca, initialPosition);

    [startIndex, endIndex] = clip_interactive_range( ...
        round(PosTime(1)), round(PosTime(1)) + round(PosTime(3)), ...
        geometry.temporal_repetition_count);

    selection = struct( ...
        'selection', "interactive", ...
        'start_index_inclusive', startIndex, ...
        'end_index_inclusive', endIndex);
end

function options = validate_options(options)
    if ~isstruct(options) || ~isscalar(options) || ...
            ~isfield(options, 'selection')
        error('OCE:Acquisition:UnsupportedCropSelection', ...
            'Time CropOptions must contain selection.');
    end
    if ~(ischar(options.selection) || ...
            (isstring(options.selection) && isscalar(options.selection)))
        error('OCE:Acquisition:UnsupportedCropSelection', ...
            'Time crop selection must be a text scalar.');
    end
    options.selection = lower(strtrim(string(options.selection)));
    if ~ismember(options.selection, ["interactive", "manual_indices"])
        error('OCE:Acquisition:UnsupportedCropSelection', ...
            'Unsupported time crop selection "%s".', options.selection);
    end
    if options.selection == "manual_indices"
        required = ["start_index_inclusive"; "end_index_inclusive"];
        for index = 1:numel(required)
            if ~isfield(options, required(index))
                error('OCE:Acquisition:InvalidTimeCrop', ...
                    'Manual time CropOptions is missing %s.', required(index));
            end
        end
    end
end

function [startIndex, endIndex] = clip_interactive_range( ...
        firstIndex, lastIndex, limit)
    if ~isnumeric([firstIndex lastIndex]) || ...
            any(~isfinite([firstIndex lastIndex]))
        error('OCE:Acquisition:InvalidTimeCrop', ...
            'Time crop ROI must contain finite coordinates.');
    end
    lower = min(firstIndex, lastIndex);
    upper = max(firstIndex, lastIndex);
    startIndex = max(1, lower);
    endIndex = min(limit, upper);
    if startIndex > endIndex
        error('OCE:Acquisition:InvalidTimeCrop', ...
            'Time crop ROI does not overlap the available data.');
    end
end

function validate_range(startIndex, endIndex, limit)
    values = [startIndex endIndex];
    if ~isnumeric(values) || numel(values) ~= 2 || ...
            any(~isfinite(values)) || any(values < 1) || ...
            any(values ~= round(values)) || startIndex > endIndex || ...
            endIndex > limit
        error('OCE:Acquisition:InvalidTimeCrop', ...
            ['Time crop must use positive integer inclusive indices with ' ...
             '1 <= start <= end <= %d.'], limit);
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
    if ~isfield(interaction, 'selectPoint')
        interaction.selectPoint = @() ginput(1);
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
