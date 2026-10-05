function report=run_frequency_detuning_probe(outputDirectory)
%RUN_FREQUENCY_DETUNING_PROBE Independent requested-frequency sensitivity.
% Run after run_speed_robustness_validation. The clean signal always remains
% at 1000 Hz; only the supplied estimator frequency changes.
    if nargin<1, outputDirectory=fileparts(mfilename('fullpath')); end
    loaded=load(fullfile(outputDirectory,'validation_settings.mat'),'settings'); settings=loaded.settings;
    trueFrequency=settings.frequency_hz; trueSpeed=settings.truth_speed_m_s;
    [X,Y]=meshgrid(settings.x_m,settings.row_m);
    phasor=exp(-1i*2*pi*trueFrequency/trueSpeed*(X*cosd(settings.propagation_angle_deg)+Y*sind(settings.propagation_angle_deg)));
    motion=real(phasor.*reshape(exp(1i*2*pi*trueFrequency*settings.t_s),1,1,[]));
    rng(5171009,'twister'); motion=motion+sqrt(mean(motion.^2,'all'))*10^(-10/20)*randn(size(motion));
    data=struct('motion',motion,'x_m',settings.x_m,'row_m',settings.row_m, ...
        't_s',settings.t_s,'valid_mask',true(size(X)),'plane_type',"enface");
    records=cell(0,1); products=cell(0,1);
    for frequency=[900 950 1000 1050 1100]
        for method=["phase_gradient","directional_phase","reverberant"]
            options=settings.options; options.frequency_hz=frequency; options.method=method;
            result=oce.dispersion.estimateLocalSpeedMap(data,options);
            values=result.speed_m_s(result.valid_mask); error=values/trueSpeed-1;
            row=struct('true_frequency_hz',trueFrequency,'supplied_frequency_hz',frequency, ...
                'method',method,'snr_db',10,'seed',5171009,'true_speed_m_s',trueSpeed, ...
                'accepted_pixels',numel(values),'coverage_pct',100*numel(values)/numel(result.valid_mask), ...
                'median_speed_m_s',NaN,'bias_pct',NaN,'median_absolute_error_pct',NaN, ...
                'median_temporal_coherence',median(result.diagnostics.temporal_coherence,'all'), ...
                'window_row_samples',result.diagnostics.window_samples(1), ...
                'window_x_samples',result.diagnostics.window_samples(2));
            if ~isempty(values)
                row.median_speed_m_s=median(values); row.bias_pct=100*median(error);
                row.median_absolute_error_pct=100*median(abs(error));
            end
            records{end+1}=row; products{end+1}=result; %#ok<AGROW>
        end
    end
    report=struct2table(vertcat(records{:}));
    writetable(report,fullfile(outputDirectory,'frequency_detuning_probe.csv'));
    save(fullfile(outputDirectory,'frequency_detuning_raw_maps.mat'),'data','products','report','settings','-v7.3');
    % Persist measured algorithm footprint, not just the requested mm value.
    settings.realized_window_samples=products{1}.diagnostics.window_samples;
    settings.realized_window_span_m=(settings.realized_window_samples-1).* ...
        [mean(diff(settings.row_m)),mean(diff(settings.x_m))];
    settings.realized_time_sample_count=products{1}.diagnostics.time_sample_count;
    settings.realized_time_span_s=settings.t_s(end)-settings.t_s(1);
    settings.realized_reverb_lag_m=products{3}.diagnostics.radial_lag_m;
    settings.realized_maximum_full_window_coverage_pct=100* ...
        prod([numel(settings.row_m),numel(settings.x_m)]-settings.realized_window_samples+1)/numel(X);
    save(fullfile(outputDirectory,'validation_settings.mat'),'settings');
    trials=readtable(fullfile(outputDirectory,'speed_robustness_trials.csv'));
    trials.window_row_samples=repmat(settings.realized_window_samples(1),height(trials),1);
    trials.window_x_samples=repmat(settings.realized_window_samples(2),height(trials),1);
    trials.time_sample_count=repmat(settings.realized_time_sample_count,height(trials),1);
    trials.window_row_span_mm=repmat(settings.realized_window_span_m(1)*1000,height(trials),1);
    trials.window_x_span_mm=repmat(settings.realized_window_span_m(2)*1000,height(trials),1);
    writetable(trials,fullfile(outputDirectory,'speed_robustness_trials.csv'));
    destination=fullfile(outputDirectory,'hallazgos_velocidad.md'); fid=fopen(destination,'a','n','UTF-8');
    cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
    fprintf(fid,'\n## Frecuencia introducida y soporte realizado\n\n');
    fprintf(fid,'La ventana efectivamente realizada es %d x %d muestras, extension entre extremos %.2f x %.2f mm; ', ...
        settings.realized_window_samples,settings.realized_window_span_m*1000);
    fprintf(fid,'%.2f %% es la cobertura maxima con una ventana completa en esta malla. Se utilizan %d muestras temporales, ', ...
        settings.realized_maximum_full_window_coverage_pct,settings.realized_time_sample_count);
    fprintf(fid,'duracion %.2f ms y %.2f ciclos fisicos; retardos AIA realizados: %.2f a %.2f mm.\n\n', ...
        settings.realized_time_span_s*1000,trueFrequency*settings.realized_time_span_s, ...
        min(settings.realized_reverb_lag_m)*1000,max(settings.realized_reverb_lag_m)*1000);
    fprintf(fid,'Se mantiene una onda verdadera de 1000 Hz y 2 m/s, con SNR 10 dB y semilla 5171009; ');
    fprintf(fid,'solo cambia la frecuencia introducida al estimador. Este control no calibra la frecuencia experimental.\n\n');
    fprintf(fid,'| Frecuencia introducida Hz | Metodo | Sesgo %% | Error mediano %% | Cobertura %% |\n|---:|---|---:|---:|---:|\n');
    for index=1:height(report)
        row=report(index,:); fprintf(fid,'| %.0f | %s | %.2f | %.2f | %.2f |\n', ...
            row.supplied_frequency_hz,row.method,row.bias_pct,row.median_absolute_error_pct,row.coverage_pct);
    end
    fprintf(fid,'\nLa relacion c=omega/k introduce sensibilidad directa a la frecuencia asumida. ');
    fprintf(fid,'Coherencia alta y cobertura estable no sustituyen un valor correcto de frecuencia. ');
    fprintf(fid,'Reproducir: startup; addpath(esta carpeta); run_speed_robustness_validation; run_frequency_detuning_probe.\n');
    disp(report);
end
