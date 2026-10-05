function test_phase_unwrap(~)
%TEST_PHASE_UNWRAP Check raw congruence, Poisson recovery and mask topology.

    [x, y] = meshgrid(linspace(-1,1,70), linspace(-1,1,55));
    truth = 6*x + 2*y + 0.7*sin(2*x).*cos(2*y);
    wrapped = angle(exp(1i*truth));
    anchored = truth - truth(1) + wrapped(1);
    for method = ["sequential", "least_squares_dct", "tie_dct"]
        result = oce.motion.unwrapPhase(wrapped, ...
            struct('method',method,'dimensions',[1 2],'iterations',8));
        assert(max(abs(result.values(:)-anchored(:))) < 2e-11, ...
            'A noiseless integrable phase must recover up to its piston: %s.', method);
        assert(result.units == "rad" && result.quantity == "unwrapped_phase");
        assert(result.diagnostics.component_count == 1);
        if method == "tie_dct"
            assert(result.iterations_executed == 8 && ...
                result.diagnostics.total_correction_updates == 8, ...
                'The correction budget must remain fixed even after stabilization.');
            assert(numel(result.diagnostics.max_integer_changes_per_update) == 8);
            assert(result.diagnostics.wrap_consistency_rms_rad < 1e-14);
        end
    end

    % The sine-based initial TIE solve underestimates this steep but sampled
    % ramp. Integer correction must actually repair wraps, not just execute a
    % no-op loop around a sequential unwrap result.
    ramp = 1.4*(0:99);
    rampWrapped = angle(exp(1i*ramp));
    corrected = oce.motion.unwrapPhase(rampWrapped, struct('method',"tie_dct", ...
        'dimensions',2,'iterations',4));
    assert(max(abs(corrected.values-ramp)) < 3e-14 && ...
        corrected.diagnostics.max_integer_changes_per_update(1) > 50 && ...
        corrected.diagnostics.total_correction_updates == 4);

    % A complete invalid seam prevents continuity and carries unknown pistons.
    mask = true(size(wrapped)); mask(:,31:34) = false;
    mask(15:20,50:54) = false; % A hole forces a graph-Neumann solve on the right.
    poisoned = wrapped; poisoned(~mask) = NaN;
    leftIndices = find(mask & repmat(1:size(mask,2) <= 30, size(mask,1),1));
    rightIndices = find(mask & repmat(1:size(mask,2) >= 35, size(mask,1),1));
    for method = ["least_squares_dct", "tie_dct"]
        result = oce.motion.unwrapPhase(poisoned, struct('method',method, ...
            'dimensions',[1 2],'valid_mask',mask,'iterations',8));
        assert(all(isnan(result.values(~mask))), 'Invalid samples must remain NaN.');
        assert(result.diagnostics.component_count == 2 && ...
            result.diagnostics.dct_neumann_component_count == 1 && ...
            result.diagnostics.masked_graph_neumann_component_count == 1);
        for component = {leftIndices, rightIndices}
            indices = component{1};
            error = result.values(indices) - truth(indices);
            assert(max(abs(error-error(1))) < 2e-10, ...
                'Holes must impose missing edges rather than filled data.');
        end
        shifted = poisoned; shifted(rightIndices) = angle(exp(1i*(shifted(rightIndices)+1.1)));
        changed = oce.motion.unwrapPhase(shifted, struct('method',method, ...
            'dimensions',[1 2],'valid_mask',mask,'iterations',8));
        assert(max(abs(changed.values(leftIndices)-result.values(leftIndices))) < 1e-12, ...
            'A disconnected acquisition must not alter another component.');
    end

    % Independent x slices preserve array layout and their own phase origin.
    volume = cat(3, wrapped, angle(exp(1i*(truth+1.3))));
    result = oce.motion.unwrapPhase(volume, struct('method',"tie_dct", ...
        'dimensions',[2 1],'iterations',5));
    assert(isequal(size(result.values),size(volume)) && ...
        result.diagnostics.independent_slice_count == 2 && ...
        result.diagnostics.total_correction_updates == 10);
    swapped = oce.motion.unwrapPhase(permute(volume,[3 1 2]), ...
        struct('method',"tie_dct",'dimensions',[3 2],'iterations',5));
    assert(max(abs(result.values(:)-reshape(ipermute(swapped.values,[3 1 2]),[],1))) < 1e-12);

    % LS solves a gradient fit; TIE returns an integer-congruent raw phase even
    % for residues. Neither result is labelled a confidence interval or speed.
    rng(51); noisy = angle(exp(1i*(truth+0.7*randn(size(truth)))));
    tie = oce.motion.unwrapPhase(noisy, struct('method',"tie_dct", ...
        'dimensions',[1 2],'iterations',3));
    assert(tie.diagnostics.wrap_consistency_rms_rad < 1e-14 && ...
        tie.diagnostics.total_correction_updates == 3);
    none = oce.motion.unwrapPhase(wrapped, struct('method',"tie_dct", ...
        'dimensions',[1 2],'valid_mask',false(size(wrapped)),'iterations',3));
    assert(all(isnan(none.values(:))) && none.iterations_executed == 0);
    line = oce.motion.unwrapPhase(wrapped(1,:),struct('method',"sequential", ...
        'dimensions',2));
    assert(max(abs(line.values-unwrap(wrapped(1,:)))) < 1e-12);
    traces = reshape(angle(exp(1i*(reshape((0:19)*0.21,4,5,1) + ...
        reshape((0:399)*0.11,1,1,400)))),4,5,400);
    temporal = oce.motion.unwrapPhase(traces,struct('method',"sequential",'dimensions',3));
    assert(isequal(temporal.values,unwrap(traces,[],3)), ...
        'Skipping a singleton axis must preserve temporal unwrap exactly.');
    for method=["sequential","least_squares_dct","tie_dct"]
        for sign=[-1 1]
            boundary=sign*repmat(single(pi),2,3);
            atPi=oce.motion.unwrapPhase(boundary,struct('method',method, ...
                'dimensions',[1 2],'iterations',3));
            assert(isequal(atPi.values,double(boundary)), ...
                'Single +/-pi representation must retain its raw branch.');
        end
    end

    assert_error(@() oce.motion.unwrapPhase(wrapped, struct('method',"fake")), ...
        'OCE:Motion:InvalidUnwrapMethod');
    assert_error(@() oce.motion.unwrapPhase(wrapped, struct('dimensions',[1 1])), ...
        'OCE:Motion:InvalidUnwrapDimensions');
    assert_error(@() oce.motion.unwrapPhase(wrapped+10), 'OCE:Motion:NotWrappedPhase');
    assert_error(@() oce.motion.unwrapPhase(single([0 pi+.01])), ...
        'OCE:Motion:NotWrappedPhase');
    assert_error(@() oce.motion.unwrapPhase(wrapped, struct('valid_mask',true(2))), ...
        'OCE:Motion:InvalidUnwrapMask');
end

function assert_error(action, expectedIdentifier)
    caught = false;
    try, action(); catch exception, caught = strcmp(exception.identifier,expectedIdentifier); end
    assert(caught, 'Expected %s.',expectedIdentifier);
end
