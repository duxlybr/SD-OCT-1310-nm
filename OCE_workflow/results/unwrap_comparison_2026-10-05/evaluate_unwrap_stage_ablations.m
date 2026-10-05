%% Stage ablations: raw optical unwrap and modal unwrap have separate owners.
here=fileparts(mfilename('fullpath'));wf=fileparts(fileparts(here));cd(wf);startup;
load(fullfile(here,'raw_phase_cases.mat'),'cases');
labels=cellfun(@(c)string(c.label),cases);
c=cases{find(contains(labels,'random_static_carrier'),1)};
load(fullfile(here,'luis3_bmode1_raw_phase.mat'),'raw');
methods=["sequential","least_squares_dct","tie_dct"];
domains=["temporal","temporal_depth"];
records=struct([]);products=cell(3,1);commonRecords=struct([]);iterationRecords=struct([]);
for source=1:3
    if source==1,native=c.exact_raw;sourceName="exact_xz";
    elseif source==2,native=c.fdtd_raw;sourceName="true_fdtd_xz";
    else,native=raw;sourceName="experimental_luis3";end
    [opts,score,modulus]=fixed_settings(c,native,source);
    sourceProducts=struct([]);temporalPlane=[];
    for domain=1:2
        dimensions=3;if domain==2,dimensions=[3 1];end
        for method=1:3
            [plane,ur,rawRmse]=raw_stage(native,source,methods(method),dimensions,8);
            if domain==1 && method==1,temporalPlane=plane;end
            frozen=opts;frozen.unwrap_method="sequential";frozen.unwrap_iterations=8;
            [r,product]=measure(plane,ur,rawRmse,score,modulus,c,source,sourceName, ...
                "raw_stage",domains(domain),methods(method),8,frozen);
            records=append(records,r);sourceProducts=append(sourceProducts,product);
            writetable(struct2table(records),fullfile(here,'unwrap_stage_ablation_metrics.csv'));
            fprintf('RAW_STAGE_ABLATION_DONE %s %s %s %d\n',sourceName,domains(domain),methods(method),r.accepted_pixels);
        end
    end
    % Hold raw optical unwrapping fixed, changing only mechanical modal unwrap.
    for method=1:3
        frozen=opts;frozen.unwrap_method=methods(method);frozen.unwrap_iterations=8;
        ur=temporalPlane.metadata.raw_unwrap;rawRmse=NaN;
        if source<3
            residual=double(temporalPlane.motion)-double(native.phase_truth_rad);
            residual=residual-mean(residual,3,'omitnan');
            valid=repmat(native.valid_mask,1,1,size(residual,3));rawRmse=sqrt(mean(residual(valid).^2,'omitnan'));
        end
        [r,product]=measure(temporalPlane,ur,rawRmse,score,modulus,c,source,sourceName, ...
            "modal_stage","temporal","sequential",8,frozen);
        records=append(records,r);sourceProducts=append(sourceProducts,product);
        writetable(struct2table(records),fullfile(here,'unwrap_stage_ablation_metrics.csv'));
        fprintf('MODAL_STAGE_ABLATION_DONE %s %s %d\n',sourceName,methods(method),r.accepted_pixels);
    end
    % Every TIE run executes its stated number of corrections, never early stop.
    for domain=1:2
        dimensions=3;if domain==2,dimensions=[3 1];end
        for budget=[4 8 12]
            [plane,ur,rawRmse]=raw_stage(native,source,"tie_dct",dimensions,budget);
            frozen=opts;frozen.unwrap_method="tie_dct";frozen.unwrap_iterations=budget;
            [r,product]=measure(plane,ur,rawRmse,score,modulus,c,source,sourceName, ...
                "tie_fixed_budget",domains(domain),"tie_dct",budget,frozen);
            records=append(records,r);sourceProducts=append(sourceProducts,product);
            writetable(struct2table(records),fullfile(here,'unwrap_stage_ablation_metrics.csv'));
            fprintf('FIXED_BUDGET_ABLATION_DONE %s %s %d %d\n',sourceName,domains(domain),budget,r.accepted_pixels);
        end
    end
    products{source}=sourceProducts;
    % Paired reductions report shared support, independently of global coverage.
    for domain=1:2
        selected=find(string({sourceProducts.stage})=="raw_stage" & string({sourceProducts.raw_domain})==domains(domain));
        common=score;
        for q=selected,common=common & sourceProducts(q).speed.valid_mask;end
        for q=selected
            p=sourceProducts(q);v=p.speed.speed_m_s(common);
            err=NaN;if source<3,err=100*median(abs(v/c.reference_speed_m_s-1),'omitnan');end
            cr=struct('source',sourceName,'raw_domain',domains(domain),'raw_method',p.raw_method, ...
                'modal_method',p.modal_method,'common_pixels',nnz(common), ...
                'common_speed_median_m_s',median(v,'omitnan'),'common_speed_error_pct',err);
            commonRecords=append(commonRecords,cr);
        end
        fixed=find(string({sourceProducts.stage})=="tie_fixed_budget" & string({sourceProducts.raw_domain})==domains(domain));
        anchor=fixed([sourceProducts(fixed).raw_iterations]==8);baseline=sourceProducts(anchor).speed;
        for q=fixed
            p=sourceProducts(q);common=score & baseline.valid_mask & p.speed.valid_mask;
            change=abs(p.speed.speed_m_s(common)./baseline.speed_m_s(common)-1)*100;
            ir=struct('source',sourceName,'raw_domain',domains(domain),'corrections_raw_and_modal',p.raw_iterations, ...
                'common_pixels_with_8',nnz(common),'accepted_mask_differences_with_8',nnz(xor(p.speed.valid_mask,baseline.valid_mask)), ...
                'median_relative_speed_change_with_8_pct',median(change,'omitnan'), ...
                'p95_relative_speed_change_with_8_pct',percentile95(change));
            iterationRecords=append(iterationRecords,ir);
        end
    end
    save(fullfile(here,'unwrap_stage_ablation_products.mat'),'products','records','commonRecords','iterationRecords','-v7.3');
end
writetable(struct2table(commonRecords),fullfile(here,'unwrap_stage_ablation_common_support.csv'));
writetable(struct2table(iterationRecords),fullfile(here,'unwrap_tie_iteration_stability.csv'));
% One supplementary experimental map shows the raw time-only comparison.
selected=find(string({products{3}.stage})=="raw_stage" & string({products{3}.raw_domain})=="temporal");
render_luis_maps(raw,products{3}(selected),wf);
disp('UNWRAP_STAGE_ABLATIONS_FINISHED');

function [opts,score,modulus]=fixed_settings(c,native,source)
    if source<3
        lambda=double(c.wavelength_m);[X,~]=meshgrid(native.x_m,native.row_m);
        score=X>=0 & X<=2.25*lambda;
        opts=struct('method',"phase_derivative_2d",'frequency_hz',double(c.frequency_hz), ...
            'window_x_mm',.5*lambda*1000,'window_row_mm',0,'pd_geometry',string(c.pd_geometry), ...
            'min_coherence',.65,'min_amplitude_fraction',.05,'min_support_fraction',.8, ...
            'fit_error_max',.30,'speed_range_m_s',[.2 8],'smoothing_mm',0, ...
            'directional_filter_enabled',false,'pd_polynomial_order',2);
        modulus=struct('model',string(c.model),'frequency_hz',double(c.frequency_hz), ...
            'density_kg_m3',double(c.density_kg_m3),'poisson_ratio',double(c.poisson_ratio), ...
            'thickness_m',double(c.thickness_m));
    else
        score=true(size(native.valid_mask));
        opts=struct('method',"phase_derivative_2d",'frequency_hz',1000,'window_x_mm',.9, ...
            'window_row_mm',.04,'pd_geometry',"lateral",'time_start_s',.002,'time_end_s',.004, ...
            'min_coherence',.2,'min_amplitude_fraction',.05,'min_support_fraction',.8, ...
            'fit_error_max',.3,'speed_range_m_s',[.2 20],'smoothing_mm',0, ...
            'directional_filter_enabled',false,'pd_polynomial_order',2);
        modulus=struct('model',"rayleigh",'frequency_hz',1000,'density_kg_m3',1000,'poisson_ratio',.495);
    end
end

function [plane,summary,rmse]=raw_stage(native,source,method,dimensions,budget)
    if source<3,wrapped=native.raw_phase_rad;else,wrapped=native.wrapped_phase;end
    nt=size(wrapped,3);mask=repmat(native.valid_mask,1,1,nt) & isfinite(wrapped);
    ur=oce.motion.unwrapPhase(wrapped,struct('method',method,'dimensions',dimensions, ...
        'iterations',budget,'valid_mask',mask));
    summary=rmfield(ur,'values');summary.performed=true;rmse=NaN;
    if source<3
        plane=rmfield(native,{'raw_phase_rad','phase_truth_rad'});plane.motion=ur.values;
        plane.metadata.raw_unwrap=summary;
        residual=ur.values-double(native.phase_truth_rad);residual=residual-mean(residual,3,'omitnan');
        rmse=sqrt(mean(residual(mask).^2,'omitnan'));
    else,plane=oce.acquisition.finalizeUnwrappedWavePlane(native,ur);end
end

function [r,p]=measure(plane,ur,rawRmse,score,modulus,c,source,sourceName,stage,domain,rawMethod,budget,opts)
    if source<3
        lambda=double(c.wavelength_m);hx=max(1,floor(opts.window_x_mm*1e-3/(2*mean(diff(plane.x_m)))+1e-10));
        far=double(c.source_distance_m)>=2*lambda;
        plane.analysis_mask=conv2(double(far),ones(1,2*hx+1),'same')==2*hx+1;
    end
    speed=oce.dispersion.estimateLocalSpeedMap(plane,opts);
    young=oce.elastography.invertYoungModulus(speed,modulus);
    v=score & speed.valid_mask;ev=v & young.valid_mask;
    cError=NaN;eError=NaN;caseName="luis3_bmode1";
    if source<3
        caseName=string(c.label);
        cError=100*median(abs(speed.speed_m_s(v)/c.reference_speed_m_s-1),'omitnan');
        eError=100*median(abs(young.young_pa(ev)./c.truth_young_pa(ev)-1),'omitnan');
    end
    r=struct('case_label',caseName,'source',sourceName,'stage',stage,'raw_domain',domain, ...
        'raw_method',rawMethod,'raw_iterations_requested',budget,'raw_iterations_executed',ur.iterations_executed, ...
        'modal_method',opts.unwrap_method,'modal_iterations_requested',opts.unwrap_iterations, ...
        'modal_iterations_executed',speed.diagnostics.modal_unwrap.iterations_executed, ...
        'input_pixels',nnz(plane.valid_mask),'score_pixels',nnz(score),'accepted_pixels',nnz(v), ...
        'coverage_pct',100*nnz(v)/nnz(score),'raw_phase_temporal_rmse_rad',rawRmse, ...
        'raw_wrap_consistency_rms_rad',ur.diagnostics.wrap_consistency_rms_rad, ...
        'speed_median_m_s',median(speed.speed_m_s(v),'omitnan'), ...
        'young_median_kpa',median(young.young_pa(ev),'omitnan')/1000, ...
        'speed_discrepancy_pct',cError,'young_discrepancy_pct',eError, ...
        'no_valid_reason',speed.diagnostics.no_valid_reason);
    p=struct('stage',stage,'raw_domain',domain,'raw_method',rawMethod,'raw_iterations',budget, ...
        'modal_method',opts.unwrap_method,'modal_iterations',opts.unwrap_iterations,'speed',speed,'young',young,'record',r);
end

function rows=append(rows,newRow)
    if isempty(rows),rows=newRow;else,rows(end+1)=newRow;end
end

function value=percentile95(x)
    if isempty(x),value=NaN;else,x=sort(x);value=x(max(1,ceil(.95*numel(x))));end
end

function render_luis_maps(raw,p,wf)
    fig=figure('Visible','off','Color','white','Position',[20 20 1500 1000]);
    lay=tiledlayout(fig,4,3,'Padding','compact','TileSpacing','compact');
    for row=1:4
        for j=1:3
            if row<=2,values=p(j).speed.speed_m_s;limits=[.2 10];units='m/s';
            else,values=p(j).young.young_pa/1000;limits=[0 120];units='kPa aparentes';end
            ax=nexttile(lay);im=imagesc(ax,raw.x_m*1000,raw.row_m*1000,values);
            im.AlphaData=isfinite(values);ax.YDir='reverse';ax.Color=[.85 .85 .85];colormap(ax,turbo);clim(ax,limits);
            if mod(row,2)==0,ylim(ax,[.18 .46]);end
            cb=colorbar(ax);cb.Label.String=units;xlabel(ax,'X (mm)');ylabel(ax,'Z (mm)');
            title(ax,p(j).raw_method+" optico | sequential modal",'Interpreter','none');
        end
    end
    title(lay,'Luis3 B-scan 1 | unwrap optico temporal | derivada lateral | registro completo y zoom');
    subtitle(lay,'Fase cruda -> unwrap temporal -> procesamiento. Parametros fijos 1000 Hz, 2–4 ms; TIE 8 correcciones. Young aparente Rayleigh, sin ground truth.');
    exportgraphics(fig,fullfile(wf,'results','Speed_Young_Maps', ...
        'experimental_unwrap_pd2d_luis3_temporal_only_speed_young.png'),'Resolution',160);close(fig);
end
