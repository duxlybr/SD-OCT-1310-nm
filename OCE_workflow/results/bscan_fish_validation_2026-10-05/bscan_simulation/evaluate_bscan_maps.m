%% Observational independent B-scan validation; no production defaults changed.
outputRoot=fileparts(mfilename('fullpath'));
workflowRoot=fileparts(fileparts(fileparts(outputRoot)));
cd(workflowRoot);startup;
galleryRoot=fullfile(workflowRoot,'results','Speed_Young_Maps');
load(fullfile(outputRoot,'bscan_forward_cases.mat'),'cases');
if isstruct(cases), cases=num2cell(cases); end
plate=load(fullfile(workflowRoot,'results','map_gallery_validation_2026-10-05','lamb_plate','physical_plate_ppw24_contrast2.mat'),'solution','physics');
s=plate.solution;p=plate.physics;lambda=p.lambda_background_m;
[~,midY]=min(abs(s.y_m));xi=find(abs(s.x_m)<=5*lambda);
x=s.x_m(xi);z=(0:.005:.2)'*1e-3;t=(0:159)'/(40*p.frequency_hz);
P=repmat(s.field_m(midY,xi),numel(z),1);
wave=real(P.*reshape(exp(2i*pi*p.frequency_hz*t),1,1,[]));
rng(20261019);sigma=sqrt(mean(wave.^2,'all'))*10^(-35/20);
E=repmat(s.young_pa(midY,xi),numel(z),1);D=repmat(s.rigidity_n_m(midY,xi),numel(z),1);
speed=2*pi*p.frequency_hz./(p.density_kg_m3*p.thickness_m*(2*pi*p.frequency_hz)^2./D).^.25;
[X,Z]=meshgrid(x,z);
data=struct('motion',single(wave+sigma*randn(size(wave))),'x_m',x,'row_m',z,'t_s',t, ...
 'valid_mask',true(size(P)),'plane_type',"bmode",'metadata',struct('frequency_hz',p.frequency_hz, ...
 'description',"XZ slice of global variable-rigidity Kirchhoff-Love solution; axial w is uniform through thin plate, no independent layer modulus"));
cases{end+1}=struct('label',"lamb_plate_physical_inclusion_xz",'model',"lamb_a0_thin", ...
 'frequency_hz',p.frequency_hz,'density_kg_m3',p.density_kg_m3,'poisson_ratio',p.poisson_ratio, ...
 'thickness_m',p.thickness_m,'truth_speed_m_s',speed,'truth_young_pa',E, ...
 'score_mask',abs(X)<=4*lambda & Z>=.02e-3 & Z<=.18e-3, ...
 'inclusion_core_mask',abs(X)<(p.inclusion_radius_lambda-p.window_lambda)*lambda & Z>=.02e-3 & Z<=.18e-3, ...
 'background_core_mask',abs(X)>(p.inclusion_radius_lambda+p.window_lambda)*lambda & abs(X)<=4*lambda & Z>=.02e-3 & Z<=.18e-3, ...
 'data',data,'speed_reference_scope',"Local homogeneous thin-plate reference in physically scattered global plate solution");
records=struct([]);maps=cell(0,1);
for j=1:numel(cases)
 c=cases{j};data=c.data;data.valid_mask=logical(data.valid_mask);c.score_mask=logical(c.score_mask);
 if string(c.model)=="lamb_a0_thin",wx=.5*lambda*1000;range=[.12 .7];else,wx=.8;range=[.3 5];end
 for method=["phase_gradient","directional_phase"]
  opts=struct('method',method,'frequency_hz',double(c.frequency_hz),'window_x_mm',wx,'window_row_mm',.04, ...
    'direction_deg',0,'directional_halfwidth_deg',45,'min_coherence',.65,'min_amplitude_fraction',.05, ...
    'min_support_fraction',.8,'fit_error_max',.30,'speed_range_m_s',range,'smoothing_mm',0);
  if isfield(c,'source_distance_m')
    hx=floor(wx*1e-3/(2*mean(diff(data.x_m)))+1e-10);
    data.analysis_mask=true(size(data.valid_mask));
    distance=c.source_distance_m;
    for r=1:size(distance,1)
     for k=1:size(distance,2)
      if k-hx<1 || k+hx>size(distance,2),data.analysis_mask(r,k)=false;
      else,data.analysis_mask(r,k)=min(distance(r,k-hx:k+hx))>=2*c.wavelength_bg_m;end
     end
    end
  end
  result=oce.dispersion.estimateLocalSpeedMap(data,opts);
  yo=struct('model',string(c.model),'frequency_hz',double(c.frequency_hz),'density_kg_m3',double(c.density_kg_m3), ...
   'poisson_ratio',double(c.poisson_ratio),'thickness_m',double(c.thickness_m),'max_kh',.6);
  young=oce.elastography.invertYoungModulus(result,yo);
  regions={c.score_mask};names="score_full";
  if isfield(c,'inclusion_core_mask')
   regions=[regions,{c.inclusion_core_mask,c.background_core_mask}];names=[names,"inclusion_core","background_core"];
  end
  for n=1:numel(regions)
   region=logical(regions{n});v=region & result.valid_mask;ev=region & young.valid_mask;
   cr=100*(result.speed_m_s(v)-c.truth_speed_m_s(v))./c.truth_speed_m_s(v);
   er=100*(young.young_pa(ev)-c.truth_young_pa(ev))./c.truth_young_pa(ev);
   rec=struct('case_label',string(c.label),'method',method,'region',names(n),'total_pixels',nnz(region), ...
    'accepted_pixels',nnz(v),'coverage_pct',100*nnz(v)/nnz(region),'speed_median_m_s',median(result.speed_m_s(v),'omitnan'), ...
    'speed_bias_pct',median(cr,'omitnan'),'speed_median_abs_error_pct',median(abs(cr),'omitnan'), ...
    'young_median_kpa',median(young.young_pa(ev),'omitnan')/1000,'young_bias_pct',median(er,'omitnan'), ...
    'young_median_abs_error_pct',median(abs(er),'omitnan'),'window_x_mm',wx,'window_z_mm',.04);
   if isempty(records),records=rec;else,records(end+1)=rec;end %#ok<SAGROW>
  end
  m=struct('case',c,'result',result,'young',young,'options',opts,'young_options',yo);maps{end+1}=m;
  fprintf('%s %s support %.1f%% c%.4g E%.4gkPa\n',string(c.label),method,rec.coverage_pct,rec.speed_median_m_s,rec.young_median_kpa);
  render(m,fullfile(galleryRoot,"simulation_bscan_"+string(c.label)+"_"+method+"_speed_young.png"));
  writetable(struct2table(records),fullfile(outputRoot,'bscan_metrics.csv'));
 end
end
save(fullfile(outputRoot,'bscan_reconstructed_maps.mat'),'maps','records','-v7.3');
disp('BSCAN_VALIDATION_FINISHED');
function render(m,file)
 c=m.case;fig=figure('Visible','off','Color','white','Position',[80 80 1380 750]);
 lay=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
 vals={c.truth_speed_m_s,m.result.speed_m_s,c.truth_young_pa/1000,m.young.young_pa/1000};
 titles=["Referencia velocidad","B-scan velocidad lateral","Referencia Young","Young condicional: "+string(c.model)];
 units=["m/s","m/s","kPa","kPa"];
 for k=1:4
  ax=nexttile(lay);v=vals{k};im=imagesc(ax,c.data.x_m*1000,c.data.row_m*1000,v);im.AlphaData=isfinite(v);
  ax.Color=[.85 .85 .85];axis(ax,'xy');set(ax,'YDir','reverse');xlabel(ax,'X (mm)');ylabel(ax,'Profundidad Z (mm)');
  title(ax,titles(k));colormap(ax,turbo);cb=colorbar(ax);cb.Label.String=units(k);
  if k<=2,clim(ax,[min(c.truth_speed_m_s,[],'all')*.8 max(c.truth_speed_m_s,[],'all')*1.2]);else,clim(ax,[8 28]);end
 end
 title(lay,replace(string(c.label),'_',' ') + " | "+m.options.method+" | sin relleno ni suavizado",'Interpreter','none');
 subtitle(lay,"Z muestra el mismo modo lateral: no acredita módulos independientes por capa. Gris = sin soporte.");
 exportgraphics(fig,file,'Resolution',160);close(fig);
end
