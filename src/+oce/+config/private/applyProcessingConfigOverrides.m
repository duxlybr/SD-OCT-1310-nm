function configForRun = applyProcessingConfigOverrides( ...
        configForRun, processingConfig, acquisitionRow)
%APPLYPROCESSINGCONFIGOVERRIDES Apply one run/file-specific config override.

    if isempty(fieldnames(processingConfig.per_acquisition))
        return;
    end

    override = struct();
    if ismember('run_id', acquisitionRow.Properties.VariableNames)
        runID = string(acquisitionRow.run_id);
        if ~ismissing(runID) && strlength(strtrim(runID)) > 0
            runField = matlab.lang.makeValidName(char(runID));
            if isfield(processingConfig.per_acquisition, runField)
                override = processingConfig.per_acquisition.(runField);
            end
        end
    end

    if isempty(fieldnames(override)) && ...
            ismember('filename', acquisitionRow.Properties.VariableNames)
        filename = string(acquisitionRow.filename);
        if ~ismissing(filename) && strlength(strtrim(filename)) > 0
            fileField = matlab.lang.makeValidName(char(filename));
            if isfield(processingConfig.per_acquisition, fileField)
                override = processingConfig.per_acquisition.(fileField);
            end
        end
    end

    if ~isempty(fieldnames(override))
        configForRun = merge_struct(configForRun, override);
    end
end

function base = merge_struct(base, override)
    names = fieldnames(override);
    for index = 1:numel(names)
        name = names{index};
        if isstruct(override.(name)) && ...
                isfield(base, name) && isstruct(base.(name))
            base.(name) = merge_struct(base.(name), override.(name));
        else
            base.(name) = override.(name);
        end
    end
end
