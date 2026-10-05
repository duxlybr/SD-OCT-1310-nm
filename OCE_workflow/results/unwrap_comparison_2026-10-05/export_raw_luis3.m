%% Explicit native raw optical phase export: one independent Luis3 B-scan
outputRoot = fileparts(mfilename('fullpath'));
workflowRoot = fileparts(fileparts(outputRoot));
cd(workflowRoot); startup;
sourcePlane = 'C:/Users/proyecto.pi1081/Desktop/OCE_fish/OCE_estimator_validation/experimental/luis3_bmode1_offset_0p00mm_plane.mat';
previous = load(sourcePlane,'data');
loadOptions = previous.data.metadata.load_options;
sourceBin = previous.data.metadata.source_file;
clear previous;
loadOptions.phase_product = "raw_wrapped";
loadOptions.plane_type = "bmode";
loadOptions.bmode_index = 1;
loadOptions.depth_start_index = 1;
loadOptions.depth_end_index = 700;
loadOptions.lateral_stride = 2;
loadOptions.surface_method = "max_in_search";
loadOptions.show_progress = false;
raw = oce.acquisition.loadWaveMotionPlane(sourceBin,loadOptions);
raw.metadata.notes(end+1) = "Exportación comparativa exploratoria: máximo OCT candidato no validado anatómicamente; no altera el detector predeterminado. Fase óptica cruda sin Loupas, diferencia, pooling ni filtros antes de unwrap.";
save(fullfile(outputRoot,'luis3_bmode1_raw_phase.mat'),'raw','loadOptions','sourceBin','-v7.3');
record = struct('phase_product',loadOptions.phase_product,'source_file',sourceBin, ...
    'depth_count',size(raw.wrapped_phase,1),'native_position_count',size(raw.wrapped_phase,2), ...
    'time_count',size(raw.wrapped_phase,3),'raw_time_start_s',raw.t_s(1), ...
    'raw_time_end_s',raw.t_s(end),'line_rate_hz',raw.metadata.line_rate_hz, ...
    'valid_native_voxel_count',nnz(raw.valid_mask),'surface_method',loadOptions.surface_method, ...
    'surface_candidate_count',nnz(isfinite(raw.native.surface_z_m)), ...
    'max_abs_wrapped_phase_rad',max(abs(raw.wrapped_phase),[],'all'), ...
    'interpretation',"Raw angle(IQ), native sampling, exploratory surface; no mechanical or anatomical ground truth");
writetable(struct2table(record),fullfile(outputRoot,'luis3_raw_input_audit.csv'));
disp(record); disp('RAW_LUIS3_EXPORT_PASS');
