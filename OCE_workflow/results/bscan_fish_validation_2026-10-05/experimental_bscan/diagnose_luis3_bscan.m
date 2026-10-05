%% Diagnose saved independent Luis3 B-mode; observation, no GT calibration
outputRoot=fileparts(mfilename('fullpath'));
workflowRoot=fileparts(fileparts(fileparts(outputRoot)));
cd(workflowRoot);startup;
source='C:/Users/proyecto.pi1081/Desktop/OCE_fish/OCE_estimator_validation/experimental/luis3_bmode1_offset_0p00mm_plane.mat';
load(source,'data');
fprintf('Shape [%s], mask %d/%d, x %.3f..%.3f mm dx %.5f mm, z %.3f..%.3f mm dz %.6f mm, t %.3f..%.3f ms dt %.3f us\n', ...
    num2str(size(data.motion)),nnz(data.valid_mask),numel(data.valid_mask), ...
    min(data.x_m)*1000,max(data.x_m)*1000,mean(diff(data.x_m))*1000, ...
    min(data.row_m)*1000,max(data.row_m)*1000,mean(diff(data.row_m))*1000, ...
    min(data.t_s)*1000,max(data.t_s)*1000,mean(diff(data.t_s))*1e6);
metadata=data.metadata;save(fullfile(outputRoot,'source_metadata.mat'),'metadata','source');
options=struct('method',"directional_phase",'frequency_hz',1000,'time_start_s',.002,'time_end_s',.004, ...
    'window_x_mm',1.2,'window_row_mm',.08,'direction_deg',0,'directional_halfwidth_deg',35, ...
    'min_coherence',.2,'min_amplitude_fraction',.08,'min_support_fraction',.6, ...
    'fit_error_max',.3,'speed_range_m_s',[.2 10],'smoothing_mm',0);
baseline=oce.dispersion.estimateLocalSpeedMap(data,options);
rows=diagnostic_rows(data,baseline,"baseline_2to4ms");
for roi=[0 .002 .004]
    roiOptions=options;
    if roi==0,roiOptions.time_start_s=data.t_s(1);roiOptions.time_end_s=data.t_s(end);tag="full_record";
    elseif roi==.002,roiOptions.time_start_s=.002;roiOptions.time_end_s=.006;tag="2to6ms";
    else,roiOptions.time_start_s=.004;roiOptions.time_end_s=.008;tag="4to8ms";end
    result=oce.dispersion.estimateLocalSpeedMap(data,roiOptions);
    rows=[rows diagnostic_rows(data,result,tag)]; %#ok<AGROW>
end
writetable(struct2table(rows),fullfile(outputRoot,'initial_rejection_counts.csv'));
disp(struct2table(rows));
save(fullfile(outputRoot,'luis3_initial_diagnosis.mat'),'data','baseline','options','rows','-v7.3');
save_diagnostics(data,baseline,fullfile(outputRoot,'luis3_initial_signal_diagnostics.png'));
disp('LUIS3_INITIAL_DIAGNOSIS_FINISHED');

function rows=diagnostic_rows(data,result,tag)
    before=data.valid_mask&isfinite(result.diagnostics.input_phasor);
    temporal=before&result.diagnostics.temporal_coherence>=result.options.min_coherence;
    amplitude=isfinite(result.phasor);
    sizes=result.diagnostics.window_samples;hr=(sizes(1)-1)/2;hx=(sizes(2)-1)/2;
    full=false(size(before));full(1+hr:end-hr,1+hx:end-hx)=true;
    center=amplitude&full;
    support=center&result.diagnostics.support_fraction>=result.options.min_support_fraction;
    fitted=support&isfinite(result.diagnostics.phase_gradient_x_rad_m);
    alias=fitted&~result.diagnostics.spatial_alias_rejected;
    fit=alias&result.diagnostics.fit_error<=result.options.fit_error_max;
    candidate=2*pi*result.options.frequency_hz./abs(result.diagnostics.phase_gradient_x_rad_m);
    range=fit&candidate>=result.options.speed_range_m_s(1)&candidate<=result.options.speed_range_m_s(2);
    stages={data.valid_mask,before,temporal,amplitude,center,support,fitted,alias,fit,range,result.valid_mask};
    names=["raw_oct_mask","finite_harmonic","temporal_coherence","directional_amplitude","full_window_centers", ...
        "local_support","fit_computed","not_aliased","circular_fit_error","speed_range","accepted"];
    rows=struct([]);
    for index=1:numel(stages)
        mask=stages{index};z=data.row_m(any(mask,2));
        if isempty(z),span=[NaN NaN];else,span=[min(z) max(z)]*1000;end
        record=struct('roi',tag,'stage',names(index),'count',nnz(mask),'fraction',mean(mask,'all'), ...
            'depth_min_mm',span(1),'depth_max_mm',span(2));
        if isempty(rows),rows=record;else,rows(end+1)=record;end %#ok<AGROW>
    end
end

function save_diagnostics(data,result,path)
    fig=figure('Visible','off','Color','w','Position',[20 20 1800 900]);
    cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(2,3,'Padding','compact','TileSpacing','compact');
    maps={data.structural_db,double(data.valid_mask),result.diagnostics.temporal_coherence, ...
        abs(result.diagnostics.input_phasor),double(isfinite(result.phasor)),result.diagnostics.fit_error};
    titles={'OCT estructural (dB)','Soporte OCT (1 = medido)','Coherencia armónica temporal', ...
        'Amplitud armónica antes del filtro (rad)','Soporte tras filtro y amplitud','Error espacial circular (rad RMS)'};
    for index=1:6
        ax=nexttile(layout);im=imagesc(data.x_m*1000,data.row_m*1000,maps{index});im.AlphaData=isfinite(maps{index});
        ax.Color=[.88 .88 .88];title(titles{index},'Interpreter','none');xlabel('x (mm)');ylabel('Profundidad OCT (mm)');colorbar;
        if ismember(index,[2 3 5]),clim([0 1]);end
        if index==6,clim([0 1]);end
    end
    title(layout,'Luis3 B-mode 1 · 1 kHz · ROI 2–4 ms · mecanismos de rechazo; sin ground truth','Interpreter','none');
    exportgraphics(fig,path,'Resolution',140,'BackgroundColor','white');
end
