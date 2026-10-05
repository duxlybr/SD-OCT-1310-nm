function evaluate_sequential_fish(fixturePath, outputPath)
% Reproducible observational comparison; source fields remain independent.
% All parameters below were fixed before viewing the forward results.
    here=fileparts(mfilename('fullpath'));
    workflow=fileparts(fileparts(fileparts(here)));
    addpath(fullfile(workflow,'src'));
    if nargin<1
        fixturePath=fullfile(fileparts(here),'fish_forward','fish_individual_fields.mat');
    end
    if nargin<2, outputPath=here; end
    if ~isfolder(outputPath), mkdir(outputPath); end
    fixture=load(fixturePath); data=fixture.data8(:); n=numel(data);
    if n~=8, error('OCE:Observational:ExcitationCount','Expected eight separate acquisitions.'); end
    first=fixture.cases{1};
    truth=pick_field(fixture,first,{'truth_speed_m_s','truth_speed'});
    truthE=pick_field(fixture,first,{'truth_young_pa','truth_young'});
    frequency=1000; rho=1000; nu=.495;
    if isfield(first,'f_hz'), frequency=double(first.f_hz); end
    if isfield(first,'rho'), rho=double(first.rho); end
    if isfield(first,'nu'), nu=double(first.nu); end
    angles=0:45:315;
    local=struct('frequency_hz',frequency,'window_x_mm',1.2,'window_row_mm',1.2, ...
        'speed_range_m_s',[.5 5],'min_coherence',.65,'min_amplitude_fraction',.05, ...
        'min_support_fraction',.75,'fit_error_max',.30,'smoothing_mm',0, ...
        'directional_halfwidth_deg',35,'direction_deg',0);
    multi=struct('local_options',local,'min_consensus_count',3, ...
        'min_consensus_fraction',.5,'max_relative_slowness_deviation',.20);
    aia=local; aia.method="reverberant"; aia.reverb_model="scalar2d";
    aia.window_x_mm=2.4; aia.window_row_mm=2.4; aia.reverb_lag_mm=1.1; aia.fit_error_max=.20;
    frozen=struct('local',local,'fusion',multi,'aia',aia,'angles_deg',angles, ...
        'frequency_hz',frequency,'density_kg_m3',rho,'poisson_ratio',nu, ...
        'interpretation',"eight independent phase-incoherent experiments; no sum of wavefields");
    save(fullfile(outputPath,'frozen_estimator_settings.mat'),'frozen');
    truthMask=isfinite(truth)&truth>0;
    if isfield(first,'roi_mask'), truthMask=truthMask&logical(first.roi_mask); end
    products=struct('label',{},'speed_m_s',{},'valid_mask',{},'quality',{},'young_pa',{});
    summaries=struct([]); fused=cell(2,1); rows=struct([]);
    for family=1:2
        if family==1, method="phase_gradient"; else, method="directional_phase"; end
        per=cell(n,1);
        for source=1:n
            options=local; options.method=method; options.direction_deg=angles(source);
            per{source}=options;
        end
        multi.local_options=per;
        fitData=data;
        for source=1:n, fitData{source}=restrict_centers(data{source},local,truthMask); end
        fused{family}=oce.dispersion.estimateMultiExcitationSpeedMap(fitData,multi);
        c=NaN([size(truth),n]); q=zeros([size(truth),n]);
        for source=1:n
            result=fused{family}.per_excitation_results{source};
            label=sprintf('%s_excitation_%03d',method,angles(source));
            [products,rows]=append_product(products,rows,label,result,truth,truthE,truthMask,local,data{1},rho,nu);
            c(:,:,source)=result.speed_m_s; q(:,:,source)=result.quality;
        end
        available=sum(isfinite(c),3)>=4;
        baselineLabels=["arithmetic_speed_mean","speed_median","arithmetic_slowness_mean","slowness_median"];
        candidates=cell(4,1);
        candidates{1}=mean(c,3,'omitnan'); candidates{2}=median(c,3,'omitnan');
        candidates{3}=1./mean(1./c,3,'omitnan'); candidates{4}=1./median(1./c,3,'omitnan');
        common=fused{family}.valid_mask;
        for baseline=1:4
            speed=candidates{baseline}; speed(~available)=NaN;
            result=struct('speed_m_s',speed,'valid_mask',available,'quality',mean(q,3));
            label=method+"_"+baselineLabels(baseline);
            [products,rows]=append_product(products,rows,label,result,truth,truthE,truthMask,local,data{1},rho,nu);
            common=common&available;
        end
        [products,rows]=append_product(products,rows,method+"_robust_slowness",fused{family},truth,truthE,truthMask,local,data{1},rho,nu);
        common=common&truthMask;
        labels=[baselineLabels,"robust_slowness"];
        compare=[candidates;{fused{family}.speed_m_s}];
        for choice=1:5
            record=struct('method',method,'fusion',labels(choice), ...
                'common_support_count',nnz(common),'median_absolute_relative_speed_error', ...
                median(abs(compare{choice}(common)./truth(common)-1)), ...
                'median_absolute_relative_young_discrepancy', ...
                median(abs((2*rho*(1+nu)*compare{choice}(common).^2)./truthE(common)-1)));
            if isempty(summaries), summaries=record; else, summaries(end+1)=record; end %#ok<AGROW>
        end
        fprintf('DONE_FUSION_%s accepted%d\n',method,nnz(fused{family}.valid_mask));
    end
    aiaResults=cell(n,1);
    for source=1:n
        fitData=restrict_centers(data{source},aia,truthMask);
        aiaResults{source}=oce.dispersion.estimateLocalSpeedMap(fitData,aia);
        label=sprintf('aia_individual_excitation_%03d',angles(source));
        [products,rows]=append_product(products,rows,label,aiaResults{source},truth,truthE,truthMask,aia,data{1},rho,nu);
    end
    ensemble=ensemble_autocorrelation(aiaResults,data{1},aia);
    [products,rows]=append_product(products,rows,"sequential_ensemble_autocorrelation",ensemble,truth,truthE,truthMask,aia,data{1},rho,nu);
    metrics=struct2table(rows); commonSupport=struct2table(summaries);
    writetable(metrics,fullfile(outputPath,'fish_estimator_metrics.csv'));
    writetable(commonSupport,fullfile(outputPath,'fish_fusion_common_support.csv'));
    x_m=data{1}.x_m; row_m=data{1}.row_m;
    head_mask=logical(first.head_mask); tail_mask=logical(first.tail_mask);
    save(fullfile(outputPath,'fish_estimator_products.mat'),'products','fused','ensemble','metrics','commonSupport','frozen','truth','truthE','truthMask','head_mask','tail_mask','x_m','row_m','-v7.3');
    write_findings(outputPath,metrics,commonSupport);
    disp('SEQUENTIAL_FISH_EVALUATION_FINISHED');
end

function data=restrict_centers(data,options,roi)
    dx=mean(diff(data.x_m)); dy=mean(diff(data.row_m));
    hx=floor(options.window_x_mm*1e-3/(2*dx)+1e-12);
    hy=floor(options.window_row_mm*1e-3/(2*dy)+1e-12);
    kernel=ones(2*hy+1,2*hx+1);
    data.analysis_mask=roi & conv2(double(data.valid_mask),kernel,'same')==numel(kernel);
end

function value=pick_field(top,first,names)
    for index=1:numel(names)
        if isfield(top,names{index}), value=double(top.(names{index})); return; end
        if isfield(first,names{index}), value=double(first.(names{index})); return; end
    end
    error('OCE:Observational:FixtureContract','Missing truth field.');
end

function [products,rows]=append_product(products,rows,label,result,truth,truthE,roi,options,data,rho,nu)
    e=oce.elastography.invertYoungModulus(result.speed_m_s, ...
        struct('model',"bulk_shear",'density_kg_m3',rho,'poisson_ratio',nu));
    products(end+1)=struct('label',string(label),'speed_m_s',result.speed_m_s, ...
        'valid_mask',result.valid_mask,'quality',result.quality,'young_pa',e.young_pa);
    accepted=result.valid_mask&roi;
    dx=mean(diff(data.x_m)); dy=mean(diff(data.row_m));
    hx=floor(options.window_x_mm*1e-3/(2*dx)+1e-12);
    hy=floor(options.window_row_mm*1e-3/(2*dy)+1e-12);
    materialValues=unique(truthE(roi));
    pure=false(size(roi));
    for value=materialValues(:)'
        region=roi & truthE==value;
        kernel=ones(2*hy+1,2*hx+1);
        pure=pure|(conv2(double(region),kernel,'same')==numel(kernel));
    end
    core=accepted&pure;
    record=struct('label',string(label),'window_x_mm',options.window_x_mm, ...
        'window_row_mm',options.window_row_mm,'accepted_count',nnz(accepted), ...
        'material_roi_count',nnz(roi),'coverage_fraction',nnz(accepted)/nnz(roi), ...
        'speed_median_m_s',median(result.speed_m_s(accepted)), ...
        'median_absolute_relative_speed_error',median(abs(result.speed_m_s(accepted)./truth(accepted)-1)), ...
        'young_median_pa',median(e.young_pa(accepted)), ...
        'median_absolute_relative_young_discrepancy',median(abs(e.young_pa(accepted)./truthE(accepted)-1)), ...
        'pure_material_count',nnz(core), ...
        'pure_material_speed_error',median(abs(result.speed_m_s(core)./truth(core)-1)), ...
        'pure_material_young_discrepancy',median(abs(e.young_pa(core)./truthE(core)-1)));
    if isempty(rows), rows=record; else, rows(end+1)=record; end
end

function result=ensemble_autocorrelation(individual,data,options)
% Each C_j uses ONLY U_j(r)*conj(U_j(r+lag)). Average those normalized
% autocorrelations, not U_j across sources. This is observational: eight
% finite directions/reflections do not establish isotropic diffuse physics.
    n=numel(individual); shape=size(individual{1}.speed_m_s);
    geometry=individual{1}.diagnostics.realized_lag_geometry;
    lags=numel(individual{1}.diagnostics.radial_lag_m);
    sums=zeros([shape,lags]); counts=zeros([shape,lags]); available=zeros(shape);
    windows=individual{1}.diagnostics.window_samples;
    hr=(windows(1)-1)/2; hx=(windows(2)-1)/2;
    full=false(shape); full(1+hr:end-hr,1+hx:end-hx)=true;
    for source=1:n
        r=individual{source}; measured=isfinite(r.phasor);
        supported=measured&r.diagnostics.analysis_mask&full&r.diagnostics.support_fraction>=options.min_support_fraction;
        available=available+supported;
        usable=r.diagnostics.angular_coverage_fraction>=.75 & supported;
        observed=r.diagnostics.autocorrelation;
        sums=sums+observed.*usable; counts=counts+usable;
    end
    observed=sums./max(1,counts);
    omega=2*pi*options.frequency_hz;
    grid=logspace(log10(omega/options.speed_range_m_s(2)),log10(omega/options.speed_range_m_s(1)),160);
    template=zeros(lags,numel(grid)); denominator=accumarray(geometry(:,1),geometry(:,4),[lags,1]);
    for index=1:numel(grid)
        template(:,index)=accumarray(geometry(:,1),geometry(:,4).*besselj(0,geometry(:,2)*grid(index)),[lags,1])./max(realmin,denominator);
    end
    speed=NaN(shape); quality=zeros(shape); fitError=NaN(shape);
    for pixel=find(available>=4)'
        [row,col]=ind2sub(shape,pixel); count=reshape(counts(row,col,:),[],1);
        usable=count>=4; if nnz(usable)<3, continue; end
        value=reshape(observed(row,col,:),[],1); weight=count; weight(~usable)=0;
        weight=weight/sum(weight); cost=sum(weight.*(value-template).^2,1);
        [~,best]=min(cost); if best==1||best==numel(grid), continue; end
        fit=@(k) sum(weight.*(value-radial_template(k,geometry,lags)).^2);
        k=fminbnd(fit,grid(best-1),grid(best+1),optimset('Display','off','TolX',1e-5));
        fitError(pixel)=sqrt(fit(k)); curve=radial_template(k,geometry,lags);
        resolved=max(1-curve(usable))>=.15 && k*max(mean(diff(data.x_m)),mean(diff(data.row_m)))<.9*pi;
        if resolved&&fitError(pixel)<=options.fit_error_max
            speed(pixel)=omega/k; quality(pixel)=available(pixel)/n*(1-fitError(pixel)/options.fit_error_max);
        end
    end
    result=struct('speed_m_s',speed,'valid_mask',isfinite(speed),'quality',quality, ...
        'available_count',available,'autocorrelation',observed,'correlation_excitation_count',counts, ...
        'fit_error',fitError,'method',"observational equal-acquisition normalized autocorrelation ensemble", ...
        'interpretation',"finite eight-source directional ensemble; no cross-source phase products and no automatic isotropy guarantee");
end

function curve=radial_template(k,geometry,lags)
    curve=accumarray(geometry(:,1),geometry(:,4).*besselj(0,geometry(:,2)*k),[lags,1])./ ...
        max(realmin,accumarray(geometry(:,1),geometry(:,4),[lags,1]));
end

function write_findings(here,metrics,common)
    fid=fopen(fullfile(here,'hallazgos_fusion_secuencial.md'),'w'); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
    fprintf(fid,'# Ocho excitaciones individuales sobre dos inclusiones\n\n');
    fprintf(fid,'PG y sector direccional: ventana 1.2 mm, C >= .65, amplitud relativa .05, soporte .75, error circular <= .30 rad. Fusion: al menos cuatro de ocho, consenso relativo en lentitud <= 20 %%; amplitudes y fases globales no se suman.\n\n');
    fprintf(fid,'Young es aparente en interfaces y regiones dispersadas; el coeficiente material conocido no fija una velocidad de fase local exacta. Se conserva toda la cobertura rechazada como NaN. AIA secuencial promedia productos internos de cada experimento, con ventana 2.4 mm; no demuestra campo isotropico. No se interpreta cobertura mayor como exactitud.\n\n');
    fprintf(fid,'| Producto | Cobertura %% | Error velocidad %% | Discrepancia Young %% | Error velocidad material puro %% |\n|---|---:|---:|---:|---:|\n');
    for index=1:height(metrics)
        fprintf(fid,'| %s | %.2f | %.2f | %.2f | %.2f |\n',metrics.label(index),100*metrics.coverage_fraction(index), ...
            100*metrics.median_absolute_relative_speed_error(index),100*metrics.median_absolute_relative_young_discrepancy(index),100*metrics.pure_material_speed_error(index));
    end
    fprintf(fid,'\nComparaciones de fusion en soporte comun de cada familia:\n\n| Metodo | Fusion | Pixeles comunes | Error velocidad %% |\n|---|---|---:|---:|\n');
    for index=1:height(common)
        fprintf(fid,'| %s | %s | %d | %.2f |\n',common.method(index),common.fusion(index),common.common_support_count(index),100*common.median_absolute_relative_speed_error(index));
    end
end
