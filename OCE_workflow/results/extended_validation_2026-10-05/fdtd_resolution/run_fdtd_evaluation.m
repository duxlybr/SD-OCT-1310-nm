function run_fdtd_evaluation()
% Reproducible observational sensitivity: no production defaults are edited.
    here=fileparts(mfilename('fullpath'));
    workflow=fileparts(fileparts(fileparts(here)));
    run(fullfile(workflow,'startup.m'));
    addpath(fullfile(workflow,'workflows'));
    evaluate_elastography_estimators(fullfile(here,'fdtd_cases.mat'),here);
    loaded=load(fullfile(here,'fdtd_cases.mat'),'cases'); cases=loaded.cases;
    loaded=load(fullfile(here,'estimator_products.mat'),'products'); products=loaded.products;
    methods=["phase_gradient","directional_phase","reverberant"];
    referenceIndex=3; records=cell(0,1);
    for index=1:numel(cases)
        c=cases{index}; d=c.data;
        for method=methods
            current=products{index}.methods.(method);
            fine=products{referenceIndex}.methods.(method);
            fd=cases{referenceIndex}.data;
            % Interpolation is exclusively for comparison at common physical
            % coordinates. NaNs propagate; this never fills an output map.
            fineInterpolator=griddedInterpolant({fd.row_m(:),fd.x_m(:)},fine.speed_m_s,'linear','none');
            [X,Y]=meshgrid(d.x_m,d.row_m); fineAtCurrent=fineInterpolator(Y,X);
            common=isfinite(current.speed_m_s)&isfinite(fineAtCurrent)&isfinite(c.truth_speed);
            delta=100*(current.speed_m_s(common)./fineAtCurrent(common)-1);
            truthSupport=isfinite(c.truth_speed)&d.valid_mask;
            accepted=current.valid_mask&truthSupport;
            inversion=oce.elastography.invertYoungModulus(current, ...
                struct('model',"rayleigh",'density_kg_m3',double(c.density_kg_m3), ...
                'poisson_ratio',double(c.poisson_ratio)));
            records{end+1}=struct('case_name',string(c.label),'method',method, ...
                'cell_mm',1000*d.metadata.fdtd_cell_m,'courant',d.metadata.courant, ...
                'coverage_pct',100*nnz(accepted)/nnz(truthSupport), ...
                'median_speed_m_s',median(current.speed_m_s(accepted),'omitnan'), ...
                'median_young_pa',median(inversion.young_pa(accepted),'omitnan'), ...
                'common_coordinate_count',nnz(common), ...
                'median_signed_difference_to_0p10mm_pct',median(delta,'omitnan'), ...
                'median_absolute_difference_to_0p10mm_pct',median(abs(delta),'omitnan'), ...
                'rms_difference_to_0p10mm_pct',sqrt(mean(delta.^2,'omitnan')), ...
                'reference_case',string(cases{referenceIndex}.label)); %#ok<AGROW>
        end
    end
    comparison=struct2table(vertcat(records{:}));
    writetable(comparison,fullfile(here,'mesh_common_coordinates.csv'));
    fig=figure('Visible','off','Color','w','Position',[50 50 1200 750]);
    layout=tiledlayout(2,2,'Padding','compact');
    for i=1:numel(cases)
        nexttile; d=cases{i}.data; r=products{i}.methods.directional_phase;
        im=imagesc(d.x_m*1000,d.row_m*1000,r.speed_m_s); im.AlphaData=r.valid_mask;
        set(gca,'Color',[.8 .8 .8]); axis image; clim([1.5 2.3]); colorbar;
        xlabel('x (mm)'); ylabel('y (mm)');
        title(string(cases{i}.label),'Interpreter','none');
    end
    title(layout,'Velocidad direccional FDTD (m/s); referencia continua 1.9126 m/s');
    exportgraphics(fig,fullfile(here,'directional_maps.png'),'Resolution',150); close(fig);
    disp(comparison); fprintf('FDTD_EVALUATION_FINISHED\n');
end
