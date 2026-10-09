function data = finalizeUnwrappedWavePlane(raw, unwrapResult)
%FINALIZEUNWRAPPEDWAVEPLANE Place native optical phase only AFTER unwrapping.
% raw is the explicit phase_product='raw_wrapped' output of an acquisition
% owner. unwrapResult.values must contain real unwrapped radian phase with
% identical [depth,native position,time] dimensions. No unwrap or temporal
% filtering is performed here. Static phase is removed by a per-native-voxel
% temporal mean, then a requested enface band is averaged and the existing
% physical geometry operator is applied. The returned motion is phase, not
% a time derivative; harmonic speed estimation is invariant to its scale.
% Borders, OCT support, missing contributors and unacquired holes remain QC.
% Absolute optical phase is not subjected to a Loupas increment pi gate or
% circular disagreement gate. Neither gate diagnoses harmonic propagation.

    validate_input(raw,unwrapResult);
    values = double(unwrapResult.values);
    np = size(values,2); nt = size(values,3);
    valid = raw.valid_mask & all(isfinite(values),3);
    values = values-mean(values,3);
    values(~repmat(valid,1,1,nt)) = NaN;
    options = raw.metadata.load_options;
    geometry = raw.native.geometry;
    metadata = raw.metadata;
    summary = rmfield(unwrapResult,'values');
    summary.performed = true;
    metadata.raw_unwrap = summary;
    metadata.motion_quantity = "unwrapped_optical_phase";
    metadata.motion_estimator = "explicit_unwrap_then_native_placement";
    metadata.processing_order = "complex_reconstruction -> raw_wrapped_phase -> unwrap -> native_temporal_mean_removal -> depth_pooling_if_enface -> geometry_placement -> filters_and_estimation_pending";
    metadata.static_phase_reference = "per_native_voxel_temporal_mean_after_unwrap";
    metadata.phase_difference_performed = false;
    data = struct('motion',single(values),'x_m',raw.x_m,'row_m',raw.row_m, ...
        't_s',raw.t_s,'valid_mask',valid,'structural_db',raw.structural_db, ...
        'coherence',raw.coherence,'plane_type',raw.plane_type,'metadata',metadata, ...
        'offsets',struct('surface_z_m',raw.native.surface_z_m, ...
            'depth_below_surface_m',raw.native.depth_below_surface_m, ...
            'depth_offset_mm',options.depth_offset_mm),'preview',raw.preview);
    if raw.plane_type == "bmode"
        [data,qc] = placeWaveBmode(data,geometry,raw.native.bmode_indices(1),raw.native.lateral_indices);
        data.metadata.bmode_qc = qc;
        data.metadata.axial_aggregation = "none";
        return;
    end
    % Each depth sample is first unwrapped independently at its native
    % acquired position. Averaging wrapped branches would lose motion.
    depth = raw.row_m(:);
    trace = nan(np,nt); slabDb = nan(np,1); slabCoherence = nan(np,1);
    slabValid = false(np,1);
    for j = 1:np
        surface = raw.native.surface_z_m(j);
        bottom = raw.native.posterior_z_m(j);
        target = surface+options.depth_offset_mm*1e-3;
        low = max(surface,target-options.depth_band_mm*1e-3/2);
        high = target+options.depth_band_mm*1e-3/2;
        support = find(depth >= low & depth <= high);
        if ~isfinite(target) || low < depth(1) || high > bottom || high > depth(end) || ...
                isempty(support) || ~all(valid(support,j))
            continue;
        end
        weight = raw.native.axial_weight(support,j);
        total = sum(weight);
        if ~isfinite(total) || total <= 0, continue; end
        local = reshape(values(support,j,:),numel(support),nt);
        trace(j,:) = sum(weight.*local,1)/total;
        slabDb(j) = 10*log10(mean(10.^(raw.structural_db(support,j)/10)));
        slabCoherence(j) = sum(weight.*raw.coherence(support,j))/total;
        slabValid(j) = true;
    end
    count = geometry.lateral_sample_count;
    indices = raw.native.global_lateral_indices;
    native = struct('values',nan(count,nt),'valid_mask',false(count,1), ...
        'structural_db',nan(count,1),'coherence',nan(count,1), ...
        'surface_z_m',nan(count,1),'depth_below_surface_m',nan(count,1));
    native.values(indices,:) = trace;
    native.valid_mask(indices) = slabValid;
    native.structural_db(indices) = slabDb;
    native.coherence(indices) = slabCoherence;
    native.surface_z_m(indices) = raw.native.surface_z_m;
    native.depth_below_surface_m(indices) = options.depth_offset_mm*1e-3;
    finiteValue = abs(trace(isfinite(trace)));
    if isempty(finiteValue), bound = 1; else, bound = max(finiteValue)+1; end
    remap = struct('lateral_stride',options.lateral_stride, ...
        'raster_line_stride',options.raster_line_stride,'min_interpolation_resultant',0, ...
        'max_triangle_edge_mm',options.max_triangle_edge_mm,'max_phase_step_rad',bound);
    mapped = oce.acquisition.applyWaveEnfaceOperator(native,geometry,remap);
    data.motion = mapped.motion; data.valid_mask = mapped.valid_mask;
    data.x_m = mapped.x_m; data.row_m = mapped.row_m;
    data.structural_db = mapped.structural_db; data.coherence = mapped.coherence;
    data.offsets.surface_z_m = mapped.surface_z_m;
    data.offsets.depth_below_surface_m = mapped.depth_below_surface_m;
    mapped.qc.interpolation = "linear_real_unwrapped_phase_after_native_mean_removal";
    mapped.qc.increment_and_circular_gates_applied = false;
    data.metadata.enface_qc = mapped.qc;
    data.metadata.axial_aggregation = "intensity_coherence_weighted_unwrapped_phase_after_native_mean_removal";
end

function validate_input(raw,result)
    required = {'wrapped_phase','layout','x_m','row_m','t_s','valid_mask', ...
        'structural_db','coherence','plane_type','metadata','native','preview'};
    if ~isstruct(raw) || ~isscalar(raw) || ~all(isfield(raw,required)) || ...
            ~isscalar(string(raw.layout)) || string(raw.layout) ~= "depth_native_position_time" || ...
            ~isnumeric(raw.wrapped_phase) || ~isreal(raw.wrapped_phase) || ndims(raw.wrapped_phase) ~= 3 || ...
            ~isstruct(result) || ~isscalar(result) || ...
            ~all(isfield(result,{'values','quantity','units','method','dimensions'})) || ...
            ~isnumeric(result.values) || ~isreal(result.values) || ...
            ~isequal(size(result.values),size(raw.wrapped_phase)) || ...
            ~isscalar(string(result.quantity)) || ~isscalar(string(result.units)) || ...
            string(result.quantity) ~= "unwrapped_phase" || string(result.units) ~= "rad" || ...
            ~isscalar(string(result.method)) || ...
            ~ismember(string(result.method),["sequential","least_squares_dct","tie_dct"])
        error('OCE:Acquisition:InvalidUnwrappedWavePhase', ...
            'Native wrapped phase and an explicit real unwrap result with identical dimensions are required.');
    end
    dimensions = result.dimensions;
    if ~isnumeric(dimensions) || ~isvector(dimensions) || isempty(dimensions) || ...
            ~ismember(3,dimensions) || any(~ismember(dimensions,[1,3])) || ...
            numel(unique(dimensions)) ~= numel(dimensions)
        error('OCE:Acquisition:InvalidUnwrappedWavePhase', ...
            'Native phase must be unwrapped in time, optionally depth, independently at each acquired position.');
    end
    if string(result.method) == "tie_dct"
        if ~all(isfield(result,{'iterations_requested','iterations_executed'})) || ...
                ~isscalar(result.iterations_requested) || ~isfinite(result.iterations_requested) || ...
                result.iterations_requested < 1 || fix(result.iterations_requested) ~= result.iterations_requested || ...
                ~isscalar(result.iterations_executed) || ~isfinite(result.iterations_executed) || ...
                (any(isfinite(result.values),'all') && result.iterations_executed ~= result.iterations_requested) || ...
                (~any(isfinite(result.values),'all') && result.iterations_executed ~= 0)
            error('OCE:Acquisition:InvalidUnwrappedWavePhase', ...
                'TIE-DCT requires an explicit fixed correction budget and matching executed iteration count.');
        end
    end
    shape = [size(raw.wrapped_phase,1),size(raw.wrapped_phase,2)];
    if ~islogical(raw.valid_mask) || ~isequal(size(raw.valid_mask),shape) || ...
            ~isequal(size(raw.structural_db),shape) || ~isequal(size(raw.coherence),shape) || ...
            numel(raw.row_m) ~= shape(1) || numel(raw.t_s) ~= size(raw.wrapped_phase,3) || ...
            ~all(isfield(raw.native,{'geometry','global_lateral_indices','lateral_indices', ...
                'bmode_indices','surface_z_m','posterior_z_m','depth_below_surface_m','axial_weight'})) || ...
            ~isequal(size(raw.native.axial_weight),shape) || ...
            numel(raw.native.global_lateral_indices) ~= shape(2) || ...
            ~isfield(raw.metadata,'load_options') || ~ismember(raw.plane_type,["bmode","enface"])
        error('OCE:Acquisition:InvalidUnwrappedWavePhase','Native masks, axes and placement must match the phase tensor.');
    end
end
