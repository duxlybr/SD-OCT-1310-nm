function test_fireice_dependency_contract(context)
%TEST_FIREICE_DEPENDENCY_CONTRACT Validate the vendored colormap dependency.

    expectedPath = fullfile(context.repoRoot, 'third_party', 'fireice', 'fireice.m');
    locations = which('fireice', '-all');
    if ischar(locations), locations = {locations}; end
    if numel(locations) ~= 1 || ~strcmpi(string(locations{1}), expectedPath)
        error('OCE:Fireice:Resolution', ...
            'Expected one fireice definition at %s.', expectedPath);
    end
    if isfile(fullfile(context.repoRoot, 'Codes', 'fireice.m'))
        error('OCE:Fireice:Duplicate', 'An additional fireice copy exists.');
    end

    reference7 = [ ...
        0.75 1 1; 0 1 1; 0 0 1; 0 0 0; ...
        1 0 0; 1 1 0; 1 1 0.75];
    actual7 = fireice(7);
    if ~isequal(actual7, reference7)
        error('OCE:Fireice:NumericContract', ...
            'The exact seven-color fireice contract changed.');
    end
    sizes = [1 2 7 64 256];
    for index = 1:numel(sizes)
        first = fireice(sizes(index));
        second = fireice(sizes(index));
        if ~isa(first, 'double') || ~isequal(size(first), [sizes(index) 3]) || ...
                ~isequal(first, second)
            error('OCE:Fireice:Contract', ...
                'Class, shape, or determinism changed for m=%d.', sizes(index));
        end
    end
    if ~isequal(fireice(1), [0 0 0])
        error('OCE:Fireice:Endpoint', 'The one-color endpoint changed.');
    end

    altered = actual7;
    altered(1, 1) = altered(1, 1) + eps;
    if isequal(actual7, altered)
        error('OCE:Fireice:NegativeControl', ...
            'Intentional colormap difference was not detected.');
    end

    spaceTimeRenderer = fullfile(context.repoRoot, 'src', '+oce', ...
        '+plotting', 'plotBmodeSpaceTime.m');
    windowContext = fullfile(context.repoRoot, 'src', '+oce', ...
        '+plotting', 'plotDispersionWindowContext.m');
    rendererSource = fileread(spaceTimeRenderer);
    contextSource = fileread(windowContext);
    if ~contains(rendererSource, 'fireice')
        error('OCE:Fireice:Caller', ...
            'Canonical space-time renderer no longer uses fireice: %s.', ...
            spaceTimeRenderer);
    end
    if ~contains(contextSource, 'oce.plotting.plotBmodeSpaceTime') || ...
            contains(contextSource, 'fireice')
        error('OCE:Fireice:RendererReuse', ...
            ['Dispersion-window context must reuse the canonical space-time ' ...
             'renderer instead of owning a second colormap implementation.']);
    end
end
