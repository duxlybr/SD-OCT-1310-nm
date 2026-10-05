%% Luis3 independent B-scans: fixed PG reference and explicit depth zoom
outputRoot=fileparts(mfilename('fullpath'));
workflowRoot=fileparts(fileparts(fileparts(outputRoot)));
cd(workflowRoot);startup;
galleryRoot=fullfile(workflowRoot,'results','Speed_Young_Maps');
archiveRoot=fullfile(outputRoot,'archived_gallery');
if ~isfolder(archiveRoot),mkdir(archiveRoot);end
oldFile=fullfile(galleryRoot,'experimental_luis3_bmode1_offset_0p00mm_directional_phase_rayleigh.png');
if isfile(oldFile),movefile(oldFile,fullfile(archiveRoot,'experimental_luis3_bmode1_offset_0p00mm_directional_phase_rayleigh.png'));end
sourcePlane='C:/Users/proyecto.pi1081/Desktop/OCE_fish/OCE_estimator_validation/experimental/luis3_bmode1_offset_0p00mm_plane.mat';
options=struct('method',"phase_gradient",'frequency_hz',1000,'time_start_s',.002,'time_end_s',.004, ...
    'window_x_mm',.9,'window_row_mm',.04,'min_coherence',.2,'min_amplitude_fraction',.08, ...
    'min_support_fraction',.6,'fit_error_max',.3,'speed_range_m_s',[.2 10],'smoothing_mm',0);
youngOptions=struct('model',"rayleigh",'density_kg_m3',1000,'poisson_ratio',.495);
records=struct([]);pulseRecords=struct([]);referenceMaps=struct([]);
for bmode=1:4
    if bmode==1,planeFile=sourcePlane;
    else,planeFile=fullfile(outputRoot,sprintf('luis3_bmode%d_plane.mat',bmode));end
    load(planeFile,'data');
    result=oce.dispersion.estimateLocalSpeedMap(data,options);
    young=oce.elastography.invertYoungModulus(result,youngOptions);
    values=result.speed_m_s(result.valid_mask);e=young.young_pa(young.valid_mask)/1000;
    z=data.row_m(any(result.valid_mask,2))*1000;
    if isempty(values),vstats=[NaN NaN NaN];estats=vstats;zstats=[NaN NaN];
    else,vstats=[min(values) median(values) max(values)];estats=[min(e) median(e) max(e)];zstats=[min(z) max(z)];end
    rec=struct('bmode',bmode,'accepted_count',nnz(result.valid_mask),'total_pixels',numel(result.valid_mask), ...
        'coverage_fraction',nnz(result.valid_mask)/numel(result.valid_mask), ...
        'speed_min_m_s',vstats(1),'speed_median_m_s',vstats(2),'speed_max_m_s',vstats(3), ...
        'apparent_Young_min_kPa',estats(1),'apparent_Young_median_kPa',estats(2),'apparent_Young_max_kPa',estats(3), ...
        'depth_min_mm',zstats(1),'depth_max_mm',zstats(2),'reference_available',false, ...
        'input_surface_method',data.metadata.load_options.surface_method, ...
        'interpretation',"Fixed PG exploratory phase speed; conditional assumed Rayleigh Young; no measured mechanical ground truth or identified mode");
    records=[records rec]; %#ok<AGROW>
    filename=sprintf('experimental_luis3_bmode%d_phase_gradient_rayleigh_full_and_zoom.png',bmode);
    render_maps(data,result,young,bmode,fullfile(galleryRoot,filename));
    [pulse,diagnostic]=focused_packet(data,result,bmode);
    pulseRecords=[pulseRecords pulse]; %#ok<AGROW>
    save(fullfile(outputRoot,sprintf('luis3_bmode%d_fixed_pg_reference.mat',bmode)), ...
        'planeFile','options','youngOptions','result','young','diagnostic','-v7.3');
    render_packet(diagnostic,bmode,fullfile(outputRoot,sprintf('luis3_bmode%d_focused_packet.png',bmode)));
    referenceMaps=[referenceMaps struct('bmode',bmode,'planeFile',planeFile,'result',result,'young',young)]; %#ok<AGROW>
    fprintf('Bmode%d PG fixed: %d/%d, median c %.4f m/s, apparentE %.3f kPa\n', ...
        bmode,rec.accepted_count,rec.total_pixels,rec.speed_median_m_s,rec.apparent_Young_median_kPa);
end
writetable(struct2table(records),fullfile(outputRoot,'fixed_pg_speed_apparent_Young_metrics.csv'));
writetable(struct2table(pulseRecords),fullfile(outputRoot,'focused_packet_metrics.csv'));
save(fullfile(outputRoot,'fixed_pg_reference_manifest.mat'),'referenceMaps','options','youngOptions','records','pulseRecords','sourcePlane','-v7.3');
paths=["src/+oce/+dispersion/estimateLocalSpeedMap.m";"src/+oce/+elastography/invertYoungModulus.m"];
hashes=strings(size(paths));
for i=1:numel(paths)
    md=java.security.MessageDigest.getInstance('SHA-256');
    fid=fopen(paths(i),'r');bytes=fread(fid,Inf,'*uint8');fclose(fid);md.update(bytes);
    hashes(i)=lower(string(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[])));
end
writetable(table(paths,hashes),fullfile(outputRoot,'fixed_pg_core_hashes.csv'));
disp('LUIS3_FIXED_GALLERY_FINISHED');

function render_maps(data,result,young,bmode,path)
    fig=figure('Visible','off','Color','w','Position',[20 20 1500 900]);cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
    arrays={result.speed_m_s,young.young_pa/1000};labels={'Velocidad de fase lateral (m/s)','Young aparente (kPa) · Rayleigh supuesto'};
    for row=1:2
        for col=1:2
            ax=nexttile;image=imagesc(data.x_m*1000,data.row_m*1000,arrays{col});
            image.AlphaData=isfinite(arrays{col});ax.Color=[.84 .84 .84];
            xlabel('x local del B-scan (mm)');ylabel('Profundidad OCT (mm)');colorbar;
            colormap(ax,turbo(256));
            if col==1,clim(ax,[.2 10]);else,clim(ax,[0 330]);end
            if row==1
                title(ax,labels{col}+" · campo adquirido completo",'Interpreter','none');
                ylim(ax,[min(data.row_m) max(data.row_m)]*1000);
            else
                title(ax,labels{col}+" · zoom axial 0.18–0.46 mm",'Interpreter','none');
                ylim(ax,[.18 .46]);
            end
            xlim(ax,[min(data.x_m) max(data.x_m)]*1000);set(ax,'YDir','reverse');
        end
    end
    title(layout,{sprintf('Luis3 B-scan %d independiente · 1000 Hz indicados · PG · ROI 2–4 ms · ventanas X0.9/Z0.04 mm · C≥0.2',bmode), ...
        sprintf('%d/%d píxeles (%.3f%%) · gris=sin estimación · referencia experimental ausente; superficie/registro temporal no verificados', ...
        nnz(result.valid_mask),numel(result.valid_mask),100*nnz(result.valid_mask)/numel(result.valid_mask)), ...
        'Entrada: MAT previo con max_in_search, candidato sin validación anatómica; resultado no equivalente al BIN con borde heredado actual', ...
        'Young: hipótesis homogénea elástica, semiespacio Rayleigh libre; rho=1000 kg/m³, nu=0.495; modo no identificado'}, ...
        'Interpreter','none','FontSize',10);
    exportgraphics(fig,path,'Resolution',160,'BackgroundColor','white');
end

function [rec,p]=focused_packet(data,result,bmode)
    % Diagnostic point/band selection by harmonic energy, not by map error.
    search=data.row_m>=.18e-3&data.row_m<=.46e-3;
    score=sum(abs(result.diagnostics.input_phasor).*result.diagnostics.temporal_coherence.*data.valid_mask,2,'omitnan');
    score(~search)=-Inf;[~,iz]=max(score);
    center=data.row_m(iz)*1000;z=abs(data.row_m*1000-center)<=.02;
    valid=data.valid_mask(z,:);input=double(data.motion(z,:,:));
    weights=10.^((data.structural_db(z,:)-max(data.structural_db(z,:),[],'all'))/10).*valid;
    input(~repmat(valid,1,1,size(input,3)))=0;
    total=sum(weights,1);supported=total>0;
    traces=squeeze(sum(input.*weights,1)./max(realmin,total));traces(~supported,:)=NaN;
    t=data.t_s(:);fs=1/mean(diff(t));n=numel(t);f=(0:n-1)'*fs/n;
    centered=traces-mean(traces,2,'omitnan');safe=centered;safe(~isfinite(safe))=0;
    taper=.5-.5*cos(2*pi*(0:n-1)/(n-1));power=abs(fft(safe.*taper,[],2)).^2;
    positive=f<=fs/2;band=f>=500&f<=1500;
    energy=sum(power(:,band),2);[~,ix]=max(energy);
    selected=unique(max(1,min(size(traces,1),ix+[-4 -2 0 2 4])));
    transform=fft(safe,[],2);keep=(f>=500&f<=1500)|(f>=fs-1500&f<=fs-500);
    transform(:,~keep)=0;analytic=zeros(size(transform));
    analytic(:,2:floor((n+1)/2))=2*transform(:,2:floor((n+1)/2));
    if mod(n,2)==0,analytic(:,n/2+1)=transform(:,n/2+1);end
    envelope=abs(ifft(analytic,[],2));envelope(~supported,:)=NaN;
    pre=t<.002;early=t>=.002&t<.004;late=t>=.004;
    rms=@(a)sqrt(mean(traces(ix,a).^2,'omitnan'));
    ps=mean(power(supported,positive),1)';freq=f(positive);ps(1)=0;[~,peak]=max(ps);
    centroids=(envelope.^2*t)./sum(envelope.^2,2);
    good=supported(:)&isfinite(centroids);x=data.x_m(:);
    coeff=[ones(nnz(good),1) x(good)]\centroids(good);
    residual=centroids(good)-[ones(nnz(good),1) x(good)]*coeff;
    r2=1-sum(residual.^2)/max(realmin,sum((centroids(good)-mean(centroids(good))).^2));
    rec=struct('bmode',bmode,'selected_depth_center_mm',center,'band_width_mm',.04, ...
        'selected_x_mm',x(ix)*1000,'supported_columns',nnz(good),'fft_resolution_hz',fs/n, ...
        'spectrum_peak_hz',freq(peak),'power_fraction_500to1500hz',sum(ps(freq>=500&freq<=1500))/sum(ps), ...
        'focused_raw_rms_early_to_pre',rms(early)/rms(pre),'focused_raw_rms_early_to_late',rms(early)/rms(late), ...
        'centroid_vs_x_r2',r2,'interpretation', ...
        "Data-selected harmonic-energy focus; transient signal exists locally, no verified arrival front or delay-speed estimator");
    p=struct('t_s',t,'x_m',x,'depth_center_mm',center,'selected_columns',selected,'traces_rad',traces, ...
        'envelope_rad',envelope,'f_hz',freq,'mean_spectrum_power',ps,'record',rec);
end

function render_packet(p,bmode,path)
    fig=figure('Visible','off','Color','w','Position',[20 20 1600 850]);cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
    nexttile;plot(p.t_s*1000,p.traces_rad(p.selected_columns,:)');xline(2,'k:');xline(4,'k:');
    xlabel('t local (ms)');ylabel('Incremento fase (rad)');title('Trazas cerca del foco de energía armónica');
    legend(compose('x %.2f mm',p.x_m(p.selected_columns)*1000),'Location','best');
    nexttile;imagesc(p.t_s*1000,p.x_m*1000,p.envelope_rad);xlabel('t local (ms)');ylabel('x (mm)');colorbar;
    title('Envolvente diagnóstica 500–1500 Hz · sin velocidad de llegada');
    nexttile;plot(p.f_hz,p.mean_spectrum_power);xlim([0 5000]);xline(1000,'k:');xlabel('Frecuencia (Hz)');ylabel('Potencia');
    title(sprintf('FFT sin padding · resolución %.1f Hz',p.record.fft_resolution_hz));
    nexttile;plot(p.t_s*1000,p.envelope_rad(p.selected_columns,:)');xline(2,'k:');xline(4,'k:');
    xlabel('t local (ms)');ylabel('Envolvente (rad)');title('Ventana corta puede producir ringing; no prueba monomodalidad');
    title(layout,{sprintf('Luis3 Bmode%d · banda centrada en z %.3f mm, ancho 0.04 mm; foco x %.2f mm', ...
        bmode,p.depth_center_mm,p.record.selected_x_mm), ...
        'Selección diagnóstica por energía armónica; no cambia parámetros del mapa. Respuesta MB/retardo entre posiciones no verificados.'},'Interpreter','none');
    exportgraphics(fig,path,'Resolution',140,'BackgroundColor','white');
end
