function result = computePhaseGradientSpeed(values, xAxisMm, timeAxisS, frequencyHz)
%COMPUTEPHASEGRADIENTSPEED Fit spatial phase at one physical target frequency.
% values contains real temporal phase increments [lateral,time] in radians,
% on the resolved directional window. xAxisMm increases in natural B-mode
% order; left propagation is not reversed. timeAxisS contains increment
% midpoint times. No filtering, detrending, taper, masking or gap filling is
% performed. A temporal difference's spatially constant harmonic factor does
% not change the spatial slope. Spatial sampling must resolve phase wraps.
% The result contains scalar diagnostics and runtime-only diagnostic vectors.
% Invalid data/projection or a numerically flat phase yields status and NaN
% estimates; malformed geometry/frequency raises an error. R squared is a fit
% diagnostic, not evidence of a single propagation mode.

    if ~isnumeric(values) || ~ismatrix(values) || ...
            size(values, 1) < 3 || size(values, 2) < 3 || ...
            any(imag(values) ~= 0, 'all')
        error('OCE:PhaseGradient:InvalidValues', ...
            'Phase increments must be real lateral-by-time values with at least 3 samples per axis.');
    end
    if ~isnumeric(xAxisMm) || ~isreal(xAxisMm) || ~isvector(xAxisMm) || ...
            numel(xAxisMm) ~= size(values, 1) || ...
            any(~isfinite(xAxisMm)) || any(diff(xAxisMm(:)) <= 0)
        error('OCE:PhaseGradient:InvalidSpaceAxis', ...
            'x_axis_mm must match the window and increase within one B-mode.');
    end
    if ~isnumeric(timeAxisS) || ~isreal(timeAxisS) || ~isvector(timeAxisS) || ...
            numel(timeAxisS) ~= size(values, 2) || ...
            any(~isfinite(timeAxisS)) || any(diff(timeAxisS(:)) <= 0)
        error('OCE:PhaseGradient:InvalidTimeAxis', ...
            'time_axis_s must match the window and increase.');
    end
    time = double(timeAxisS(:));
    dt = time(2) - time(1);
    if any(abs(diff(time) - dt) > 64 * eps(max(abs(time))))
        error('OCE:PhaseGradient:InvalidTimeAxis', ...
            'Temporal projection requires uniformly sampled increments.');
    end
    if ~isnumeric(frequencyHz) || ~isreal(frequencyHz) || ...
            ~isscalar(frequencyHz) || ~isfinite(frequencyHz) || ...
            frequencyHz <= 0 || frequencyHz >= 0.5 / dt
        error('OCE:PhaseGradient:InvalidPhysicalFrequency', ...
            'Target frequency must be positive, finite and below Nyquist.');
    end

    x = (double(xAxisMm(:)) - double(xAxisMm(1))) * 1e-3;
    result = struct('status', "nonfinite_signal", ...
        'phase_slope_rad_per_m', NaN, 'wavenumber_cycles_per_m', NaN, ...
        'phase_speed_m_per_s', NaN, 'r_squared', NaN, 'phase_rmse_rad', NaN, ...
        'spatial_sample_count', numel(x), ...
        'spatial_span_mm', double(xAxisMm(end) - xAxisMm(1)), ...
        'diagnostic', struct('x_axis_mm', xAxisMm(:), ...
            'complex_projection', [], 'unwrapped_phase_rad', [], ...
            'fitted_phase_rad', []));
    signal = double(real(values));
    if any(~isfinite(signal), 'all')
        return;
    end
    % A common time-origin shift changes only the intercept and avoids large
    % exponential arguments for late acquisition crops.
    projection = signal * exp(-1i * 2*pi*frequencyHz * (time - time(1)));
    result.diagnostic.complex_projection = projection;
    % Roundoff guard only: no amplitude/SNR threshold or row exclusion.
    projectionRoundoff = 32 * eps * sum(abs(signal), 2);
    if any(~isfinite(projection)) || any(abs(projection) <= projectionRoundoff)
        result.status = "undefined_projection";
        return;
    end
    phase = unwrap(angle(projection));
    centeredX = x - mean(x);
    centeredPhase = phase - mean(phase);
    slope = (centeredX' * centeredPhase) / (centeredX' * centeredX);
    fitted = mean(phase) + slope * centeredX;
    residual = phase - fitted;
    result.diagnostic.unwrapped_phase_rad = phase;
    result.diagnostic.fitted_phase_rad = fitted;
    phaseRoundoff = 128 * eps(max(1, max(abs(phase))));
    if ~isfinite(slope) || abs(slope) * (x(end) - x(1)) <= phaseRoundoff
        result.status = "degenerate_slope";
        return;
    end
    result.status = "valid";
    result.phase_slope_rad_per_m = slope;
    result.wavenumber_cycles_per_m = abs(slope) / (2*pi);
    result.phase_speed_m_per_s = frequencyHz / result.wavenumber_cycles_per_m;
    result.r_squared = 1 - sum(residual.^2) / sum(centeredPhase.^2);
    result.phase_rmse_rad = sqrt(mean(residual.^2));
end
