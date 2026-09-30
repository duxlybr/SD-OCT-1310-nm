function experiment = summarizeDispersionSamples(experiment, requestedFrequencyHz)
%SUMMARIZEDISPERSIONSAMPLES Sample aligned dispersion summaries at fixed frequencies.
%
% The requested frequencies are mapped to the nearest bins of the maintained
% aligned frequency axis. No interpolation, rounding, or new repetition
% statistics are performed; existing repetition mean/SD/SEM/CI95/n values are
% sampled at the same selected bins.

    validate_summary(experiment);

    requestedFrequencyHz = double(requestedFrequencyHz(:));
    if isempty(requestedFrequencyHz) || any(~isfinite(requestedFrequencyHz)) || ...
            any(requestedFrequencyHz <= 0)
        error('OCE:Results:InvalidDispersionSampleFrequency', ...
            'Requested dispersion sample frequencies must be positive finite values.');
    end
    if numel(unique(requestedFrequencyHz, 'stable')) ~= numel(requestedFrequencyHz)
        error('OCE:Results:DuplicateDispersionSampleFrequency', ...
            'Requested dispersion sample frequencies must be unique.');
    end

    refFreq = double(experiment.summary.frequency_alignment.refFreq(:));
    if isempty(refFreq) || any(~isfinite(refFreq))
        error('OCE:Results:InvalidAlignedFrequencyAxis', ...
            'Aligned dispersion frequency axis is missing or invalid.');
    end
    if any(requestedFrequencyHz < min(refFreq) | requestedFrequencyHz > max(refFreq))
        error('OCE:Results:DispersionSampleOutsideAxis', ...
            'Requested dispersion sample frequencies must lie within the aligned axis.');
    end

    selectedIndex = knnsearch(refFreq, requestedFrequencyHz, 'K', 1);
    selectedFrequencyHz = refFreq(selectedIndex);

    meanData = experiment.summary.repetition_mean_data;
    stdData = experiment.summary.repetition_std_data;
    semData = experiment.summary.repetition_sem_data;
    ci95Data = experiment.summary.repetition_ci95_data;
    nData = experiment.summary.repetition_n_data;

    meanSampled = cell(size(meanData));
    stdSampled = cell(size(meanData));
    semSampled = cell(size(meanData));
    ci95Sampled = cell(size(meanData));
    nSampled = cell(size(meanData));

    for index = 1:numel(meanData)
        if isempty(meanData{index})
            continue;
        end
        meanSampled{index} = sample_summary(meanData{index}, selectedIndex, true);
        stdSampled{index} = sample_summary(stdData{index}, selectedIndex, false);
        semSampled{index} = sample_summary(semData{index}, selectedIndex, false);
        ci95Sampled{index} = sample_summary(ci95Data{index}, selectedIndex, false);
        nSampled{index} = sample_summary(nData{index}, selectedIndex, false);
    end

    sampling = struct();
    sampling.method = "nearest_aligned_bin";
    sampling.requested_frequency_hz = requestedFrequencyHz;
    sampling.selected_frequency_hz = selectedFrequencyHz;
    sampling.frequency_error_hz = selectedFrequencyHz - requestedFrequencyHz;
    sampling.selected_bin_index = selectedIndex;
    sampling.mean_data = meanSampled;
    sampling.std_data = stdSampled;
    sampling.sem_data = semSampled;
    sampling.ci95_data = ci95Sampled;
    sampling.n_data = nSampled;
    experiment.summary.dispersion_sampling = sampling;
end

function sampled = sample_summary(S, selectedIndex, includeAngles)
    if ~isstruct(S) || ...
            ~isfield(S, 'direction_smoothed_phase_speed_m_per_s') || ...
            ~iscell(S.direction_smoothed_phase_speed_m_per_s)
        error('OCE:Results:DispersionSamplingSource', ...
            'Repetition dispersion summary is incomplete.');
    end

    speed = S.direction_smoothed_phase_speed_m_per_s;
    nAngles = numel(speed);
    values = NaN(nAngles, numel(selectedIndex));
    for angleIndex = 1:nAngles
        current = double(speed{angleIndex}(:));
        if any(selectedIndex > numel(current))
            error('OCE:Results:DispersionSamplingSource', ...
                'Dispersion summary vectors do not match the aligned frequency axis.');
        end
        values(angleIndex, :) = current(selectedIndex)';
    end

    sampled = struct('phase_speed_m_per_s', values);
    if includeAngles
        if ~isfield(S, 'full_circle_angles_deg') || ...
                numel(S.full_circle_angles_deg) ~= nAngles
            error('OCE:Results:DispersionSamplingAngles', ...
                'Angular coordinates do not match the dispersion directions.');
        end
        sampled.full_circle_angles_deg = double(S.full_circle_angles_deg(:));
    end
end

function validate_summary(experiment)
    if ~isfield(experiment, 'summary') || ...
            ~isfield(experiment.summary, 'frequency_alignment') || ...
            ~isfield(experiment.summary.frequency_alignment, 'refFreq')
        error(['Aligned dispersion frequencies not found. Run ' ...
            'oce.results.alignDispersionFrequencies first.']);
    end

    required = {'repetition_mean_data', 'repetition_std_data', ...
        'repetition_sem_data', 'repetition_ci95_data', 'repetition_n_data'};
    if any(~isfield(experiment.summary, required))
        error(['Repetition summary data not found. Run ' ...
            'oce.results.summarizeRepetitions first.']);
    end
end
