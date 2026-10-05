%% Matched XZ comparisons of independent analytical and FDTD fields.
here=fileparts(mfilename('fullpath'));wf=fileparts(fileparts(here));cd(wf);startup;
gallery=fullfile(wf,'results','Speed_Young_Maps');load(fullfile(here,'paired_xz_cases.mat'),'cases');
records=struct([]);common_records=struct([]);paired_maps=cell(size(cases));
for j=1:numel(cases)
 c=cases{j};lambda=double(c.wavelength_m);freq=double(c.frequency_hz);bg=double(min(c.truth_young_pa,[],'all'));
 options=struct('frequency_hz',freq,'window_x_mm',.5*lambda*1000,'window_row_mm',0, ...
  'min_coherence',.65,'min_amplitude_fraction',.05,'min_support_fraction',.8,'fit_error_max',.30, ...
  'speed_range_m_s',[.2 8],'smoothing_mm',0,'direction_deg',0,'directional_halfwidth_deg',45);
 results=cell(2,2);young=cell(2,2);datasets={c.exact_data,c.fdtd_data};
 [X,Z]=meshgrid(c.x_m,c.row_m);score=X>=0 & X<=2.25*lambda;
 if string(c.model)=="rayleigh",score=score & Z<=.6*lambda;end
 for source=1:2
  data=datasets{source};data.valid_mask=logical(data.valid_mask);
  hx=max(1,floor(options.window_x_mm*1e-3/(2*mean(diff(data.x_m)))+1e-10));
  far=double(c.source_distance_m)>=2*lambda;
  data.analysis_mask=conv2(double(far),ones(1,2*hx+1),'same')==(2*hx+1);
  for method=1:2
   if method==1,options.method="phase_gradient";else,options.method="directional_phase";end
   results{source,method}=oce.dispersion.estimateLocalSpeedMap(data,options);
   yo=struct('model',string(c.model),'frequency_hz',freq,'density_kg_m3',double(c.density_kg_m3), ...
    'poisson_ratio',double(c.poisson_ratio),'thickness_m',double(c.thickness_m));
   young{source,method}=oce.elastography.invertYoungModulus(results{source,method},yo);
   sourceName="exact_xz";if source==2,sourceName="true_fdtd_xz";end
   v=score & results{source,method}.valid_mask;ev=score & young{source,method}.valid_mask;
   rec=struct('case_label',string(c.label),'source',sourceName,'method',options.method,'has_inclusion',logical(c.has_inclusion), ...
    'score_pixels',nnz(score),'accepted_pixels',nnz(v),'coverage_pct',100*nnz(v)/nnz(score), ...
    'speed_median_m_s',median(results{source,method}.speed_m_s(v),'omitnan'), ...
    'speed_discrepancy_homogeneous_pct',100*median(abs(results{source,method}.speed_m_s(v)/c.reference_speed_m_s-1),'omitnan'), ...
    'young_median_kpa',median(young{source,method}.young_pa(ev),'omitnan')/1000, ...
    'young_discrepancy_homogeneous_pct',100*median(abs(young{source,method}.young_pa(ev)/bg-1),'omitnan'), ...
    'young_discrepancy_constitutive_pct',100*median(abs(young{source,method}.young_pa(ev)./c.truth_young_pa(ev)-1),'omitnan'), ...
    'cell_mm',c.grid_cell_m*1000,'frequency_hz',freq,'window_x_mm',options.window_x_mm,'window_z_mm',0);
   if isempty(records),records=rec;else,records(end+1)=rec;end %#ok<SAGROW>
  end
 end
 for method=1:2
  common=score & results{1,method}.valid_mask & results{2,method}.valid_mask;
  ey=common & young{1,method}.valid_mask & young{2,method}.valid_mask;
  methodName="phase_gradient";if method==2,methodName="directional_phase";end
  for source=1:2
   sourceName="exact_xz";if source==2,sourceName="true_fdtd_xz";end
   entry=struct('case_label',string(c.label),'method',methodName,'source',sourceName, ...
    'common_speed_pixels',nnz(common),'common_young_pixels',nnz(ey), ...
    'common_speed_discrepancy_homogeneous_pct',100*median(abs(results{source,method}.speed_m_s(common)/c.reference_speed_m_s-1),'omitnan'), ...
    'common_young_discrepancy_homogeneous_pct',100*median(abs(young{source,method}.young_pa(ey)/bg-1),'omitnan'));
   if isempty(common_records),common_records=entry;else,common_records(end+1)=entry;end %#ok<SAGROW>
  end
 end
 m=struct('case',c,'results',{results},'young',{young},'score_mask',score,'options',options);paired_maps{j}=m;
 render(m,fullfile(gallery,"comparison_exact_fdtd_"+string(c.label)+"_speed_young.png"));
 writetable(struct2table(records),fullfile(here,'paired_xz_metrics.csv'));
 fprintf('PAIRED_RENDER_DONE %s\n',string(c.label));
end
writetable(struct2table(common_records),fullfile(here,'paired_xz_common_support.csv'));
save(fullfile(here,'paired_xz_maps.mat'),'paired_maps','records','common_records','-v7.3');disp('PAIRED_COMPARISON_FINISHED');
function render(m,path)
 c=m.case;fig=figure('Visible','off','Color','white','Position',[30 40 1850 850]);
 lay=tiledlayout(fig,2,4,'Padding','compact','TileSpacing','compact');
 colTitles=["Exact XZ | PG","True FDTD XZ | PG","Exact XZ | Direccional","True FDTD XZ | Direccional"];
 if logical(c.has_inclusion),colTitles([1 3])=["Exact XZ homogéneo | PG","Exact XZ homogéneo | Direccional"];end
 for kind=1:2
  for col=1:4
   source=1+mod(col-1,2);method=1+(col>2);r=m.results{source,method};
   if kind==1,values=r.speed_m_s;units='m/s';limits=c.reference_speed_m_s*[.7 1.5];
   else,values=m.young{source,method}.young_pa/1000;units='kPa';limits=[.6*min(c.truth_young_pa,[],'all') 1.4*max(c.truth_young_pa,[],'all')]/1000;end
   ax=nexttile(lay);im=imagesc(ax,c.x_m*1000,c.row_m*1000,values);im.AlphaData=isfinite(values);ax.Color=[.85 .85 .85];
   axis(ax,'xy');ax.YDir='reverse';xlabel(ax,'X (mm)');ylabel(ax,'Z (mm)');colormap(ax,turbo);clim(ax,limits);
   cb=colorbar(ax);cb.Label.String=units;title(ax,colTitles(col),'Interpreter','none');
   if logical(c.has_inclusion) && source==2
    hold(ax,'on');contour(ax,c.x_m*1000,c.row_m*1000,double(c.truth_young_pa>min(c.truth_young_pa,[],'all')),[.5 .5],'w--','LineWidth',1.1);hold(ax,'off');
   end
  end
 end
 title(lay,replace(string(c.label),'_',' ')+sprintf(' | f %.0f Hz | dx %.3g mm | SNR 30 dB',c.frequency_hz,c.grid_cell_m*1000),'Interpreter','none');
 scope="Mismos ejes y ventanas; escalas compartidas. Gris = sin soporte. Exact: modo homogéneo; FDTD: fuente y dominio finitos.";
 if logical(c.has_inclusion),scope="Exact XZ es baseline homogéneo, no solución exacta de la inclusión. Blanco: geometría constitutiva de referencia.";end
 scope=scope+sprintf(' Cambio FDTD entre bloques: %.3g%%; %g ciclos.',100*c.record_info.convergencia_rel,c.record_info.periodos);
 subtitle(lay,scope,'Interpreter','none');exportgraphics(fig,path,'Resolution',160);close(fig);
end
