function processing_config = getDefaultProcessingConfig(profile)
%GETDEFAULTPROCESSINGCONFIG Create the canonical editable processing config.
%
% Usage:
%   processing_config = oce.config.getDefaultProcessingConfig("phantom")
%   processing_config = oce.config.getDefaultProcessingConfig("in_vivo_eye")
%   processing_config = oce.config.getDefaultProcessingConfig("ex_vivo_eye")

    if nargin ~= 1
        error('OCE:Config:InvalidProcessingProfile', ...
            ['Processing profile must be one scalar canonical name: ' ...
             '"phantom", "in_vivo_eye", or "ex_vivo_eye".']);
    end
    profile = validate_profile(profile);

    processing_config = struct();
    processing_config.profile = profile;
    processing_config.created_by = "get_default_processing_config";
    processing_config.created_at = string(datetime('now'));

    processing_config.AcquisitionOptions = struct( ...
        'acquisition_mode', "mb_mode", ...
        'scan_geometry_selection', "automatic", ...
        'scan_geometry', "");
    processing_config.OCTSystemOptions = ...
        oce.config.getOCTSystemOptions("swept_source_1300");
    processing_config.SampleOpticalOptions = ...
        getDefaultSampleOpticalOptions(profile);

    processing_config.DispersionAnalysisOptions = ...
        getDefaultDispersionAnalysisOptions();
    processing_config.FilterOptions = getDefaultFilterOptions();
    processing_config.BorderOptions = getDefaultBorderOptions(profile);
    processing_config.MotionOptions = getDefaultMotionOptions();
    processing_config.DispersionWindowOptions = ...
        getDefaultDispersionWindowOptions();

    processing_config.VisualizationOptions = struct();
    processing_config.VisualizationOptions.CLim = 0.1;
    processing_config.VisualizationOptions.save_figures = true;
    processing_config.VisualizationOptions.save_videos = true;
    processing_config.VisualizationOptions.close_figures = true;

    processing_config.VideoOptions = struct();
    processing_config.VideoOptions.time_start_idx = 1;
    processing_config.VideoOptions.max_frames = 350;
    processing_config.VideoOptions.frame_rate = 30;
    processing_config.VideoOptions.filename = "Video_2D_Filtered.mp4";

    processing_config.per_acquisition = struct();
    oce.config.validateProcessingConfig(processing_config);
end

function profile = validate_profile(profile)
    if ~(ischar(profile) || (isstring(profile) && isscalar(profile)))
        error('OCE:Config:InvalidProcessingProfile', ...
            ['Processing profile must be one scalar canonical name: ' ...
             '"phantom", "in_vivo_eye", or "ex_vivo_eye".']);
    end

    profile = string(profile);
    supportedProfiles = ["phantom", "in_vivo_eye", "ex_vivo_eye"];
    if ismissing(profile) || ~ismember(profile, supportedProfiles)
        error('OCE:Config:InvalidProcessingProfile', ...
            ['Unsupported processing profile "%s". Supported profiles ' ...
             'are "phantom", "in_vivo_eye", and "ex_vivo_eye".'], ...
            profile);
    end
end
