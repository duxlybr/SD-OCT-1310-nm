function metrics=estimate_scalar_helmholtz_maps(outputDirectory,suffix)
%ESTIMATE_SCALAR_HELMHOLTZ_MAPS Observational scalar forward-solver audit.
% Saves raw maps and background/core/interface metrics outside the PNG gallery.
    if nargin<1, outputDirectory=fileparts(mfilename('fullpath')); end
    if nargin<2, suffix=""; end
    artifactName="scalar_helmholtz"+string(suffix);
    workflowRoot=fileparts(fileparts(fileparts(outputDirectory)));
    run(fullfile(workflowRoot,'startup.m'));
    loaded=load(fullfile(outputDirectory,artifactName+"_fields.mat"),'cases');
    records={}; maps=cell(size(loaded.cases));
    for index=1:numel(loaded.cases)
        c=loaded.cases{index}; c.data.valid_mask=logical(c.data.valid_mask);
        opts=struct('frequency_hz',double(c.f_hz),'method',"reverberant", ...
            'window_x_mm',2.4,'window_row_mm',2.4,'reverb_model',"scalar2d", ...
            'reverb_lag_mm',0.9,'speed_range_m_s',[0.8 4], ...
            'min_coherence',0.35,'min_amplitude_fraction',0.015, ...
            'min_support_fraction',0.75,'fit_error_max',0.35,'smoothing_mm',0);
        speed=oce.dispersion.estimateLocalSpeedMap(c.data,opts);
        young=oce.elastography.invertYoungModulus(speed,struct('model',"bulk_shear", ...
            'density_kg_m3',double(c.density_kg_m3),'poisson_ratio',double(c.poisson_ratio)));
        maps{index}=struct('label',string(c.label),'speed',speed,'young',young);
        for region=["core","background","interface","farfield"]
            support=logical(c.(region+"_mask")); accepted=support&speed.valid_mask;
            speedError=100*(speed.speed_m_s(accepted)./c.truth_speed(accepted)-1);
            youngError=100*(young.young_pa(accepted)./c.truth_young(accepted)-1);
            row=struct('case_name',string(c.label),'region',region,'truth_pixels',nnz(support), ...
                'accepted_pixels',nnz(accepted),'coverage_pct',100*nnz(accepted)/max(1,nnz(support)), ...
                'speed_median_m_s',median(speed.speed_m_s(accepted),'omitnan'), ...
                'speed_bias_pct',median(speedError,'omitnan'), ...
                'speed_median_abs_error_pct',median(abs(speedError),'omitnan'), ...
                'young_median_kpa',median(young.young_pa(accepted)/1000,'omitnan'), ...
                'young_bias_pct',median(youngError,'omitnan'), ...
                'young_median_abs_error_pct',median(abs(youngError),'omitnan'));
            records{end+1,1}=row; %#ok<AGROW>
        end
        fprintf('%s completed; map coverage %.2f %%\n',string(c.label),100*nnz(speed.valid_mask)/numel(speed.valid_mask));
    end
    metrics=struct2table(vertcat(records{:}));
    writetable(metrics,fullfile(outputDirectory,artifactName+"_metrics.csv"));
    % Save ordinary v7 maps without the full motion tensor for Python rendering.
    save(fullfile(outputDirectory,artifactName+"_maps.mat"),'maps','-v7');
    disp(metrics);
end
