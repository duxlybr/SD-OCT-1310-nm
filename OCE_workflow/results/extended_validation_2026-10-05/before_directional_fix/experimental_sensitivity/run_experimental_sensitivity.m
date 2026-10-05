%% Observational sensitivity and fixed nulls on saved experimental motion planes
% No raw BIN reread, no production edits, no Young inversion or ground truth.
% Each run records missing estimates as NaN; display interpolation is disabled.
outputRoot = fileparts(mfilename('fullpath'));
workflowRoot = fileparts(fileparts(fileparts(outputRoot)));
cd(workflowRoot); startup;
inputRoot = 'C:/Users/proyecto.pi1081/Desktop/OCE_fish/OCE_estimator_validation/experimental';
planeNames = ["luis3_bmode1_offset_0p00mm", "raster_offset_0p00mm", ...
    "raster_offset_0p10mm", "raster_offset_0p25mm"];
coherences = [.2 .4 .6];
windowSizesMm = [.8 1.2 1.8];
seedBase = 20261004;
records = struct([]);
manifest = struct('ground_truth_available', false, 'young_model', "none", ...
    'reference', struct('roi', "early_2to4ms", 'coherence', .2, ...
        'window_x_mm', 1.2, 'window_row_raster_mm', 1.2, ...
        'window_row_bmode_mm', .08), 'seed_base', seedBase, ...
    'source_owner', string(which('oce.dispersion.estimateLocalSpeedMap')), ...
    'source_plane_files', strings(4,1), 'source_metadata', {{}});
trialId = 0;
for planeIndex = 1:numel(planeNames)
    planeName = planeNames(planeIndex);
    planeFile = fullfile(inputRoot, planeName + "_plane.mat");
    load(planeFile, 'data');
    manifest.source_plane_files(planeIndex) = planeFile;
    manifest.source_metadata{planeIndex} = data.metadata;
    frequency = data.metadata.observation.frequency_hz_supplied_for_observation;
    configs = struct('method',{},'model',{});
    configs(1) = struct('method',"directional_phase",'model',"scalar2d");
    if data.plane_type == "enface"
        configs(2) = struct('method',"reverberant",'model',"scalar2d");
        configs(3) = struct('method',"reverberant",'model',"shear3d");
    end
    fprintf('Plane %s: [%s], saved MAT only\n', planeName, num2str(size(data.motion)));
    for configIndex = 1:numel(configs)
        config = configs(configIndex);
        tag = config.method + "_" + config.model;
        referenceOptions = make_options(data, config, frequency, .2, 1.2, "early_2to4ms");
        reference = oce.dispersion.estimateLocalSpeedMap(data, referenceOptions);
        referenceManifest = struct('source_plane_file', planeFile, ...
            'source_metadata', data.metadata, 'settings_predeclared', true, ...
            'ground_truth_available', false, 'young_model', "none");
        save(fullfile(outputRoot,planeName+"_"+tag+"_reference.mat"), ...
            'reference','referenceOptions','referenceManifest','-v7.3');
        save_preview(data, reference, fullfile(outputRoot,planeName+"_"+tag+"_reference.png"), ...
            "Referencia predeclarada: 2-4 ms, C0.2, ventana1.2 mm");
        for roi = ["early_2to4ms", "full_record"]
            for coherence = coherences
                for windowMm = windowSizesMm
                    options = make_options(data,config,frequency,coherence,windowMm,roi);
                    timer = tic;
                    trialId = trialId + 1;
                    [result,status,errorText] = evaluate(data,options);
                    record = trial_record(trialId,planeName,planeFile,data,config,options,roi, ...
                        "observed",NaN,result,reference,status,errorText,toc(timer));
                    if isempty(records), records=record; else, records(end+1)=record; end %#ok<SAGROW>
                    fprintf('%d %s %s %s C%.1f W%.1f: coverage %.4f IoU %.3g median %.3g status %s\n', ...
                        trialId,planeName,tag,roi,coherence,windowMm, ...
                        record.map_coverage_fraction,record.pixel_iou_reference,record.speed_median_m_s,status);
                    if status == "ok" && coherence == .6 && windowMm == 1.8 && roi == "early_2to4ms"
                        selected = result; %#ok<NASGU>
                        save(fullfile(outputRoot,planeName+"_"+tag+"_strict_large_window.mat"), ...
                            'selected','options','-v7.3');
                    end
                    writetable(struct2table(records),fullfile(outputRoot,'experimental_sensitivity_trials.csv'));
                end
            end
        end
        %% Fixed-seed perturbations at reference settings, not statistical tests
        for nullIndex=1:2
            nullSeed = seedBase + planeIndex * 100 + nullIndex;
            rng(nullSeed,'twister');
            nullData = data;
            selectedTime = data.t_s >= .002 & data.t_s <= .004;
            if nullIndex == 1
                nullType = "temporal_shuffle_common";
                permutation = randperm(sum(selectedTime));
                input = data.motion(:,:,selectedTime);
                nullData.motion(:,:,selectedTime) = input(:,:,permutation);
                nullRecipe = struct('type',nullType,'seed',nullSeed, ...
                    'permutation',permutation,'selected_time_indices',find(selectedTime), ...
                    'description',"Common permutation of ROI samples; times and spatial mask are retained.");
            else
                nullType = "independent_harmonic_phase";
                phases = 2*pi*rand(size(data.valid_mask));
                % Use an existing measured diagnostic, not a second harmonic
                % estimator. Its phasor origin is mean(selected time).
                inputPhasor = reference.diagnostics.input_phasor;
                deltaPhasor = inputPhasor .* (exp(1i*phases)-1);
                deltaPhasor(~isfinite(deltaPhasor)) = 0;
                tau = data.t_s(selectedTime)-mean(data.t_s(selectedTime));
                delta = real(reshape(deltaPhasor,[],1) * exp(1i*2*pi*frequency*tau(:)'));
                nullData.motion(:,:,selectedTime) = data.motion(:,:,selectedTime) + ...
                    reshape(single(delta), size(data.motion,1),size(data.motion,2),sum(selectedTime));
                nullRecipe = struct('type',nullType,'seed',nullSeed, ...
                    'phases_rad',phases,'selected_time_indices',find(selectedTime), ...
                    'description',"Independent phase rotations of the fitted harmonic; same harmonic magnitudes and residual to float precision; temporal coherence need not be exactly invariant.");
            end
            options = referenceOptions;
            timer = tic;
            trialId = trialId + 1;
            [result,status,errorText] = evaluate(nullData,options);
            record=trial_record(trialId,planeName,planeFile,data,config,options,"early_2to4ms", ...
                nullType,nullSeed,result,reference,status,errorText,toc(timer));
            records(end+1)=record; %#ok<SAGROW>
            fprintf('%d NULL %s %s %s: coverage %.4f reference %.4f IoU %.3g\n', ...
                trialId,planeName,tag,nullType,record.map_coverage_fraction, ...
                record.reference_coverage_fraction,record.pixel_iou_reference);
            save(fullfile(outputRoot,planeName+"_"+tag+"_"+nullType+".mat"), ...
                'result','options','nullRecipe','-v7.3');
            if status=="ok"
                save_preview(data,result,fullfile(outputRoot,planeName+"_"+tag+"_"+nullType+".png"), ...
                    "Perturbacion seedfija: "+nullType+"; no p-value");
            end
            writetable(struct2table(records),fullfile(outputRoot,'experimental_sensitivity_trials.csv'));
        end
    end
end
save(fullfile(outputRoot,'experimental_sensitivity_manifest.mat'),'manifest');
disp('EXPERIMENTAL_SENSITIVITY_FINISHED');

function options = make_options(data,config,frequency,coherence,windowMm,roi)
    if roi=="early_2to4ms", start=.002; stop=.004;
    else,start=data.t_s(1); stop=data.t_s(end);end
    if data.plane_type=="enface",rowWindow=windowMm;else,rowWindow=.08;end
    options=struct('method',config.method,'reverb_model',config.model, ...
        'frequency_hz',frequency,'time_start_s',start,'time_end_s',stop, ...
        'window_x_mm',windowMm,'window_row_mm',rowWindow, ...
        'direction_deg',0,'directional_halfwidth_deg',35, ...
        'min_coherence',coherence,'min_amplitude_fraction',.08, ...
        'min_support_fraction',.6,'fit_error_max',.3,'reverb_lag_mm',.6, ...
        'speed_range_m_s',[.2 10],'smoothing_mm',0);
end

function [result,status,errorText] = evaluate(data,options)
    result=[];status="ok";errorText="";
    try,result=oce.dispersion.estimateLocalSpeedMap(data,options);
    catch exception,status="error";errorText=string(exception.identifier)+": "+exception.message;end
end

function record = trial_record(id,name,file,data,config,options,roi,variant,seed,result,reference,status,errorText,elapsed)
    referenceMask=reference.valid_mask;
    total=numel(referenceMask);
    referenceCount=sum(referenceMask,'all');
    referenceCoverage=referenceCount/total;
    values=nan(1,14); % Uniform numeric schema also for failed parameter contracts.
    if status=="ok"
        valid=result.valid_mask;count=sum(valid,'all');speed=result.speed_m_s(valid);
        common=valid&referenceMask;union=valid|referenceMask;shared=sum(common,'all');
        if isempty(speed),speedRange=[NaN NaN NaN];
        else,speedRange=[min(speed) median(speed) max(speed)];end
        iou=NaN;if any(union,'all'),iou=shared/sum(union,'all');end
        retention=NaN;if referenceCount>0,retention=shared/referenceCount;end
        precision=NaN;if count>0,precision=shared/count;end
        if shared>0
            delta=result.speed_m_s(common)-reference.speed_m_s(common);
            relative=abs(delta)./reference.speed_m_s(common);
            sharedStats=[median(abs(delta)),sqrt(mean(delta.^2)),100*median(relative)];
        else,sharedStats=[NaN NaN NaN];end
        values=[count/total,count,mean(isfinite(result.phasor),'all'),speedRange, ...
            iou,retention,precision,shared,sharedStats,sum(xor(valid,referenceMask),'all')/total];
    end
    record=struct('trial_id',id,'plane',name,'source_plane_file',string(file), ...
        'plane_type',data.plane_type,'depth_offset_mm',data.offsets.depth_offset_mm, ...
        'frequency_hz',options.frequency_hz,'method',config.method,'reverb_model',config.model, ...
        'variant',variant,'seed',seed,'roi',roi,'time_start_s',options.time_start_s,'time_end_s',options.time_end_s, ...
        'min_coherence',options.min_coherence,'window_x_mm',options.window_x_mm,'window_row_mm',options.window_row_mm, ...
        'map_coverage_fraction',values(1),'valid_pixel_count',values(2),'harmonic_support_fraction',values(3), ...
        'speed_min_m_s',values(4),'speed_median_m_s',values(5),'speed_max_m_s',values(6), ...
        'reference_coverage_fraction',referenceCoverage,'pixel_iou_reference',values(7), ...
        'reference_retention_fraction',values(8),'accepted_precision_to_reference',values(9), ...
        'shared_pixel_count',values(10),'median_abs_delta_shared_m_s',values(11), ...
        'rmse_delta_shared_m_s',values(12),'median_abs_relative_delta_shared_pct',values(13), ...
        'mask_changed_fraction',values(14),'seconds',elapsed,'status',status,'error',errorText, ...
        'ground_truth_available',false,'young_model',"none",'surface_verified',false,'repeatability_verified',false, ...
        'interpretation',"Coverage/overlap measure estimator support and parameter stability, not accuracy. Fixed null variants are diagnostics, not p-values.");
end

function save_preview(data,result,path,caption)
    figureHandle=figure('Visible','off','Color','w','Position',[10 10 1300 460]);
    layout=tiledlayout(1,3,'Padding','compact');
    nexttile;handle=imagesc(data.x_m*1e3,data.row_m*1e3,result.speed_m_s);
    handle.AlphaData=isfinite(result.speed_m_s);clim([.2 10]);colorbar;title('Velocidad estimada (m/s), sin rellenar NaN');
    nexttile;imagesc(data.x_m*1e3,data.row_m*1e3,result.quality);clim([0 1]);colorbar;title('Calidad empirica, no incertidumbre');
    nexttile;imagesc(data.x_m*1e3,data.row_m*1e3,result.diagnostics.temporal_coherence);clim([0 1]);colorbar;title('Coherencia armonica temporal');
    for axesHandle=findall(figureHandle,'Type','axes')'
        xlabel(axesHandle,'x (mm)');
        if data.plane_type=="enface",ylabel(axesHandle,'y (mm)');else,ylabel(axesHandle,'Profundidad (mm)');end
    end
    title(layout,caption+" | superficie y repetibilidad no verificadas",'Interpreter','none');
    exportgraphics(figureHandle,path,'Resolution',140);close(figureHandle);
end
