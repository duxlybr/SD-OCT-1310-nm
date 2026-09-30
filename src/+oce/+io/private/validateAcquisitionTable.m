function T = validateAcquisitionTable(T, context)
%VALIDATEACQUISITIONTABLE Validate and normalize canonical acquisition metadata.

    if nargin < 2 || strlength(strtrim(string(context))) == 0
        context = "acquisition_table";
    else
        context = string(context);
    end
    if ~istable(T) || height(T) < 1
        error('OCE:IO:InvalidAcquisitionTable', ...
            '%s must be a nonempty table.', context);
    end

    actual = string(T.Properties.VariableNames);
    legacy = intersect( ...
        ["acquisition_protocol"; "scan_type"; "study_type"], ...
        actual, 'stable');
    if ~isempty(legacy)
        error('OCE:IO:LegacyAcquisitionTableSchema', ...
            ['%s contains retired column(s): %s. Use experiment_type for ' ...
             'experiment semantics, excitation_type for excitation semantics, ' ...
             'acquisition_mode + scan_geometry for acquisition taxonomy, and ' ...
             'oct_system_profile for OCT hardware.'], ...
            context, strjoin(legacy, ', '));
    end

    retiredDimensions = intersect( ...
        ["alines_per_bframe"; "bframes_3d"; "cluster_count"; "sync_samples"], ...
        actual, 'stable');
    if ~isempty(retiredDimensions)
        error('OCE:IO:LegacyAcquisitionTableSchema', ...
            ['%s contains retired acquisition-dimension column(s): %s. ' ...
             'Use alines_per_bscan, m_repetitions, and bscan_count. ' ...
             'Hardware/storage-specific sync samples belong to raw-header ' ...
             'provenance, not canonical Experimental Log geometry metadata.'], ...
            context, strjoin(retiredDimensions, ', '));
    end

    required = [ ...
        "experiment_id"; "sub_experiment"; "run_id"; "filename"; ...
        "sample_type"; "experiment_type"; "excitation_type"; ...
        "acquisition_mode"; "scan_geometry"; "oct_system_profile"; ...
        "frequency_Hz"; "rep_id"];
    missing = setdiff(required, actual, 'stable');
    if ~isempty(missing)
        error('OCE:IO:InvalidAcquisitionTable', ...
            '%s is missing required column(s): %s.', ...
            context, strjoin(missing, ', '));
    end

    textColumns = ["experiment_id"; "sub_experiment"; "run_id"; ...
        "filename"; "sample_type"; "experiment_type"; ...
        "excitation_type"; "acquisition_mode"; "scan_geometry"; ...
        "oct_system_profile"];
    for index = 1:numel(textColumns)
        name = textColumns(index);
        T.(name) = normalize_text_column(T.(name), context + "." + name);
    end

    T.sample_type = lower(T.sample_type);
    T.experiment_type = lower(T.experiment_type);
    T.excitation_type = lower(T.excitation_type);
    T.acquisition_mode = lower(T.acquisition_mode);
    T.scan_geometry = lower(T.scan_geometry);
    T.oct_system_profile = lower(T.oct_system_profile);

    validate_identifiers(T.experiment_type, context + ".experiment_type");
    validate_identifiers(T.excitation_type, context + ".excitation_type");
    validate_allowed(T.sample_type, ...
        ["phantom", "in_vivo_eye", "ex_vivo_eye"], ...
        context + ".sample_type");
    validate_allowed(T.acquisition_mode, "mb_mode", ...
        context + ".acquisition_mode");
    validate_allowed(T.scan_geometry, ...
        ["angular_bmodes", "raster"], context + ".scan_geometry");
    validate_allowed(T.oct_system_profile, ...
        ["swept_source_1300", "spectral_domain_1040", ...
         "spectral_domain_1310"], ...
        context + ".oct_system_profile");

    if any(~endsWith(lower(T.filename), ".bin"))
        error('OCE:IO:InvalidAcquisitionTable', ...
            '%s.filename values must identify .bin acquisitions.', context);
    end

    if isnumeric(T.frequency_Hz)
        frequencyValues = double(T.frequency_Hz(:));
    else
        frequencyValues = str2double(string(T.frequency_Hz(:)));
    end
    pulseRows = T.excitation_type == "pulse";
    invalidFrequency = (~pulseRows & ...
        (~isfinite(frequencyValues) | frequencyValues <= 0)) | ...
        (pulseRows & ~(isnan(frequencyValues) | ...
        (isfinite(frequencyValues) & frequencyValues > 0)));
    if any(invalidFrequency)
        error('OCE:IO:InvalidAcquisitionTable', ...
            ['%s.frequency_Hz must be positive and finite, or NaN when ' ...
             'excitation_type="pulse".'], context);
    end

    validate_positive_numeric_column(T.rep_id, context + ".rep_id", true);

    dimensionColumns = ["alines_per_bscan"; "m_repetitions"; "bscan_count"];
    for index = 1:numel(dimensionColumns)
        name = dimensionColumns(index);
        if ismember(name, actual)
            validate_optional_positive_integer_column( ...
                T.(name), context + "." + name);
        end
    end

    validate_subexperiment_invariants(T, context);
end

function values = normalize_text_column(raw, label)
    if iscell(raw)
        try
            values = string(raw);
        catch
            error('OCE:IO:InvalidAcquisitionTable', ...
                '%s must contain text values.', label);
        end
    elseif ischar(raw) || isstring(raw) || iscategorical(raw)
        values = string(raw);
    else
        error('OCE:IO:InvalidAcquisitionTable', ...
            '%s must contain text values.', label);
    end
    values = strtrim(values(:));
    if any(ismissing(values) | strlength(values) == 0)
        error('OCE:IO:InvalidAcquisitionTable', ...
            '%s must not contain blank values.', label);
    end
end

function validate_identifiers(values, label)
    for index = 1:numel(values)
        if isempty(regexp(char(values(index)), '^[a-z][a-z0-9_]*$', 'once'))
            error('OCE:IO:InvalidAcquisitionTable', ...
                '%s must use lower_snake_case identifiers; received "%s".', ...
                label, values(index));
        end
    end
end

function validate_allowed(values, allowed, label)
    invalid = unique(values(~ismember(values, allowed)), 'stable');
    if ~isempty(invalid)
        error('OCE:IO:InvalidAcquisitionTable', ...
            '%s contains unsupported value(s): %s. Allowed: %s.', ...
            label, strjoin(invalid, ', '), strjoin(allowed, ', '));
    end
end

function validate_positive_numeric_column(raw, label, requireInteger)
    if isnumeric(raw)
        values = double(raw(:));
    else
        values = str2double(string(raw(:)));
    end
    invalid = ~isfinite(values) | values <= 0;
    if requireInteger
        invalid = invalid | values ~= round(values);
    end
    if any(invalid)
        qualifier = "positive finite";
        if requireInteger
            qualifier = qualifier + " integer";
        end
        error('OCE:IO:InvalidAcquisitionTable', ...
            '%s must contain %s values.', label, qualifier);
    end
end

function validate_optional_positive_integer_column(raw, label)
    if isnumeric(raw)
        values = double(raw(:));
        present = ~isnan(values);
    else
        text = strtrim(string(raw(:)));
        present = ~(ismissing(text) | strlength(text) == 0);
        values = str2double(text);
    end
    invalid = present & ...
        (~isfinite(values) | values <= 0 | values ~= round(values));
    if any(invalid)
        error('OCE:IO:InvalidAcquisitionTable', ...
            '%s must contain positive finite integers when provided.', label);
    end
end

function validate_subexperiment_invariants(T, context)
    groups = unique(T.sub_experiment, 'stable');
    invariantColumns = ["acquisition_mode"; "scan_geometry"; ...
        "oct_system_profile"];
    for groupIndex = 1:numel(groups)
        rows = T.sub_experiment == groups(groupIndex);
        for columnIndex = 1:numel(invariantColumns)
            name = invariantColumns(columnIndex);
            values = unique(T.(name)(rows), 'stable');
            if numel(values) ~= 1
                error('OCE:IO:MixedSubexperimentAcquisitionMetadata', ...
                    ['%s sub_experiment "%s" must use exactly one %s. ' ...
                     'Found: %s.'], context, groups(groupIndex), name, ...
                    strjoin(values, ', '));
            end
        end
    end
end
