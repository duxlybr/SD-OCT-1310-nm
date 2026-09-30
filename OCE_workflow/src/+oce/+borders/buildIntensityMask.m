function intensityMask = buildIntensityMask(reconstructionResult, maskThreshold)
%BUILDINTENSITYMASK Build the maintained log-amplitude intensity mask.

    if ~isnumeric(maskThreshold) || ~isscalar(maskThreshold) || ...
            ~isfinite(maskThreshold)
        error('OCE:Borders:InvalidMaskThreshold', ...
            'maskThreshold must be one finite numeric scalar.');
    end

    intensityMask = reconstructionResult.log_amplitude.values > maskThreshold;
end
