function initialize_repository()
%INITIALIZE_REPOSITORY Initialize maintained paths for human workflows.

    repositoryRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    wasOnPath = contains(path, repositoryRoot);
    if ~wasOnPath
        addpath(repositoryRoot);
    end
    cleanup = onCleanup(@() restore_path(repositoryRoot, wasOnPath));
    startup;
    clear cleanup
end

function restore_path(repositoryRoot, wasOnPath)
    if ~wasOnPath
        rmpath(repositoryRoot);
    end
end
