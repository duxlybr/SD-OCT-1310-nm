function frame = postprocessMotionOverlayFrame(frame, medianWindow)
%POSTPROCESSMOTIONOVERLAYFRAME Apply display-only spatial median denoising.
% This helper never modifies scientific phase products.

    if ~isnumeric(frame) || ~ismatrix(frame) || isempty(frame)
        error('OCE:Plotting:InvalidMotionFrame', ...
            'Motion overlay frame must be a nonempty numeric matrix.');
    end
    if nargin < 2 || isempty(medianWindow)
        return;
    end
    if ~isnumeric(medianWindow) || ~isvector(medianWindow) || ...
            numel(medianWindow) ~= 2 || any(~isfinite(medianWindow)) || ...
            any(medianWindow < 1) || any(medianWindow ~= round(medianWindow))
        error('OCE:Plotting:InvalidMotionMedianWindow', ...
            'Motion median window must contain two positive integers.');
    end

    frame = medfilt2(frame, double(reshape(medianWindow, 1, 2)), 'Symmetric');
end
