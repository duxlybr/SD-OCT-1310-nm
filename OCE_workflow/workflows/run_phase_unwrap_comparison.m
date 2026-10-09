%% 0. INITIALIZATION
% Open this workflow in the MATLAB Editor and execute sections in order.
workflow_file = matlab.desktop.editor.getActiveFilename;
assert(~isempty(workflow_file),'Open this workflow in the MATLAB Editor.');
repository_root = fileparts(fileparts(workflow_file));
startup_file = fullfile(repository_root, 'startup.m');
assert(isfile(startup_file),'Cannot locate the OCE workflow repository.');
current_paths = string(strsplit(path,pathsep));
foreign_paths = current_paths(contains(current_paths,filesep+"OCE_workflow"+filesep) & ...
    ~startsWith(current_paths,string(repository_root),'IgnoreCase',true));
if ~isempty(foreign_paths), rmpath(foreign_paths{:}); clear functions; end
run(startup_file);

%% 1. INPUT AND SHARED PARAMETERS
% Raw wrapped optical phase must be loaded before unwrap/filter/estimation.
% "bin" streams selected positions. "stepwise" reuses reconstructed IQ and
% validated borders; previous Loupas/phase products are not used.
input_mode = "bin";  % "bin" | "stepwise"
source_file = "";    % empty opens a BIN selector
plane_options = struct('phase_product',"raw_wrapped", ...
    'plane_type',"bmode",'bmode_index',1,'depth_offset_mm',0,'depth_band_mm',.04);
unwrap_methods = ["sequential","least_squares_dct","tie_dct"];
unwrap_dimensions = [3 1]; % time/depth independently at each acquired position
tie_iterations = 8;        % fixed budget, no early stopping
map_options = struct('method',"phase_derivative_2d",'frequency_hz',1000, ...
    'window_x_mm',.9,'window_row_mm',.04,'pd_geometry',"auto", ...
    'directional_filter_enabled',false,'direction_deg',0,'directional_halfwidth_deg',45, ...
    'min_coherence',.5, ...
    'min_amplitude_fraction',.05,'min_support_fraction',.8, ...
    'fit_error_max',.3,'smoothing_mm',0,'unwrap_iterations',tie_iterations);
young_options = struct('model',"none",'frequency_hz',1000, ...
    'density_kg_m3',1000,'poisson_ratio',.495,'thickness_m',.6e-3);
% Choose the mechanical mode explicitly before enabling Young.
output_folder = fullfile(repository_root,'results','interactive_unwrap_comparison');
gallery_folder = fullfile(repository_root,'results','Speed_Young_Maps');
speed_limits_m_s = [.2 8];
young_limits_kpa = [0 100]; % identical color scales for all unwrap methods

%% 2. ACQUIRE THE NATIVE RAW PHASE PRODUCT
switch input_mode
    case "bin"
        if strlength(source_file)==0
            [selected_file,selected_folder]=uigetfile('*.bin','Raw OCE acquisition');
            assert(~isequal(selected_file,0),'No acquisition selected.');
            source_file=fullfile(selected_folder,selected_file);
        end
        raw_wave_plane=oce.acquisition.loadWaveMotionPlane(source_file,plane_options);
    case "stepwise"
        assert(exist('acquisition_state','var')==1 && exist('border_result','var')==1, ...
            'Reconstruct IQ and detect borders in the stepwise workflow first.');
        raw_wave_plane=oce.acquisition.buildWaveMotionPlane( ...
            acquisition_state,[],border_result,plane_options);
    otherwise
        error('OCE:Workflow:InvalidWaveInput','input_mode must be bin or stepwise.');
end

%% 3. UNWRAP, THEN PLACE/FILTER/ESTIMATE ON IDENTICAL SUPPORT
comparison=cell(1,numel(unwrap_methods));
for method_index=1:numel(unwrap_methods)
    unwrap_options=struct('method',unwrap_methods(method_index), ...
        'dimensions',unwrap_dimensions,'iterations',tie_iterations);
    % Native mask dimensions are explicitly repeated over measured times.
    unwrap_options.valid_mask=repmat(raw_wave_plane.valid_mask,1,1, ...
        numel(raw_wave_plane.t_s)) & isfinite(raw_wave_plane.wrapped_phase);
    unwrapped=oce.motion.unwrapPhase(raw_wave_plane.wrapped_phase,unwrap_options);
    wave_plane=oce.acquisition.finalizeUnwrappedWavePlane(raw_wave_plane,unwrapped);
    map_options.unwrap_method=unwrap_methods(method_index);
    speed_map=oce.dispersion.estimateLocalSpeedMap(wave_plane,map_options);
    young_map=oce.elastography.invertYoungModulus(speed_map,young_options);
    comparison{method_index}=struct('unwrap',unwrapped,'data',wave_plane, ...
        'speed',speed_map,'young',young_map);
end

%% 4. REVIEW NUMERICAL PRODUCTS AND SAVE ONLY MAP IMAGES TO THE GALLERY
if ~isfolder(output_folder),mkdir(output_folder);end
if ~isfolder(gallery_folder),mkdir(gallery_folder);end
save(fullfile(output_folder,'unwrap_comparison.mat'),'comparison', ...
    'plane_options','unwrap_dimensions','tie_iterations','map_options','young_options','-v7.3');
comparison_figure=figure('Color','white','Position',[60 40 1500 850]);
comparison_layout=tiledlayout(comparison_figure,2,numel(unwrap_methods),'TileSpacing','compact');
for kind=1:2
    for method_index=1:numel(unwrap_methods)
        current=comparison{method_index};
        if kind==1,values=current.speed.speed_m_s;units='m/s';limits=speed_limits_m_s;
        else,values=current.young.young_pa/1000;units='kPa';limits=young_limits_kpa;end
        current_axes=nexttile(comparison_layout);
        image_handle=imagesc(current_axes,current.data.x_m*1000,current.data.row_m*1000,values);
        image_handle.AlphaData=isfinite(values);current_axes.Color=[.85 .85 .85];
        colormap(current_axes,turbo);clim(current_axes,limits);
        color_handle=colorbar(current_axes);color_handle.Label.String=units;
        xlabel(current_axes,'X (mm)');ylabel(current_axes,'Y/Z (mm)');
        title(current_axes,unwrap_methods(method_index),'Interpreter','none');
    end
end
title(comparison_layout,'Raw optical phase → unwrap → processing → phase derivative 2D');
exportgraphics(comparison_figure,fullfile(gallery_folder,'unwrap_interactive_speed_young.png'),'Resolution',160);
