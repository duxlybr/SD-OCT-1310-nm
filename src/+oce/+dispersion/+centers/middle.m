function resolution = middle(~, ~, samplesPerBmode, bmodeCount, ~, ~)
%MIDDLE Select the middle local lateral index for every B-mode.

    resolution = struct( ...
        'local_indices', repmat(round(samplesPerBmode / 2), ...
            bmodeCount, 1));
end
