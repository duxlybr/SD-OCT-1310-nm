function report = evaluate_elastography_estimators(caseFile, resultsDirectory)
%EVALUATE_ELASTOGRAPHY_ESTIMATORS Compare local maps with independent truth.
% caseFile: MAT produced by export_simulator_wave_cases.py; contains cases.
% Writes CSV metrics and raw result MAT. Coverage accompanies error because
% rejection can reduce error by discarding the difficult parts of a phantom.
% Simulator FDTD truth/model and analytic cases must be interpreted separately.
    if nargin < 2, resultsDirectory=fullfile(tempdir,'codex_oce_benchmark'); end
    workflowRoot=fileparts(fileparts(mfilename('fullpath')));
    run(fullfile(workflowRoot,'startup.m'));
    loaded=load(caseFile,'cases');
    assert(isfield(loaded,'cases'),'Expected cases in fixture MAT.');
    cases=loaded.cases; if ~iscell(cases), cases=num2cell(cases); end
    if ~isfolder(resultsDirectory), mkdir(resultsDirectory); end
    records=cell(0,1); products=cell(numel(cases),1);
    for index=1:numel(cases)
        c=cases{index}; data=c.data;
        data.plane_type=string(data.plane_type);
        data.valid_mask=logical(data.valid_mask);
        opts=struct('frequency_hz',double(c.f_hz),'window_x_mm',2.5, ...
            'window_row_mm',2.5,'speed_range_m_s',[0.2 6], ...
            'min_coherence',0.35,'min_amplitude_fraction',0.04, ...
            'min_support_fraction',0.75,'smoothing_mm',0, ...
            'direction_deg',0,'directional_halfwidth_deg',35, ...
            'reverb_model',"scalar2d",'reverb_lag_mm',1, 'fit_error_max',0.3);
        if isfield(c,'direction_deg'), opts.direction_deg=double(c.direction_deg); end
        if isfield(c,'reverb_model'), opts.reverb_model=string(c.reverb_model); end
        if isfield(c,'window_m')
            opts.window_x_mm=double(c.window_m)*1000;
            opts.window_row_mm=double(c.window_m)*1000;
        end
        products{index}=struct('label',string(c.label),'methods',struct());
        for method=["phase_gradient","directional_phase","reverberant"]
            opts.method=method;
            result=oce.dispersion.estimateLocalSpeedMap(data,opts);
            products{index}.methods.(method)=result;
            record=measure(c,method,result.speed_m_s);
            baseline="old_phase_gradient";
            if method=="reverberant"
                baseline="old_reverberant_normalized";
                if opts.reverb_model=="shear3d", baseline="old_reverberant_3d_normalized"; end
            end
            if isfield(c,baseline)
                old=c.(baseline);
                common=isfinite(result.speed_m_s)&isfinite(old)&isfinite(c.truth_speed)& ...
                    c.truth_speed>0&logical(c.data.valid_mask);
                record.paired_baseline=baseline; record.common_support_pixels=nnz(common);
                if any(common,'all')
                    record.common_absolute_error_pct=100*median(abs(result.speed_m_s(common)./c.truth_speed(common)-1));
                    record.baseline_common_absolute_error_pct=100*median(abs(old(common)./c.truth_speed(common)-1));
                end
            end
            records{end+1}=record; %#ok<AGROW>
        end
        caseFields=string(fieldnames(c))';
        oldFields=caseFields(startsWith(caseFields,"old_")&~contains(caseFields,"young"));
        for method=oldFields
            if isfield(c,method), records{end+1}=measure(c,method,c.(method)); end %#ok<AGROW>
        end
        model=string(c.model); if model=="lamb_a0", model="lamb_a0_free"; end
        inversionOpts=struct('model',model,'density_kg_m3',double(c.density_kg_m3), ...
            'poisson_ratio',double(c.poisson_ratio),'thickness_m',double(c.thickness_m), ...
            'frequency_hz',double(c.f_hz),'max_kh',0.5);
        % Inversion-only comparison removes speed-estimator error.
        inversion=oce.elastography.invertYoungModulus(c.truth_speed,inversionOpts);
        products{index}.inversion_of_truth=inversion;
        products{index}.inversion_options=inversionOpts;
        products{index}.truth_speed=c.truth_speed;
        if isfield(c,'truth_young')
            accepted=isfinite(inversion.young_pa)&isfinite(c.truth_young)&c.truth_young>0;
            if any(accepted,'all')
                products{index}.young_median_relative_error=median(abs( ...
                    inversion.young_pa(accepted)./c.truth_young(accepted)-1));
            else
                products{index}.young_median_relative_error=NaN;
            end
        end
        fprintf('%s: %d/%d finite truth pixels\n',string(c.label), ...
            nnz(isfinite(c.truth_speed)),numel(c.truth_speed));
    end
    report=struct2table(vertcat(records{:}));
    writetable(report,fullfile(resultsDirectory,'estimator_metrics.csv'));
    save(fullfile(resultsDirectory,'estimator_products.mat'),'products','report','-v7.3');
    disp(report);
end

function row=measure(c,method,map)
    truth=double(c.truth_speed); measured=double(map);
    support=isfinite(truth)&truth>0&logical(c.data.valid_mask);
    accepted=support&isfinite(measured)&measured>0;
    errorFraction=measured(accepted)./truth(accepted)-1;
    row=struct('case_name',string(c.label),'method',string(method), ...
        'coverage_pct',100*nnz(accepted)/max(1,nnz(support)), ...
        'accepted_pixels',nnz(accepted),'median_speed_m_s',NaN, ...
        'bias_pct',NaN,'median_absolute_error_pct',NaN,'relative_rmse_pct',NaN, ...
        'paired_baseline',"",'common_support_pixels',0,'common_absolute_error_pct',NaN, ...
        'baseline_common_absolute_error_pct',NaN);
    if ~isempty(errorFraction)
        row.median_speed_m_s=median(measured(accepted));
        row.bias_pct=100*median(errorFraction);
        row.median_absolute_error_pct=100*median(abs(errorFraction));
        row.relative_rmse_pct=100*sqrt(mean(errorFraction.^2));
    end
end
