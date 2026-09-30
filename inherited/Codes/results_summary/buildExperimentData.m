function experiment = buildExperimentData(rootdir, loadfile, vars_keys, variables, vars_to_save)
% BUILDEXPERIMENTDATA Builds an N-dimensional dataset from folder structure.
%
% This function scans a directory tree containing .mat files, extracts
% experimental parameters encoded in folder names, and organizes the
% loaded variables into an N-dimensional cell array.
%
% Inputs:
%   rootdir      - Root directory containing experiment folders.
%   loadfile     - Name of the .mat file to load in each folder.
%   vars_keys    - Cell array of parameter keys encoded in folder names.
%   variables    - Cell array defining possible values for each dimension.
%   vars_to_save - Cell array of variable names to extract from .mat files.
%
% Outputs:
%   experiment   - Struct containing:
%                  .variables -> experimental grid definition
%                  .data      -> N-D cell array with loaded data structs
%
% Notes:
%   - Folder names must encode parameters using vars_keys.
%   - Each folder must contain the file specified in loadfile.
%   - Assumes consistent ordering of experimental dimensions.

%% Get all .mat files recursively
filelist = dir(fullfile(rootdir, '**\*.mat'));
folders = {filelist.folder};

% Determine size of each experimental dimension
dim_sizes = cellfun(@length, variables);

% Initialize N-D cell storage
data_storage = cell(dim_sizes);

% Loop over each folder
for i_folder = 1:length(folders)
    folder_name = folders{i_folder};

    % Split folder path and extract experiment encoding
    sub_folders = strsplit(folder_name, '\');
    exp_values = strsplit(sub_folders{end}, '_');

    % Match keys inside folder tags
    results = cellfun(@(x) regexp(x, strjoin(strcat('(', vars_keys, ')'), '|'), 'once'), ...
        exp_values, 'UniformOutput', false);

    % Logical mask for valid matches
    mask = ~cellfun(@isempty, results);

    % Keep only matched values
    values = exp_values(mask);

    % Identify which key corresponds to each value
    keys = vars_keys(cellfun(@(x) find(~cellfun(@isempty, regexp(x, vars_keys))), values));

    % Extract parameter values after keys
    param_values = arrayfun(@(x) values{x}(length(keys{x})+1:end), ...
        1:length(values), 'UniformOutput', false);

    disp(param_values);

    % Convert parameter values to numeric indices
    dim_indices = zeros(1, length(variables));
    for i_dim = 1:length(variables)
        dim_indices(i_dim) = find(strcmp(variables{i_dim}, param_values{i_dim}));
    end

    % Load .mat file
    mat_data = load(fullfile(folder_name, loadfile));

    % Store selected variables
    experiment_data = struct();
    for i_var = 1:length(vars_to_save)
        var_name = vars_to_save{i_var};
        experiment_data.(var_name) = mat_data.(var_name);
    end

    % Convert indices for N-D assignment
    indices_cell = num2cell(dim_indices);

    % Store experiment data in N-D cell
    data_storage{indices_cell{:}} = experiment_data;
end

% Wrap output into struct
experiment = struct();
experiment.vars_keys = vars_keys;
experiment.variables = variables;
experiment.data = data_storage;

end