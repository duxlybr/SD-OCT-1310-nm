function export_validation_maps()
% Render accepted raw values without smoothing or filling missing support.
    here=fileparts(mfilename('fullpath'));
    loaded=load(fullfile(here,'speed_robustness','selected_raw_maps.mat'),'selected');
    names=["planar","strong_reflection","scalar2d_diffuse","axial_shear3d_xy"];
    titles=["Onda plana · fase","Reflexión fuerte · direccional", ...
        "Campo difuso 2D · AIA planar","Corte 3D · AIA axial"];
    methodIndices=[1 2 3 3];
    fig=figure('Visible','off','Color','w','Position',[30 30 1500 1100]);
    layout=tiledlayout(4,3,'Padding','compact','TileSpacing','compact');
    for row=1:4
        match=[];
        for i=1:numel(loaded.selected)
            s=loaded.selected{i};
            if string(s.case_name)==names(row)&&s.snr_db==5&&s.seed==101, match=s;break;end
        end
        assert(~isempty(match),'Missing representative SNR5 trial.');
        d=match.data; r=match.products{methodIndices(row)};
        truth=2*ones(size(r.speed_m_s));
        speed=r.speed_m_s; error=100*abs(speed./truth-1);
        for col=1:3
            ax=nexttile;
            if col==1, values=truth; titleText=[titles(row);"Referencia: 2 m/s"];
            elseif col==2, values=speed; titleText=[string(sprintf('Estimado | error mediano %.2f%%', ...
                    median(error(isfinite(error)))));string(sprintf('Cobertura %.1f%%',100*mean(r.valid_mask,'all')))];
            else, values=error; titleText="Error absoluto relativo (%)"; end
            im=imagesc(d.x_m*1e3,d.row_m*1e3,values); im.AlphaData=isfinite(values);
            ax.Color=[.83 .85 .88]; axis image; set(ax,'YDir','normal');
            if col<3, clim([1 3]); colormap(ax,turbo(256));
            else, clim([0 15]); colormap(ax,parula(256)); end
            colorbar; title(titleText,'FontSize',11,'Interpreter','none');
            xlabel('x (mm)'); ylabel('y (mm)');
        end
    end
    title(layout,'Validación independiente · SNR temporal 5 dB · semilla 101','FontSize',18);
    subtitle(layout,'Mapas sin suavizado. Gris: rechazo; cobertura incluye bordes. Color de error saturado a 15%.','FontSize',12);
    exportgraphics(fig,fullfile(here,'speed_examples.png'),'Resolution',160);close(fig);

    planes=["raster_offset_0p00mm","raster_offset_0p10mm","raster_offset_0p25mm"];
    planeLabels=["Superficie propuesta","+0,10 mm","+0,25 mm"];
    configs=["directional_phase_scalar2d","reverberant_scalar2d"];
    configLabels=["Direccional 0°","AIA planar"];
    fig=figure('Visible','off','Color','w','Position',[30 30 1400 930]);
    layout=tiledlayout(3,2,'Padding','compact','TileSpacing','compact');
    for row=1:3
        for col=1:2
            file=fullfile(here,'experimental_sensitivity',planes(row)+"_"+configs(col)+"_reference.mat");
            s=load(file); input=load(s.referenceManifest.source_plane_file,'data');
            d=input.data; r=s.reference;
            ax=nexttile; im=imagesc(d.x_m*1e3,d.row_m*1e3,r.speed_m_s);
            im.AlphaData=r.valid_mask; ax.Color=[.83 .85 .88]; axis image; set(ax,'YDir','normal');
            clim([1.5 3.5]);colormap(ax,turbo(256));colorbar;
            title([planeLabels(row)+" · "+configLabels(col);string(sprintf('Cobertura %.2f%%',100*mean(r.valid_mask,'all')))], ...
                'Interpreter','none','FontSize',11);xlabel('x (mm)');ylabel('y (mm)');
        end
    end
    title(layout,'Raster experimental · velocidades aceptadas (m/s) · intervalo 2–4 ms','FontSize',17);
    subtitle(layout,'Superficie y modo físico sin verificar. Gris: sin soporte; sin ground truth ni Young experimental.','FontSize',11);
    exportgraphics(fig,fullfile(here,'experimental_depth_maps.png'),'Resolution',160);close(fig);
    fprintf('VALIDATION_MAPS_EXPORTED\n');
end
