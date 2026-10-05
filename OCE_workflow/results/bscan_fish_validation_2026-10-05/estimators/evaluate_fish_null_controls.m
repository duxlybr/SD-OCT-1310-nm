function evaluate_fish_null_controls()
% Observe false support; a coherent tone with independent spatial phase has
% no propagating ground truth even if a Fourier sector makes a smooth field.
    here=fileparts(mfilename('fullpath'));
    workflow=fileparts(fileparts(fileparts(here))); addpath(fullfile(workflow,'src'));
    s=load(fullfile(fileparts(here),'fish_forward','fish_individual_fields.mat'));
    settings=load(fullfile(here,'frozen_estimator_settings.mat'));
    base=s.data8(:); frozen=settings.frozen; records=struct([]); controls=cell(2,2);
    rng(826205,'twister'); frequency=frozen.frequency_hz;
    for control=1:2
        data=base;
        for excitation=1:numel(base)
            signal=double(base{excitation}.motion);
            if control==1
                % Preserve spatial RMS/attenuation and exact harmonic tone;
                % destroy phase relation between every independent position.
                gain=std(signal,0,3)*sqrt(2);
                phase=2*pi*rand(size(gain));
                data{excitation}.motion=gain.*cos(phase+reshape(2*pi*frequency*base{excitation}.t_s,1,1,[]));
            else
                % Independent temporal permutations remove the physical tone
                % at each position while retaining the sample distribution.
                matrix=reshape(signal,[],size(signal,3));
                for pixel=1:size(matrix,1), matrix(pixel,:)=matrix(pixel,randperm(size(matrix,2))); end
                data{excitation}.motion=reshape(matrix,size(signal));
            end
            dx=mean(diff(base{excitation}.x_m)); dy=mean(diff(base{excitation}.row_m));
            hx=floor(frozen.local.window_x_mm*1e-3/(2*dx)+1e-12);
            hy=floor(frozen.local.window_row_mm*1e-3/(2*dy)+1e-12);
            kernel=ones(2*hy+1,2*hx+1);
            data{excitation}.analysis_mask=logical(s.cases{1}.roi_mask)& ...
                (conv2(double(base{excitation}.valid_mask),kernel,'same')==numel(kernel));
        end
        for family=1:2
            options=frozen.fusion; local=cell(numel(data),1);
            if family==1, method="phase_gradient"; else, method="directional_phase"; end
            for excitation=1:numel(data)
                local{excitation}=frozen.local; local{excitation}.method=method;
                local{excitation}.direction_deg=frozen.angles_deg(excitation);
            end
            options.local_options=local;
            result=oce.dispersion.estimateMultiExcitationSpeedMap(data,options);
            controls{control,family}=result;
            if control==1, name="independent_spatial_phase_harmonic"; else, name="independent_temporal_shuffle"; end
            record=struct('control',name,'method',method, ...
                'accepted_count',nnz(result.valid_mask), ...
                'roi_count',nnz(s.cases{1}.roi_mask), ...
                'accepted_coverage_fraction',nnz(result.valid_mask&logical(s.cases{1}.roi_mask))/nnz(s.cases{1}.roi_mask), ...
                'median_reported_speed_without_physical_truth',median(result.speed_m_s(result.valid_mask)), ...
                'median_consensus_count',median(result.consensus_count(result.valid_mask)));
            if isempty(records), records=record; else, records(end+1)=record; end %#ok<AGROW>
        end
    end
    table=struct2table(records); writetable(table,fullfile(here,'fish_null_controls.csv'));
    save(fullfile(here,'fish_null_control_products.mat'),'table','controls','-v7.3');
    disp(table); disp('FISH_NULL_CONTROLS_FINISHED');
end
