%% Raw wrapped optical phase comparisons; all processing follows unwrap.
here=fileparts(mfilename('fullpath'));wf=fileparts(fileparts(here));cd(wf);startup;
load(fullfile(here,'raw_phase_cases.mat'),'cases');
if exist('selected_labels','var'),cases=cases(cellfun(@(c)any(string(c.label)==selected_labels),cases));end
filterEnabled=exist('use_directional','var') && use_directional;
suffix="";if filterEnabled,suffix="_filtered";end
gallery=fullfile(wf,'results','Speed_Young_Maps');
methods=["sequential","least_squares_dct","tie_dct"];
records=struct([]);commonRecords=struct([]);maps=cell(size(cases));
for j=1:numel(cases)
 c=cases{j};freq=double(c.frequency_hz);lambda=double(c.wavelength_m);
 opts=struct('method',"phase_derivative_2d",'frequency_hz',freq, ...
  'window_x_mm',.5*lambda*1000,'window_row_mm',0,'pd_geometry',string(c.pd_geometry), ...
  'min_coherence',.65,'min_amplitude_fraction',.05,'min_support_fraction',.8, ...
  'fit_error_max',.30,'speed_range_m_s',[.2 8],'smoothing_mm',0, ...
  'directional_filter_enabled',filterEnabled,'direction_deg',0,'directional_halfwidth_deg',45, ...
  'unwrap_iterations',8,'pd_polynomial_order',2);
 if opts.pd_geometry=="in_plane",opts.window_row_mm=.5*lambda*1000;end
 [X,Z]=meshgrid(c.x_m,c.row_m);score=X>=0 & X<=2.25*lambda;
 if string(c.model)=="rayleigh",score=score & Z<=.6*lambda;end
 datasets={c.exact_raw,c.fdtd_raw};results=cell(2,3);young=cell(2,3);unwrapDiagnostics=cell(2,3);
 for source=1:2
  raw=datasets{source};mask=logical(raw.valid_mask);nt=numel(raw.t_s);
  hx=max(1,floor(opts.window_x_mm*1e-3/(2*mean(diff(raw.x_m)))+1e-10));
  far=double(c.source_distance_m)>=2*lambda;
  centers=conv2(double(far),ones(1,2*hx+1),'same')==2*hx+1;
  for method=1:3
   ur=oce.motion.unwrapPhase(raw.raw_phase_rad,struct('method',methods(method), ...
    'iterations',8,'dimensions',[3 1],'valid_mask',repmat(mask,1,1,nt)));
   data=rmfield(raw,{'raw_phase_rad','phase_truth_rad'});data.motion=ur.values;
   data.valid_mask=mask;data.analysis_mask=centers;
   urDiagnostic=rmfield(ur,'values');urDiagnostic.performed=true;
   data.metadata.raw_unwrap=urDiagnostic;
   opts.unwrap_method=methods(method);
   results{source,method}=oce.dispersion.estimateLocalSpeedMap(data,opts);
   young{source,method}=oce.elastography.invertYoungModulus(results{source,method}, ...
    struct('model',string(c.model),'frequency_hz',freq,'density_kg_m3',double(c.density_kg_m3), ...
     'poisson_ratio',double(c.poisson_ratio),'thickness_m',double(c.thickness_m)));
   delta=ur.values-double(raw.phase_truth_rad);delta=delta-mean(delta,3,'omitnan');
   sampleMask=repmat(mask,1,1,nt);temporalRmse=sqrt(mean(delta(sampleMask).^2,'omitnan'));
   v=score & results{source,method}.valid_mask;ev=v & young{source,method}.valid_mask;
   sourceName="exact_xz";if source==2,sourceName="true_fdtd_xz";end
   if string(c.model)=="bulk_shear",sourceName="analytic_bulk_realization"+source;end
   r=struct('case_label',string(c.label),'source',sourceName,'unwrap_method',methods(method), ...
    'estimator',"phase_derivative_2d",'pd_geometry',opts.pd_geometry,'directional_filter',filterEnabled, ...
    'raw_iterations_executed',ur.iterations_executed,'raw_phase_temporal_rmse_rad',temporalRmse, ...
    'score_pixels',nnz(score),'accepted_pixels',nnz(v),'coverage_pct',100*nnz(v)/nnz(score), ...
    'speed_median_m_s',median(results{source,method}.speed_m_s(v),'omitnan'), ...
    'speed_discrepancy_homogeneous_pct',100*median(abs(results{source,method}.speed_m_s(v)/c.reference_speed_m_s-1),'omitnan'), ...
    'young_discrepancy_constitutive_pct',100*median(abs(young{source,method}.young_pa(ev)./c.truth_young_pa(ev)-1),'omitnan'), ...
    'raw_wrap_consistency_rms_rad',ur.diagnostics.wrap_consistency_rms_rad);
   if isempty(records),records=r;else,records(end+1)=r;end %#ok<SAGROW>
   unwrapDiagnostics{source,method}=urDiagnostic;
  end
 end
 for source=1:2
  common=score;
  for method=1:3,common=common & results{source,method}.valid_mask;end
  for method=1:3
   r=struct('case_label',string(c.label),'source_index',source,'unwrap_method',methods(method), ...
    'common_pixels',nnz(common), ...
    'speed_error_common_pct',100*median(abs(results{source,method}.speed_m_s(common)/c.reference_speed_m_s-1),'omitnan'));
   if isempty(commonRecords),commonRecords=r;else,commonRecords(end+1)=r;end %#ok<SAGROW>
  end
 end
 maps{j}=struct('label',string(c.label),'results',{results},'young',{young}, ...
  'unwrap_diagnostics',{unwrapDiagnostics},'score_mask',score,'options',opts);
 render_maps(c,results,young,methods,gallery,suffix);
 writetable(struct2table(records),fullfile(here,"raw_unwrap_speed_young_metrics"+suffix+".csv"));
 fprintf('RAW_UNWRAP_MAP_DONE %s\n',string(c.label));
end
writetable(struct2table(commonRecords),fullfile(here,"raw_unwrap_common_support"+suffix+".csv"));
save(fullfile(here,"raw_unwrap_maps"+suffix+".mat"),'maps','records','commonRecords','-v7.3');
disp('RAW_UNWRAP_COMPARISON_FINISHED');

function render_maps(c,results,young,methods,gallery,suffix)
 fig=figure('Visible','off','Color','white','Position',[20 20 1500 1100]);
 lay=tiledlayout(fig,4,3,'Padding','compact','TileSpacing','compact');
 for row=1:4
  source=1+mod(row-1,2);isYoung=row>2;
  for method=1:3
   if isYoung,values=young{source,method}.young_pa/1000;limits=[.6*min(c.truth_young_pa,[],'all') 1.8*max(c.truth_young_pa,[],'all')]/1000;units='kPa';
   else,values=results{source,method}.speed_m_s;limits=c.reference_speed_m_s*[.6 1.8];units='m/s';end
   ax=nexttile(lay);im=imagesc(ax,c.x_m*1000,c.row_m*1000,values);im.AlphaData=isfinite(values);
   ax.Color=[.85 .85 .85];ax.YDir='reverse';colormap(ax,turbo);clim(ax,limits);
   cb=colorbar(ax);cb.Label.String=units;xlabel(ax,'X (mm)');ylabel(ax,'Z (mm)');
   sourceTitle="Exact XZ";if source==2,sourceTitle="True FDTD XZ";end
   if string(c.model)=="bulk_shear",sourceTitle="Bulk analítico, ruido "+source;end
   methodTitle=methods(method);if method==3,methodTitle="TIE-DCT | 8 correcciones fijas";end
   title(ax,sourceTitle+" | "+methodTitle,'Interpreter','none');
   if logical(c.has_inclusion) && source==2
    hold(ax,'on');contour(ax,c.x_m*1000,c.row_m*1000,double(c.truth_young_pa>min(c.truth_young_pa,[],'all')),[.5 .5],'w--');hold(ax,'off');
   end
  end
 end
 title(lay,replace(string(c.label),'_',' ')+" | phase derivative 2D",'Interpreter','none');
 scope="Fase óptica cruda → unwrap → proyección armónica → unwrap modal → derivadas. Gris = sin soporte; escalas compartidas.";
 if strlength(suffix)>0,scope="Fase cruda → unwrap → proyección/filtro direccional → unwrap modal → derivadas. Gris = sin soporte.";end
 if logical(c.has_inclusion),scope=scope+" Exact: baseline homogéneo; contorno: material de referencia.";end
 subtitle(lay,scope,'Interpreter','none');
 exportgraphics(fig,fullfile(gallery,"comparison_unwrap_pd2d"+suffix+"_"+string(c.label)+"_speed_young.png"),'Resolution',160);
 close(fig);
end
