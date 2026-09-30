function fixture = create_motion_fixture()
%CREATE_MOTION_FIXTURE Build deterministic complex inputs for motion contracts.

    nLateral = 4;
    nDepth = 9;
    nTime = 7;
    [lateral, depth, time] = ndgrid(1:nLateral, 1:nDepth, 1:nTime);
    amplitude = 1 + 0.01 * lateral + 0.02 * depth;
    constantPhase = 0.35 * ones(nLateral, nDepth, nTime);
    dynamicPhase = 0.15 * lateral + 0.08 * depth + ...
        0.20 * (time - 1) + 0.01 * sin(2 * lateral + 3 * depth + 5 * time);

    fixture.constantCplx = amplitude .* exp(-1i * constantPhase);
    fixture.dynamicCplx = amplitude .* exp(-1i * dynamicPhase);
    fixture.border = [4 NaN 6 2];
    fixture.validBorder = [4 5 6 4];
    fixture.dimensions = [nLateral nDepth nTime];
end
