function render_fish_speed_young_products()
% Render raw products. This file performs no scientific fitting or filling.
    here=fileparts(mfilename('fullpath')); parent=fileparts(here);
    workflow=fileparts(fileparts(parent)); gallery=fullfile(workflow,'results','Speed_Young_Maps');
    diagnostic=fullfile(here,'diagnostic_maps');
    if ~isfolder(gallery), mkdir(gallery); end
    if ~isfolder(diagnostic), mkdir(diagnostic); end
    s=load(fullfile(here,'fish_estimator_products.mat'));
    records=struct([]);
    for index=1:numel(s.products)
        p=s.products(index);
        if ~startsWith(p.label,"phase_gradient_excitation_") && ...
                ~any(p.label==["phase_gradient_robust_slowness","directional_phase_robust_slowness","sequential_ensemble_autocorrelation"])
            continue;
        end
        metric=s.metrics(s.metrics.label==p.label,:);
        hr=floor(metric.window_row_mm*1e-3/(2*mean(diff(s.row_m)))+1e-12);
        hx=floor(metric.window_x_mm*1e-3/(2*mean(diff(s.x_m)))+1e-12);
        kernel=ones(2*hr+1,2*hx+1);
        inclusion=(s.truthE==24000);
        pureInclusion=conv2(double(inclusion),kernel,'same')==numel(kernel);
        pureBackground=conv2(double(s.truthE==12000),kernel,'same')==numel(kernel);
        valid=p.valid_mask&s.truthMask;
        head=valid&pureInclusion&s.head_mask; tail=valid&pureInclusion&s.tail_mask;
        background=valid&pureBackground;
        record=struct('label',p.label,'head_core_count',nnz(head),'tail_core_count',nnz(tail), ...
            'head_core_young_median_pa',median(p.young_pa(head)), ...
            'tail_core_young_median_pa',median(p.young_pa(tail)), ...
            'head_core_young_discrepancy',median(abs(p.young_pa(head)/24000-1)), ...
            'tail_core_young_discrepancy',median(abs(p.young_pa(tail)/24000-1)), ...
            'background_young_discrepancy',median(abs(p.young_pa(background)/12000-1)));
        % Show all eight separate PG experiments and their fixed fusion,
        % including incomplete support/model bias. Residuals are reported
        % outside the gallery and never used to select the displayed pixels.
        publish=startsWith(p.label,"phase_gradient_");
        record.published=publish;
        if isempty(records), records=record; else, records(end+1)=record; end %#ok<AGROW>
        if publish, destination=gallery; else, destination=diagnostic; end
        filename="fish_"+p.label+"_speed_young.png";
        draw_product(p,s,metric,fullfile(destination,filename));
    end
    regional=struct2table(records); writetable(regional,fullfile(here,'fish_regional_gallery_metrics.csv'));
    disp(regional); disp('FISH_MAP_RENDERING_FINISHED');
end

function draw_product(p,s,metric,path)
    f=figure('Visible','off','Color','w','Position',[60 60 1400 610]); cleanup=onCleanup(@()close(f)); %#ok<NASGU>
    layout=tiledlayout(f,1,2,'TileSpacing','compact','Padding','compact');
    values={p.speed_m_s,p.young_pa/1000}; limits={[1.3 3.5],[0 30]};
    titles={"Velocidad de fase [m/s]","Young aparente [kPa]"};
    x=double(s.x_m(:))*1000; y=double(s.row_m(:))*1000;
    roi=logical(s.truthMask);
    for panel=1:2
        a=nexttile(layout); image=imagesc(a,x,y,values{panel});
        image.AlphaData=isfinite(values{panel})&p.valid_mask&roi;
        a.Color=[.84 .84 .84]; a.YDir='normal'; axis(a,'image');
        colormap(a,turbo(256)); clim(a,limits{panel}); colorbar(a);
        xlim(a,[-6 6]); ylim(a,[-6 6]);
        hold(a,'on'); contour(a,x,y,double(s.truthE>12000),[.5 .5],'w--','LineWidth',1.4);
        title(a,titles{panel},'FontSize',15); xlabel(a,'x [mm]'); ylabel(a,'y [mm]');
        a.FontSize=12; grid(a,'off'); box(a,'on');
    end
    if contains(p.label,"excitation_")
        heading=replace(p.label,"phase_gradient_excitation_","Excitacion individual ")+" grados; PG";
    elseif p.label=="phase_gradient_robust_slowness"
        heading="Fusion robusta de 8 excitaciones individuales; PG; minimo 4/8";
    elseif p.label=="directional_phase_robust_slowness"
        heading="Comparacion: fusion robusta de 8 sectores direccionales";
    else
        heading="Comparacion: autocorrelacion de ocho campos independientes";
    end
    subtitle=sprintf('%.1f kHz | ventana solicitada %.1f mm | cobertura %.1f %% | inclusiones 24 kPa, fondo 12 kPa | NaN en gris', ...
        s.frozen.frequency_hz/1000,metric.window_x_mm,100*metric.coverage_fraction);
    title(layout,{char(heading),subtitle, ...
        'Contorno blanco: geometria material de referencia simulada'},'FontSize',15,'Interpreter','none');
    exportgraphics(f,path,'Resolution',160);
end
