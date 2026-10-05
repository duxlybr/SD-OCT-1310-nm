function result = estimateMultiExcitationSpeedMap(dataCell, options)
%ESTIMATEMULTIEXCITATIONSPEEDMAP Consensus of independent harmonic acquisitions.
% DATA CELL contains co-registered motion planes accepted by
% estimateLocalSpeedMap. OPTIONS.local_options is a common local-options
% struct or one struct per acquisition (e.g. independently directed sectors).
% Physical spatial axes, plane type and frequency must match; temporal origins
% and measured masks may differ. No spatial registration is performed here.
%
% Each acquisition is fitted independently. An unweighted median of valid
% slownesses anchors a fixed relative consensus gate; only its inliers enter
% a quality-weighted robust slowness average. At least min_consensus_count
% AND min_consensus_fraction of ALL acquisitions must agree. This prevents
% one surviving acquisition from manufacturing an ensemble result.
% A gap at the median anchor is rejected: at least one retained measurement
% must lie within half the relative tolerance from it. This conservative
% ambiguity guard does not establish that only one physical mode is present.
% No complex phasors are summed, invalid pixels are not filled, and empirical
% inter-acquisition spread is neither a confidence interval nor mode proof.
% In B-mode the constituent estimator returns lateral phase speed; combining
% different oblique projections does not establish an in-plane bulk speed.

    if nargin < 2, options=struct(); end
    if ~iscell(dataCell) || ~isvector(dataCell) || numel(dataCell)<2 || ...
            ~isstruct(options) || ~isscalar(options) || ~isfield(options,'local_options')
        error('OCE:MultiSpeed:InvalidInputs', ...
            'Provide at least two independent motion planes and local_options.');
    end
    dataCell=dataCell(:); count=numel(dataCell);
    defaults=struct('min_consensus_count',min(3,count), ...
        'min_consensus_fraction',0.5,'max_relative_slowness_deviation',0.2);
    for name=string(fieldnames(defaults))'
        if ~isfield(options,name), options.(name)=defaults.(name); end
        value=options.(name);
        if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ~isfinite(value)
            error('OCE:MultiSpeed:InvalidOptions','%s must be a finite real scalar.',name);
        end
        options.(name)=double(value);
    end
    if options.min_consensus_count<2 || options.min_consensus_count>count || ...
            options.min_consensus_count~=floor(options.min_consensus_count) || ...
            options.min_consensus_fraction<=0 || options.min_consensus_fraction>1 || ...
            options.max_relative_slowness_deviation<=0 || options.max_relative_slowness_deviation>=1
        error('OCE:MultiSpeed:InvalidOptions','Invalid consensus count, fraction or relative slowness tolerance.');
    end
    localOptions=options.local_options;
    if isstruct(localOptions) && isscalar(localOptions)
        localOptions=repmat({localOptions},count,1);
    elseif iscell(localOptions) && numel(localOptions)==count
        localOptions=localOptions(:);
    else
        error('OCE:MultiSpeed:InvalidOptions','local_options must be a common struct or one struct per acquisition.');
    end
    localResults=cell(count,1);
    for excitation=1:count
        % Existing owner validates each independently acquired plane and its
        % local physics. Matching geometry/frequency is the new trust boundary.
        localResults{excitation}=oce.dispersion.estimateLocalSpeedMap(dataCell{excitation},localOptions{excitation});
        if excitation==1
            reference=dataCell{1}; frequency=localResults{1}.options.frequency_hz;
            shape=size(localResults{1}.speed_m_s);
            slowness=NaN([shape,count]); localQuality=zeros([shape,count]);
        else
            verify_matching_plane(reference,dataCell{excitation});
            candidateFrequency=localResults{excitation}.options.frequency_hz;
            if abs(candidateFrequency-frequency)>1e-9*frequency
                error('OCE:MultiSpeed:FrequencyMismatch','Independent fields must share the same supplied physical frequency.');
            end
        end
        valid=localResults{excitation}.valid_mask;
        values=NaN(shape); values(valid)=1./localResults{excitation}.speed_m_s(valid);
        slowness(:,:,excitation)=values;
        localQuality(:,:,excitation)=localResults{excitation}.quality;
        localOptions{excitation}=localResults{excitation}.options;
    end
    needed=max(options.min_consensus_count,ceil(count*options.min_consensus_fraction));
    available=sum(isfinite(slowness),3); consensus=zeros(shape);
    inlierMask=false([shape,count]); fusedSlowness=NaN(shape); spread=NaN(shape);
    ambiguous=false(shape);
    quality=zeros(shape); tolerance=options.max_relative_slowness_deviation;
    for pixel=find(available>=needed)'
        [row,col]=ind2sub(shape,pixel);
        values=reshape(slowness(row,col,:),[],1);
        weights=reshape(localQuality(row,col,:),[],1);
        finite=isfinite(values); anchor=median(values(finite));
        inlier=finite & abs(values-anchor)<=tolerance*anchor;
        consensus(pixel)=sum(inlier); inlierMask(row,col,:)=reshape(inlier,1,1,[]);
        if ~any(abs(values(inlier)-anchor)<=0.5*tolerance*anchor)
            % An even ensemble can put its median between two incompatible
            % groups (e.g. four c=2 and four c=3). Do not invent c=2.4.
            ambiguous(pixel)=true; continue;
        end
        if consensus(pixel)<needed, continue; end
        values=values(inlier); weights=weights(inlier);
        % A single high-quality measurement cannot dominate an otherwise
        % coherent independent consensus. Quality remains an empirical score.
        weights=min(weights,2*median(weights));
        if sum(weights)<=realmin, continue; end
        location=median(values);
        for iteration=1:4
            residual=abs(values-location)/(0.5*tolerance*anchor);
            robustWeights=weights./max(1,residual);
            location=sum(robustWeights.*values)/sum(robustWeights);
        end
        fusedSlowness(pixel)=location;
        spread(pixel)=median(abs(values-median(values)))/median(values);
        quality(pixel)=sum(weights.*weights)/sum(weights)* ...
            (consensus(pixel)/count)*max(0,1-spread(pixel)/tolerance);
    end
    valid=isfinite(fusedSlowness); speed=NaN(shape); speed(valid)=1./fusedSlowness(valid);
    quality(~valid)=0; options.local_options=localOptions;
    diagnostic=struct('fusion',"quality-weighted robust slowness consensus", ...
        'required_consensus_count',needed,'excitation_count',count, ...
        'frequency_hz',frequency,'plane_type',string(reference.plane_type), ...
        'phase_combination',"none; independent per-acquisition speed estimates", ...
        'ambiguous_consensus_mask',ambiguous, ...
        'ambiguity_rule',"reject if no consensus measurement lies within half the relative slowness tolerance of the median anchor; conservative observed-gap check, not a physical mode test", ...
        'spread_interpretation',"relative unscaled median absolute slowness deviation among retained acquisitions; not a confidence interval", ...
        'independence_interpretation',"sequential excitations need not have mutually coherent phase; agreement can retain a shared model bias");
    result=struct('speed_m_s',speed,'display_speed_m_s',speed, ...
        'valid_mask',valid,'quality',quality,'slowness_s_m',fusedSlowness, ...
        'available_count',available,'consensus_count',consensus, ...
        'inlier_mask',inlierMask,'relative_slowness_mad',spread, ...
        'per_excitation_results',{localResults},'diagnostics',diagnostic,'options',options);
end

function verify_matching_plane(reference,candidate)
    if string(candidate.plane_type)~=string(reference.plane_type)
        error('OCE:MultiSpeed:GeometryMismatch','All acquisitions must use the same physical plane type.');
    end
    for name=["x_m","row_m"]
        first=double(reference.(name)(:)); second=double(candidate.(name)(:));
        if numel(first)~=numel(second)
            error('OCE:MultiSpeed:GeometryMismatch','Spatial axes must be co-registered without interpolation.');
        end
        if numel(first)>1, scale=mean(diff(first)); else, scale=max(abs(first),1e-3); end
        if any(abs(first-second)>max(1e-12,1e-7*scale))
            error('OCE:MultiSpeed:GeometryMismatch','Spatial axes must be co-registered without interpolation.');
        end
    end
end
