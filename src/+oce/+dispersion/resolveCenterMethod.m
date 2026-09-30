function centerMethod = resolveCenterMethod(centerMode)
%RESOLVECENTERMETHOD Resolve a dispersion-window center strategy.

    centerMode = lower(string(centerMode));
    if ~isscalar(centerMode), unsupported(centerMode); end

    switch centerMode
        case "middle"
            centerMethod = @oce.dispersion.centers.middle;
        case "manual_local_index"
            centerMethod = @oce.dispersion.centers.manualLocalIndex;
        case "max_rms_phase_increment"
            centerMethod = @oce.dispersion.centers.maxRmsPhaseIncrement;
        case "max_mirrored_correlation"
            centerMethod = @oce.dispersion.centers.maxMirroredCorrelation;
        otherwise
            unsupported(centerMode);
    end
end

function unsupported(value)
    error('OCE:DispersionWindows:UnsupportedCenterMethod', ...
        'Unsupported dispersion-window center method: %s.', ...
        strjoin(string(value), ', '));
end
