%% Experimental gallery: measured support and conditional apparent Young
% Saved motion planes only. No BIN read, interpolation, smoothing or GT claim.
% Young uses the measured speed and mask under explicitly assumed mechanics.
outputRoot = fileparts(mfilename('fullpath'));
workflowRoot = fileparts(fileparts(fileparts(outputRoot)));
cd(workflowRoot); startup;
galleryRoot = fullfile(workflowRoot,'results','Speed_Young_Maps');
if ~isfolder(galleryRoot), mkdir(galleryRoot); end
inputRoot = 'C:/Users/proyecto.pi1081/Desktop/OCE_fish/OCE_estimator_validation/experimental';
finalCsv = fullfile(workflowRoot,'results','extended_validation_2026-10-05', ...
    'experimental_sensitivity','experimental_sensitivity_trials.csv');
finalTrials = readtable(finalCsv,'TextType','string');
configs = struct('plane',{},'method',{},'reverb_model',{},'young_model',{},'title',{});
configs(1) = struct('plane',"luis3_bmode1_offset_0p00mm",'method',"directional_phase", ...
    'reverb_model',"scalar2d",'young_model',"rayleigh",'title',"Luis3 · B-mode 1 independiente");
configs(2) = struct('plane',"raster_offset_0p00mm",'method',"directional_phase", ...
    'reverb_model',"scalar2d",'young_model',"rayleigh",'title',"Raster · plano candidato 0.00 mm");
configs(3) = struct('plane',"raster_offset_0p10mm",'method',"directional_phase", ...
    'reverb_model',"scalar2d",'young_model',"rayleigh",'title',"Raster · plano candidato +0.10 mm");
configs(4) = struct('plane',"raster_offset_0p00mm",'method',"reverberant", ...
    'reverb_model',"shear3d",'young_model',"bulk_shear",'title',"Raster · plano candidato 0.00 mm");
configs(5) = struct('plane',"raster_offset_0p10mm",'method',"reverberant", ...
    'reverb_model',"shear3d",'young_model',"bulk_shear",'title',"Raster · plano candidato +0.10 mm");
records = struct([]);
hashFiles = [string(which('oce.dispersion.estimateLocalSpeedMap')); ...
    string(which('oce.elastography.invertYoungModulus')); string(mfilename('fullpath'))+".m"];
sourceHashes = table(hashFiles,strings(size(hashFiles)), ...
    'VariableNames',{'file','sha256'});
for index=1:height(sourceHashes)
    sourceHashes.sha256(index) = sha256_file(sourceHashes.file(index));
end
writetable(sourceHashes,fullfile(outputRoot,'source_hashes.csv'));
for index=1:numel(configs)
    config=configs(index);
    sourcePlane = fullfile(inputRoot,config.plane+"_plane.mat");
    load(sourcePlane,'data');
    frequency=data.metadata.observation.frequency_hz_supplied_for_observation;
    rowWindow=1.2;
    if data.plane_type=="bmode", rowWindow=.08; end
    options=struct('method',config.method,'reverb_model',config.reverb_model, ...
        'frequency_hz',frequency,'time_start_s',.002,'time_end_s',.004, ...
        'window_x_mm',1.2,'window_row_mm',rowWindow,'direction_deg',0, ...
        'directional_halfwidth_deg',35,'min_coherence',.2, ...
        'min_amplitude_fraction',.08,'min_support_fraction',.6, ...
        'fit_error_max',.3,'reverb_lag_mm',.6,'speed_range_m_s',[.2 10],'smoothing_mm',0);
    result=oce.dispersion.estimateLocalSpeedMap(data,options);
    youngOptions=struct('model',config.young_model,'density_kg_m3',1000, ...
        'poisson_ratio',.495,'frequency_hz',frequency);
    young=oce.elastography.invertYoungModulus(result,youngOptions);
    assert(isequal(young.valid_mask,result.valid_mask), ...
        'Gallery:MaskMismatch','Elastic inversion must preserve measured support.');
    assert(all(isnan(result.speed_m_s(~result.valid_mask)),'all') && ...
        all(isnan(young.young_pa(~young.valid_mask)),'all'), ...
        'Gallery:InvalidWasFilled','Rejected pixels must remain NaN.');
    values=result.speed_m_s(result.valid_mask);
    eValues=young.young_pa(young.valid_mask)/1000;
    speeds=[min(values) median(values) max(values)];
    moduli=[min(eValues) median(eValues) max(eValues)];
    count=nnz(result.valid_mask); coverage=count/numel(result.valid_mask);
    previous=finalTrials(finalTrials.plane==config.plane & ...
        finalTrials.method==config.method & finalTrials.reverb_model==config.reverb_model & ...
        finalTrials.variant=="observed" & finalTrials.roi=="early_2to4ms" & ...
        finalTrials.min_coherence==.2 & finalTrials.window_x_mm==1.2,:);
    assert(height(previous)==1,'Gallery:ReferenceMissing','One final reference trial is required.');
    assert(previous.valid_pixel_count==count && ...
        abs(previous.speed_median_m_s-speeds(2))<1e-10, ...
        'Gallery:ReferenceChanged','Current core differs from final sensitivity reference.');
    tag="experimental_"+config.plane+"_"+config.method+"_"+config.young_model;
    pngFile=fullfile(galleryRoot,tag+".png");
    provenance=struct('source_plane_file',sourcePlane,'final_reference_csv',finalCsv, ...
        'source_metadata',data.metadata,'settings_predeclared',true, ...
        'ground_truth_available',false,'surface_verified',false,'repeatability_verified',false, ...
        'frequency_source',"Explicit experimental analysis frequency from user/acquisition filename; old header has no function-generator metadata", ...
        'young_interpretation',"Conditional apparent elastic Young modulus under selected wave model; mode and boundary conditions unverified", ...
        'rendering',"Full reconstructed physical extent; measured masks and NaN preserved; no spatial interpolation or smoothing", ...
        'source_hashes',sourceHashes);
    save(fullfile(outputRoot,tag+".mat"),'data','result','young','options','youngOptions','provenance','-v7.3');
    save_map_figure(data,result,young,config,pngFile,count,coverage,speeds,moduli);
    record=struct('plane',config.plane,'source_plane_file',string(sourcePlane), ...
        'png_file',string(pngFile),'method',config.method,'reverb_model',config.reverb_model, ...
        'frequency_hz',frequency,'time_start_s',.002,'time_end_s',.004, ...
        'min_coherence',.2,'window_x_mm',1.2,'window_row_mm',rowWindow,'direction_deg',0, ...
        'valid_pixel_count',count,'total_pixel_count',numel(result.valid_mask), ...
        'coverage_fraction',coverage,'speed_min_m_s',speeds(1),'speed_median_m_s',speeds(2), ...
        'speed_max_m_s',speeds(3),'young_model',config.young_model,'density_kg_m3',1000, ...
        'poisson_ratio',.495,'young_min_kpa',moduli(1),'young_median_kpa',moduli(2), ...
        'young_max_kpa',moduli(3),'ground_truth_available',false, ...
        'surface_verified',false,'repeatability_verified',false,'reference_reproduced',true);
    if isempty(records),records=record;else,records(end+1)=record;end %#ok<SAGROW>
    fprintf('%s: %d/%d accepted (%.4f%%), speed %.6f m/s, conditional E %.6f kPa\n', ...
        tag,count,numel(result.valid_mask),100*coverage,speeds(2),moduli(2));
end
writetable(struct2table(records),fullfile(outputRoot,'experimental_speed_young_metrics.csv'));
save(fullfile(outputRoot,'experimental_gallery_manifest.mat'),'configs','records','sourceHashes','finalCsv');
disp('EXPERIMENTAL_SPEED_YOUNG_GALLERY_FINISHED');

function save_map_figure(data,result,young,config,path,count,coverage,speeds,moduli)
    fig=figure('Visible','off','Color','w','Position',[20 20 1500 900]);
    cleanup=onCleanup(@() close(fig)); %#ok<NASGU>
    layout=tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
    layout.Units='normalized';layout.OuterPosition=[.025 .24 .95 .72];
    title(layout,"Experimental · "+config.title,'FontSize',20,'FontWeight','bold','Interpreter','none');
    if config.method=="directional_phase"
        methodLabel="Fase direccional 0° (sector ±35°)";
        modelLabel="Rayleigh · semiespacio elástico libre supuesto";
        physics="E sólo si la velocidad corresponde a Rayleigh; modo y bordes no verificados.";
    else
        methodLabel="Autocorrelación angular AIA · corte 3D isotrópico";
        modelLabel="Corte volumétrico supuesto";
        physics="AIA requiere campo difuso e isotrópico; E sólo si c representa velocidad de corte.";
    end
    subtitle(layout,sprintf('%s | f = %g Hz asumida | ROI 2–4 ms', ...
        methodLabel,result.options.frequency_hz),'FontSize',13,'Interpreter','none');
    speedAx=nexttile(layout);
    im=imagesc(speedAx,data.x_m*1000,data.row_m*1000,result.speed_m_s);
    im.AlphaData=result.valid_mask;
    speedAx.Color=[.88 .88 .88];clim(speedAx,[0 4]);
    cb=colorbar(speedAx);cb.Label.String='Velocidad (m/s)';
    title(speedAx,'Velocidad estimada','FontSize',17,'Interpreter','none');
    youngAx=nexttile(layout);
    im=imagesc(youngAx,data.x_m*1000,data.row_m*1000,young.young_pa/1000);
    im.AlphaData=young.valid_mask;
    youngAx.Color=[.88 .88 .88];clim(youngAx,[0 30]);
    cb=colorbar(youngAx);cb.Label.String='Young aparente (kPa)';
    title(youngAx,{'Young aparente · modelo supuesto',char(modelLabel)}, ...
        'FontSize',15,'Interpreter','none');
    for ax=[speedAx youngAx]
        colormap(ax,parula(256));ax.FontSize=12;ax.Box='on';
        xlabel(ax,'x (mm)');
        if data.plane_type=="enface"
            ylabel(ax,'y (mm)');axis(ax,'image');
        else
            ylabel(ax,'Profundidad OCT (mm)');axis(ax,'tight');
        end
        ax.XLim=[min(data.x_m) max(data.x_m)]*1000;
        ax.YLim=[min(data.row_m) max(data.row_m)]*1000;
    end
    if data.plane_type=="enface"
        depthText=sprintf('Plano relativo al máximo OCT no verificado: %+0.2f mm; banda axial 0.04 mm.',data.offsets.depth_offset_mm);
        acquisitionText='Superficie y repetibilidad de fase entre posiciones MB no verificadas; sin ground truth.';
    else
        depthText='B-mode 1 independiente; profundidad con índice óptico n = 1.4. No se unen meridianos.';
        acquisitionText='Interfaz y modo de onda no verificados; sin ground truth. Soporte muy escaso.';
    end
    footer={sprintf('Soporte aceptado: %d/%d píxeles (%.3f%%). Gris = rechazado / ausente; sin relleno ni suavizado.', ...
        count,numel(result.valid_mask),100*coverage), ...
        sprintf('Velocidad: mediana %.3f m/s [%.3f, %.3f]. E aparente: mediana %.2f kPa [%.2f, %.2f].', ...
        speeds(2),speeds(1),speeds(3),moduli(2),moduli(1),moduli(3)), ...
        sprintf('Ventana X %.2f / fila %.2f mm; coherencia mínima 0.20. Densidad 1000 kg/m³ y Poisson 0.495 supuestos.', ...
        result.options.window_x_mm,result.options.window_row_mm), ...
        char(depthText),char(acquisitionText),char(physics)};
    annotation(fig,'textbox',[.045 .025 .92 .18],'String',footer, ...
        'FontSize',11,'Interpreter','none','EdgeColor','none','VerticalAlignment','middle');
    exportgraphics(fig,path,'Resolution',160,'BackgroundColor','white');
end

function value=sha256_file(path)
    fid=fopen(path,'rb');
    cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
    bytes=fread(fid,Inf,'*uint8');
    digest=java.security.MessageDigest.getInstance('SHA-256');
    digest.update(bytes);
    value=lower(string(reshape(dec2hex(typecast(digest.digest(),'uint8'),2)',1,[])));
end
