function [idx, fullCircleAnglesDeg] = orderBidirectionalAngles( ...
        scanAxisCount, bmodeDirectionsDeg)
%ORDERBIDIRECTIONALANGLES Order left/right directions counterclockwise.
% [idx, anglesDeg] = orderBidirectionalAngles(scanAxisCount)
% keeps the maintained ordering of historical angular B-modes: scan axis b
% lies at 180*(b-1)/N and odd axes are scanned toward theta + 180 deg.
%
% [idx, anglesDeg] = orderBidirectionalAngles(scanAxisCount, bmodeDirectionsDeg)
% orders B-modes whose increasing local A-line index runs toward
% bmodeDirectionsDeg (deg, counterclockwise from +x): the right window lies at
% that direction and the left window at the opposite one.
%
% Directions are listed left then right for each scan axis. idx selects them
% counterclockwise from 0 deg (stable for equal angles) and anglesDeg is the
% matching full-circle angle column.

    if nargin < 2 || isempty(bmodeDirectionsDeg) || ...
            all(isnan(bmodeDirectionsDeg))
        Jumps1 = repmat([3 1], 1, scanAxisCount);
        Jumps1 = Jumps1(1:scanAxisCount-1);
        Jumps2 = repmat([1 3], 1, scanAxisCount);
        Jumps2 = Jumps2(1:scanAxisCount-1);
        idx1 = cumsum([1, Jumps1]);
        idx2 = cumsum([2, Jumps2]);
        idx = [idx1 idx2];
        fullCircleAnglesDeg = (0:180 / scanAxisCount: ...
            180 / scanAxisCount * (2 * scanAxisCount - 1))';
        return;
    end

    directions = reshape(double(bmodeDirectionsDeg), 1, []);
    if numel(directions) ~= scanAxisCount || any(~isfinite(directions))
        error('OCE:Dispersion:InvalidScanDirections', ...
            'One finite scan direction is required per scan axis.');
    end
    directionAngles = [mod(directions + 180, 360); mod(directions, 360)];
    [fullCircleAnglesDeg, idx] = sort(directionAngles(:));
    idx = idx';
end
