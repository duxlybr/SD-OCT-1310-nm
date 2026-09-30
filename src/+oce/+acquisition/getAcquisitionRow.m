function acquisition_row = getAcquisitionRow(acquisition_table, queryValue, varargin)
%GETACQUISITIONROW Return one exact acquisition row from acquisition_table.
% Matching is case-insensitive and uses the selected canonical table column.

    if nargin < 1 || isempty(acquisition_table)
        error('acquisition_table is required.');
    end
    if nargin < 2 || isempty(queryValue)
        error('queryValue is required.');
    end

    p = inputParser;
    addParameter(p, 'Key', 'filename', @(x) ischar(x) || isstring(x));
    parse(p, varargin{:});
    key = char(p.Results.Key);

    if ~istable(acquisition_table)
        error('acquisition_table must be a MATLAB table.');
    end
    if ~ismember(key, acquisition_table.Properties.VariableNames)
        error('Column "%s" was not found in acquisition_table.', key);
    end

    columnValues = lower(string(acquisition_table.(key)));
    queryValue = lower(string(queryValue));
    matchIdx = columnValues == queryValue;
    nMatches = nnz(matchIdx);

    if nMatches == 0
        error('No acquisition row found where %s matches "%s".', key, queryValue);
    end
    if nMatches > 1
        error(['Multiple acquisition rows found where %s matches "%s". ' ...
            'Use a more specific query.'], key, queryValue);
    end

    acquisition_row = acquisition_table(matchIdx, :);
end
