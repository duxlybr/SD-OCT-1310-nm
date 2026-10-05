function result = unwrapPhase(wrappedPhase, options)
%UNWRAPPHASE Unwrap raw radians on independent one- or two-dimensional slices.
% options.method is sequential, least_squares_dct, or tie_dct. dimensions is
% an ordered vector of one or two array dimensions; all other dimensions are
% independent acquisitions/slices. For [depth,x,time] optical phase, [3 1]
% means time first, then depth, independently at each x. Never select a
% dimension containing independent B-modes or unregistered acquisitions.
% valid_mask has the input size. Invalid samples remain NaN; no interpolation
% or connection across holes occurs. Pixel-neighbor weights are equal.
%
% Rectangular valid components use a DCT-II Neumann Poisson inverse. Irregular
% components use the same graph-Neumann operator with a sparse anchored solve,
% recorded in diagnostics. least_squares_dct minimizes wrapped-gradient error
% and need not be exactly congruent to the input in inconsistent/noisy data.
% tie_dct solves Im(conj(exp(i*p))*L(exp(i*p))) and applies Zhao et al.'s integer
% correction (2018, doi:10.1088/1361-6501/aaec5c). iterations is the positive,
% fixed number of correction updates AFTER the initial TIE solve. There is no
% convergence stop. TIE's final output is raw phase plus integer multiples of
% 2*pi, so its internal smooth estimate is not returned as filtered phase.
% No temporal difference, detrending, filtering, displacement, or speed is
% calculated here. A disconnected component retains its own unknown piston.

    if nargin < 2, options = struct(); end
    validateattributes(wrappedPhase, {'numeric'}, {'real','nonempty'}, ...
        mfilename, 'wrappedPhase');
    opts = resolve_options(wrappedPhase, options);
    dimensions = opts.dimensions;
    otherDimensions = setdiff(1:ndims(wrappedPhase), dimensions, 'stable');
    order = [dimensions otherDimensions];
    shape = size(wrappedPhase);
    selectedShape = shape(dimensions);
    if isscalar(dimensions), selectedShape(2) = 1; end
    phase = reshape(permute(double(wrappedPhase), order), ...
        selectedShape(1), selectedShape(2), []);
    mask = reshape(permute(opts.valid_mask, order), size(phase));
    output = NaN(size(phase));
    rectCount = 0; graphCount = 0; componentCount = 0;
    updateCount = 0; maxChangedIntegers = zeros(1, opts.iterations);
    sliceComponents = zeros(size(phase, 3), 1);
    for sliceIndex = 1:size(phase, 3)
        localPhase = phase(:, :, sliceIndex);
        localMask = mask(:, :, sliceIndex);
        components = valid_components(localMask);
        sliceComponents(sliceIndex) = numel(components);
        localOutput = NaN(size(localPhase));
        for componentIndex = 1:numel(components)
            indices = components{componentIndex};
            [rows, columns] = ind2sub(size(localMask), indices);
            rowRange = min(rows):max(rows);
            columnRange = min(columns):max(columns);
            componentMask = false(numel(rowRange), numel(columnRange));
            componentIndices = sub2ind(size(componentMask), ...
                rows - rowRange(1) + 1, columns - columnRange(1) + 1);
            componentMask(componentIndices) = true;
            local = localPhase(rowRange, columnRange);
            componentCount = componentCount + 1;
            if opts.method == "sequential"
                unwrapped = sequential_unwrap(local, componentMask);
            else
                solver = prepare_poisson(componentMask);
                if solver.kind == "dct_neumann"
                    rectCount = rectCount + 1;
                else
                    graphCount = graphCount + 1;
                end
                if opts.method == "least_squares_dct"
                    rhs = gradient_source(local, componentMask);
                    unwrapped = poisson_solve(rhs, solver);
                    anchor = find(componentMask, 1);
                    unwrapped = unwrapped + local(anchor) - unwrapped(anchor);
                else
                    [unwrapped, changed] = tie_unwrap(local, ...
                        componentMask, solver, opts.iterations);
                    updateCount = updateCount + opts.iterations;
                    maxChangedIntegers = max(maxChangedIntegers, changed);
                end
            end
            localOutput(indices) = unwrapped(componentIndices);
        end
        output(:, :, sliceIndex) = localOutput;
    end
    permutedShape = shape(order);
    values = ipermute(reshape(output, permutedShape), order);
    residual = principal(values(opts.valid_mask) - double(wrappedPhase(opts.valid_mask)));
    if isempty(residual), wrapRms = NaN; else, wrapRms = sqrt(mean(residual.^2)); end
    executed = 0;
    if opts.method == "tie_dct" && componentCount > 0
        executed = opts.iterations;
    end
    result = struct('values', values, 'quantity', "unwrapped_phase", ...
        'units', "rad", 'method', opts.method, 'dimensions', dimensions, ...
        'iterations_requested', opts.iterations, ...
        'iterations_executed', executed, ...
        'diagnostics', struct('valid_sample_count', nnz(opts.valid_mask), ...
        'independent_slice_count', size(phase, 3), ...
        'component_count', componentCount, ...
        'components_per_slice', sliceComponents, ...
        'dct_neumann_component_count', rectCount, ...
        'masked_graph_neumann_component_count', graphCount, ...
        'total_correction_updates', updateCount, ...
        'max_integer_changes_per_update', maxChangedIntegers, ...
        'wrap_consistency_rms_rad', wrapRms, ...
        'iteration_policy', "fixed correction budget; no early stop", ...
        'coordinate_metric', "equal weights for valid pixel-neighbor edges", ...
        'component_piston', "independent; first valid sample anchors each component"));
end

function opts = resolve_options(phase, options)
    if ~isstruct(options) || ~isscalar(options) || ...
            any(~ismember(string(fieldnames(options)), ...
            ["method"; "dimensions"; "iterations"; "valid_mask"]))
        error('OCE:Motion:InvalidUnwrapOptions', 'Unknown or invalid unwrap options.');
    end
    lastDimension = find(size(phase) > 1, 1, 'last');
    if isempty(lastDimension), lastDimension = 1; end
    opts = struct('method', "sequential", 'dimensions', lastDimension, ...
        'iterations', 8, 'valid_mask', isfinite(phase));
    names = fieldnames(options);
    for index = 1:numel(names), opts.(names{index}) = options.(names{index}); end
    opts.method = string(opts.method);
    if ~isscalar(opts.method) || ~ismember(opts.method, ...
            ["sequential", "least_squares_dct", "tie_dct"])
        error('OCE:Motion:InvalidUnwrapMethod', 'Unsupported phase unwrap method.');
    end
    validateattributes(opts.dimensions, {'numeric'}, ...
        {'integer','positive','vector','<=',ndims(phase)}, mfilename, 'dimensions');
    opts.dimensions = double(opts.dimensions(:).');
    if numel(opts.dimensions) > 2 || ...
            numel(unique(opts.dimensions)) ~= numel(opts.dimensions)
        error('OCE:Motion:InvalidUnwrapDimensions', 'Select one or two distinct dimensions.');
    end
    validateattributes(opts.iterations, {'numeric'}, ...
        {'scalar','integer','positive','<=',10000}, mfilename, 'iterations');
    if ~islogical(opts.valid_mask) || ~isequal(size(opts.valid_mask), size(phase)) || ...
            any(~isfinite(phase(opts.valid_mask)))
        error('OCE:Motion:InvalidUnwrapMask', 'Valid mask must match finite phase samples.');
    end
    boundaryTolerance = 64*eps(pi);
    if isa(phase,'single')
        % angle(IQ) stored as single can round +/-pi just outside the double
        % principal bound. Accept representation roundoff without changing
        % the raw branch or relaxing the double-precision contract.
        boundaryTolerance = 8*double(eps(single(pi)));
    end
    if any(abs(double(phase(opts.valid_mask))) > pi + boundaryTolerance)
        error('OCE:Motion:NotWrappedPhase', 'Input phase must lie within [-pi,pi].');
    end
end

function components = valid_components(mask)
    indices = find(mask);
    if isempty(indices), components = {}; return; end
    if all(mask(:)), components = {indices}; return; end
    nodes = zeros(size(mask)); nodes(indices) = 1:numel(indices);
    [first, second] = neighbor_edges(nodes);
    labels = conncomp(graph(first, second, [], numel(indices)));
    components = cell(1, max(labels));
    for index = 1:numel(components), components{index} = indices(labels == index); end
end

function output = sequential_unwrap(phase, mask)
    output = phase;
    output(~mask) = NaN;
    for axis = 1:2
        % A one-dimensional slice has no phase neighbors on its singleton
        % axis. Avoid an unwrap call for every scalar time sample.
        if size(output, axis) == 1, continue; end
        if axis == 2, output = output.'; mask = mask.'; end
        for column = 1:size(output, 2)
            changes = diff([false; mask(:, column); false]);
            starts = find(changes == 1); stops = find(changes == -1) - 1;
            for segment = 1:numel(starts)
                range = starts(segment):stops(segment);
                output(range, column) = unwrap(output(range, column));
            end
        end
        if axis == 2, output = output.'; mask = mask.'; end
    end
    anchor = find(mask, 1);
    output = output - 2*pi*round((output(anchor) - phase(anchor))/(2*pi));
end

function solver = prepare_poisson(mask)
    solver = struct('kind', "dct_neumann", 'mask', mask);
    if all(mask(:))
        rowLambda = -4*sin(pi*(0:size(mask,1)-1)'/(2*size(mask,1))).^2;
        columnLambda = -4*sin(pi*(0:size(mask,2)-1)/(2*size(mask,2))).^2;
        solver.lambda = rowLambda + columnLambda;
        return;
    end
    solver.kind = "masked_graph_neumann";
    indices = find(mask);
    nodes = zeros(size(mask)); nodes(indices) = 1:numel(indices);
    [first, second] = neighbor_edges(nodes);
    n = numel(indices);
    laplacian = sparse([first; second; first; second], ...
        [second; first; first; second], ...
        [ones(2*numel(first),1); -ones(2*numel(first),1)], n, n);
    solver.indices = indices;
    solver.laplacian = laplacian;
    if n > 1
        solver.factor = decomposition(-laplacian(2:end, 2:end), 'chol');
    end
end

function [first, second] = neighbor_edges(nodes)
    a = nodes(1:end-1, :); b = nodes(2:end, :);
    valid = a > 0 & b > 0;
    first = a(valid); second = b(valid);
    a = nodes(:, 1:end-1); b = nodes(:, 2:end);
    valid = a > 0 & b > 0;
    first = [first; a(valid)]; second = [second; b(valid)];
end

function output = poisson_solve(source, solver)
    output = zeros(size(source));
    if solver.kind == "dct_neumann"
        transformed = dct(dct(source, [], 1), [], 2);
        transformed(1) = 0;
        lambda = solver.lambda; lambda(1) = 1;
        output = idct(idct(transformed ./ lambda, [], 2), [], 1);
    else
        if numel(solver.indices) > 1
            vector = zeros(numel(solver.indices), 1);
            sourceVector = source(solver.indices);
            vector(2:end) = solver.factor \ (-sourceVector(2:end));
            output(solver.indices) = vector;
        end
        output(~solver.mask) = NaN;
    end
end

function source = gradient_source(phase, mask)
    source = zeros(size(phase));
    for axis = 1:2
        if axis == 2, phase = phase.'; mask = mask.'; source = source.'; end
        gradient = principal(diff(phase, 1, 1));
        gradient(~(mask(1:end-1,:) & mask(2:end,:))) = 0;
        source(1:end-1,:) = source(1:end-1,:) + gradient;
        source(2:end,:) = source(2:end,:) - gradient;
        if axis == 2, phase = phase.'; mask = mask.'; source = source.'; end
    end
end

function source = tie_source(phase, mask)
    % The edge contribution is sin(p_neighbor-p), exactly Im(conj(z)*Lz).
    % Missing graph edges impose zero normal flux, rather than padded data.
    source = zeros(size(phase));
    for axis = 1:2
        if axis == 2, phase = phase.'; mask = mask.'; source = source.'; end
        gradient = sin(diff(phase, 1, 1));
        gradient(~(mask(1:end-1,:) & mask(2:end,:))) = 0;
        source(1:end-1,:) = source(1:end-1,:) + gradient;
        source(2:end,:) = source(2:end,:) - gradient;
        if axis == 2, phase = phase.'; mask = mask.'; source = source.'; end
    end
end

function [output, changed] = tie_unwrap(phase, mask, solver, iterations)
    anchor = find(mask, 1);
    estimate = poisson_solve(tie_source(phase, mask), solver);
    estimate = estimate + phase(anchor) - estimate(anchor);
    integers = round((estimate - phase)/(2*pi));
    changed = zeros(1, iterations);
    for update = 1:iterations
        congruent = phase + 2*pi*integers;
        residual = congruent - estimate;
        correction = poisson_solve(tie_source(residual, mask), solver);
        correction = correction - correction(anchor);
        estimate = estimate + correction;
        newIntegers = round((estimate - phase)/(2*pi));
        changed(update) = nnz(newIntegers(mask) ~= integers(mask));
        integers = newIntegers;
    end
    output = phase + 2*pi*integers;
    output(~mask) = NaN;
end

function value = principal(value)
    value = atan2(sin(value), cos(value));
end
