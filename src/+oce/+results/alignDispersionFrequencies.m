function experiment = alignDispersionFrequencies(experiment)
%ALIGNDISPERSIONFREQUENCIES Align frequency-dependent fields to one axis.
%
% Aligns all frequency-dependent fields to a global frequency axis while
% preserving the original experiment.data grid. Empty cells are ignored and
% left empty, which allows unbalanced designs such as different numbers of
% repetitions per frequency.
%
% Frequency bins are matched by exact numeric Hz values. No interpolation,
% rounding, or tolerance-based merging is performed. Heterogeneous grids are
% therefore represented on their union axis with unmatched samples as NaN.
%
% Inputs:
%   experiment - Structure containing .data as an N-D cell array.
%
% Outputs:
%   experiment - Structure with aligned frequency-dependent fields in .data.

    dataSize = size(experiment.data);
    nData = numel(experiment.data);
    allFreq = [];

    for p = 1:nData
        S = experiment.data{p};
        if isempty(S)
            continue;
        end
        if ~isfield(S, 'direction_frequency_axes_hz') || ...
                isempty(S.direction_frequency_axes_hz)
            warning(['Skipping cell %d because direction_frequency_axes_hz ' ...
                'is missing or empty.'], p);
            continue;
        end
        for k = 1:numel(S.direction_frequency_axes_hz)
            if isempty(S.direction_frequency_axes_hz{k})
                continue;
            end
            allFreq = [allFreq; S.direction_frequency_axes_hz{k}(:)]; %#ok<AGROW>
        end
    end

    if isempty(allFreq)
        warning('No frequency vectors found. Frequency alignment was skipped.');
        return;
    end

    refFreq = sort(unique(allFreq(:)));
    for p = 1:nData
        S = experiment.data{p};
        if isempty(S)
            continue;
        end

        requiredFields = {'direction_frequency_axes_hz', ...
            'direction_temporal_diagnostic_magnitude', ...
            'direction_smoothed_phase_speed_m_per_s'};
        missingFields = requiredFields(~isfield(S, requiredFields));
        if ~isempty(missingFields)
            warning('Skipping cell %d because required field(s) are missing: %s', ...
                p, strjoin(missingFields, ', '));
            continue;
        end

        freqOriginal = S.direction_frequency_axes_hz;
        S.direction_frequency_axes_hz = ...
            alignToReference(freqOriginal, refFreq);
        S.direction_temporal_diagnostic_magnitude = alignToReference( ...
            S.direction_temporal_diagnostic_magnitude, refFreq, freqOriginal);
        S.direction_smoothed_phase_speed_m_per_s = alignToReference( ...
            S.direction_smoothed_phase_speed_m_per_s, refFreq, freqOriginal);
        experiment.data{p} = S;
    end

    experiment.data = reshape(experiment.data, dataSize);
    if ~isfield(experiment, 'summary') || isempty(experiment.summary)
        experiment.summary = struct();
    end
    experiment.summary.frequency_alignment = struct();
    experiment.summary.frequency_alignment.refFreq = refFreq;
    experiment.summary.frequency_alignment.nFrequencyPoints = numel(refFreq);
end

function alignedCells = alignToReference(dataCells, refFreq, freqCells)
%ALIGNTOREFERENCE Align vectors inside a cell array to a reference axis.

    if nargin < 3
        freqCells = dataCells;
    end

    n = numel(dataCells);
    alignedCells = cell(size(dataCells));
    refFreq = refFreq(:);
    for k = 1:n
        alignedVec = NaN(size(refFreq));
        if isempty(dataCells{k}) || isempty(freqCells{k})
            alignedCells{k} = alignedVec;
            continue;
        end

        dataVec = dataCells{k}(:);
        freqVec = freqCells{k}(:);
        nMatch = min(numel(dataVec), numel(freqVec));
        dataVec = dataVec(1:nMatch);
        freqVec = freqVec(1:nMatch);
        [tf, loc] = ismember(freqVec, refFreq);
        alignedVec(loc(tf)) = dataVec(tf);
        alignedCells{k} = alignedVec;
    end
end
