function data = loadWaveMotionPlane(binFile, options)
%LOADWAVEMOTIONPLANE Load an experimental wave plane with bounded raw memory.
% data.motion is real [row,column,time] Loupas phase increment (rad), with
% physical x_m, row_m and midpoint t_s axes. An independent B-mode retains
% depth; raster/polar extracts a band at depth_offset_mm BELOW EACH local surface.
% Files need not contain generator metadata: unavailable frequency stays NaN.
% The raster is assembled from repeated MB responses. Its temporal origin is
% local to each position; cross-position/line phase coherence is conditional
% on repeatable trigger-to-wave timing, not proved by a hardware trigger flag.
% Raw uint16 and complex reconstruction are held only for a position block.
% A first streaming pass estimates the same temporal-then-lateral median
% background over all SELECTED positions; selection and scope are recorded.
%
% options: plane_type='auto'|'bmode'|'enface', bmode_index=1,
% depth_offset_mm=0, depth_band_mm=.04, depth_start_index=10,
% depth_end_index=[] (FFT half), surface_search_start_index=20,
% surface_search_end_index=[] (crop end), refractive_index=1.4,
% line_rate_hz=[] (header required or supplied), intensity_floor_db=-35,
% lateral_stride=1, raster_line_stride=1, block_positions=8,
% loupas_axial_window=3, coherence_threshold=.15, show_progress=false.
% surface_method='inherited_threshold'|'max_in_search'|'manual_index';
% surface_index=[] is the raw FFT depth index for manual_index.
% OCTSystemOptions optionally supplies the existing OCTSystemOptions
% contract, for an independently reviewed optical calibration.
% phase_product='phase_increment' (default) preserves the existing path.
% 'raw_wrapped' instead returns angle(IQ) as wrapped_phase in native
% [depth,position,time] coordinates. No Loupas estimate, depth pooling,
% temporal filter/difference or spatial interpolation precedes unwrapping.
% Pass its explicit unwrap result to finalizeUnwrappedWavePlane afterwards.

    if nargin < 2, options = struct(); end
    options = resolve_options(options);
    rawMode = options.phase_product == "raw_wrapped";
    if ~(ischar(binFile) || (isstring(binFile) && isscalar(binFile)))
        error('OCE:Acquisition:InvalidWavePlaneFile', 'binFile must be one path.');
    end
    [folder, name, extension] = fileparts(char(binFile));
    if isempty(folder), folder = pwd; end
    filename = [name extension];
    header = oce.io.readAcquisitionHeader(filename, folder);
    if isfield(header, 'bscan_angle_deg')
        geometry = oce.acquisition.buildAcquisitionGeometry(header, "automatic");
    else
        geometry = oce.acquisition.buildAcquisitionGeometry(header, "angular_bmodes");
    end
    planeType = options.plane_type;
    if planeType == "auto"
        if ismember(geometry.scan_geometry,["raster","polar"]), planeType = "enface";
        else, planeType = "bmode"; end
    end
    if planeType == "enface" && ~isfield(geometry,'enface')
        error('OCE:Acquisition:InvalidWavePlaneGeometry', ...
            'An acquired enface plane requires raster or polar geometry; choose one independent B-mode.');
    end
    if isempty(options.OCTSystemOptions)
        systemOptions = oce.config.getOCTSystemOptions("spectral_domain_1310");
    else
        systemOptions = options.OCTSystemOptions;
    end
    system = oce.config.resolveOCTSystemOptions(systemOptions, "", header);
    if isempty(options.line_rate_hz)
        if ~isfield(header, 'a_scan_rate_hz') || ~isfinite(header.a_scan_rate_hz)
            error('OCE:Acquisition:MissingWavePlaneLineRate', ...
                'The file lacks a camera line rate; supply options.line_rate_hz explicitly.');
        end
    else
        system.a_scan_rate = options.line_rate_hz / 1000;
        system.a_scan_rate_source = "wave_plane_explicit_override";
    end
    optics = oce.config.resolveSampleOpticalOptions(struct( ...
        'refractive_index', struct('value', options.refractive_index, ...
            'source', "wave_plane_user_configuration")));
    depthEnd = options.depth_end_index;
    if isempty(depthEnd), depthEnd = floor(header.samples_in_Aline / 2); end
    depthStart = options.depth_start_index;
    window = options.loupas_axial_window;
    if rawMode, window = 1; end
    if depthEnd > floor(header.samples_in_Aline / 2) || ...
            depthEnd - depthStart + 1 < window
        error('OCE:Acquisition:InvalidWavePlaneCrop', ...
            'Depth crop must fit the FFT half-spectrum and Loupas axial window.');
    end
    if header.Alines_in_Bframe < 2
        error('OCE:Acquisition:InvalidWavePlaneTime', 'At least two M repetitions are required.');
    end
    searchStart = max(depthStart, options.surface_search_start_index);
    searchEnd = options.surface_search_end_index;
    if isempty(searchEnd), searchEnd = depthEnd; end
    searchEnd = min(searchEnd, depthEnd);
    if searchEnd - searchStart < 11
        error('OCE:Acquisition:InvalidWavePlaneSurfaceRange', ...
            'The surface search interval needs at least 12 depth samples inside the crop.');
    end
    lateral = 1:options.lateral_stride:header.Bframes_in_3Dscan;
    if planeType == "enface"
        bmodes = 1:options.raster_line_stride:header.No_3Dscans;
    else
        if options.bmode_index > header.No_3Dscans
            error('OCE:Acquisition:InvalidWavePlaneBmode', 'bmode_index exceeds the file.');
        end
        bmodes = options.bmode_index;
    end
    if numel(lateral) < 2
        error('OCE:Acquisition:InvalidWavePlaneSampling', 'At least two lateral positions are required.');
    end
    crop = struct('depth', range_contract(depthStart, depthEnd), ...
        'time', range_contract(1, header.Alines_in_Bframe));
    context = build_selected_context(filename, folder, header, system, ...
        bmodes, lateral, options);
    nr = numel(bmodes);
    nz = depthEnd - depthStart - window + 2;
    nx = numel(lateral);
    nt = header.Alines_in_Bframe - 1;
    if rawMode, nt = header.Alines_in_Bframe; end
    if planeType == "bmode", nr = nz; end
    if rawMode, nr = nz; planeColumns = nx*numel(bmodes);
    else, planeColumns = nx; end
    motion = zeros(nr, planeColumns, nt, 'single');
    structural = nan(nr, planeColumns);
    coherence = nan(nr, planeColumns);
    surface = nan(numel(bmodes), nx);
    inside = false(nr, planeColumns);
    depthBelow = nan(nr, planeColumns);
    previewAmplitude = nan(depthEnd - depthStart + 1, nx);
    depthAxis = [];
    for line = 1:numel(bmodes)
        for first = 1:options.block_positions:nx
            last = min(nx, first + options.block_positions - 1);
            % One selected-position halo preserves the existing 3-column
            % surface median filter at block seams.
            block = max(1, first - 1):min(nx, last + 1);
            measurement = oce.io.readRawAcquisition(filename, folder, ...
                struct('bmode_indices', bmodes(line), 'lateral_indices', lateral(block)));
            blockGeometry = geometry;
            blockGeometry.lateral_sample_count = numel(block);
            reconstruction = oce.acquisition.reconstructComplexVolume( ...
                measurement, system, optics, blockGeometry, crop, ...
                'SpectralContext', context);
            amplitude = reconstruction.amplitude.values;
            localStart = searchStart - depthStart + 1;
            localEnd = searchEnd - depthStart + 1;
            surfaceGeometry = struct('initial_depth_index', localStart, ...
                'PeakThresMult', options.surface_peak_threshold_db, ...
                'PeakThresWinSize', min(10, localEnd - localStart), ...
                'lateral_sample_count', numel(block), ...
                'surface_method', options.surface_method);
            if options.surface_method == "manual_index"
                surfaceLocalIndex = options.surface_index - depthStart + 1;
                if surfaceLocalIndex < 1 || surfaceLocalIndex > size(amplitude, 1)
                    error('OCE:Acquisition:InvalidManualSurface', ...
                        'surface_index must lie inside the retained raw depth crop.');
                end
                border = struct('Idx', repmat(surfaceLocalIndex, 1, numel(block)));
            else
                border = oce.borders.findSurface(amplitude(1:localEnd, :), surfaceGeometry);
            end
            rawDepthAxis = reconstruction.axes.depth.values;
            dz = reconstruction.geometry.depth_sample_interval_mm;
            % Restore raw FFT depth origin (reconstruction owns local crop
            % origin), then center each valid Loupas axial support.
            rawDepthAxis = rawDepthAxis + (depthStart - 1) * dz;
            depthAxis = rawDepthAxis(1:nz) + (window - 1) / 2 * dz;
            for column = first:last
                j = column - block(1) + 1;
                if line == 1, previewAmplitude(:, column) = amplitude(:, j); end
                iq = reshape(reconstruction.complex_volume.values(j, :, :), ...
                    size(amplitude, 1), header.Alines_in_Bframe);
                if rawMode, phase = angle(iq);
                else, phase = oce.motion.estimateLoupasPhaseIncrement(iq, window); end
                supportAmplitude = conv(amplitude(:, j), ones(window, 1) / window, 'valid');
                c = waveTemporalCoherence(iq, window);
                surfaceIndex = border.Idx(j);
                if isfinite(surfaceIndex) && surfaceIndex >= 1 && surfaceIndex <= numel(rawDepthAxis)
                    surfaceMm = interp1(1:numel(rawDepthAxis), rawDepthAxis, surfaceIndex);
                else
                    surfaceMm = NaN;
                end
                surface(line, column) = surfaceMm * 1e-3;
                if rawMode
                    nativeColumn = (line-1)*nx+column;
                    motion(:,nativeColumn,:) = reshape(single(phase),nz,1,nt);
                    structural(:,nativeColumn) = 20*log10(max(supportAmplitude,realmin));
                    coherence(:,nativeColumn) = c;
                    inside(:,nativeColumn) = isfinite(surfaceMm) & depthAxis >= surfaceMm;
                    depthBelow(:,nativeColumn) = (depthAxis-surfaceMm)*1e-3;
                elseif planeType == "bmode"
                    motion(:, column, :) = reshape(single(phase), nz, 1, nt);
                    structural(:, column) = 20 * log10(max(supportAmplitude, realmin));
                    coherence(:, column) = c;
                    inside(:, column) = isfinite(surfaceMm) & depthAxis >= surfaceMm;
                    depthBelow(:, column) = (depthAxis - surfaceMm) * 1e-3;
                else
                    targetMm = surfaceMm + options.depth_offset_mm;
                    lowMm = max(surfaceMm, targetMm - options.depth_band_mm / 2);
                    highMm = targetMm + options.depth_band_mm / 2;
                    support = find(depthAxis >= lowMm & depthAxis <= highMm);
                    % Never clip/extrapolate a requested layer into the crop.
                    contained = isfinite(targetMm) && lowMm >= rawDepthAxis(1) && ...
                        highMm <= rawDepthAxis(end) && ~isempty(support);
                    if contained
                        weights = supportAmplitude(support).^2 .* c(support);
                        total = sum(weights);
                        if total > 0
                            % Loupas increments are real measurements; its
                            % axial correction can exceed pi. Do not wrap the
                            % physical increment again during depth pooling.
                            trace = sum(weights .* phase(support, :), 1) / total;
                            motion(line, column, :) = reshape(single(trace), 1, 1, nt);
                            structural(line, column) = 20 * log10(mean(supportAmplitude(support)));
                            coherence(line, column) = sum(weights .* c(support)) / total;
                            inside(line, column) = true;
                            depthBelow(line, column) = options.depth_offset_mm * 1e-3;
                        end
                    end
                end
            end
            if options.show_progress
                fprintf('Wave plane: line %d/%d, columns %d/%d\n', ...
                    line, numel(bmodes), last, nx);
            end
        end
    end
    finiteStructural = structural(isfinite(structural) & inside);
    if isempty(finiteStructural), referenceDb = NaN;
    else, referenceDb = max(finiteStructural); end
    structural = structural - referenceDb;
    valid = inside & isfinite(structural) & ...
        structural >= options.intensity_floor_db & coherence >= options.coherence_threshold;
    if rawMode
        % An absolute phase is always in the principal branch. The increment
        % pi gate belongs to the old incremental path and cannot reject raw
        % optical phase before an explicitly selected unwrap method.
        valid = valid & all(isfinite(motion),3);
    elseif planeType == "bmode"
        valid = valid & all(isfinite(motion),3) & all(abs(motion) <= options.max_phase_step_rad,3);
    end
    % Keep measured rejected traces for diagnosis; valid_mask controls maps.
    if planeType == "enface" && geometry.scan_geometry == "raster"
        rowAxis = geometry.raster.slow_axis_mm(bmodes) * 1e-3;
    else
        rowAxis = depthAxis * 1e-3;
    end
    usedOptions = options;
    usedOptions.plane_type = planeType;
    usedOptions.depth_start_index = depthStart;
    usedOptions.depth_end_index = depthEnd;
    usedOptions.surface_search_start_index = searchStart;
    usedOptions.surface_search_end_index = searchEnd;
    usedOptions.line_rate_hz = system.a_scan_rate * 1000;
    usedOptions.OCTSystemOptions = systemOptions;
    metadata = plane_metadata(header, system, usedOptions, bmodes, lateral, planeType);
    metadata.source_file = string(fullfile(folder, filename));
    metadata.reconstruction_provenance = reconstruction.provenance;
    metadata.background_scope = "temporal_median_then_lateral_median_over_selected_positions";
    metadata.background_position_count = numel(bmodes) * nx;
    metadata.structural_reference_db = referenceDb;
    metadata.depth_crop_fft_indices = [depthStart depthEnd];
    metadata.surface_search_fft_indices = [searchStart searchEnd];
    previewDb = 20 * log10(max(previewAmplitude, realmin));
    previewDb = previewDb - max(previewDb, [], 'all');
    if rawMode
        [a,b] = ndgrid(lateral,bmodes);
        indices = a(:)+(b(:)-1)*geometry.samples_per_bmode;
        nativeSurface = reshape(surface',1,[]);
        data = struct('wrapped_phase',motion,'layout',"depth_native_position_time", ...
            'x_m',geometry.bmode_lateral_axis_mm(lateral)'*1e-3, ...
            'row_m',depthAxis(:)'*1e-3,'t_s',(0:nt-1)/(system.a_scan_rate*1000), ...
            'valid_mask',valid,'structural_db',structural,'coherence',coherence, ...
            'plane_type',planeType,'metadata',metadata, ...
            'native',struct('geometry',geometry,'global_lateral_indices',indices(:)', ...
                'lateral_indices',lateral,'bmode_indices',bmodes, ...
                'surface_z_m',nativeSurface,'posterior_z_m',repmat(rawDepthAxis(end)*1e-3,1,planeColumns), ...
                'depth_below_surface_m',depthBelow,'axial_weight',10.^(structural/10).*coherence), ...
            'preview',struct('intensity_db',previewDb,'depth_m',rawDepthAxis*1e-3, ...
                'x_m',geometry.bmode_lateral_axis_mm(lateral)'*1e-3, ...
                'surface_m',surface(1,:),'bmode_index',bmodes(1)));
        data.metadata.source_kind = "bounded_bin_raw_phase";
        data.metadata.motion_quantity = "wrapped_optical_phase";
        data.metadata.motion_estimator = "angle_complex_volume";
        data.metadata.phase_convention = "angle_IQ";
        data.metadata.time_origin = "local_response_original_sample";
        data.metadata.processing_order = "complex_reconstruction -> raw_wrapped_phase -> unwrap_pending";
        data.metadata.phase_registration_status = options.phase_registration_status;
        data.metadata.spatial_phase_repeatability_verified = options.phase_registration_status == "verified";
        data.metadata.phase_registration_performed = false;
        data.metadata.scan_geometry = geometry.scan_geometry;
        data.metadata.axial_aggregation = "none_before_unwrap";
        if planeType == "bmode"
            [coordinates,qc] = placeWaveBmode(struct('x_m',data.x_m),geometry,bmodes(1),lateral);
            data.x_m = coordinates.x_m;
            data.preview.x_m = data.x_m;
            data.metadata.bmode_qc = qc;
        end
        return;
    end
    data = struct('motion', motion, ...
        'x_m', geometry.bmode_lateral_axis_mm(lateral)' * 1e-3, ...
        'row_m', rowAxis(:)', 't_s', ((0:nt-1) + .5) / (system.a_scan_rate * 1000), ...
        'valid_mask', valid, 'structural_db', structural, ...
        'coherence', coherence, 'plane_type', planeType, 'metadata', metadata, ...
        'offsets', struct('surface_z_m', surface, ...
            'depth_below_surface_m', depthBelow, 'depth_offset_mm', options.depth_offset_mm), ...
        'preview', struct('intensity_db', previewDb, ...
            'depth_m', rawDepthAxis * 1e-3, ...
            'x_m', geometry.bmode_lateral_axis_mm(lateral)' * 1e-3, ...
            'surface_m', surface(1, :), 'bmode_index', bmodes(1)));
    data.metadata.source_kind = "bounded_bin_reconstruction";
    data.metadata.phase_registration_status = options.phase_registration_status;
    data.metadata.spatial_phase_repeatability_verified = options.phase_registration_status == "verified";
    data.metadata.phase_registration_performed = false;
    data.metadata.scan_geometry = geometry.scan_geometry;
    data.metadata.axial_aggregation = "intensity_coherence_weighted_real_phase_increment";
    if planeType == "bmode"
        [data,bmodeQc] = placeWaveBmode(data,geometry,options.bmode_index,lateral);
        data.metadata.bmode_qc = bmodeQc;
    elseif planeType == "enface"
        % The full geometry owns placement. Unread native positions remain
        % missing, so a coarse source selection never fills unsupported holes.
        count = geometry.lateral_sample_count;
        [a,b] = ndgrid(lateral,bmodes);
        indices = a(:)+(b(:)-1)*geometry.samples_per_bmode;
        native = struct('values',nan(count,nt),'valid_mask',false(count,1), ...
            'structural_db',nan(count,1),'coherence',nan(count,1), ...
            'surface_z_m',nan(count,1),'depth_below_surface_m',nan(count,1));
        native.values(indices,:) = reshape(permute(motion,[2,1,3]),[],nt);
        native.valid_mask(indices) = reshape(valid',[],1);
        native.structural_db(indices) = reshape(structural',[],1);
        native.coherence(indices) = reshape(coherence',[],1);
        native.surface_z_m(indices) = reshape(surface',[],1);
        native.depth_below_surface_m(indices) = reshape(depthBelow',[],1);
        remapOptions = struct('lateral_stride',options.lateral_stride, ...
            'raster_line_stride',options.raster_line_stride, ...
            'min_interpolation_resultant',options.min_interpolation_resultant, ...
            'max_triangle_edge_mm',options.max_triangle_edge_mm, ...
            'max_phase_step_rad',options.max_phase_step_rad);
        mapped = oce.acquisition.applyWaveEnfaceOperator(native,geometry,remapOptions);
        data.motion = mapped.motion; data.valid_mask = mapped.valid_mask;
        data.x_m = mapped.x_m; data.row_m = mapped.row_m;
        data.structural_db = mapped.structural_db; data.coherence = mapped.coherence;
        data.offsets.surface_z_m = mapped.surface_z_m;
        data.offsets.depth_below_surface_m = mapped.depth_below_surface_m;
        data.metadata.enface_qc = mapped.qc;
        if geometry.scan_geometry == "polar"
            data.metadata.notes(end+1) = "Polar: se reutiliza la interpolación de geometría adquirida; hueco central de anillos, exterior, triángulos largos y contribuyentes ausentes permanecen NaN. El grid no aumenta resolución física.";
            [previewAxis,~] = placeWaveBmode(struct('x_m',data.preview.x_m), ...
                geometry,bmodes(1),lateral);
            data.preview.x_m = previewAxis.x_m;
        end
    end
end

function context = build_selected_context(filename, folder, header, system, bmodes, lateral, options)
    count = numel(bmodes) * numel(lateral);
    medians = zeros(header.samples_in_Aline, count);
    context = [];
    cursor = 0;
    for bmode = bmodes
        for first = 1:options.block_positions:numel(lateral)
            block = first:min(numel(lateral), first + options.block_positions - 1);
            measurement = oce.io.readRawAcquisition(filename, folder, ...
                struct('bmode_indices', bmode, 'lateral_indices', lateral(block)));
            if isempty(context)
                context = oce.acquisition.prepareSpectralSamples(measurement.rawdata, system);
            end
            for j = 1:numel(block)
                medians(:, cursor + j) = median(double(measurement.rawdata(:, :, j)), 2);
            end
            cursor = cursor + numel(block);
        end
    end
    if system.spectral_preprocessing.background_method == "sample_derived_global_median"
        context.background_spectrum = median(medians, 2);
    end
end

function metadata = plane_metadata(header, system, options, bmodes, lateral, planeType)
    excitation = struct('available', false, 'source', "", 'frequency_hz', NaN);
    if isfield(header, 'excitation'), excitation = header.excitation; end
    notes = strings(0, 1);
    if ~excitation.available
        notes(end+1) = "El archivo no contiene el generador: indicar la frecuencia experimental; no se infiere del nombre ni del pulso de trigger.";
    end
    synchronized = false;
    synchronization = struct();
    if isfield(header, 'source_synchronization')
        synchronization = header.source_synchronization;
        synchronized = isfield(synchronization, 'oce_enabled') && ...
            isequal(synchronization.oce_enabled, true) && ...
            isfield(synchronization, 'oce_trigger_stride_sweeps') && ...
            isequal(synchronization.oce_trigger_stride_sweeps, 1);
    end
    if planeType == "enface"
        notes(end+1) = "Enface MB: las trazas pertenecen a excitaciones sucesivas; la coherencia espacial requiere retardo y respuesta repetibles. El header no prueba esa repetibilidad.";
    else
        notes(end+1) = "Un B-mode independiente: no se crea continuidad temporal ni espacial entre meridianos almacenados.";
    end
    if isfield(header, 'source_calibration')
        notes(end+1) = "La calibración de preview registrada en GUI se conserva como evidencia. La reconstrucción usa OCTSystemOptions explícito, sin adoptar automáticamente parámetros del preview.";
    end
    if options.surface_method == "max_in_search"
        notes(end+1) = "Superficie: máximo OCT dentro de búsqueda; revisar sobre la imagen estructural y excluir bandas DC. Un máximo no garantiza una interfaz anatómica.";
    elseif options.surface_method == "manual_index"
        notes(end+1) = "Superficie manual plana: corresponde al índice FFT indicado por el usuario; no sigue curvatura local.";
    else
        notes(end+1) = "Superficie: detector heredado del primer pico sobre umbral. Revisar bandas DC, ausencia de pico y continuidad local.";
    end
    metadata = struct('header', header, 'excitation', excitation, ...
        'frequency_hz', excitation.frequency_hz, ...
        'line_rate_hz', system.a_scan_rate * 1000, ...
        'line_rate_source', system.a_scan_rate_source, ...
        'motion_quantity', "temporal_phase_increment", 'motion_units', "rad", ...
        'motion_estimator', "loupas", 'time_origin', "local_response_increment_midpoint", ...
        'bmode_indices', bmodes, 'lateral_indices', lateral, ...
        'synchronization', synchronization, 'hardware_trigger_documented', synchronized, ...
        'spatial_phase_repeatability_verified', false, ...
        'surface_detection_verified', false, ...
        'notes', notes, 'load_options', options);
end

function value = range_contract(first, last)
    value = struct('start_index_inclusive', first, ...
        'end_index_inclusive', last, 'sample_count', last - first + 1);
end

function options = resolve_options(value)
    options = struct('plane_type', "auto", 'bmode_index', 1, ...
        'depth_offset_mm', 0, 'depth_band_mm', .04, ...
        'depth_start_index', 10, 'depth_end_index', [], ...
        'surface_search_start_index', 20, 'surface_search_end_index', [], ...
        'refractive_index', 1.4, 'line_rate_hz', [], 'intensity_floor_db', -35, ...
        'lateral_stride', 1, 'raster_line_stride', 1, 'block_positions', 8, ...
        'loupas_axial_window', 3, 'coherence_threshold', .15, ...
        'surface_peak_threshold_db', 6, 'surface_method', "inherited_threshold", ...
        'surface_index', [], 'show_progress', false, 'OCTSystemOptions', [], ...
        'phase_registration_status',"unverified",'min_interpolation_resultant',.5, ...
        'max_triangle_edge_mm',[],'max_phase_step_rad',pi,'phase_product',"phase_increment");
    if ~isstruct(value) || ~isscalar(value)
        error('OCE:Acquisition:InvalidWavePlaneOptions', 'options must be a scalar struct.');
    end
    names = fieldnames(value);
    for i = 1:numel(names)
        if ~isfield(options, names{i})
            error('OCE:Acquisition:InvalidWavePlaneOptions', 'Unknown option %s.', names{i});
        end
        options.(names{i}) = value.(names{i});
    end
    options.plane_type = lower(string(options.plane_type));
    options.phase_product = lower(string(options.phase_product));
    if ~isscalar(options.phase_product) || ~ismember(options.phase_product,["phase_increment","raw_wrapped"])
        error('OCE:Acquisition:InvalidWavePlaneOptions','phase_product must be phase_increment or raw_wrapped.');
    end
    if ~isscalar(options.plane_type) || ~ismember(options.plane_type, ["auto", "bmode", "enface"])
        error('OCE:Acquisition:InvalidWavePlaneOptions', 'plane_type must be auto, bmode or enface.');
    end
    options.surface_method = lower(string(options.surface_method));
    options.phase_registration_status = lower(string(options.phase_registration_status));
    if ~isscalar(options.phase_registration_status) || ...
            ~ismember(options.phase_registration_status,["unverified","assumed_repeatable","verified"])
        error('OCE:Acquisition:InvalidWavePlaneOptions','Invalid phase registration declaration.');
    end
    validateattributes(options.min_interpolation_resultant,{'numeric'},{'scalar','finite','>=',0,'<=',1});
    validateattributes(options.max_phase_step_rad,{'numeric'},{'scalar','finite','positive'});
    if ~isempty(options.max_triangle_edge_mm)
        validateattributes(options.max_triangle_edge_mm,{'numeric'},{'scalar','finite','positive'});
    end
    if ~isscalar(options.surface_method) || ~ismember(options.surface_method, ...
            ["inherited_threshold", "max_in_search", "manual_index"])
        error('OCE:Acquisition:InvalidWavePlaneOptions', 'Unknown surface_method.');
    end
    if options.surface_method == "manual_index"
        validateattributes(options.surface_index, {'numeric'}, {'scalar', 'integer', 'positive', 'finite'});
    end
    for name = ["bmode_index", "depth_start_index", "surface_search_start_index", ...
            "lateral_stride", "raster_line_stride", "block_positions", "loupas_axial_window"]
        validateattributes(options.(name), {'numeric'}, {'scalar', 'integer', 'positive', 'finite'}, mfilename, name);
    end
    for name = ["depth_end_index", "surface_search_end_index"]
        if ~isempty(options.(name))
            validateattributes(options.(name), {'numeric'}, {'scalar', 'integer', 'positive', 'finite'}, mfilename, name);
        end
    end
    for name = ["refractive_index", "depth_band_mm"]
        validateattributes(options.(name), {'numeric'}, {'scalar', 'positive', 'finite'}, mfilename, name);
    end
    validateattributes(options.depth_offset_mm, {'numeric'}, {'scalar', 'nonnegative', 'finite'});
    validateattributes(options.intensity_floor_db, {'numeric'}, {'scalar', 'finite', '<=', 0});
    validateattributes(options.coherence_threshold, {'numeric'}, {'scalar', 'finite', '>=', 0, '<=', 1});
    validateattributes(options.surface_peak_threshold_db, {'numeric'}, {'scalar', 'finite'});
    if options.loupas_axial_window < 2
        error('OCE:Acquisition:InvalidWavePlaneOptions', 'Loupas axial window must be at least 2.');
    end
    if ~isempty(options.line_rate_hz)
        validateattributes(options.line_rate_hz, {'numeric'}, {'scalar', 'positive', 'finite'});
    end
    if ~islogical(options.show_progress) || ~isscalar(options.show_progress)
        error('OCE:Acquisition:InvalidWavePlaneOptions', 'show_progress must be scalar logical.');
    end
end
