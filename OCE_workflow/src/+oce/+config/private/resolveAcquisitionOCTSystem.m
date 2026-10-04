function resolved = resolveAcquisitionOCTSystem( ...
        configured, acquisitionRow, acquisitionParameters, acquisitionHeader)
%RESOLVEACQUISITIONOCTSYSTEM Resolve OCT profile from canonical acquisition metadata.
% The normalized acquisition header supplies the measured A-line rate when
% it records one.

    profile = required_row_text(acquisitionRow, 'oct_system_profile');
    profile = lower(strtrim(profile));
    if ~ismember(profile, ["swept_source_1300", ...
            "spectral_domain_1040", "spectral_domain_1310"])
        error('OCE:Config:InvalidOCTSystemProfile', ...
            'Unsupported acquisition_row.oct_system_profile "%s".', profile);
    end

    if ~isstruct(configured) || ~isscalar(configured) || ...
            ~isfield(configured, 'profile') || ...
            lower(strtrim(string(configured.profile))) ~= profile
        error('OCE:Config:OCTSystemProfileMismatch', ...
            ['ProcessingConfig OCT profile must match acquisition metadata. ' ...
             'Row="%s" Config="%s".'], profile, configured_profile(configured));
    end

    resolved = oce.config.resolveOCTSystemOptions( ...
        configured, prepared_oct_profile(acquisitionParameters), ...
        acquisitionHeader);
    resolved.selection_source = "acquisition_row.oct_system_profile";
end

function value = configured_profile(options)
    value = "<missing>";
    if isstruct(options) && isscalar(options) && isfield(options, 'profile')
        value = string(options.profile);
    end
end

function value = required_row_text(row, columnName)
    if ~istable(row) || height(row) ~= 1 || ...
            ~ismember(columnName, row.Properties.VariableNames)
        error('OCE:Config:MissingAcquisitionMetadata', ...
            'acquisition_row.%s is required.', columnName);
    end

    raw = row.(columnName);
    if iscell(raw) && isscalar(raw)
        raw = raw{1};
    end
    if ~(ischar(raw) || (isstring(raw) && isscalar(raw)))
        error('OCE:Config:MissingAcquisitionMetadata', ...
            'acquisition_row.%s must be a text scalar.', columnName);
    end

    value = strtrim(string(raw));
    if ismissing(value) || strlength(value) == 0
        error('OCE:Config:MissingAcquisitionMetadata', ...
            'acquisition_row.%s must not be empty.', columnName);
    end
end

function profile = prepared_oct_profile(acquisitionParameters)
    profile = "";
    if isstruct(acquisitionParameters) && ...
            isfield(acquisitionParameters, 'source') && ...
            isstruct(acquisitionParameters.source) && ...
            isfield(acquisitionParameters.source, 'oct_system_profile')
        profile = acquisitionParameters.source.oct_system_profile;
    end
end
