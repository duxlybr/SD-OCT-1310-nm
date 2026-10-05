%% 0. INITIALIZATION
% Eight separate acquisitions of the same stationary medium, not simultaneous
% reverberant excitation. Run sections in order; compare constituent maps.
workflow_file = matlab.desktop.editor.getActiveFilename;
assert(~isempty(workflow_file),'Open this workflow in the MATLAB Editor.');
repository_root = fileparts(fileparts(workflow_file));
startup_file = fullfile(repository_root, 'startup.m');
assert(isfile(startup_file),'Cannot locate the OCE workflow repository.');
run(startup_file);

%% 1. LOAD INDEPENDENT MOTION PLANES
input_mode="mat";  % "mat" | "bin" | "stepwise"
% Validation fixture created from a global variable-mu SH forward PDE:
case_file=fullfile(repository_root,'results','bscan_fish_validation_2026-10-05', ...
    'fish_forward','fish_individual_fields.mat');
% For your acquisitions fill eight paths in excitation order:
bin_files=strings(0,1);
load_options=struct('plane_type',"enface",'depth_offset_mm',0,'depth_band_mm',.04, ...
    'phase_registration_status',"unverified");
% In stepwise mode fill state_cells, phase_cells, border_cells in your workspace.
% Each element is a separate acquisition; borders remain mandatory.
excitation_angles_deg=(0:45:315)';
source_cases={};
switch input_mode
    case "mat"
        loaded=load(case_file,'data8','cases');
        assert(isfield(loaded,'data8'),'MAT must contain data8, one plane per excitation.');
        data_cells=loaded.data8;
        if isstruct(data_cells),data_cells=num2cell(data_cells);end
        if isfield(loaded,'cases'),source_cases=loaded.cases;end
        if isstruct(source_cases),source_cases=num2cell(source_cases);end
    case "bin"
        assert(numel(bin_files)==numel(excitation_angles_deg),'List one BIN for each excitation.');
        data_cells=cell(numel(bin_files),1);
        for excitation_index=1:numel(bin_files)
            data_cells{excitation_index}=oce.acquisition.loadWaveMotionPlane(bin_files(excitation_index),load_options);
        end
    case "stepwise"
        assert(exist('state_cells','var')==1 && exist('phase_cells','var')==1 && exist('border_cells','var')==1, ...
            'Provide state_cells, phase_cells, border_cells from separate stepwise acquisitions.');
        assert(numel(state_cells)==numel(excitation_angles_deg) && numel(phase_cells)==numel(state_cells) && ...
            numel(border_cells)==numel(state_cells),'One state/phase/border product per excitation is required.');
        data_cells=cell(numel(state_cells),1);
        for excitation_index=1:numel(state_cells)
            data_cells{excitation_index}=oce.acquisition.buildWaveMotionPlane( ...
                state_cells{excitation_index},phase_cells{excitation_index},border_cells{excitation_index},load_options);
        end
    otherwise
        error('OCE:Workflow:InvalidMultiInput','Choose mat, bin or stepwise.');
end
assert(iscell(data_cells) && numel(data_cells)==numel(excitation_angles_deg),'One plane per excitation is required.');
% The fusion owner requires identical physical axes and mechanical frequency.
% Experimental planes need spatial registration before this stage. A matching
% array size alone does not establish that the same material was measured.

%% 2. EDIT LOCAL ESTIMATOR AND CONDITIONAL MATERIAL MODEL
frequency_hz=1000;  % legacy input: explicitly measured/known mechanical Hz
if isfield(data_cells{1},'metadata') && isfield(data_cells{1}.metadata,'frequency_hz') && ...
        isfinite(data_cells{1}.metadata.frequency_hz)
    frequency_hz=double(data_cells{1}.metadata.frequency_hz);
end
local_options=cell(size(data_cells));
for excitation_index=1:numel(data_cells)
    local_options{excitation_index}=struct('method',"phase_gradient",'frequency_hz',frequency_hz, ...
        'window_x_mm',1.2,'window_row_mm',1.2,'min_coherence',.65,'min_amplitude_fraction',.05, ...
        'min_support_fraction',.75,'fit_error_max',.30,'speed_range_m_s',[.3 8],'smoothing_mm',0, ...
        'direction_deg',mod(excitation_angles_deg(excitation_index)+180,360)-180);
    if string(data_cells{excitation_index}.plane_type)=="bmode"
        local_options{excitation_index}.window_row_mm=.04;
    end
end
% Set to directional_phase when a direction can be isolated; phase_gradient
% is the predeclared primary estimator for the validation SH fish fixture.
young_options=struct('model',"none",'density_kg_m3',1000,'poisson_ratio',.495, ...
    'frequency_hz',frequency_hz,'thickness_m',.0005,'max_kh',.6);
% For the SH validation fixture only: model="bulk_shear" is its constitutive
% conversion. Experimental Rayleigh/Lamb require their corresponding models.
% Do not fuse B-scan projections acquired at different unknown oblique angles.

%% 3. OPTIONAL INTERACTIVE TUNING OF ONE ACQUISITION
% Execute, adjust controls, then execute the second part after Recalcular.
open_individual_ui=false;excitation_to_tune=1;
if open_individual_ui
    tune_options=local_options{excitation_to_tune};
    tune_options.young_model=char(young_options.model);
    tune_options.density_kg_m3=young_options.density_kg_m3;
    tune_options.poisson_ratio=young_options.poisson_ratio;
    individual_ui=oce.interaction.tuneWaveSpeedMaps(data_cells{excitation_to_tune},tune_options);
end
% After tuning, execute these lines separately to adopt accepted parameters:
% tuned_session=individual_ui.UserData;
% assert(~isempty(tuned_session.speed_result),'Press Recalcular first.');
% local_options{excitation_to_tune}=tuned_session.speed_result.options;
% young_options=tuned_session.modulus_options;

%% 4. COMPLETE-WINDOW FAR FIELD AND ROBUST FUSION
% Simulation cases provide geometry-only farfield masks. For experimental
% input, replace source_cases with a cell of structs having farfield_mask,
% based on measured source footprint and >=2 reference wavelengths clearance.
% Their erosion restricts output centres only; neighbours remain measured.
for excitation_index=1:numel(data_cells)
    data=data_cells{excitation_index};opts=local_options{excitation_index};
    if ~isempty(source_cases)
        far=logical(source_cases{excitation_index}.farfield_mask);
        assert(isequal(size(far),size(data.valid_mask)),'Source mask must match physical axes.');
        hx=max(1,floor(opts.window_x_mm*1e-3/(2*mean(diff(data.x_m)))+1e-10));
        hy=0;if numel(data.row_m)>1,hy=floor(opts.window_row_mm*1e-3/(2*mean(diff(data.row_m)))+1e-10);end
        kernel=ones(2*hy+1,2*hx+1);
        centres=conv2(double(far),kernel,'same')==numel(kernel);
        if isfield(data,'analysis_mask'),centres=centres & data.analysis_mask;end
        data.analysis_mask=centres;
    end
    data_cells{excitation_index}=data;
end
fusion_options=struct('local_options',{local_options},'min_consensus_count',4, ...
    'min_consensus_fraction',.5,'max_relative_slowness_deviation',.20);
combined_speed=oce.dispersion.estimateMultiExcitationSpeedMap(data_cells,fusion_options);
combined_young=oce.elastography.invertYoungModulus(combined_speed,young_options);
% Consensus / spread measure agreement between acquisitions, not statistical
% confidence. Every output retains raw valid support; there is no inpainting.

%% 5. SHOW AND SAVE ONLY VELOCITY / YOUNG MAP IMAGES
fig=figure('Color','white','Name','OCE separate excitations: robust combined map');
layout=tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
map_values={combined_speed.speed_m_s,combined_young.young_pa/1000};
map_titles=["Velocidad combinada (m/s)","Young condicional (kPa): "+string(young_options.model)];
for map_index=1:2
    ax=nexttile(layout);values=map_values{map_index};
    im=imagesc(ax,data_cells{1}.x_m*1000,data_cells{1}.row_m*1000,values);im.AlphaData=isfinite(values);
    ax.Color=[.85 .85 .85];axis(ax,'image');axis(ax,'xy');xlabel(ax,'X (mm)');
    if string(data_cells{1}.plane_type)=="bmode",ylabel(ax,'Z (mm)');ax.YDir='reverse';else,ylabel(ax,'Y (mm)');end
    colormap(ax,turbo);colorbar(ax);title(ax,map_titles(map_index));
end
title(layout,sprintf('%d excitaciones individuales; soporte combinado %.1f%%', ...
    numel(data_cells),100*nnz(combined_speed.valid_mask)/numel(combined_speed.valid_mask)));
write_results=false;output_name="multi_excitation_speed_young";
if write_results
    image_directory=fullfile(repository_root,'results','Speed_Young_Maps');
    numerical_directory=fullfile(repository_root,'results','multi_excitation');
    if ~isfolder(image_directory),mkdir(image_directory);end
    if ~isfolder(numerical_directory),mkdir(numerical_directory);end
    exportgraphics(fig,fullfile(image_directory,output_name+".png"),'Resolution',180);
    save(fullfile(numerical_directory,output_name+".mat"),'combined_speed','combined_young', ...
        'local_options','fusion_options','young_options','excitation_angles_deg','source_cases','-v7.3');
end
