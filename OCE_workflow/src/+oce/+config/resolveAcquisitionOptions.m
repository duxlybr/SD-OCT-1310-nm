function options = resolveAcquisitionOptions( ...
        baseOptions, acquisitionRow, acquisitionHeader)
%RESOLVEACQUISITIONOPTIONS Resolve canonical acquisition mode and geometry.

    base = validate_base_options(baseOptions);
    rowMode = row_taxonomy(acquisitionRow, 'acquisition_mode');
    configuredMode = validate_mode(base.acquisition_mode);
    if rowMode ~= configuredMode
        error('OCE:Acquisition:AcquisitionModeMismatch', ...
            ['Acquisition row mode "%s" does not match configured mode ' ...
             '"%s".'], rowMode, configuredMode);
    end

    rowGeometry = row_taxonomy(acquisitionRow, 'scan_geometry');
    selection = lower(strtrim(require_text_scalar( ...
        base.scan_geometry_selection, ...
        'OCE:Acquisition:InvalidGeometrySelection', ...
        'AcquisitionOptions.scan_geometry_selection')));
    switch selection
        case "automatic"
            scanGeometry = rowGeometry;
        case "manual"
            scanGeometry = require_scan_geometry(base.scan_geometry);
            if scanGeometry ~= rowGeometry
                error('OCE:Acquisition:ScanGeometryMismatch', ...
                    ['Manual scan geometry "%s" contradicts acquisition row ' ...
                     'scan_geometry "%s".'], scanGeometry, rowGeometry);
            end
        otherwise
            error('OCE:Acquisition:InvalidGeometrySelection', ...
                ['AcquisitionOptions.scan_geometry_selection must be ' ...
                 '"automatic" or "manual"; received "%s".'], selection);
    end

    scanGeometry = validate_supported_geometry(scanGeometry);
    validate_bmode_header(acquisitionHeader);
    sourceMetadata = struct( ...
        'num_3d_scans', acquisitionHeader.No_3Dscans, ...
        'bframes_in_3d_scan', acquisitionHeader.Bframes_in_3Dscan, ...
        'alines_in_bframe', acquisitionHeader.Alines_in_Bframe, ...
        'samples_in_aline', acquisitionHeader.samples_in_Aline);
    options = struct( ...
        'acquisition_mode', rowMode, ...
        'scan_geometry', scanGeometry, ...
        'acquisition_mode_source', "acquisition_row.acquisition_mode", ...
        'scan_geometry_source', "acquisition_row.scan_geometry", ...
        'source_metadata', sourceMetadata);
end

function base = validate_base_options(value)
    if ~isstruct(value) || ~isscalar(value)
        error('OCE:Acquisition:InvalidAcquisitionOptions', ...
            'AcquisitionOptions must be a scalar struct.');
    end
    canonical = ["acquisition_mode"; "scan_geometry_selection"; ...
        "scan_geometry"];
    if ~isequal(string(fieldnames(value)), canonical)
        error('OCE:Acquisition:InvalidAcquisitionOptions', ...
            ['AcquisitionOptions must contain exactly acquisition_mode, ' ...
             'scan_geometry_selection, and scan_geometry. Legacy selection/' ...
             'protocol configuration is no longer accepted.']);
    end
    base = value;
end

function value = validate_mode(value)
    value = lower(strtrim(require_text_scalar(value, ...
        'OCE:Acquisition:InvalidAcquisitionMode', ...
        'AcquisitionOptions.acquisition_mode')));
    if value ~= "mb_mode"
        error('OCE:Acquisition:UnsupportedAcquisitionMode', ...
            ['Unsupported acquisition mode "%s". The only maintained ' ...
             'mode is "mb_mode".'], value);
    end
end

function value = row_taxonomy(row, columnName)
    if ~istable(row) || height(row) ~= 1 || ...
            ~ismember(columnName, row.Properties.VariableNames)
        error('OCE:Acquisition:UnknownGeometryMetadata', ...
            'Acquisition row must contain canonical column %s.', columnName);
    end
    value = row.(columnName);
    if iscell(value) && isscalar(value)
        value = value{1};
    end
    value = lower(strtrim(require_text_scalar(value, ...
        'OCE:Acquisition:UnknownGeometryMetadata', ...
        "acquisition_row." + string(columnName))));
    if strlength(value) == 0
        error('OCE:Acquisition:UnknownGeometryMetadata', ...
            'acquisition_row.%s must not be empty.', columnName);
    end
end

function value = require_scan_geometry(value)
    value = lower(strtrim(require_text_scalar(value, ...
        'OCE:Acquisition:MissingScanGeometry', ...
        'AcquisitionOptions.scan_geometry')));
    if strlength(value) == 0
        error('OCE:Acquisition:MissingScanGeometry', ...
            'scan_geometry is required for manual geometry selection.');
    end
end

function value = validate_supported_geometry(value)
    if ismember(value, ["angular_bmodes", "raster"])
        return;
    end
    error('OCE:Acquisition:UnsupportedScanGeometry', ...
        'Unsupported scan geometry "%s".', value);
end

function value = require_text_scalar(value, identifier, label)
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error(identifier, '%s must be a text scalar.', label);
    end
    value = string(value);
    if ismissing(value)
        value = "";
    end
end

function validate_bmode_header(header)
    if ~isstruct(header) || ~isscalar(header)
        error('OCE:Acquisition:GeometryHeaderMismatch', ...
            'A scalar acquisition header is required.');
    end
    fields = {'No_3Dscans', 'Bframes_in_3Dscan', ...
        'Alines_in_Bframe', 'samples_in_Aline'};
    for index = 1:numel(fields)
        name = fields{index};
        if ~isfield(header, name) || ~isnumeric(header.(name)) || ...
                ~isscalar(header.(name)) || ~isfinite(header.(name)) || ...
                header.(name) <= 0 || header.(name) ~= round(header.(name))
            error('OCE:Acquisition:GeometryHeaderMismatch', ...
                'Header field %s must be a positive integer.', name);
        end
    end
end
