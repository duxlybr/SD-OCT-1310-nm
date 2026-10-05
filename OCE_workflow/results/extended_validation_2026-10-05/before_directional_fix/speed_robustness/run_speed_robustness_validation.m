function outputs = run_speed_robustness_validation(outputDirectory)
%RUN_SPEED_ROBUSTNESS_VALIDATION Reproducible observational stochastic audit.
% This is a Results artifact, not a maintained test or a golden baseline.
% Run from OCE_workflow after startup, then add this folder to the path.
% Independent analytic plane-wave superpositions provide known SI speed.
% Temporal white Gaussian noise is scaled by global clean-signal RMS.
% No invalid pixel is filled and accepted error is always paired with coverage.

    if nargin<1, outputDirectory=fileparts(mfilename('fullpath')); end
    if ~isfolder(outputDirectory), mkdir(outputDirectory); end
    settings=struct('seeds',[101 307 619 941],'snr_db',[Inf 20 10 5 0], ...
        'case_names',["planar","strong_reflection","scalar2d_diffuse","axial_shear3d_xy"], ...
        'frequency_hz',1000,'truth_speed_m_s',2,'x_m',(0:60)*100e-6, ...
        'row_m',(0:60)*100e-6,'t_s',(0:79)*50e-6, ...
        'spatial_wave_count_scalar',192,'spatial_wave_count_shear3d',384, ...
        'reflection_amplitude',0.85,'reflection_phase_rad',0.73, ...
        'propagation_angle_deg',27,'time_convention',"motion = real(P exp(+i omega t))", ...
        'noise_definition',"global clean motion RMS / temporal Gaussian noise standard deviation", ...
        'support_definition',"all measured finite truth pixels; spatial window edges count as rejected", ...
        'wavefield_assumptions',"analytic homogeneous scalar2D or isotropic bulk3D; no FDTD, OCT reconstruction or constitutive inference");
    settings.options=struct('frequency_hz',settings.frequency_hz, ...
        'window_x_mm',2.4,'window_row_mm',2.4,'speed_range_m_s',[0.5 6], ...
        'min_coherence',0.45,'min_amplitude_fraction',0.04, ...
        'min_support_fraction',0.75,'smoothing_mm',0, ...
        'direction_deg',settings.propagation_angle_deg,'directional_halfwidth_deg',35, ...
        'reverb_model',"scalar2d",'reverb_lag_mm',1,'fit_error_max',0.25);
    save(fullfile(outputDirectory,'validation_settings.mat'),'settings');
    records=cell(0,1); selected=cell(0,1); trial=0;
    started=tic;
    for seed=settings.seeds
        for caseName=settings.case_names
            clean=make_field(caseName,seed,settings);
            for snr=settings.snr_db
                trial=trial+1; noiseSeed=seed*1000+trial;
                [data,sigma]=make_data(clean,snr,noiseSeed,settings);
                [rows,products]=evaluate_trial(data,caseName,seed,snr,"full_support", ...
                    sigma,trial,"main",settings);
                records=[records; rows]; %#ok<AGROW>
                if seed==settings.seeds(1) && (isinf(snr)||snr==5)
                    selected{end+1}=struct('trial_id',trial,'case_name',caseName, ...
                        'seed',seed,'snr_db',snr,'data',data,'products',{products}); %#ok<AGROW>
                end
                fprintf('main %d/80 %s seed %d SNR %.0f elapsed %.1fs\n', ...
                    trial,caseName,seed,snr,toc(started));
            end
        end
    end
    % Additional measured gaps: identical input for all three methods.
    for seed=settings.seeds
        for caseName=["planar","strong_reflection"]
            clean=make_field(caseName,seed,settings);
            trial=trial+1; [data,sigma]=make_data(clean,10,seed*2000+trial,settings);
            data.valid_mask(25:33,25:33)=false;
            data.valid_mask(15:45,39:40)=false;
            rng(seed+791,'twister'); data.valid_mask(rand(size(data.valid_mask))<0.04)=false;
            [rows,products]=evaluate_trial(data,caseName,seed,10,"block_stripe_4pct_gaps", ...
                sigma,trial,"gaps",settings);
            records=[records; rows]; %#ok<AGROW>
            if seed==settings.seeds(1)
                selected{end+1}=struct('trial_id',trial,'case_name',caseName, ...
                    'seed',seed,'snr_db',10,'data',data,'products',{products}); %#ok<AGROW>
            end
        end
    end
    % Null controls report accepted pixels as false positives, not accuracy.
    for seed=settings.seeds
        trial=trial+1; rng(seed*3001,'twister');
        null=zeros(numel(settings.row_m),numel(settings.x_m));
        [data,~]=make_data(null,Inf,seed,settings); data.motion=randn(size(data.motion));
        [rows,products]=evaluate_trial(data,"noise_only",seed,NaN,"full_support", ...
            1,trial,"null",settings); records=[records;rows]; %#ok<AGROW>
        if seed==settings.seeds(1)
            selected{end+1}=struct('trial_id',trial,'case_name',"noise_only", ...
                'seed',seed,'snr_db',NaN,'data',data,'products',{products}); %#ok<AGROW>
        end
        for snr=[Inf 10 0]
            trial=trial+1;
            [data,sigma]=make_data(ones(size(null)),snr,seed*4001+trial,settings);
            [rows,products]=evaluate_trial(data,"uniform_harmonic",seed,snr,"full_support", ...
                sigma,trial,"null",settings); records=[records;rows]; %#ok<AGROW>
            if seed==settings.seeds(1) && isinf(snr)
                selected{end+1}=struct('trial_id',trial,'case_name',"uniform_harmonic", ...
                    'seed',seed,'snr_db',snr,'data',data,'products',{products}); %#ok<AGROW>
            end
        end
        fprintf('controls seed %d elapsed %.1fs\n',seed,toc(started));
    end
    trials=struct2table(vertcat(records{:}));
    aggregates=aggregate_trials(trials);
    guards=probe_input_guards(settings);
    writetable(trials,fullfile(outputDirectory,'speed_robustness_trials.csv'));
    writetable(aggregates,fullfile(outputDirectory,'speed_robustness_aggregate.csv'));
    writetable(guards,fullfile(outputDirectory,'speed_input_guards.csv'));
    save(fullfile(outputDirectory,'selected_raw_maps.mat'),'selected','settings','-v7.3');
    save(fullfile(outputDirectory,'speed_validation_summary.mat'),'trials','aggregates','guards','settings');
    write_findings(outputDirectory,aggregates,guards,settings,toc(started));
    outputs=struct('trials',trials,'aggregates',aggregates,'guards',guards, ...
        'output_directory',string(outputDirectory),'elapsed_s',toc(started));
    fprintf('DONE %d realizations / %d method runs; %.1fs\n',trial,height(trials),toc(started));
end

function phasor=make_field(caseName,seed,settings)
    rng(seed,'twister'); [X,Y]=meshgrid(settings.x_m,settings.row_m);
    k=2*pi*settings.frequency_hz/settings.truth_speed_m_s;
    phase=-k*(X*cosd(settings.propagation_angle_deg)+Y*sind(settings.propagation_angle_deg));
    if caseName=="planar"
        phasor=exp(1i*phase);
    elseif caseName=="strong_reflection"
        phasor=exp(1i*phase)+settings.reflection_amplitude*exp(-1i*phase+1i*settings.reflection_phase_rad);
    elseif caseName=="scalar2d_diffuse"
        phasor=zeros(size(X));
        for wave=1:settings.spatial_wave_count_scalar
            angle=2*pi*(wave-1)/settings.spatial_wave_count_scalar;
            phasor=phasor+exp(1i*(-k*(X*cos(angle)+Y*sin(angle))+2*pi*rand));
        end
    else
        phasor=zeros(size(X));
        for wave=1:settings.spatial_wave_count_shear3d
            nz=2*rand-1; angle=2*pi*rand; transverse=sqrt(1-nz^2);
            nx=transverse*cos(angle); ny=transverse*sin(angle);
            % For isotropic transverse bulk waves the axial covariance
            % weights orientation by the squared axial polarization.
            phasor=phasor+transverse*exp(1i*(-k*(nx*X+ny*Y)+2*pi*rand));
        end
    end
    phasor=phasor/sqrt(mean(abs(phasor).^2,'all'));
end

function [data,sigma]=make_data(phasor,snr,noiseSeed,settings)
    motion=real(phasor.*reshape(exp(1i*2*pi*settings.frequency_hz*settings.t_s),1,1,[]));
    sigma=0;
    if isfinite(snr)
        sigma=sqrt(mean(motion.^2,'all'))*10^(-snr/20);
        rng(noiseSeed,'twister'); motion=motion+sigma*randn(size(motion));
    end
    data=struct('motion',motion,'x_m',settings.x_m,'row_m',settings.row_m, ...
        't_s',settings.t_s,'valid_mask',true(size(phasor)),'plane_type',"enface");
end

function [rows,products]=evaluate_trial(data,caseName,seed,snr,maskName,sigma,trial,group,settings)
    methods=["phase_gradient","directional_phase","reverberant"];
    products=cell(3,1); runtimes=zeros(3,1);
    for index=1:3
        options=settings.options; options.method=methods(index);
        if caseName=="axial_shear3d_xy", options.reverb_model="shear3d"; end
        started=tic; products{index}=oce.dispersion.estimateLocalSpeedMap(data,options); runtimes(index)=toc(started);
        assert(all(isnan(products{index}.speed_m_s(~data.valid_mask))),'Measured gap was filled.');
        assert(all(isnan(products{index}.display_speed_m_s(~products{index}.valid_mask))),'Display filled missing support.');
    end
    measured=data.valid_mask; common=measured;
    for index=1:3, common=common&products{index}.valid_mask; end
    rows=cell(3,1); physical=group~="null";
    for index=1:3
        product=products{index}; accepted=product.valid_mask&measured;
        paired=accepted&products{1}.valid_mask;
        values=product.speed_m_s(accepted);
        row=struct('trial_id',trial,'group',group,'case_name',caseName,'seed',seed, ...
            'snr_db',snr,'mask_name',maskName,'noise_standard_deviation',sigma, ...
            'method',methods(index),'truth_speed_m_s',settings.truth_speed_m_s, ...
            'measured_support_pixels',nnz(measured),'accepted_pixels',nnz(accepted), ...
            'coverage_pct',100*nnz(accepted)/nnz(measured),'median_speed_m_s',NaN, ...
            'bias_pct',NaN,'median_absolute_error_pct',NaN,'relative_rmse_pct',NaN, ...
            'p95_absolute_error_pct',NaN,'median_quality',NaN, ...
            'common_three_method_pixels',nnz(common),'common_three_method_absolute_error_pct',NaN, ...
            'common_with_phase_pixels',nnz(paired),'common_with_phase_absolute_error_pct',NaN, ...
            'phase_reference_common_absolute_error_pct',NaN, ...
            'null_false_positive_pct',NaN,'runtime_s',runtimes(index));
        if ~isempty(values)
            row.median_speed_m_s=median(values); row.median_quality=median(product.quality(accepted));
        end
        if physical && ~isempty(values)
            error=values/settings.truth_speed_m_s-1;
            row.bias_pct=100*median(error); row.median_absolute_error_pct=100*median(abs(error));
            row.relative_rmse_pct=100*sqrt(mean(error.^2)); row.p95_absolute_error_pct=100*percentile(abs(error),0.95);
            if any(common,'all'), row.common_three_method_absolute_error_pct=100*median(abs(product.speed_m_s(common)/settings.truth_speed_m_s-1)); end
            if any(paired,'all')
                row.common_with_phase_absolute_error_pct=100*median(abs(product.speed_m_s(paired)/settings.truth_speed_m_s-1));
                row.phase_reference_common_absolute_error_pct=100*median(abs(products{1}.speed_m_s(paired)/settings.truth_speed_m_s-1));
            end
        elseif ~physical
            row.truth_speed_m_s=NaN; row.null_false_positive_pct=row.coverage_pct;
        end
        rows{index}=row;
    end
end

function aggregate=aggregate_trials(trials)
    groups=unique(trials(:,{'group','case_name','snr_db','mask_name','method'}),'rows');
    rows=cell(height(groups),1);
    for index=1:height(groups)
        group=groups(index,:);
        same=trials.group==group.group & trials.case_name==group.case_name & ...
            (trials.snr_db==group.snr_db | isnan(trials.snr_db)&isnan(group.snr_db)) & ...
            trials.mask_name==group.mask_name & trials.method==group.method;
        current=trials(same,:); row=table2struct(group);
        row.seed_count=height(current); row.coverage_median_pct=median(current.coverage_pct); ...
            row.coverage_min_pct=min(current.coverage_pct); row.coverage_max_pct=max(current.coverage_pct);
        row.error_median_pct=finite_reduction(current.median_absolute_error_pct,"median");
        row.error_min_pct=finite_reduction(current.median_absolute_error_pct,"min");
        row.error_max_pct=finite_reduction(current.median_absolute_error_pct,"max");
        row.bias_median_pct=finite_reduction(current.bias_pct,"median");
        row.rmse_median_pct=finite_reduction(current.relative_rmse_pct,"median");
        row.p95_error_median_pct=finite_reduction(current.p95_absolute_error_pct,"median");
        row.common_three_pixels_median=median(current.common_three_method_pixels);
        row.common_three_error_median_pct=finite_reduction(current.common_three_method_absolute_error_pct,"median");
        row.null_false_positive_median_pct=finite_reduction(current.null_false_positive_pct,"median");
        row.null_false_positive_max_pct=finite_reduction(current.null_false_positive_pct,"max");
        row.runtime_median_s=median(current.runtime_s); rows{index}=row;
    end
    aggregate=struct2table(vertcat(rows{:}));
end

function guards=probe_input_guards(settings)
    clean=make_field("planar",101,settings); [data,~]=make_data(clean,Inf,1,settings);
    callbacks={@()oce.dispersion.estimateLocalSpeedMap(data,struct('frequency_hz',10000)), ...
        @()oce.dispersion.estimateLocalSpeedMap(data,struct('frequency_hz',1000,'time_end_s',1e-4)), ...
        @()oce.dispersion.estimateLocalSpeedMap(data,struct('frequency_hz',1000,'speed_range_m_s',[6 .5]))};
    names=["temporal_Nyquist","insufficient_cycle","descending_speed_range"];
    expected=["OCE:LocalSpeed:InvalidOptions","OCE:LocalSpeed:InsufficientCycles","OCE:LocalSpeed:InvalidOptions"];
    records=cell(0,1);
    for index=1:numel(callbacks)
        identifier="none"; try, callbacks{index}(); catch exception, identifier=string(exception.identifier); end
        records{end+1}=struct('probe',names(index),'expected',expected(index),'observed',identifier, ...
            'pass',identifier==expected(index),'accepted_pixels',NaN,'median_measured_speed_m_s',NaN, ...
            'physical_truth_speed_m_s',NaN,'finding',"guard rejects invalid request"); %#ok<AGROW>
    end
    % Already-aliased input is deliberately demonstrated, not counted as an
    % input guard success: without a acquisition prior it is unidentifiable.
    aliasSettings=settings; aliasSettings.truth_speed_m_s=0.12;
    clean=make_field("planar",101,aliasSettings); [aliased,~]=make_data(clean,Inf,1,aliasSettings);
    options=settings.options; options.method="phase_gradient"; options.speed_range_m_s=[.1 6];
    result=oce.dispersion.estimateLocalSpeedMap(aliased,options);
    speed=result.speed_m_s(result.valid_mask);
    records{end+1}=struct('probe',"already_spatially_aliased_input", ...
        'expected',"cannot identify alias uniquely",'observed',"map alone is insufficient", ...
        'pass',true,'accepted_pixels',nnz(result.valid_mask),'median_measured_speed_m_s',finite_reduction(speed,"median"), ...
        'physical_truth_speed_m_s',aliasSettings.truth_speed_m_s, ...
        'finding',"physical input speed violates spatial Nyquist; any returned alias is not an accuracy success");
    guards=struct2table(vertcat(records{:}));
end

function value=finite_reduction(values,operation)
    values=values(isfinite(values));
    if isempty(values), value=NaN;
    elseif operation=="median", value=median(values);
    elseif operation=="min", value=min(values); else, value=max(values); end
end

function value=percentile(values,fraction)
    values=sort(values); value=values(max(1,ceil(fraction*numel(values))));
end

function write_findings(directory,aggregate,guards,settings,elapsed)
    destination=fullfile(directory,'hallazgos_velocidad.md'); fid=fopen(destination,'w','n','UTF-8');
    cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
    fprintf(fid,'# Validacion estocastica independiente de velocidad\n\n');
    fprintf(fid,'Se ejecutaron 80 realizaciones principales (4 campos x 4 semillas x 5 SNR), ');
    fprintf(fid,'8 realizaciones con huecos y 16 controles nulos. Cada realizacion se proceso con 3 metodos: 312 ejecuciones. Tiempo %.1f s.\n\n',elapsed);
    fprintf(fid,'Frecuencia %.0f Hz; velocidad fisica %.1f m/s; malla 61 x 61, paso 100 um, campo 6 x 6 mm; ',settings.frequency_hz,settings.truth_speed_m_s);
    fprintf(fid,'80 tiempos a 50 us. Ventana 2.4 x 2.4 mm; retardo reverberante maximo 1 mm. ');
    fprintf(fid,'El borde que no permite ventana completa cuenta como rechazo: la cobertura maxima es aproximadamente 37 % del campo completo.\n\n');
    fprintf(fid,'El SNR corresponde al RMS global de movimiento limpio sobre la desviacion estandar de ruido temporal gaussiano. ');
    fprintf(fid,'El error se calcula solamente en pixeles aceptados. No hay inpainting ni penalizacion oculta de NaN. ');
    fprintf(fid,'Los rangos entre semillas son descriptivos; cuatro semillas no establecen intervalos de confianza.\n\n');
    fprintf(fid,'## Resultados principales: mediana entre semillas\n\n');
    fprintf(fid,'| Campo | SNR dB | Metodo | Error mediano %% [min-max] | Cobertura %% [min-max] | Error P95 %% |\n|---|---:|---|---:|---:|---:|\n');
    main=aggregate(aggregate.group=="main",:);
    for index=1:height(main)
        row=main(index,:);
        fprintf(fid,'| %s | %.0f | %s | %.2f [%.2f-%.2f] | %.2f [%.2f-%.2f] | %.2f |\n', ...
            row.case_name,row.snr_db,row.method,row.error_median_pct,row.error_min_pct,row.error_max_pct, ...
            row.coverage_median_pct,row.coverage_min_pct,row.coverage_max_pct,row.p95_error_median_pct);
    end
    fprintf(fid,'\n## Controles nulos: falsos positivos\n\n');
    fprintf(fid,'Un campo armonico espacialmente uniforme no tiene velocidad de propagacion identificable. ');
    fprintf(fid,'El ruido temporal puro tampoco tiene ground truth de velocidad. Se informa la fraccion aceptada, sin etiquetarla como precision.\n\n');
    fprintf(fid,'| Control | SNR dB | Metodo | Falsos positivos mediana %% | Maximo %% |\n|---|---:|---|---:|---:|\n');
    null=aggregate(aggregate.group=="null",:);
    for index=1:height(null)
        row=null(index,:);
        fprintf(fid,'| %s | %.0f | %s | %.4f | %.4f |\n',row.case_name,row.snr_db,row.method, ...
            row.null_false_positive_median_pct,row.null_false_positive_max_pct);
    end
    fprintf(fid,'\n## Huecos medidos\n\n');
    fprintf(fid,'Se incluyen un bloque 9 x 9, una franja 31 x 2 y aproximadamente 4 %% de huecos aleatorios. ');
    fprintf(fid,'La mascara es identica para los tres estimadores; todas las regiones excluidas permanecen NaN.\n\n');
    gaps=aggregate(aggregate.group=="gaps",:);
    for index=1:height(gaps)
        row=gaps(index,:); fprintf(fid,'- %s / %s: error %.2f %% [%.2f-%.2f], cobertura %.2f %% [%.2f-%.2f].\n', ...
            row.case_name,row.method,row.error_median_pct,row.error_min_pct,row.error_max_pct, ...
            row.coverage_median_pct,row.coverage_min_pct,row.coverage_max_pct);
    end
    fprintf(fid,'\n## Muestreo y limites\n\n');
    fprintf(fid,'Los tres guardas de entrada (Nyquist temporal, menos de un ciclo, rango de velocidad descendente) ');
    fprintf(fid,'se rechazaron: %d/%d. El control de alias espacial ya adquirido muestra que el mapa no identifica por si solo la velocidad fisica original.\n\n', ...
        nnz(guards.pass(1:3)),3);
    alias=guards(end,:); fprintf(fid,'Velocidad fisica aliasada: %.3f m/s; mediana medida: %.3f m/s; %d pixeles aceptados. ', ...
        alias.physical_truth_speed_m_s,alias.median_measured_speed_m_s,alias.accepted_pixels);
    fprintf(fid,'Ese resultado no debe contarse como exactitud.\n\n');
    fprintf(fid,'Las ondas planas y reflejadas son campos escalares 2D. El campo bulk3D se genera con direcciones esfericas isotropicas y componente axial. ');
    fprintf(fid,'No se valida anisotropia material, dispersion Lamb, reconstruccion OCT, conversion de fase a movimiento ni E experimental en este subestudio. ');
    fprintf(fid,'Una imagen limpia, un residual pequeno o una cobertura mayor no prueban que el modelo de onda sea correcto.\n\n');
    fprintf(fid,'Los CSV conservan metricas por realizacion, soporte comun entre los tres metodos, soporte comun con phase_gradient y percentil 95 de error. ');
    fprintf(fid,'selected_raw_maps.mat contiene mapas sin suavizar, mascaras, diagnosticos y movimiento de casos representativos; validation_settings.mat fija todos los parametros.\n');
end
