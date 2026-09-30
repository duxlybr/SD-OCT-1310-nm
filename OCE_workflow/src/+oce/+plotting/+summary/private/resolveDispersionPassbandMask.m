function [mask, passbandHz] = resolveDispersionPassbandMask( ...
        experiment, conditionIndices, frequencyHz)
%RESOLVEDISPERSIONPASSBANDMASK Resolve one condition's display passband mask.
%
% The passband is read from flattened per-acquisition processing provenance.
% Repetitions within one condition must agree when the field is available.
% Legacy result sets without this field retain the full finite frequency axis.

    frequencyHz = double(frequencyHz(:));
    mask = isfinite(frequencyHz);
    passbandHz = [];

    if ~isfield(experiment, 'data') || isempty(experiment.data) || ...
            ~isfield(experiment, 'design') || ...
            ~isfield(experiment.design, 'dimension_keys') || ...
            ~isfield(experiment.design, 'dimension_values')
        return;
    end

    nDimensions = numel(experiment.design.dimension_keys);
    nConditionDims = nDimensions - 1;
    if numel(conditionIndices) ~= nConditionDims
        error('OCE:Plotting:SummaryPassbandIndex', ...
            'Condition index count does not match the experiment design.');
    end

    repetitionCount = numel(experiment.design.dimension_values{end});
    resolvedBands = zeros(0, 2);
    for repetitionIndex = 1:repetitionCount
        idxCell = [conditionIndices {repetitionIndex}];
        result = experiment.data{idxCell{:}};
        if isempty(result) || ~isstruct(result) || ...
                ~isfield(result, 'filter_effective_passband_hz') || ...
                isempty(result.filter_effective_passband_hz)
            continue;
        end

        candidate = double(result.filter_effective_passband_hz(:)');
        if numel(candidate) ~= 2 || any(~isfinite(candidate)) || ...
                candidate(1) < 0 || candidate(2) <= candidate(1)
            error('OCE:Plotting:SummaryPassbandValue', ...
                'Invalid effective filter passband in summary source data.');
        end
        resolvedBands(end + 1, :) = candidate; %#ok<AGROW>
    end

    if isempty(resolvedBands)
        return;
    end

    passbandHz = resolvedBands(1, :);
    if any(abs(resolvedBands - passbandHz) > ...
            max(1, max(abs(passbandHz))) * 1e-12, 'all')
        error('OCE:Plotting:SummaryPassbandMismatch', ...
            ['Effective filter passband changes across repetitions of the ' ...
             'same experimental condition.']);
    end

    mask = mask & frequencyHz >= passbandHz(1) & ...
        frequencyHz <= passbandHz(2);
end
