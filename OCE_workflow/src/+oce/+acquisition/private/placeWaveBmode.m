function [plane, qc] = placeWaveBmode(plane, geometry, bmode, lateral)
%PLACEWAVEBMODE Place one independent measured cut on its physical axis.
% Polar cuts use cumulative chord lengths between acquired positions. A
% nonuniform curved cut is linearly resampled onto a uniform local arc axis.
% Both contributors must be valid: no extrapolation, closing ring or phase
% registration occurs. Straight B-modes pass through without interpolation.
    qc = struct('resampled',false,'closed_seam',false,'axis_meaning', ...
        "independent_straight_bmode_distance",'native_axis_m',plane.x_m(:));
    if geometry.scan_geometry ~= "polar", return; end
    index = (bmode-1)*geometry.samples_per_bmode+(1:geometry.samples_per_bmode);
    positions = geometry.polar.positions_mm(index,:);
    fullArc = [0;cumsum(hypot(diff(positions(:,1)),diff(positions(:,2))))]*1e-3;
    source = fullArc(lateral);
    qc.native_axis_m = source;
    qc.axis_meaning = "independent_curved_scan_physical_arc_length";
    plane.x_m = source;
    if ~isfield(plane,'motion'), return; end
    if any(diff(source) <= 0)
        error('OCE:Acquisition:InvalidPolarBmodeAxis','Independent polar segment must have distinct consecutive positions.');
    end
    if max(abs(diff(source)-mean(diff(source)))) <= 1e-8*max(source(end),eps), return; end
    target = linspace(source(1),source(end),numel(source))';
    left = discretize(target,source);
    left(end) = numel(source)-1;
    right = left+1;
    fraction = (target-source(left))./(source(right)-source(left));
    fraction = max(0,min(1,fraction));
    op = sparse([(1:numel(target))';(1:numel(target))'], ...
        [left;right],[1-fraction;fraction],numel(target),numel(source));
    % Native intervals grow along a spiral. Detect missing positions using
    % the full acquired arc, rather than calling normal curvature a gap.
    maxGap = 1.5*max(diff(fullArc))*max(1,max(diff(lateral)));
    gapValid = source(right)-source(left) <= maxGap;
    bad = full(spones(op)*double(~plane.valid_mask')) > 0;
    valid = ~bad' & gapValid';
    nr = size(plane.motion,1); nt = size(plane.motion,3);
    flattened = reshape(permute(double(plane.motion),[2,1,3]),numel(source),[]);
    missing = full(spones(op)*double(~isfinite(flattened))) > 0;
    flattened(~isfinite(flattened)) = 0;
    mapped = op*flattened; mapped(missing) = NaN;
    plane.motion = permute(reshape(single(mapped),numel(target),nr,nt),[2,1,3]);
    valid = valid & all(isfinite(plane.motion),3);
    plane.motion(~repmat(valid,1,1,nt)) = NaN;
    plane.valid_mask = valid;
    for name = ["structural_db","coherence"]
        value = double(plane.(name));
        missing = full(spones(op)*double(~isfinite(value'))) > 0;
        value(~isfinite(value)) = 0;
        mapped = op*value'; mapped(missing) = NaN;
        plane.(name) = mapped';
    end
    plane.offsets.surface_z_m = map_vector(plane.offsets.surface_z_m);
    plane.offsets.depth_below_surface_m = map_matrix(plane.offsets.depth_below_surface_m);
    if isfield(plane,'preview')
        plane.preview.intensity_db = map_matrix(plane.preview.intensity_db);
        plane.preview.surface_m = map_vector(plane.preview.surface_m);
        if isfield(plane.preview,'posterior_m')
            plane.preview.posterior_m = map_vector(plane.preview.posterior_m);
        end
        plane.preview.x_m = target;
    end
    plane.x_m = target;
    qc.resampled = true;
    qc.maximum_native_gap_m = maxGap;
    qc.contributors_valid = ~bad';
    qc.interpolation = "linear_real_phase_increment_on_independent_arc";
    if isfield(plane,'metadata') && isfield(plane.metadata,'motion_quantity') && ...
            plane.metadata.motion_quantity == "unwrapped_optical_phase"
        qc.interpolation = "linear_real_unwrapped_phase_after_native_mean_removal_on_independent_arc";
    end

    function result = map_vector(value)
        result = map_matrix(value(:)');
    end
    function result = map_matrix(value)
        missingValue = full(spones(op)*double(~isfinite(value'))) > 0;
        value(~isfinite(value)) = 0;
        result = op*value'; result(missingValue) = NaN; result = result';
    end
end
