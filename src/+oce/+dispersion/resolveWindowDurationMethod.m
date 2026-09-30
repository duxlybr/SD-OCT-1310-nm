function method = resolveWindowDurationMethod(methodName)
%RESOLVEWINDOWDURATIONMETHOD Resolve an explicit temporal-duration strategy.

    methodName = lower(strtrim(string(methodName)));
    if ~isscalar(methodName)
        unsupported(methodName);
    end
    switch methodName
        case "manual_interval_count"
            method = @oce.dispersion.windowdurations.manualIntervalCount;
        case "cycle_count"
            method = @oce.dispersion.windowdurations.cycleCount;
        case "to_end"
            method = @oce.dispersion.windowdurations.toEnd;
        otherwise
            unsupported(methodName);
    end
end

function unsupported(value)
    error('OCE:DispersionWindows:UnsupportedDurationMethod', ...
        'Unsupported dispersion-window temporal method: %s.', ...
        strjoin(string(value), ', '));
end
