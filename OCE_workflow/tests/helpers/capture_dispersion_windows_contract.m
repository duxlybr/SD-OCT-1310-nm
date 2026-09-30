function contract = capture_dispersion_windows_contract(method, fixture)
%CAPTURE_DISPERSION_WINDOWS_CONTRACT Capture explicit results and errors.

    names = fieldnames(fixture.cases);
    contract.outputs = struct();
    for index = 1:numel(names)
        name = names{index};
        transcript = evalc('result = method(fixture.cases.(name), fixture.filter_result, fixture.x_axis_mm, fixture.resolved_filter, fixture.geometry);');
        contract.outputs.(name) = struct( ...
            'result', result, 'transcript', string(transcript));
    end
    names = fieldnames(fixture.invalid);
    contract.errors = struct();
    for index = 1:numel(names)
        name = names{index};
        contract.errors.(name) = capture_error(@() method( ...
            fixture.invalid.(name), fixture.filter_result, ...
            fixture.x_axis_mm, fixture.resolved_filter, fixture.geometry));
    end
end

function captured = capture_error(callback)
    try
        callback();
        captured = struct('identifier', "", 'message', "");
    catch ME
        captured = struct('identifier', string(ME.identifier), ...
            'message', string(ME.message));
    end
end
