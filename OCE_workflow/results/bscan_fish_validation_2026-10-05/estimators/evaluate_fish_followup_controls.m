function evaluate_fish_followup_controls()
% Fixed-parameter second-noise and independent 0-degree grid probes.
    here=fileparts(mfilename('fullpath')); folder=fileparts(here);
    workflow=fileparts(fileparts(folder)); addpath(fullfile(workflow,'src'));
    primary=load(fullfile(here,'fish_estimator_products.mat'));
    secondary=load(fullfile(folder,'fish_forward','fish_individual_fields_noise2.mat'));
    frozen=primary.frozen; rows=struct([]); results=cell(2,1);
    for family=1:2
        if family==1, method="phase_gradient"; else, method="directional_phase"; end
        data=secondary.data8(:); local=cell(8,1);
        for source=1:8
            local{source}=frozen.local; local{source}.method=method;
            local{source}.direction_deg=frozen.angles_deg(source);
            data{source}=restrict_centers(data{source},local{source},primary.truthMask);
        end
        options=frozen.fusion; options.local_options=local;
        results{family}=oce.dispersion.estimateMultiExcitationSpeedMap(data,options);
        rows=append_metric(rows,"noise2_"+method,results{family},secondary.cases{1},frozen.local);
        common=primary.fused{family}.valid_mask&results{family}.valid_mask&primary.truthMask;
        rows(end).common_with_primary_count=nnz(common);
        rows(end).median_relative_speed_change_on_common=median(abs(results{family}.speed_m_s(common)./primary.fused{family}.speed_m_s(common)-1));
        save(fullfile(here,'fish_noise2_fusion_checkpoint.mat'),'results','rows','frozen','-v7.3');
        fprintf('NOISE2_DONE_%s\n',method);
    end
    metrics=struct2table(rows); writetable(metrics,fullfile(here,'fish_noise2_fusion_metrics.csv'));
    save(fullfile(here,'fish_noise2_fusion_products.mat'),'results','metrics','frozen','-v7.3');
    clear secondary data results;
    coarse=load(fullfile(folder,'fish_forward','fish_individual_fields.mat'),'cases');
    fine=load(fullfile(folder,'fish_forward','fish_grid_check_000deg.mat'),'cases');
    cases={coarse.cases{1},fine.cases{1}}; gridResults=cell(2,2); rows=struct([]); differences=struct([]);
    for grid=1:2
        c=cases{grid}; d=c.data; phi=c.forward_phasor;
        % Remove only the exported additive temporal noise. The independently
        % solved PDE phasor is retained, with its stated -omega*t convention.
        d.motion=real(phi.*reshape(exp(-1i*2*pi*frozen.frequency_hz*d.t_s),1,1,[]));
        for family=1:2
            if family==1, method="phase_gradient"; else, method="directional_phase"; end
            options=frozen.local; options.method=method; options.direction_deg=0;
            fitData=restrict_centers(d,options,logical(c.roi_mask));
            result=oce.dispersion.estimateLocalSpeedMap(fitData,options);
            gridResults{grid,family}=result;
            label=sprintf('noise_free_grid_%d_%s',grid,method);
            rows=append_metric(rows,label,result,c,options);
            rows(end).common_with_primary_count=NaN;
            rows(end).median_relative_speed_change_on_common=NaN;
        end
    end
    for family=1:2
        if family==1, method="phase_gradient"; else, method="directional_phase"; end
        [X,Y]=meshgrid(cases{1}.data.x_m,cases{1}.data.row_m);
        sampled=interp2(double(cases{2}.data.x_m(:)'),double(cases{2}.data.row_m(:)), ...
            gridResults{2,family}.speed_m_s,X,Y,'linear',NaN);
        common=gridResults{1,family}.valid_mask&isfinite(sampled)&logical(cases{1}.roi_mask);
        record=struct('method',method,'common_nominal_grid_pixels',nnz(common), ...
            'median_absolute_relative_speed_difference',median(abs(sampled(common)./gridResults{1,family}.speed_m_s(common)-1)), ...
            'p95_absolute_relative_speed_difference',prctile(abs(sampled(common)./gridResults{1,family}.speed_m_s(common)-1),95), ...
            'scope',"0-degree independent noise-free forward fields; native fitting then interpolation for comparison only");
        if isempty(differences), differences=record; else, differences(end+1)=record; end %#ok<AGROW>
    end
    gridMetrics=struct2table(rows); gridDifferences=struct2table(differences);
    writetable(gridMetrics,fullfile(here,'fish_grid_estimator_metrics.csv'));
    writetable(gridDifferences,fullfile(here,'fish_grid_common_support.csv'));
    save(fullfile(here,'fish_grid_estimator_products.mat'),'gridResults','gridMetrics','gridDifferences','frozen','-v7.3');
    disp(metrics); disp(gridMetrics); disp(gridDifferences);
    disp('FISH_FOLLOWUP_CONTROLS_FINISHED');
end

function data=restrict_centers(data,options,roi)
    dx=mean(diff(data.x_m)); dy=mean(diff(data.row_m));
    hx=floor(options.window_x_mm*1e-3/(2*dx)+1e-12); hy=floor(options.window_row_mm*1e-3/(2*dy)+1e-12);
    kernel=ones(2*hy+1,2*hx+1);
    data.analysis_mask=roi & (conv2(double(data.valid_mask),kernel,'same')==numel(kernel));
end

function rows=append_metric(rows,label,result,c,options)
    truth=double(c.truth_speed); young=double(c.truth_young_pa); roi=logical(c.roi_mask);
    physics=struct('model',"bulk_shear",'density_kg_m3',1000,'poisson_ratio',.495);
    e=oce.elastography.invertYoungModulus(result.speed_m_s,physics);
    valid=result.valid_mask&roi;
    dx=mean(diff(c.data.x_m)); dy=mean(diff(c.data.row_m));
    hx=floor(options.window_x_mm*1e-3/(2*dx)+1e-12); hy=floor(options.window_row_mm*1e-3/(2*dy)+1e-12);
    kernel=ones(2*hy+1,2*hx+1);
    pure=conv2(double(young==24000),kernel,'same')==numel(kernel);
    head=valid&pure&logical(c.head_mask); tail=valid&pure&logical(c.tail_mask);
    record=struct('label',string(label),'dx_m',dx,'window_samples_x',2*hx+1, ...
        'realized_window_span_x_m',2*hx*dx,'coverage_fraction',nnz(valid)/nnz(roi), ...
        'median_absolute_relative_speed_error',median(abs(result.speed_m_s(valid)./truth(valid)-1)), ...
        'median_absolute_relative_young_discrepancy',median(abs(e.young_pa(valid)./young(valid)-1)), ...
        'head_core_count',nnz(head),'tail_core_count',nnz(tail), ...
        'head_core_young_discrepancy',median(abs(e.young_pa(head)/24000-1)), ...
        'tail_core_young_discrepancy',median(abs(e.young_pa(tail)/24000-1)), ...
        'common_with_primary_count',NaN,'median_relative_speed_change_on_common',NaN);
    if isempty(rows), rows=record; else, rows(end+1)=record; end
end
