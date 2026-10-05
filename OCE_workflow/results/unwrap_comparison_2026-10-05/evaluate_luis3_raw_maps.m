%% Actual Luis3 raw optical phase: identical acquisition and post-unwrap settings.
here=fileparts(mfilename('fullpath'));wf=fileparts(fileparts(here));cd(wf);startup;
load(fullfile(here,'luis3_bmode1_raw_phase.mat'),'raw');
methods=["sequential","least_squares_dct","tie_dct"];results=cell(1,3);young=cell(1,3);planes=cell(1,3);records=struct([]);
for j=1:3
 ur=oce.motion.unwrapPhase(raw.wrapped_phase,struct('method',methods(j), ...
  'dimensions',[3 1],'iterations',8,'valid_mask',repmat(raw.valid_mask,1,1,numel(raw.t_s)) & isfinite(raw.wrapped_phase)));
 data=oce.acquisition.finalizeUnwrappedWavePlane(raw,ur);planes{j}=data;
 opts=struct('method',"phase_derivative_2d",'frequency_hz',1000,'window_x_mm',.9, ...
  'window_row_mm',.04,'pd_geometry',"lateral",'time_start_s',.002,'time_end_s',.004, ...
  'min_coherence',.2,'min_amplitude_fraction',.05,'min_support_fraction',.8, ...
  'fit_error_max',.3,'speed_range_m_s',[.2 20],'smoothing_mm',0, ...
  'directional_filter_enabled',false,'unwrap_method',methods(j),'unwrap_iterations',8,'pd_polynomial_order',2);
 results{j}=oce.dispersion.estimateLocalSpeedMap(data,opts);
 young{j}=oce.elastography.invertYoungModulus(results{j},struct('model',"rayleigh", ...
  'frequency_hz',1000,'density_kg_m3',1000,'poisson_ratio',.495));
 valid=results{j}.valid_mask;
 r=struct('unwrap_method',methods(j),'raw_iterations_executed',ur.iterations_executed, ...
  'input_pixels',nnz(data.valid_mask),'accepted_pixels',nnz(valid),'coverage_acquired_pct',100*nnz(valid)/numel(valid), ...
  'speed_median_m_s',median(results{j}.speed_m_s(valid),'omitnan'), ...
  'apparent_young_median_kpa',median(young{j}.young_pa(valid),'omitnan')/1000, ...
  'raw_wrap_consistency_rms_rad',ur.diagnostics.wrap_consistency_rms_rad);
 if isempty(records),records=r;else,records(end+1)=r;end %#ok<SAGROW>
 fprintf('LUIS3_RAW_PD2D_DONE %s %d\n',methods(j),nnz(valid));
end
writetable(struct2table(records),fullfile(here,'luis3_raw_pd2d_metrics.csv'));
save(fullfile(here,'luis3_raw_pd2d_maps.mat'),'planes','results','young','records','-v7.3');
fig=figure('Visible','off','Color','white','Position',[20 20 1500 1000]);lay=tiledlayout(fig,4,3,'Padding','compact');
for row=1:4
 for j=1:3
  if row<=2,values=results{j}.speed_m_s;limits=[.2 10];units='m/s';
  else,values=young{j}.young_pa/1000;limits=[0 120];units='kPa aparentes';end
  ax=nexttile(lay);im=imagesc(ax,planes{j}.x_m*1000,planes{j}.row_m*1000,values);
  im.AlphaData=isfinite(values);ax.YDir='reverse';ax.Color=[.85 .85 .85];colormap(ax,turbo);clim(ax,limits);
  if mod(row,2)==0,ylim(ax,[.18 .46]);end
  cb=colorbar(ax);cb.Label.String=units;xlabel(ax,'X (mm)');ylabel(ax,'Z (mm)');title(ax,methods(j),'Interpreter','none');
 end
end
title(lay,'Luis3 B-scan1 | fase óptica cruda | phase derivative 2D | registro completo y zoom');
subtitle(lay,'2–4 ms, 1000 Hz. Máximo OCT candidato: anatomía sin verificar. Young aparente Rayleigh, sin ground truth. TIE-DCT: 8 correcciones fijas.');
exportgraphics(fig,fullfile(wf,'results','Speed_Young_Maps','experimental_unwrap_pd2d_luis3_bmode1_speed_young.png'),'Resolution',160);close(fig);
disp('LUIS3_RAW_COMPARISON_FINISHED');
