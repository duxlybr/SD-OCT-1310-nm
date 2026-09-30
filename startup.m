function startup
%STARTUP Initialize the maintained OCE runtime paths.
%
% Canonical first-party code and required third-party roots are added explicitly.
% Historical Codes, Processing, inherited, demos, and FEX dependency folders
% are intentionally excluded.

    repositoryRoot = fileparts(mfilename('fullpath'));
    requiredPaths = [ ...
        string(fullfile(repositoryRoot, 'src')); ...
        string(fullfile(repositoryRoot, 'third_party', 'MIMT')); ...
        string(fullfile(repositoryRoot, 'third_party', 'fireice'))];

    currentPaths = string(strsplit(path, pathsep));
    for index = 1:numel(requiredPaths)
        if ~any(strcmpi(currentPaths, requiredPaths(index)))
            addpath(requiredPaths(index), '-end');
            currentPaths(end + 1) = requiredPaths(index); %#ok<AGROW>
        end
    end
end
