function oceResult = loadScientificResult(resultPath)
%LOADSCIENTIFICRESULT Load and validate one versioned scientific result.

    if ~(ischar(resultPath) || ...
            (isstring(resultPath) && isscalar(resultPath))) || ...
            ~isfile(resultPath)
        error('OCE:Result:MissingRootVariable', ...
            'A readable scientific-result MAT file is required.');
    end
    variables = whos('-file', resultPath);
    names = string({variables.name});
    if ~any(names == "oce_result")
        error('OCE:Result:MissingRootVariable', ...
            'MAT file does not contain the required oce_result root variable.');
    end
    if numel(variables) ~= 1
        error('OCE:Result:UnexpectedVariables', ...
            'Scientific-result MAT must contain only oce_result.');
    end
    if ~strcmp(variables.class, 'struct') || ...
            ~isequal(variables.size, [1 1])
        error('OCE:Result:InvalidContract', ...
            'oce_result must be a scalar struct.');
    end
    loaded = load(resultPath, '-mat');
    oceResult = loaded.oce_result;
    oce.results.validateScientificResult(oceResult);
end
