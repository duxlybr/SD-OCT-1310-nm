function value = waveTemporalCoherence(iq, window)
%WAVETEMPORALCOHERENCE OCT IQ coherence over the estimator axial support.
% This is measurement support, distinct from harmonic-fit coherence.
    previous = iq(:,1:end-1); next = iq(:,2:end);
    numerator = abs(sum(conj(previous).*next,2));
    denominator = sqrt(sum(abs(previous).^2,2).*sum(abs(next).^2,2));
    value = conv(numerator,ones(window,1),'valid') ./ ...
        max(conv(denominator,ones(window,1),'valid'),realmin);
    value = min(1,max(0,value));
end
