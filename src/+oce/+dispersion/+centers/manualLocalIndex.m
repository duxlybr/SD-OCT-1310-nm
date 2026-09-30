function resolution = manualLocalIndex(~, options, samplesPerBmode, bmodeCount, ~, ~)
%MANUALLOCALINDEX Use configured local lateral indices.

    indices = options.manual_local_index(:);
    if isscalar(indices)
        indices = repmat(indices, bmodeCount, 1);
    elseif numel(indices) ~= bmodeCount
        error('OCE:DispersionWindows:CenterCountMismatch', ...
            ['center.manual_local_index must be scalar or contain one ' ...
             'value per B-mode.']);
    end
    if any(indices < 1) || any(indices > samplesPerBmode)
        error('OCE:DispersionWindows:CenterOutsideBmode', ...
            ['center.manual_local_index must remain within the complete ' ...
             'local B-mode range 1:%d.'], samplesPerBmode);
    end
    resolution = struct('local_indices', indices);
end
