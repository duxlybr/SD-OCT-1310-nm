function options = resolveRunVideoOptions(options, resolvedCrop)
%RESOLVERUNVIDEOOPTIONS Add crop-dependent runtime video bounds.

    if isempty(fieldnames(options))
        return;
    end

    if isfield(resolvedCrop, 'time') && ...
            isfield(resolvedCrop.time, 'sample_count')
        options.time_sample_count = resolvedCrop.time.sample_count;
        options.Time_ini = options.time_start_idx;
        options.Time_end = min( ...
            options.max_frames, resolvedCrop.time.sample_count);
    end
end
