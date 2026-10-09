cd('C:/Users/proyecto.pi1081/Desktop/SD-OCT-1310-nm/OCE_workflow');
startup;
s = load('results/unwrap_comparison_2026-10-05/luis3_bmode1_raw_phase.mat','raw');
raw = s.raw;
rows=find(any(raw.valid_mask,2));
if isempty(rows),rows=1:size(raw.wrapped_phase,1);end
rows=rows(1:min(7,numel(rows))); columns=1:min(31,size(raw.wrapped_phase,2));
time=1:min(80,size(raw.wrapped_phase,3));
raw.wrapped_phase=raw.wrapped_phase(rows,columns,time);
raw.valid_mask=raw.valid_mask(rows,columns);
raw.structural_db=raw.structural_db(rows,columns);
raw.coherence=raw.coherence(rows,columns);
raw.row_m=raw.row_m(rows);raw.x_m=raw.x_m(columns);raw.t_s=raw.t_s(time);
for n={'global_lateral_indices','lateral_indices','surface_z_m','posterior_z_m'}
 raw.native.(n{1})=raw.native.(n{1})(columns);
end
raw.native.depth_below_surface_m=raw.native.depth_below_surface_m(rows,columns);
raw.native.axial_weight=raw.native.axial_weight(rows,columns);
opt=struct('method','phase_derivative_2d','frequency_hz',1000,'window_x_mm',.9,'window_row_mm',0, ...
 'unwrap_method','tie_dct','unwrap_iterations',3,'raw_unwrap_domain','temporal','pd_geometry','lateral');
w=oce.interaction.tuneWaveSpeedMaps(raw,opt);
cleanup=onCleanup(@()delete(w));
assert(~isempty(w.UserData.speed_result));
assert(w.UserData.data.metadata.raw_unwrap.iterations_executed==3);
assert(isequal(w.UserData.data.metadata.raw_unwrap.dimensions,3));
assert(w.UserData.controls.raw_unwrap_domain=="temporal");
assert(isfield(w.UserData,'raw_data'));
menus=findall(w,'Type','uidropdown');
for q=1:numel(menus)
 if strcmp(menus(q).Value,'temporal'), menus(q).Value='temporal_depth';end
end
buttons=findall(w,'Type','uibutton');
for q=1:numel(buttons)
 if strcmp(buttons(q).Text,'Recalcular mapas'),buttons(q).ButtonPushedFcn(buttons(q),[]);end
end
assert(isequal(w.UserData.data.metadata.raw_unwrap.dimensions,[3 1]));
assert(w.UserData.data.metadata.raw_unwrap.iterations_executed==3);
assert(w.UserData.speed_result.options.method=="phase_derivative_2d");
disp('RAW_INTERACTIVE_TIE_FIXED_AND_DOMAIN_SWITCH_PASS');
