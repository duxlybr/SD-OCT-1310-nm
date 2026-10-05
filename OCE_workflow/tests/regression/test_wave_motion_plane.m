function test_wave_motion_plane(~)
%TEST_WAVE_MOTION_PLANE Verify bounded I/O, shared FFT and layer coordinates.
    fixture = create_io_acquisition_fixture();
    for pattern = ["linear", "raster", "crosshair"]
        entry = fixture.octocePatterns.(pattern);
        folder = fixture.rawDir;
        filename = string(entry.filename);
        complete = oce.io.readRawAcquisition(filename, folder);
        h = complete.raw_descriptor;
        bmodes = 1:h.No_3Dscans;
        lateral = unique([1 h.Bframes_in_3Dscan]);
        partial = oce.io.readRawAcquisition(filename, folder, ...
            struct('bmode_indices', bmodes, 'lateral_indices', lateral));
        indices = partial.raw_selection.global_lateral_indices;
        assert(isequal(partial.rawdata, complete.rawdata(:, :, indices)), ...
            'Selected reads must agree exactly, including reversed MB lines.');
        assert(isequaln(partial.raw_descriptor, complete.raw_descriptor));
    end
    assert_shared_reconstruction_context();
    root = tempname;
    mkdir(root);
    cleanup = onCleanup(@() rmdir(root, 's')); %#ok<NASGU>
    filename = fullfile(root, 'contains_no_generator_2000Hz.bin');
    write_wave_fixture(filename);
    options = struct('plane_type', "enface", 'depth_start_index', 10, ...
        'depth_end_index', 180, 'surface_search_start_index', 20, ...
        'surface_search_end_index', 100, 'coherence_threshold', 0, ...
        'intensity_floor_db', -60, 'block_positions', 2);
    surface = oce.acquisition.loadWaveMotionPlane(filename, options);
    assert(isequal(size(surface.motion), [3 6 40]));
    assert(isreal(surface.motion) && isa(surface.motion, 'single'));
    assert(iscolumn(surface.x_m) && isrow(surface.row_m));
    assert(abs(surface.t_s(1) - .5 / 50000) < eps);
    assert(isnan(surface.metadata.frequency_hz), ...
        'No excitation frequency may be invented from the filename.');
    assert(~surface.metadata.spatial_phase_repeatability_verified);
    assert(any(surface.valid_mask, 'all'));
    assert(all(surface.offsets.depth_below_surface_m(surface.valid_mask) == 0));
    options.depth_offset_mm = .12;
    deep = oce.acquisition.loadWaveMotionPlane(filename, options);
    assert(isequaln(surface.offsets.surface_z_m, deep.offsets.surface_z_m));
    assert(all(deep.offsets.depth_below_surface_m(deep.valid_mask) == .12e-3));
    assert(deep.metadata.load_options.depth_offset_mm == .12);
    options.plane_type = "bmode";
    options.bmode_index = 2;
    bmode = oce.acquisition.loadWaveMotionPlane(filename, options);
    assert(size(bmode.motion, 1) == 169 && size(bmode.motion, 2) == 6);
    assert(isequal(bmode.metadata.bmode_indices, 2));
    assert(abs(bmode.row_m(1) - 10 * (5.92e-6 / 1.4)) < 1e-12, ...
        'Depth coordinates include raw crop origin and axial-support midpoint.');
    assert(all(bmode.offsets.depth_below_surface_m(bmode.valid_mask) >= 0));
    options.surface_method = "manual_index";
    options.surface_index = 71;
    manual = oce.acquisition.loadWaveMotionPlane(filename, options);
    assert(all(abs(manual.offsets.surface_z_m - 70*(5.92e-6/1.4)) < 1e-12, 'all'));
    assert(isequal(size(manual.preview.intensity_db), [171 6]));
    assert_product_conversion(filename);
    assert_polar_support();
    for pattern = ["rings","spiral"]
        polarFilename = fullfile(root,char(pattern+".bin"));
        write_wave_fixture(polarFilename,pattern);
        polarOptions = options;
        polarOptions.plane_type = "auto";
        polarOptions.depth_offset_mm = 0;
        polarOptions.depth_band_mm = .06;
        polar = oce.acquisition.loadWaveMotionPlane(polarFilename,polarOptions);
        assert(polar.plane_type == "enface");
        assert(isfield(polar.metadata,'enface_qc'));
        assert(~polar.metadata.phase_registration_performed);
        assert(all(isnan(polar.motion(~repmat(polar.valid_mask,1,1,size(polar.motion,3))))));
        polarOptions.plane_type = "bmode";
        polarOptions.bmode_index = 2;
        cut = oce.acquisition.loadWaveMotionPlane(polarFilename,polarOptions);
        assert(size(cut.motion,2) == 6 && all(diff(cut.x_m) > 0));
        assert(max(abs(diff(cut.x_m)-mean(diff(cut.x_m)))) < 1e-10);
        assert(~cut.metadata.bmode_qc.closed_seam);
        if pattern == "spiral", assert(cut.metadata.bmode_qc.resampled); end
    end
end

function assert_product_conversion(filename)
    [folder,name,extension] = fileparts(filename);
    measurement = oce.io.readRawAcquisition([name extension],folder);
    geometry = oce.acquisition.buildAcquisitionGeometry(measurement.raw_descriptor,"automatic");
    system = oce.config.resolveOCTSystemOptions(oce.config.getOCTSystemOptions("spectral_domain_1310"),"",measurement.raw_descriptor);
    optics = struct('refractive_index',struct('value',1.4,'source',"test"));
    crop = struct('depth',range_contract(10,180),'time',range_contract(5,31));
    reconstruction = oce.acquisition.reconstructComplexVolume(measurement,system,optics,geometry,crop);
    state = struct('geometry',geometry,'reconstruction',reconstruction, ...
        'raw',struct('descriptor',measurement.raw_descriptor));
    resolved = struct('difference_axis',"time",'show_progress',false,'depth_resolved', ...
        struct('quantity',"phase_increment",'units',"rad",'layout',"lateral_depth_time", ...
        'estimator',"loupas",'loupas',struct('axial_window_samples',3), ...
        'smoothing',struct('method',"none")));
    phase = struct('depth_resolved',oce.motion.computeDepthResolvedPhase(reconstruction.complex_volume.values,resolved));
    borders = struct('surface_mode',"anterior_posterior", ...
        'indices',struct('anterior',62*ones(1,18),'posterior',142*ones(1,18)), ...
        'intensityMask',true(171,18));
    options = struct('plane_type',"bmode",'bmode_index',2,'coherence_threshold',0, ...
        'intensity_floor_db',-80,'max_phase_step_rad',8*pi);
    cut = oce.acquisition.buildWaveMotionPlane(state,phase,borders,options);
    assert(isequal(size(cut.motion),[169,6,26]));
    assert(abs(cut.t_s(1)-4.5/50000) < eps);
    assert(abs(cut.row_m(1)-10*(5.92e-6/1.4)) < 1e-12);
    assert(cut.metadata.source_kind == "stepwise_products");
    expected = permute(real(phase.depth_resolved.values(7:12,:,:)),[2,1,3]);
    selected = repmat(cut.valid_mask,1,1,26);
    assert(any(selected,'all'));
    assert(max(abs(double(cut.motion(selected))-expected(selected))) < 1e-6);
    assert(all(isnan(cut.motion(~selected))));
    missing = borders; missing.indices.posterior(8) = NaN;
    rejected = oce.acquisition.buildWaveMotionPlane(state,phase,missing,options);
    assert(~any(rejected.valid_mask(:,2)),'Missing posterior must remain invalid in two-boundary mode.');
    missing = borders; missing.intensityMask(:,9) = false;
    rejected = oce.acquisition.buildWaveMotionPlane(state,phase,missing,options);
    assert(~any(rejected.valid_mask(:,3)),'STEPWISE OCT mask is fundamental support.');
    options.plane_type = "enface"; options.depth_offset_mm = .12; options.depth_band_mm = .04;
    layer = oce.acquisition.buildWaveMotionPlane(state,phase,borders,options);
    assert(isequal(size(layer.motion),[3,6,26]) && any(layer.valid_mask,'all'));
    assert(all(layer.offsets.depth_below_surface_m(layer.valid_mask) == .12e-3));
    options.depth_offset_mm = .7;
    outside = oce.acquisition.buildWaveMotionPlane(state,phase,borders,options);
    assert(~any(outside.valid_mask,'all') && all(isnan(outside.motion),'all'));
    invalidPhase = phase; invalidPhase.depth_resolved.quantity = "wrapped_phase";
    caught = false;
    try
        oce.acquisition.buildWaveMotionPlane(state,invalidPhase,borders,options);
    catch exception
        caught = strcmp(exception.identifier,'OCE:Acquisition:WrappedWaveMotion');
    end
    assert(caught,'Wrapped phases require an existing incremental estimator, not implicit unwrap.');
    for pattern = ["rings","spiral"]
        polarDescriptor = measurement.raw_descriptor;
        polarDescriptor.type = pattern;
        polarDescriptor.Hor_scan_length_mm = 2;
        polarDescriptor.Ver_scan_length_mm = 2;
        state.geometry = oce.acquisition.buildAcquisitionGeometry(polarDescriptor,"automatic");
        options.depth_offset_mm = .12;
        polarLayer = oce.acquisition.buildWaveMotionPlane(state,phase,borders,options);
        assert(polarLayer.plane_type == "enface" && isfield(polarLayer.metadata,'enface_qc'));
        options.plane_type = "bmode";
        polarCut = oce.acquisition.buildWaveMotionPlane(state,phase,borders,options);
        assert(size(polarCut.motion,2) == 6);
        assert(max(abs(diff(polarCut.x_m)-mean(diff(polarCut.x_m)))) < 1e-10);
        if pattern == "spiral", assert(polarCut.metadata.bmode_qc.resampled); end
        options.plane_type = "enface";
    end
end

function assert_polar_support()
    descriptor = struct('samples_in_Aline',2048,'Alines_in_Bframe',41, ...
        'Bframes_in_3Dscan',24,'No_3Dscans',5,'Hor_scan_length_mm',2, ...
        'Ver_scan_length_mm',2,'bscan_angle_deg',zeros(1,5),'type',"rings");
    geometry = oce.acquisition.buildAcquisitionGeometry(descriptor,"automatic");
    count = geometry.lateral_sample_count;
    values = .02*sin((0:40)*.2)+.01*geometry.polar.positions_mm(:,1);
    native = struct('values',values,'valid_mask',true(count,1),'structural_db',zeros(count,1), ...
        'coherence',ones(count,1),'surface_z_m',ones(count,1)*.2e-3, ...
        'depth_below_surface_m',zeros(count,1));
    mapped = oce.acquisition.applyWaveEnfaceOperator(native,geometry);
    [~,ix] = min(abs(mapped.x_m)); [~,iy] = min(abs(mapped.row_m));
    assert(~mapped.valid_mask(iy,ix) && all(isnan(mapped.motion(iy,ix,:)),'all'), ...
        'The unacquired inner-ring hole must not be filled by a convex hull.');
    assert(any(mapped.valid_mask,'all') && ~mapped.valid_mask(1,1));
    native.valid_mask(25:48) = false;
    missing = oce.acquisition.applyWaveEnfaceOperator(native,geometry);
    assert(nnz(missing.valid_mask) < nnz(mapped.valid_mask),'Missing contributors must reduce support.');
    strict = oce.acquisition.applyWaveEnfaceOperator(native,geometry,struct('max_triangle_edge_mm',.01));
    assert(nnz(strict.valid_mask) < nnz(missing.valid_mask));
    native.valid_mask(:) = true;
    native.values(:) = 5;
    bounded = oce.acquisition.applyWaveEnfaceOperator(native,geometry);
    assert(~any(bounded.valid_mask,'all'));
    realIncrement = oce.acquisition.applyWaveEnfaceOperator(native,geometry,struct('max_phase_step_rad',8*pi));
    selected = repmat(realIncrement.valid_mask,1,1,size(realIncrement.motion,3));
    assert(any(selected,'all') && max(abs(realIncrement.motion(selected)-5)) < 1e-6, ...
        'The remapper must preserve real Loupas increments without wrapping them.');
end

function value = range_contract(first,last)
    value = struct('start_index_inclusive',first,'end_index_inclusive',last,'sample_count',last-first+1);
end

function assert_shared_reconstruction_context()
    count = 2048;
    raw = uint16(2000 + 150 * cos((0:count-1)' * .31 + ...
        reshape(0:.15:1.2, 1, [], 1) + reshape([0 .8 2.1], 1, 1, [])));
    measurement = struct('rawdata', raw);
    system = oce.config.resolveOCTSystemOptions( ...
        oce.config.getOCTSystemOptions("spectral_domain_1310"));
    optics = struct('refractive_index', struct('value', 1.4, 'source', "test"));
    geometry = struct('spectral_sample_count', count, ...
        'temporal_repetition_count', size(raw, 2), ...
        'available_depth_sample_count', count / 2, 'lateral_sample_count', 3);
    crop = struct('depth', struct('start_index_inclusive', 10, ...
        'end_index_inclusive', 160, 'sample_count', 151), ...
        'time', struct('start_index_inclusive', 1, ...
        'end_index_inclusive', size(raw, 2), 'sample_count', size(raw, 2)));
    full = oce.acquisition.reconstructComplexVolume(measurement, system, optics, geometry, crop);
    context = oce.acquisition.prepareSpectralSamples(raw, system);
    for lateral = 1:3
        geometry.lateral_sample_count = 1;
        part = oce.acquisition.reconstructComplexVolume( ...
            struct('rawdata', raw(:, :, lateral)), system, optics, geometry, crop, ...
            'SpectralContext', context);
        assert(isequal(part.complex_volume.values, full.complex_volume.values(lateral, :, :)), ...
            'Block reconstruction must use exactly the same median background and FFT.');
    end
end

function write_wave_fixture(filename,pattern)
    if nargin < 2, pattern = "raster"; end
    sampleCount = 2048;
    temporalCount = 41;
    lateralCount = 6;
    bmodeCount = 3;
    offset = 65536;
    source = struct('format_version', '1.0', 'dtype', '<u2', ...
        'format', 'OCT/OCE raw acquisition', 'created_utc', '2026-10-04T00:00:00Z', ...
        'axis_order', {{'bscan', 'aline', 'm_repetition', 'pixel'}}, ...
        'planned_shape', [bmodeCount lateralCount temporalCount sampleCount], ...
        'raw_storage', struct('data_offset_bytes', offset, ...
            'layout', 'C-order, contiguous, no sync samples'), ...
        'scan', struct('mode', 'MB', 'pattern', char(pattern), 'orientation', 'horizontal', ...
            'alines', lateralCount, 'bscans', bmodeCount, 'm_repetitions', temporalCount, ...
            'x_length_mm', 2, 'y_length_mm', 1, 'raster_bidirectional', false), ...
        'hardware', struct('spectral_samples', sampleCount, 'effective_line_rate_hz', 50000));
    jsonBytes = unicode2native(jsonencode(source), 'UTF-8');
    fid = fopen(filename, 'w', 'ieee-le');
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fwrite(fid, zeros(offset, 1, 'uint8'), 'uint8');
    fseek(fid, 0, 'bof'); fwrite(fid, uint8(['OCTOCE1' char(0)]), 'uint8');
    fseek(fid, 20, 'bof'); fwrite(fid, numel(jsonBytes), 'uint32');
    fseek(fid, 28, 'bof'); fwrite(fid, offset, 'uint32');
    fseek(fid, 64, 'bof'); fwrite(fid, jsonBytes, 'uint8');
    lambda = linspace(1261.36, 1472.76, sampleCount)';
    sigma = 1e7 ./ lambda;
    q = (sigma - sigma(1)) / (sigma(end) - sigma(1)) * (sampleCount - 1);
    t = (0:temporalCount-1) / 50000;
    fseek(fid, offset, 'bof');
    for bmode = 1:bmodeCount
        for lateral = 1:lateralCount
            phase = .03 * sin(2*pi*1250*t - .4*lateral) + 2*pi*(lateral-1)/lateralCount;
            raw = 2000 + 200*cos(2*pi*70*q/sampleCount + phase) + ...
                40*cos(2*pi*110*q/sampleCount + .3 + phase);
            fwrite(fid, uint16(round(raw)), 'uint16');
        end
    end
end
