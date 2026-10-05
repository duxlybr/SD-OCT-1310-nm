%% Independent experimental meridians, fixed rejection gates and pulse audit
outputRoot=fileparts(mfilename('fullpath'));
workflowRoot=fileparts(fileparts(fileparts(outputRoot)));
cd(workflowRoot);startup;
sourcePlane='C:/Users/proyecto.pi1081/Desktop/OCE_fish/OCE_estimator_validation/experimental/luis3_bmode1_offset_0p00mm_plane.mat';
load(sourcePlane,'data');
binFile=data.metadata.source_file;
loadOptions=data.metadata.load_options;
configs=struct('method',{"directional_phase","directional_phase","phase_gradient"},'direction',{0,180,0});
windowX=[.6 .9 1.2];windowRow=[0 .02 .04 .08];
rois=[.00001 .00797; .00001 .002; .002 .004; .002 .006; .004 .00797];
roiNames=["full_record","pre_0to2ms","early_2to4ms","2to6ms","late_4to8ms"];
records=struct([]);pulseRecords=struct([]);nullRecords=struct([]);references=struct([]);
for bmode=1:4
    if bmode>1
        planeFile=fullfile(outputRoot,sprintf('luis3_bmode%d_plane.mat',bmode));
        if isfile(planeFile),load(planeFile,'data');
        else
            loadOptions.bmode_index=bmode;loadOptions.show_progress=false;
            data=oce.acquisition.loadWaveMotionPlane(binFile,loadOptions);
            save(planeFile,'data','-v7.3');
        end
    end
    fprintf('Independent B-mode%d: OCT mask %d/%d\n',bmode,nnz(data.valid_mask),numel(data.valid_mask));
    [pulseRows,pulseDiagnostic]=pulse_audit(data,bmode);
    pulseRecords=[pulseRecords pulseRows]; %#ok<AGROW>
    save(fullfile(outputRoot,sprintf('luis3_bmode%d_pulse.mat',bmode)),'pulseDiagnostic');
    save_pulse_figure(data,pulseDiagnostic,bmode,fullfile(outputRoot,sprintf('luis3_bmode%d_pulse_diagnostic.png',bmode)));
    for configIndex=1:numel(configs)
        config=configs(configIndex);
        for roiIndex=1:numel(roiNames)
            for wx=windowX
                for wz=windowRow
                    options=map_options(config,rois(roiIndex,:),wx,wz);
                    result=oce.dispersion.estimateLocalSpeedMap(data,options);
                    record=summarize(data,result,bmode,roiNames(roiIndex),"observed",NaN);
                    if isempty(records),records=record;else,records(end+1)=record;end %#ok<SAGROW>
                    if roiIndex==3 && wx==.9 && wz==.04
                        reference=struct('bmode',bmode,'config',config,'options',options,'result',result);
                        if isempty(references),references=reference;else,references(end+1)=reference;end %#ok<SAGROW>
                        save_map_diagnostic(data,result,bmode, ...
                            fullfile(outputRoot,sprintf('luis3_bmode%d_%s_dir%d_reference.png',bmode,config.method,config.direction)));
                    end
                end
            end
            fprintf('Bmode%d %s dir%d %s: complete\n',bmode,config.method,config.direction,roiNames(roiIndex));
            writetable(struct2table(records),fullfile(outputRoot,'independent_bscan_trials.csv'));
        end
    end
    % Explicitly test AIA at a physically resolved axial/radial aperture;
    % this is a premise diagnostic, not evidence of a diffuse shear field.
    for model=["scalar2d","shear3d"]
        options=map_options(configs(1),[.002 .004],1.2,1.2);
        options.method="reverberant";options.reverb_model=model;options.reverb_lag_mm=.6;
        result=oce.dispersion.estimateLocalSpeedMap(data,options);
        record=summarize(data,result,bmode,"early_2to4ms","observed_AIA",NaN);
        records(end+1)=record; %#ok<SAGROW>
        fprintf('Bmode%d AIA%s support %d\n',bmode,model,nnz(result.valid_mask));
    end
    if bmode==1
        chosen=references([references.bmode]==1);
        selected=data.t_s>=.002&data.t_s<=.004;
        tau=data.t_s(selected)-mean(data.t_s(selected));
        for configIndex=1:numel(chosen)
            ref=chosen(configIndex);
            for seed=1:10
                rng(20261005+100*configIndex+seed,'twister');
                % One independent phase per lateral position, shared by all
                % depth rows, preserves depth structure and harmonic power.
                phases=2*pi*rand(1,size(data.motion,2));
                inputPhasor=ref.result.diagnostics.input_phasor;
                delta=inputPhasor.*(exp(1i*phases)-1);delta(~isfinite(delta))=0;
                adjustment=real(reshape(delta,[],1)*exp(1i*2*pi*1000*tau(:)'));
                nullData=data;
                nullData.motion(:,:,selected)=data.motion(:,:,selected)+ ...
                    reshape(single(adjustment),size(data.motion,1),size(data.motion,2),sum(selected));
                result=oce.dispersion.estimateLocalSpeedMap(nullData,ref.options);
                record=summarize(data,result,bmode,"early_2to4ms","independent_position_phase",seed);
                if isempty(nullRecords),nullRecords=record;else,nullRecords(end+1)=record;end %#ok<SAGROW>
            end
            rng(20261005+configIndex,'twister');nullData=data;
            input=data.motion(:,:,selected);order=randperm(sum(selected));
            nullData.motion(:,:,selected)=input(:,:,order);
            result=oce.dispersion.estimateLocalSpeedMap(nullData,ref.options);
            nullRecords(end+1)=summarize(data,result,bmode,"early_2to4ms","temporal_shuffle_common",20261005+configIndex); %#ok<SAGROW>
        end
        writetable(struct2table(nullRecords),fullfile(outputRoot,'bmode1_phase_controls.csv'));
    end
    writetable(struct2table(records),fullfile(outputRoot,'independent_bscan_trials.csv'));
    writetable(struct2table(pulseRecords),fullfile(outputRoot,'independent_bscan_pulse_metrics.csv'));
    save(fullfile(outputRoot,'independent_bscan_references.mat'),'references','configs','rois','roiNames', ...
        'windowX','windowRow','loadOptions','sourcePlane','binFile','-v7.3');
end
disp('INDEPENDENT_LUIS3_STUDY_FINISHED');

function options=map_options(config,roi,wx,wz)
    options=struct('method',config.method,'frequency_hz',1000,'time_start_s',roi(1),'time_end_s',roi(2), ...
        'window_x_mm',wx,'window_row_mm',wz,'direction_deg',config.direction,'directional_halfwidth_deg',35, ...
        'min_coherence',.2,'min_amplitude_fraction',.08,'min_support_fraction',.6,'fit_error_max',.3, ...
        'speed_range_m_s',[.2 10],'smoothing_mm',0);
end

function record=summarize(data,result,bmode,roi,variant,seed)
    v=result.speed_m_s(result.valid_mask);
    if isempty(v),stats=[NaN NaN NaN];z=[NaN NaN];
    else,stats=[min(v) median(v) max(v)];depth=data.row_m(any(result.valid_mask,2));z=[min(depth) max(depth)]*1000;end
    temp=data.valid_mask&isfinite(result.diagnostics.input_phasor)&result.diagnostics.temporal_coherence>=.2;
    amplitude=isfinite(result.phasor);
    model="none";if isfield(result.options,'reverb_model'),model=result.options.reverb_model;end
    record=struct('bmode',bmode,'roi',roi,'variant',variant,'seed',seed,'method',result.options.method, ...
        'reverb_model',model,'direction_deg',result.options.direction_deg, ...
        'window_x_mm',result.options.window_x_mm,'window_row_mm',result.options.window_row_mm, ...
        'realized_rows',result.diagnostics.window_samples(1),'realized_columns',result.diagnostics.window_samples(2), ...
        'oct_count',nnz(data.valid_mask),'temporal_count',nnz(temp),'amplitude_count',nnz(amplitude), ...
        'local_support_count',nnz(amplitude&result.diagnostics.support_fraction>=.6), ...
        'accepted_count',nnz(result.valid_mask),'coverage_fraction',mean(result.valid_mask,'all'), ...
        'speed_min_m_s',stats(1),'speed_median_m_s',stats(2),'speed_max_m_s',stats(3), ...
        'depth_min_mm',z(1),'depth_max_mm',z(2),'ground_truth_available',false, ...
        'interpretation',"Exploratory support under fixed gates; no accuracy claim or wave-mode identification");
end

function [rows,diagnostic]=pulse_audit(data,bmode)
    depths=[.27 .50 1.00 2.00];t=data.t_s(:);dt=mean(diff(t));n=numel(t);fs=1/dt;
    f=(0:n-1)'*fs/n;positive=f<=fs/2;
    records=struct([]);traces=cell(numel(depths),1);spectra=cell(numel(depths),1);envelopes=cell(numel(depths),1);
    for i=1:numel(depths)
        z=abs(data.row_m*1000-depths(i))<=.02;
        m=data.valid_mask(z,:);input=double(data.motion(z,:,:));
        weights=10.^((data.structural_db(z,:)-max(data.structural_db(z,:),[],'all'))/10).*m;
        averaged=squeeze(sum(input.*weights,1)./max(realmin,sum(weights,1)));
        traces{i}=averaged;centered=averaged-mean(averaged,2);
        taper=.5-.5*cos(2*pi*(0:n-1)/(n-1));spec=abs(fft(centered.*taper,[],2)).^2;
        spectra{i}=mean(spec,1)';
        % A diagnostic 500–1500 Hz envelope, not a new speed estimator.
        transform=fft(centered,[],2);bands=(f>=500&f<=1500)|(f>=fs-1500&f<=fs-500);
        transform(:,~bands)=0;analytic=zeros(size(transform));
        analytic(:,2:floor((n+1)/2))=2*transform(:,2:floor((n+1)/2));
        if mod(n,2)==0,analytic(:,n/2+1)=transform(:,n/2+1);end
        envelope=abs(ifft(analytic,[],2));envelopes{i}=envelope;
        powers=mean(averaged.^2,1);
        pre=t<.002;early=t>=.002&t<.004;late=t>=.004;
        spectrum=spectra{i};freq=f(positive);ps=spectrum(positive);ps(1)=0;
        [~,peak]=max(ps);band=freq>=500&freq<=1500;
        envelopeEnergy=envelope.^2;centroid=(envelopeEnergy*t)./max(realmin,sum(envelopeEnergy,2));
        coeff=[ones(size(data.x_m)) data.x_m(:)]\centroid;
        residual=centroid-[ones(size(data.x_m)) data.x_m(:)]*coeff;
        r2=1-sum(residual.^2)/max(realmin,sum((centroid-mean(centroid)).^2));
        record=struct('bmode',bmode,'depth_center_mm',depths(i),'band_width_mm',.04, ...
            'oct_supported_columns',nnz(any(m,1)),'rms_pre_rad',sqrt(mean(powers(pre))), ...
            'rms_early_rad',sqrt(mean(powers(early))),'rms_late_rad',sqrt(mean(powers(late))), ...
            'early_to_pre_rms_ratio',sqrt(mean(powers(early))/max(realmin,mean(powers(pre)))), ...
            'early_to_late_rms_ratio',sqrt(mean(powers(early))/max(realmin,mean(powers(late)))), ...
            'spectrum_peak_hz',freq(peak),'power_fraction_500to1500hz',sum(ps(band))/max(realmin,sum(ps)), ...
            'envelope_centroid_min_ms',min(centroid)*1000,'envelope_centroid_max_ms',max(centroid)*1000, ...
            'envelope_centroid_slope_s_m',coeff(2),'envelope_centroid_linear_r2',r2, ...
            'interpretation',"Envelope centroid is a timing diagnostic, not arrival velocity; short-record filtering can ring and MB repeatability is unverified");
        if isempty(records),records=record;else,records(end+1)=record;end %#ok<SAGROW>
    end
    rows=records;diagnostic=struct('depths_mm',depths,'traces_rad',{traces},'spectrum_power',{spectra}, ...
        'envelopes_rad',{envelopes},'f_hz',f,'t_s',t,'x_m',data.x_m,'metrics',records, ...
        'spectrum_resolution_hz',fs/n,'no_zero_padding',true,'bandpass_hz',[500 1500]);
end

function save_pulse_figure(data,p,bmode,path)
    fig=figure('Visible','off','Color','w','Position',[20 20 1700 1200]);cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(4,3,'Padding','compact','TileSpacing','compact');
    for i=1:4
        nexttile;positions=round(linspace(15,size(data.motion,2)-15,4));
        plot(p.t_s*1000,p.traces_rad{i}(positions,:)');xlabel('t local (ms)');ylabel('Incremento fase (rad)');
        title(sprintf('z %.2f mm · trazas x ≈ 2/4/6/8 mm',p.depths_mm(i)));xline(2,'k:');xline(4,'k:');
        nexttile;imagesc(p.t_s*1000,data.x_m*1000,p.envelopes_rad{i});xlabel('t local (ms)');ylabel('x (mm)');colorbar;
        title('Envolvente diagnóstica 500–1500 Hz');
        nexttile;mask=p.f_hz>=0&p.f_hz<=5000;plot(p.f_hz(mask),p.spectrum_power{i}(mask));
        xlabel('Frecuencia (Hz)');ylabel('Potencia relativa');title(sprintf('FFT sin padding · resolución %.1f Hz',p.spectrum_resolution_hz));xline(1000,'k:');
    end
    title(layout,sprintf('Luis3 B-mode%d independiente · transiente/estacionario; no velocidad de llegada ni modo verificado',bmode),'Interpreter','none');
    exportgraphics(fig,path,'Resolution',140,'BackgroundColor','white');
end

function save_map_diagnostic(data,result,bmode,path)
    fig=figure('Visible','off','Color','w','Position',[20 20 1500 600]);cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(1,3,'Padding','compact','TileSpacing','compact');
    arrays={result.speed_m_s,result.diagnostics.temporal_coherence,result.diagnostics.support_fraction};
    labels={'Velocidad (m/s), NaN gris','Coherencia temporal','Soporte local'};
    for i=1:3
        ax=nexttile;im=imagesc(data.x_m*1000,data.row_m*1000,arrays{i});im.AlphaData=isfinite(arrays{i});
        ax.Color=[.88 .88 .88];xlabel('x (mm)');ylabel('Profundidad OCT (mm)');title(labels{i});colorbar;
        if i==1,clim([.2 10]);else,clim([0 1]);end
    end
    title(layout,sprintf('Bmode%d %s dir%g · ROI2–4ms · wx0.9/wz0.04mm · C0.2 y rechazo original · sin GT', ...
        bmode,result.options.method,result.options.direction_deg),'Interpreter','none');
    exportgraphics(fig,path,'Resolution',140,'BackgroundColor','white');
end
