function rgb = composeMotionOverlay(backgroundDb, phaseFrame, visualizationMask, ...
        backgroundLimitsDb, phaseLimits, alphaFactor)
%COMPOSEMOTIONOVERLAY Fuse grayscale OCT structure with fireice phase motion.
% Preview/video utility only; it does not modify scientific arrays.

    validateattributes(backgroundDb, {'numeric'}, {'2d', 'nonempty'}, ...
        mfilename, 'backgroundDb');
    validateattributes(phaseFrame, {'numeric'}, {'2d', 'size', size(backgroundDb)}, ...
        mfilename, 'phaseFrame');
    if ~islogical(visualizationMask) || ...
            ~isequal(size(visualizationMask), size(backgroundDb))
        error('OCE:Plotting:InvalidMotionMask', ...
            'visualizationMask must be logical and match the motion frame size.');
    end
    if ~isnumeric(backgroundLimitsDb) || numel(backgroundLimitsDb) ~= 2 || ...
            any(~isfinite(backgroundLimitsDb)) || ...
            backgroundLimitsDb(1) >= backgroundLimitsDb(2)
        error('OCE:Plotting:InvalidBackgroundLimits', ...
            'backgroundLimitsDb must be [low high].');
    end
    if ~isnumeric(phaseLimits) || numel(phaseLimits) ~= 2 || ...
            any(~isfinite(phaseLimits)) || phaseLimits(1) >= phaseLimits(2)
        error('OCE:Plotting:InvalidPhaseLimits', ...
            'phaseLimits must be [low high].');
    end
    if ~isnumeric(alphaFactor) || ~isscalar(alphaFactor) || ...
            ~isfinite(alphaFactor) || alphaFactor < 0 || alphaFactor > 1
        error('OCE:Plotting:InvalidAlpha', ...
            'alphaFactor must lie between 0 and 1.');
    end

    backgroundIndex = scale_to_uint8(backgroundDb, backgroundLimitsDb);
    backgroundRgb = ind2rgb(backgroundIndex, gray(256));
    phaseIndex = scale_to_uint8(phaseFrame, phaseLimits);
    phaseRgb = ind2rgb(phaseIndex, fireice(256));
    mask3 = repmat(double(visualizationMask), 1, 1, 3);
    alpha = double(alphaFactor) .* mask3;
    rgb = phaseRgb .* alpha + backgroundRgb .* (1 - alpha);
end

function values = scale_to_uint8(data, limits)
    normalized = (double(data) - limits(1)) ./ diff(limits);
    normalized(~isfinite(normalized)) = 0;
    normalized = min(max(normalized, 0), 1);
    values = uint8(round(255 * normalized));
end
