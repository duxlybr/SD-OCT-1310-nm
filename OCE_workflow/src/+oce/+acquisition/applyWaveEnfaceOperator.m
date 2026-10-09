function result = applyWaveEnfaceOperator(native, geometry, options)
%APPLYWAVEENFACEOPERATOR Map measured real phase using acquisition geometry.
% native.values is [acquired lateral position,time], never a painted phase.
% The existing enface.operator owns spatial placement/interpolation. This
% function rejects missing contributors, ring holes, long interpolation edges
% and phase disagreement; it never fills a hole or registers excitations.
% Real Loupas increments are interpolated linearly, not wrapped through exp(i*p).
% Circular resultant is an additional disagreement diagnostic only.
% finalizeUnwrappedWavePlane also reuses this placement after native unwrap
% and mean removal, explicitly disabling the incremental/circular gates.

    if nargin < 3, options = struct(); end
    options = resolve_options(options);
    fields = {'values','valid_mask','structural_db','coherence','surface_z_m','depth_below_surface_m'};
    if ~isstruct(native) || ~isscalar(native) || any(~isfield(native, fields)) || ...
            ~isstruct(geometry) || ~isfield(geometry, 'enface')
        error('OCE:Acquisition:InvalidWaveEnfaceInput', 'Native wave traces and enface geometry are required.');
    end
    op = geometry.enface.operator;
    n = size(op, 2);
    if ~isnumeric(native.values) || ~isreal(native.values) || ...
            size(native.values, 1) ~= n || size(native.values, 2) < 2
        error('OCE:Acquisition:InvalidWaveEnfaceInput', 'Native values must be real [lateral,time] increments matching geometry.');
    end
    for j = 2:numel(fields)
        if numel(native.(fields{j})) ~= n
            error('OCE:Acquisition:InvalidWaveEnfaceInput', 'Native %s must match acquired lateral count.', fields{j});
        end
    end
    coverage = geometry.enface.coverage;
    nr = size(coverage, 1); nc = size(coverage, 2);
    if ~issparse(op) || size(op, 1) ~= nr*nc || any(nonzeros(op) < -1e-12) || ...
            any(abs(full(sum(op, 2)) - double(coverage(:))) > 1e-9)
        error('OCE:Acquisition:InvalidWaveEnfaceGeometry', 'The validated nonnegative acquisition interpolation operator is required.');
    end
    % Decimate output coordinates, retaining the same acquired geometry.
    [row, col] = ndgrid(1:options.raster_line_stride:nr, 1:options.lateral_stride:nc);
    selected = row(:) + (col(:)-1)*nr;
    op = op(selected, :);
    shape = size(row);
    inside = coverage(selected);
    geometryValid = inside;
    maxEdgeMm = NaN;
    nativeSpacingMm = NaN;
    if geometry.scan_geometry == "polar"
        p = geometry.polar;
        [xx, yy] = meshgrid(geometry.enface.x_axis_mm(col(1,:)), ...
            geometry.enface.y_axis_mm(row(:,1)));
        if p.pattern == "rings"
            rho = hypot(xx/(p.x_scan_length_mm/2), yy/(p.y_scan_length_mm/2));
            % The inner ring is a boundary of acquired support. Convex hull
            % triangulation alone would incorrectly interpolate across its hole.
            geometryValid = geometryValid & rho(:) >= min(p.radius_fraction)-1e-12;
        end
        radial = min(p.x_scan_length_mm,p.y_scan_length_mm)/(2*geometry.bmode_count);
        arc = pi*max(p.x_scan_length_mm,p.y_scan_length_mm)/geometry.samples_per_bmode;
        nativeSpacingMm = max(radial,arc);
        maxEdgeMm = options.max_triangle_edge_mm;
        if isempty(maxEdgeMm), maxEdgeMm = 2.5*hypot(radial,arc); end
        [r,c] = find(op);
        count = accumarray(r,1,[size(op,1),1]);
        if any(count > 3)
            error('OCE:Acquisition:InvalidWaveEnfaceGeometry', 'Polar acquisition operator must have at most three contributors per cell.');
        end
        % FIND orders columns, so sort by output row before assigning vertices.
        [r,order] = sort(r); c = c(order);
        rank = (1:numel(r))' - repelem(cumsum([0;count(1:end-1)]),count);
        ids = ones(size(op,1),3);
        ids(sub2ind(size(ids),r,rank)) = c;
        lengthMax = zeros(size(op,1),1);
        for a = 1:2
            for b = a+1:3
                available = count >= b;
                delta = p.positions_mm(ids(:,a),:) - p.positions_mm(ids(:,b),:);
                distance = hypot(delta(:,1),delta(:,2));
                lengthMax(available) = max(lengthMax(available),distance(available));
            end
        end
        geometryValid = geometryValid & lengthMax <= maxEdgeMm;
    end
    sourceValid = logical(native.valid_mask(:)) & all(isfinite(native.values),2) & ...
        all(abs(native.values) <= options.max_phase_step_rad,2) & ...
        isfinite(native.structural_db(:)) & isfinite(native.coherence(:)) & ...
        isfinite(native.surface_z_m(:)) & isfinite(native.depth_below_surface_m(:));
    contributorsValid = full(spones(op)*double(~sourceValid)) == 0;
    traces = double(native.values);
    traces(~isfinite(traces)) = 0;
    mapped = op*traces;
    resultant = mean(abs(op*exp(1i*traces)),2);
    valid = geometryValid & contributorsValid & resultant >= options.min_interpolation_resultant;
    mapped(~valid,:) = NaN;
    result = struct('motion',reshape(single(mapped),[shape,size(mapped,2)]), ...
        'valid_mask',reshape(valid,shape), ...
        'x_m',geometry.enface.x_axis_mm(col(1,:))'*1e-3, ...
        'row_m',geometry.enface.y_axis_mm(row(:,1))*1e-3, ...
        'structural_db',map_scalar(native.structural_db), ...
        'coherence',map_scalar(native.coherence), ...
        'surface_z_m',map_scalar(native.surface_z_m), ...
        'depth_below_surface_m',map_scalar(native.depth_below_surface_m), ...
        'qc',struct('geometry_valid',reshape(geometryValid,shape), ...
            'contributors_valid',reshape(contributorsValid,shape), ...
            'interpolation_resultant',reshape(resultant,shape), ...
            'max_triangle_edge_mm',maxEdgeMm,'native_spacing_mm',nativeSpacingMm, ...
            'interpolation',"linear_real_phase_increment", ...
            'phase_registration_performed',false));

    function image = map_scalar(value)
        value = double(value(:)); value(~isfinite(value)) = 0;
        image = op*value;
        image(~valid) = NaN;
        image = reshape(image,shape);
    end
end

function options = resolve_options(value)
    options = struct('lateral_stride',1,'raster_line_stride',1, ...
        'min_interpolation_resultant',.5,'max_triangle_edge_mm',[], ...
        'max_phase_step_rad',pi);
    if ~isstruct(value) || ~isscalar(value) || ...
            (~isempty(fieldnames(value)) && any(~isfield(options,fieldnames(value))))
        error('OCE:Acquisition:InvalidWaveEnfaceOptions','Unknown or invalid enface QC options.');
    end
    names = fieldnames(value);
    for j = 1:numel(names), options.(names{j}) = value.(names{j}); end
    for name = ["lateral_stride","raster_line_stride"]
        validateattributes(options.(name),{'numeric'},{'scalar','finite','integer','positive'});
    end
    validateattributes(options.min_interpolation_resultant,{'numeric'},{'scalar','finite','>=',0,'<=',1});
    validateattributes(options.max_phase_step_rad,{'numeric'},{'scalar','finite','positive'});
    if ~isempty(options.max_triangle_edge_mm)
        validateattributes(options.max_triangle_edge_mm,{'numeric'},{'scalar','finite','positive'});
    end
end
