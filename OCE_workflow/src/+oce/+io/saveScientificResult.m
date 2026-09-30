function resultPath = saveScientificResult(outputDirectory, oceResult)
%SAVESCIENTIFICRESULT Atomically persist one validated oce_result variable.

    if ~(ischar(outputDirectory) || ...
            (isstring(outputDirectory) && isscalar(outputDirectory))) || ...
            ~isfolder(outputDirectory)
        error('OCE:Result:InvalidOutputDirectory', ...
            'An existing output directory is required.');
    end
    oce.results.validateScientificResult(oceResult);
    outputDirectory = char(outputDirectory);
    resultPath = fullfile(outputDirectory, 'PhaseSpeed.mat');
    temporaryPath = fullfile(outputDirectory, 'PhaseSpeed.tmp.mat');
    if isfile(temporaryPath)
        error('OCE:Result:TemporaryExists', ...
            'Refusing to overwrite existing temporary file: %s', ...
            temporaryPath);
    end
    cleanup = onCleanup(@() remove_temporary(temporaryPath));
    oce_result = oceResult;
    save(temporaryPath, 'oce_result', '-v7');
    reloaded = oce.io.loadScientificResult(temporaryPath);
    if ~isequaln(reloaded, oceResult)
        error('OCE:Result:ReloadMismatch', ...
            'Reloaded temporary result differs from the input contract.');
    end
    [moved, message] = movefile(temporaryPath, resultPath, 'f');
    if ~moved
        error('OCE:Result:AtomicReplaceFailed', '%s', message);
    end
    final = oce.io.loadScientificResult(resultPath);
    if ~isequaln(final, oceResult)
        error('OCE:Result:ReloadMismatch', ...
            'Final persisted result differs from the input contract.');
    end
    clear cleanup
end

function remove_temporary(pathValue)
    if isfile(pathValue), delete(pathValue); end
end
