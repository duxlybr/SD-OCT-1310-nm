function method = resolveSpatialExtentMethod(methodName)
%RESOLVESPATIALEXTENTMETHOD Resolve an explicit spatial-extent strategy.

    methodName = lower(strtrim(string(methodName)));
    if ~isscalar(methodName)
        unsupported(methodName);
    end
    switch methodName
        case "fraction_of_bmode"
            method = @oce.dispersion.spatialextents.fractionOfBmode;
        case "manual_interval_count"
            method = @oce.dispersion.spatialextents.manualIntervalCount;
        otherwise
            unsupported(methodName);
    end
end

function unsupported(value)
    error('OCE:DispersionWindows:UnsupportedSpatialExtentMethod', ...
        'Unsupported dispersion-window spatial method: %s.', ...
        strjoin(string(value), ', '));
end
