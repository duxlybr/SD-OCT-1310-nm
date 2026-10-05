function data = buildWaveMotionPlane(state, phaseResult, borderResult, options)
%BUILDWAVEMOTIONPLANE Build a map input from existing STEPWISE products.
% No file is read and no phase estimator is rerun. state is the validated
% acquisition_state, phaseResult.depth_resolved contains real phase increments
% and borderResult is the existing detectAndMask product. Both boundaries and
% its OCT intensityMask remain fundamental support constraints. Independent
% B-modes are never concatenated; raster/polar enface maps are conditional on
% repeated trigger-to-wave timing, which this conversion does not establish.
% The output has the same [row,column,time] SI-axis contract as loadWaveMotionPlane.
%
% options: plane_type='auto'|'bmode'|'enface', bmode_index=1,
% depth_offset_mm=0, depth_band_mm=.04, intensity_floor_db=-35,
% coherence_threshold=.15, lateral_stride=1, raster_line_stride=1,
% preview_bmode=1, phase_registration_status='unverified'|'assumed_repeatable'|
% 'verified', min_interpolation_resultant=.5, max_triangle_edge_mm=[],
% max_phase_step_rad=pi. Registration status is declared provenance, not a
% registration algorithm. Polar remapping uses the existing geometry operator.

    if nargin < 4, options = struct(); end
    options = resolve_options(options);
    validate_inputs(state,phaseResult,borderResult);
    reconstruction = state.reconstruction;
    geometry = state.geometry;
    phase = phaseResult.depth_resolved;
    if phase.quantity ~= "phase_increment"
        error('OCE:Acquisition:WrappedWaveMotion', ...
            ['Wave maps require an existing real phase_increment product. ' ...
             'Choose Loupas or unwrap_then_difference in MotionOptions; ' ...
             'wrapped_phase is not silently unwrapped by this converter.']);
    end
    nl = geometry.lateral_sample_count;
    nd = size(reconstruction.amplitude.values,1);
    np = size(phase.values,2);
    nt = size(phase.values,3);
    window = nd-np+1;
    if nt ~= size(reconstruction.complex_volume.values,3)-1 || window < 1 || ...
            (phase.estimator ~= "loupas" && window ~= 1)
        error('OCE:Acquisition:InvalidWavePhaseDimensions', ...
            'Increment dimensions must agree with reconstruction and the estimator axial support.');
    end
    dz = reconstruction.geometry.depth_sample_interval_mm;
    dt = reconstruction.geometry.time_sample_interval_s;
    crop = reconstruction.crop;
    rawDepth = reconstruction.axes.depth.values(:)' + (crop.depth.start_index_inclusive-1)*dz;
    depth = rawDepth(1:np)+(window-1)/2*dz;
    time = ((crop.time.start_index_inclusive-1)+(0:nt-1)+.5)*dt;
    amplitude = reconstruction.amplitude.values;
    supportAmplitude = conv2(ones(window,1)/window,1,amplitude,'valid');
    supportMask = conv2(ones(window,1),1,double(borderResult.intensityMask),'valid') == window;
    anterior = double(borderResult.indices.anterior(:)');
    posterior = double(borderResult.indices.posterior(:)');
    surface = interp1(1:nd,rawDepth,anterior,'linear',NaN);
    if borderResult.surface_mode == "anterior_posterior"
        bottom = interp1(1:nd,rawDepth,posterior,'linear',NaN);
        surfaceValid = isfinite(surface) & isfinite(bottom) & bottom > surface;
    else
        bottom = repmat(rawDepth(end),1,nl);
        surfaceValid = isfinite(surface);
    end
    % Every sample of a Loupas support must remain inside the specimen.
    low = rawDepth(1:np)'; high = low+(window-1)*dz;
    inside = surfaceValid & low >= surface & high <= bottom & supportMask;
    coherence = zeros(np,nl);
    for j = 1:nl
        iq = reshape(reconstruction.complex_volume.values(j,:,:),nd,nt+1);
        coherence(:,j) = waveTemporalCoherence(iq,window);
    end
    structural = 20*log10(max(supportAmplitude,realmin));
    reference = structural(inside & isfinite(structural));
    if isempty(reference), referenceDb = NaN; else, referenceDb = max(reference); end
    structural = structural-referenceDb;
    nativeValid = inside & isfinite(structural) & structural >= options.intensity_floor_db & ...
        coherence >= options.coherence_threshold;
    planeType = options.plane_type;
    if planeType == "auto"
        if ismember(geometry.scan_geometry,["raster","polar"]), planeType = "enface";
        else, planeType = "bmode"; end
    end
    if planeType == "enface" && ~isfield(geometry,'enface')
        error('OCE:Acquisition:InvalidWavePlaneGeometry','Enface requires an acquired raster or polar geometry.');
    end
    lateral = 1:options.lateral_stride:geometry.samples_per_bmode;
    if options.bmode_index > geometry.bmode_count || options.preview_bmode > geometry.bmode_count
        error('OCE:Acquisition:InvalidWavePlaneBmode','Requested B-mode exceeds acquired geometry.');
    end
    values = real(phase.values);
    if planeType == "bmode"
        indices = (options.bmode_index-1)*geometry.samples_per_bmode+lateral;
        motion = permute(single(values(indices,:,:)),[2,1,3]);
        valid = nativeValid(:,indices) & all(isfinite(motion),3) & ...
            all(abs(motion) <= options.max_phase_step_rad,3);
        motion(~repmat(valid,1,1,nt)) = NaN;
        [x,axisMeaning] = bmode_axis(geometry,options.bmode_index,lateral);
        row = depth*1e-3;
        structural = structural(:,indices);
        coherence = coherence(:,indices);
        offsets = struct('surface_z_m',surface(indices)*1e-3, ...
            'depth_below_surface_m',(depth'-surface(indices))*1e-3, ...
            'depth_offset_mm',options.depth_offset_mm);
        bmodeIndices = options.bmode_index;
        qc = struct('border_and_intensity_valid',inside(:,indices), ...
            'phase_registration_performed',false);
    else
        traces = nan(nl,nt); slabDb = nan(nl,1); slabCoherence = nan(nl,1);
        slabValid = false(nl,1);
        for j = 1:nl
            target = surface(j)+options.depth_offset_mm;
            bandLow = max(surface(j),target-options.depth_band_mm/2);
            bandHigh = target+options.depth_band_mm/2;
            support = find(low >= bandLow & high <= bandHigh);
            contained = surfaceValid(j) && bandLow >= rawDepth(1) && ...
                bandHigh <= bottom(j) && bandHigh <= rawDepth(end) && ~isempty(support);
            if ~contained, continue; end
            % A rejected OCT sample does not get rescued by an axial average.
            if ~all(nativeValid(support,j)), continue; end
            local = reshape(values(j,support,:),numel(support),nt);
            if any(~isfinite(local),'all') || any(abs(local)>options.max_phase_step_rad,'all'), continue; end
            weight = supportAmplitude(support,j).^2 .* coherence(support,j);
            total = sum(weight);
            if total <= 0, continue; end
            traces(j,:) = sum(weight.*local,1)/total;
            slabDb(j) = 20*log10(mean(supportAmplitude(support,j)))-referenceDb;
            slabCoherence(j) = sum(weight.*coherence(support,j))/total;
            slabValid(j) = true;
        end
        % Input decimation on regular rasters is exact output selection.
        % Polar grids instead decimate the output operator: their true native
        % sampling remains recorded and is never replaced by display grid spacing.
        native = struct('values',traces,'valid_mask',slabValid,'structural_db',slabDb, ...
            'coherence',slabCoherence,'surface_z_m',surface'*1e-3, ...
            'depth_below_surface_m',repmat(options.depth_offset_mm*1e-3,nl,1));
        mapped = oce.acquisition.applyWaveEnfaceOperator(native,geometry,enface_options(options));
        motion = mapped.motion; valid = mapped.valid_mask; x = mapped.x_m; row = mapped.row_m;
        structural = mapped.structural_db; coherence = mapped.coherence; qc = mapped.qc;
        offsets = struct('surface_z_m',mapped.surface_z_m, ...
            'depth_below_surface_m',mapped.depth_below_surface_m,'depth_offset_mm',options.depth_offset_mm);
        bmodeIndices = 1:geometry.bmode_count;
        axisMeaning = "cartesian_acquired_or_interpolated";
    end
    options.plane_type = planeType;
    metadata = build_metadata(state,phase,borderResult,options,bmodeIndices,lateral,axisMeaning,qc);
    metadata.structural_reference_db = referenceDb;
    metadata.depth_crop_fft_indices = [crop.depth.start_index_inclusive crop.depth.end_index_inclusive];
    metadata.reconstruction_provenance = reconstruction.provenance;
    previewBmode = options.preview_bmode;
    if planeType == "bmode", previewBmode = options.bmode_index; end
    previewIndices = (previewBmode-1)*geometry.samples_per_bmode+lateral;
    [previewX,~] = bmode_axis(geometry,previewBmode,lateral);
    previewDb = reconstruction.log_amplitude.values(:,previewIndices);
    previewDb = previewDb-max(previewDb,[],'all');
    data = struct('motion',motion,'x_m',x(:),'row_m',row(:)', ...
        't_s',time,'valid_mask',valid,'structural_db',structural, ...
        'coherence',coherence,'plane_type',planeType,'metadata',metadata, ...
        'offsets',offsets,'preview',struct('intensity_db',previewDb, ...
            'depth_m',rawDepth*1e-3,'x_m',previewX(:),'surface_m',surface(previewIndices)*1e-3, ...
            'posterior_m',bottom(previewIndices)*1e-3,'bmode_index',previewBmode));
    if planeType == "bmode"
        [data,bmodeQc] = placeWaveBmode(data,geometry,options.bmode_index,lateral);
        data.metadata.bmode_qc = bmodeQc;
    end
end

function validate_inputs(state,phaseResult,borderResult)
    if ~isstruct(state) || ~isscalar(state) || ~all(isfield(state,{'reconstruction','geometry'}))
        error('OCE:Acquisition:InvalidWavePlaneState','The existing acquisition_state is required.');
    end
    oce.results.validateReconstructionResult(state.reconstruction);
    geometry = state.geometry;
    if ~all(isfield(geometry,{'scan_geometry','lateral_sample_count','samples_per_bmode','bmode_count'})) || ...
            geometry.lateral_sample_count ~= size(state.reconstruction.complex_volume.values,1)
        error('OCE:Acquisition:InvalidWavePlaneGeometry','Acquisition geometry must match the reconstruction.');
    end
    if ~isstruct(phaseResult) || ~isscalar(phaseResult) || ~isfield(phaseResult,'depth_resolved') || ...
            ~all(isfield(phaseResult.depth_resolved,{'values','quantity','units','layout','estimator','difference_axis'}))
        error('OCE:Acquisition:MissingDepthWavePhase', ...
            'phase_result.depth_resolved is required; surface-only products cannot supply deeper layers or B-scans.');
    end
    phase = phaseResult.depth_resolved;
    if phase.layout ~= "lateral_depth_time" || phase.units ~= "rad" || phase.difference_axis ~= "time" || ...
            ~isnumeric(phase.values) || ~isreal(phase.values) || size(phase.values,1) ~= geometry.lateral_sample_count || ...
            ~ismember(phase.quantity,["phase_increment","wrapped_phase"]) || ...
            ~ismember(phase.estimator,["loupas","unwrap_then_difference","direct_phase"])
        error('OCE:Acquisition:InvalidWavePhaseProduct','Depth phase must be the existing radian lateral_depth_time product.');
    end
    nd = size(state.reconstruction.amplitude.values,1);
    if ~isstruct(borderResult) || ~isscalar(borderResult) || ...
            ~all(isfield(borderResult,{'surface_mode','indices','intensityMask'})) || ...
            ~all(isfield(borderResult.indices,{'anterior','posterior'})) || ...
            ~ismember(string(borderResult.surface_mode),["anterior_only","anterior_posterior"]) || ...
            ~islogical(borderResult.intensityMask) || ...
            ~isequal(size(borderResult.intensityMask),[nd,geometry.lateral_sample_count]) || ...
            numel(borderResult.indices.anterior) ~= geometry.lateral_sample_count || ...
            numel(borderResult.indices.posterior) ~= geometry.lateral_sample_count
        error('OCE:Acquisition:InvalidWaveBorderProduct','The detectAndMask product must match reconstruction depth/lateral coordinates.');
    end
end

function [axis,meaning] = bmode_axis(geometry,bmode,lateral)
    if geometry.scan_geometry == "polar"
        index = (bmode-1)*geometry.samples_per_bmode+(1:geometry.samples_per_bmode);
        p = geometry.polar.positions_mm(index,:);
        axis = [0;cumsum(hypot(diff(p(:,1)),diff(p(:,2))))]*1e-3;
        axis = axis(lateral); meaning = "independent_curved_scan_physical_arc_length";
    else
        axis = geometry.bmode_lateral_axis_mm(lateral)'*1e-3;
        meaning = "independent_straight_bmode_distance";
    end
end

function metadata = build_metadata(state,phase,borders,options,bmodes,lateral,axisMeaning,qc)
    descriptor = struct();
    if isfield(state,'raw') && isfield(state.raw,'descriptor'), descriptor = state.raw.descriptor;
    elseif isfield(state,'metadata') && isfield(state.metadata,'raw_descriptor'), descriptor = state.metadata.raw_descriptor; end
    excitation = struct('available',false,'source',"",'frequency_hz',NaN);
    if isfield(descriptor,'excitation'), excitation = descriptor.excitation; end
    notes = strings(0,1);
    notes(end+1) = "Plano construido de productos STEPWISE: sin releer BIN ni recalcular fase; se conservan bordes y máscara OCT.";
    if ~excitation.available
        notes(end+1) = "Generador no documentado: indicar frecuencia mecánica explícita; no se infiere del nombre ni del trigger.";
    end
    if options.plane_type == "enface"
        notes(end+1) = "Enface MB: cada posición corresponde a otra excitación. La comparación espacial exige retardo y respuesta repetibles; esta conversión no registra fases ni verifica sincronización.";
    else
        notes(end+1) = "B-mode independiente: no se unen repeticiones ni extremos de curvas, ni se concatenan B-modes.";
    end
    if state.geometry.scan_geometry == "polar"
        notes(end+1) = "Geometría polar: interpolación no crea resolución física ni evita alias. Revisar el muestreo nativo, huecos y soporte de triángulos.";
        if options.plane_type == "bmode"
            notes(end+1) = "B-scan polar sobre arco físico curvo: el estimador sólo aproxima propagación local sobre ese arco; no es un corte cartesiano recto.";
        end
    end
    notes(end+1) = "La validez computacional de bordes no certifica una superficie anatómica ni un módulo de Young experimental.";
    metadata = struct('header',descriptor,'excitation',excitation,'frequency_hz',excitation.frequency_hz, ...
        'line_rate_hz',1/state.reconstruction.geometry.time_sample_interval_s, ...
        'motion_quantity',"temporal_phase_increment",'motion_units',"rad",'motion_estimator',phase.estimator, ...
        'time_origin',"acquisition_crop_increment_midpoint",'bmode_indices',bmodes,'lateral_indices',lateral, ...
        'scan_geometry',state.geometry.scan_geometry,'spatial_axis_meaning',axisMeaning, ...
        'phase_registration_status',options.phase_registration_status, ...
        'spatial_phase_repeatability_verified',options.phase_registration_status == "verified", ...
        'phase_registration_performed',false,'surface_detection_verified',false, ...
        'border_surface_mode',string(borders.surface_mode),'source_kind',"stepwise_products", ...
        'notes',notes,'load_options',options,'enface_qc',qc);
end

function options = resolve_options(value)
    options = struct('plane_type',"auto",'bmode_index',1,'depth_offset_mm',0,'depth_band_mm',.04, ...
        'intensity_floor_db',-35,'coherence_threshold',.15,'lateral_stride',1,'raster_line_stride',1, ...
        'preview_bmode',1,'phase_registration_status',"unverified", ...
        'min_interpolation_resultant',.5,'max_triangle_edge_mm',[],'max_phase_step_rad',pi);
    if ~isstruct(value) || ~isscalar(value) || ...
            (~isempty(fieldnames(value)) && any(~isfield(options,fieldnames(value))))
        error('OCE:Acquisition:InvalidWavePlaneOptions','Unknown or invalid product-to-plane options.');
    end
    names = fieldnames(value);
    for j = 1:numel(names), options.(names{j}) = value.(names{j}); end
    options.plane_type = lower(string(options.plane_type));
    options.phase_registration_status = lower(string(options.phase_registration_status));
    if ~isscalar(options.plane_type) || ~ismember(options.plane_type,["auto","bmode","enface"]) || ...
            ~isscalar(options.phase_registration_status) || ...
            ~ismember(options.phase_registration_status,["unverified","assumed_repeatable","verified"])
        error('OCE:Acquisition:InvalidWavePlaneOptions','Invalid plane type or phase registration declaration.');
    end
    for name = ["bmode_index","preview_bmode","lateral_stride","raster_line_stride"]
        validateattributes(options.(name),{'numeric'},{'scalar','finite','integer','positive'});
    end
    validateattributes(options.depth_offset_mm,{'numeric'},{'scalar','finite','nonnegative'});
    validateattributes(options.depth_band_mm,{'numeric'},{'scalar','finite','positive'});
    validateattributes(options.intensity_floor_db,{'numeric'},{'scalar','finite','<=',0});
    validateattributes(options.coherence_threshold,{'numeric'},{'scalar','finite','>=',0,'<=',1});
    % The shared remapper owns validation of its QC options.
    validateattributes(options.min_interpolation_resultant,{'numeric'},{'scalar','finite','>=',0,'<=',1});
    validateattributes(options.max_phase_step_rad,{'numeric'},{'scalar','finite','positive'});
    if ~isempty(options.max_triangle_edge_mm)
        validateattributes(options.max_triangle_edge_mm,{'numeric'},{'scalar','finite','positive'});
    end
end

function value = enface_options(options)
    names = {'lateral_stride','raster_line_stride','min_interpolation_resultant','max_triangle_edge_mm','max_phase_step_rad'};
    value = struct();
    for j = 1:numel(names), value.(names{j}) = options.(names{j}); end
end
