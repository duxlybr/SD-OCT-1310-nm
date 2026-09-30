function [logTable, sheetTables, savedPaths] = loadExperimentalLog(logPath, varargin)
%LOADEXPERIMENTALLOG Read, validate, and optionally persist acquisition metadata.
% Row 1 contains visual section headers, row 2 variable names, row 3+ data.

    if nargin < 1 || isempty(logPath)
        error('logPath is required.');
    end

    p = inputParser;
    addParameter(p, 'Sheet', 'Experiment', @(x) ischar(x) || isstring(x));
    addParameter(p, 'HeaderRow', 2, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'DataStartRow', 3, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'SaveAcquisitionParams', false, @islogical);
    addParameter(p, 'Overwrite', true, @islogical);
    parse(p, varargin{:});

    logPath = char(logPath);
    if ~isfile(logPath)
        error('Experimental log not found: %s', logPath);
    end

    experimentRoot = fileparts(logPath);
    requestedSheet = string(p.Results.Sheet);
    if strcmpi(requestedSheet, 'all')
        sheetsToRead = string(sheetnames(logPath));
    else
        sheetsToRead = requestedSheet;
    end

    sheetTables = struct();
    savedPaths = struct();
    allTables = cell(0, 1);

    for index = 1:numel(sheetsToRead)
        sheetName = sheetsToRead(index);
        T = read_log_sheet(logPath, sheetName, ...
            p.Results.HeaderRow, p.Results.DataStartRow);
        T = remove_empty_rows(T);
        if height(T) == 0
            continue;
        end

        T = ensure_source_sheet(T, sheetName);
        T = validateAcquisitionTable(T, ...
            "experimental_log sheet " + sheetName);

        safeSheetField = matlab.lang.makeValidName(char(sheetName));
        sheetTables.(safeSheetField) = T;
        allTables{end + 1, 1} = T; %#ok<AGROW>

        if p.Results.SaveAcquisitionParams
            saved = save_by_subexperiment( ...
                T, experimentRoot, p.Results.Overwrite);
            savedPaths = merge_structs(savedPaths, saved);
        end
    end

    if isempty(allTables)
        logTable = table();
        warning('No data rows were found in the selected sheet(s).');
        return;
    end

    logTable = allTables{1};
    for index = 2:numel(allTables)
        logTable = vertcat_with_missing_columns(logTable, allTables{index});
    end
    logTable = validateAcquisitionTable(logTable, "combined experimental_log");
end

function T = read_log_sheet(logPath, sheetName, headerRow, dataStartRow)
    opts = detectImportOptions(logPath, ...
        'Sheet', char(sheetName), ...
        'VariableNamesRange', sprintf('%d:%d', headerRow, headerRow), ...
        'DataRange', sprintf('A%d', dataStartRow), ...
        'VariableNamingRule', 'preserve');
    opts.VariableNamingRule = 'preserve';
    opts = setvartype(opts, opts.VariableNames, 'char');
    T = readtable(logPath, opts);
    for column = 1:width(T)
        value = T.(column);
        if iscellstr(value) || ischar(value) || isstring(value)
            T.(column) = string(value);
        end
    end
end

function T = remove_empty_rows(T)
    if isempty(T)
        return;
    end
    keep = false(height(T), 1);
    for row = 1:height(T)
        for column = 1:width(T)
            if is_nonempty_value(T{row, column})
                keep(row) = true;
                break;
            end
        end
    end
    T = T(keep, :);
end

function tf = is_nonempty_value(value)
    if iscell(value)
        tf = any(cellfun(@is_nonempty_value, value));
    elseif isstring(value)
        tf = any(~ismissing(value) & strlength(strtrim(value)) > 0);
    elseif ischar(value)
        tf = ~isempty(strtrim(value));
    elseif isnumeric(value)
        tf = any(~isnan(value(:)));
    elseif islogical(value)
        tf = any(value(:));
    else
        tf = ~isempty(value);
    end
end

function T = ensure_source_sheet(T, sheetName)
    if ~ismember('source_sheet', T.Properties.VariableNames)
        T.source_sheet = repmat(string(sheetName), height(T), 1);
    end
end

function savedPaths = save_by_subexperiment(T, experimentRoot, overwrite)
    savedPaths = struct();
    groups = unique(string(T.sub_experiment), 'stable');
    for index = 1:numel(groups)
        subExperiment = groups(index);
        acquisition_table = T(string(T.sub_experiment) == subExperiment, :);

        safeName = matlab.lang.makeValidName(char(subExperiment));
        paramsDir = fullfile(experimentRoot, 'Params', char(subExperiment));
        if ~exist(paramsDir, 'dir')
            mkdir(paramsDir);
        end
        savedPath = fullfile(paramsDir, ['AcquisitionParams_' safeName '.mat']);
        if exist(savedPath, 'file') && ~overwrite
            error(['Acquisition params file already exists:\n%s\n' ...
                'Use Overwrite=true to replace it.'], savedPath);
        end
        save(savedPath, 'acquisition_table');
        fprintf('Saved acquisition params to:\n%s\n', savedPath);
        savedPaths.(safeName) = savedPath;
    end
end

function output = merge_structs(output, added)
    names = fieldnames(added);
    for index = 1:numel(names)
        output.(names{index}) = added.(names{index});
    end
end

function T = vertcat_with_missing_columns(A, B)
    allColumns = union(string(A.Properties.VariableNames), ...
        string(B.Properties.VariableNames), 'stable');
    A = add_missing_columns(A, allColumns);
    B = add_missing_columns(B, allColumns);
    T = [A(:, cellstr(allColumns)); B(:, cellstr(allColumns))];
end

function T = add_missing_columns(T, allColumns)
    missing = setdiff(allColumns, string(T.Properties.VariableNames), 'stable');
    for index = 1:numel(missing)
        T.(missing(index)) = strings(height(T), 1);
    end
end
