%% Eight individual excitations; raw unwrap then PD2D and robust fusion.
here=fileparts(mfilename('fullpath'));wf=fileparts(fileparts(here));cd(wf);startup;
load(fullfile(here,'fish_raw_phase.mat'),'data8','truth_young_pa','x_m','frequency_hz');
methods=["sequential","least_squares_dct","tie_dct"];results=cell(1,3);young=cell(1,3);records=struct([]);
[X,Y]=meshgrid(x_m,x_m);score=abs(X)<=5e-3 & abs(Y)<=5e-3;
head=(X+1e-3).^2+Y.^2<(2.2e-3-.9e-3)^2;
tail=(X-2.3e-3).^2+Y.^2<(1.2e-3-.9e-3)^2;
for j=1:3
 opts=struct('method',"phase_derivative_2d",'frequency_hz',frequency_hz, ...
  'window_x_mm',1.2,'window_row_mm',1.2,'pd_geometry',"in_plane", ...
  'min_coherence',.65,'min_amplitude_fraction',.05,'min_support_fraction',.75, ...
  'fit_error_max',.30,'speed_range_m_s',[.2 8],'smoothing_mm',0, ...
  'directional_filter_enabled',false,'unwrap_method',methods(j),'unwrap_iterations',8, ...
  'raw_unwrap_dimensions',3,'pd_polynomial_order',2);
 results{j}=oce.dispersion.estimateMultiExcitationSpeedMap(data8, ...
  struct('local_options',opts,'min_consensus_count',4,'min_consensus_fraction',.5, ...
   'max_relative_slowness_deviation',.2));
 young{j}=oce.elastography.invertYoungModulus(results{j},struct('model',"bulk_shear", ...
  'frequency_hz',frequency_hz,'density_kg_m3',1000,'poisson_ratio',.495));
 valid=score & results{j}.valid_mask;
 r=struct('unwrap_method',methods(j),'score_pixels',nnz(score),'accepted_pixels',nnz(valid), ...
  'coverage_pct',100*nnz(valid)/nnz(score), ...
  'speed_error_pct',100*median(abs(results{j}.speed_m_s(valid)./sqrt(truth_young_pa(valid)/(2*1000*(1+.495)))-1),'omitnan'), ...
  'young_error_pct',100*median(abs(young{j}.young_pa(valid)./truth_young_pa(valid)-1),'omitnan'), ...
  'head_core_pixels',nnz(head & valid),'head_median_kpa',median(young{j}.young_pa(head & valid),'omitnan')/1000, ...
  'tail_core_pixels',nnz(tail & valid),'tail_median_kpa',median(young{j}.young_pa(tail & valid),'omitnan')/1000);
 if isempty(records),records=r;else,records(end+1)=r;end %#ok<SAGROW>
 fprintf('FISH_RAW_PD2D_DONE %s\n',methods(j));
end
writetable(struct2table(records),fullfile(here,'fish_raw_pd2d_metrics.csv'));
save(fullfile(here,'fish_raw_pd2d_maps.mat'),'results','young','records','-v7.3');
fig=figure('Visible','off','Color','white','Position',[20 20 1500 900]);lay=tiledlayout(fig,2,3,'Padding','compact');
for kind=1:2
 for j=1:3
  if kind==1,values=results{j}.speed_m_s;limits=[1.6 3.2];units='m/s';
  else,values=young{j}.young_pa/1000;limits=[8 30];units='kPa';end
  ax=nexttile(lay);im=imagesc(ax,x_m*1000,x_m*1000,values);im.AlphaData=isfinite(values);
  axis(ax,'image');ax.YDir='normal';ax.Color=[.85 .85 .85];colormap(ax,turbo);clim(ax,limits);
  cb=colorbar(ax);cb.Label.String=units;xlabel(ax,'X (mm)');ylabel(ax,'Y (mm)');
  hold(ax,'on');contour(ax,x_m*1000,x_m*1000,double(truth_young_pa>12000),[.5 .5],'w--');hold(ax,'off');
  title(ax,methods(j),'Interpreter','none');
 end
end
title(lay,'Pez enface | fase óptica cruda → unwrap → phase derivative 2D → fusión robusta');
subtitle(lay,'8 excitaciones individuales, sin sumar campos. Fondo 12 / inclusión 24 kPa. Blanco = referencia material. TIE-DCT: 8 correcciones fijas.');
exportgraphics(fig,fullfile(wf,'results','Speed_Young_Maps','comparison_unwrap_pd2d_fish_8individual_speed_young.png'),'Resolution',160);close(fig);
disp('FISH_RAW_COMPARISON_FINISHED');
