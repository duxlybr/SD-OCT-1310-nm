function result = estimateLocalSpeedMap(data, options)
%ESTIMATELOCALSPEEDMAP Opt-in harmonic OCE speed mapping with explicit QC.
% DATA.motion is real [row,x,time], DATA.x_m/row_m/t_s increase in SI;
% DATA.valid_mask marks measured support, and plane_type is enface or bmode.
% Optional DATA.analysis_mask (logical [row,x], default true) restricts output
% centres only; it never removes measured neighbours from a local fit.
% Phase increments or velocity may be used: their harmonic scale does not
% change spatial phase. One physical frequency is required in OPTIONS.
% Methods: phase_gradient (robust local circular plane), directional_phase
% (a directed spatial FFT sector before that fit), reverberant (angularly
% averaged local normalized autocorrelation, Asemani et al. 2024).
% In bmode, gradient speed is lateral phase speed; row is pooling/depth,
% not a second propagation coordinate. Enface fits both lateral components.
% The directed sector assumes real(P*exp(i*omega*t)); direction_deg is the
% physical propagation angle from +x towards +row, NOT the Fourier sign.
% RAW speed is never inpainted. display_speed_m_s optionally smooths within
% valid support only and cannot establish missing measurements. Quality is
% an empirical fit/support score, not a confidence interval or mode proof.

    if nargin < 2, options = struct(); end
    [data, options] = resolve_inputs(data, options);
    selected = data.t_s >= options.time_start_s & data.t_s <= options.time_end_s;
    [phasor, temporalCoherence] = harmonic_projection(data.motion(:,:,selected), ...
        data.t_s(selected), options.frequency_hz);
    inputPhasor = phasor;
    measured = data.valid_mask & isfinite(phasor) & temporalCoherence >= options.min_coherence;
    temporalValidCount=nnz(measured);
    phasor(~measured) = 0;
    directionalDiagnostic = struct();
    if options.method == "directional_phase"
        [phasor, directionalDiagnostic] = directional_filter(phasor, measured, data, options);
    end
    amplitude = abs(phasor);
    positive = sort(amplitude(measured & amplitude > 0));
    if isempty(positive), referenceAmplitude = Inf;
    else, referenceAmplitude = positive(max(1,ceil(0.95*numel(positive)))); end
    if options.method == "directional_phase"
        % Reference the measured field as well as its selected component.
        % Renormalizing a nearly empty sector to its own noise would let a
        % weak filtering artifact pass the relative-amplitude gate.
        inputPositive=sort(abs(inputPhasor(measured & abs(inputPhasor)>0)));
        if isempty(inputPositive), inputReference=Inf;
        else, inputReference=inputPositive(max(1,ceil(0.95*numel(inputPositive)))); end
        referenceAmplitude=max(referenceAmplitude,inputReference);
        directionalDiagnostic.input_amplitude_reference=inputReference;
    end
    measured = measured & amplitude > max(realmin, options.min_amplitude_fraction*referenceAmplitude);
    phasor(~measured) = NaN;
    spanX=options.window_x_mm*1e-3/(2*mean(diff(data.x_m)));
    halfX = max(1, floor(spanX+16*eps(spanX)));
    if numel(data.row_m) > 1
        spanRow=options.window_row_mm*1e-3/(2*mean(diff(data.row_m)));
        halfRow = floor(spanRow+16*eps(spanRow));
    else, halfRow = 0; end
    if options.method == "reverberant"
        [speed, quality, diagnostic] = reverberant_map(phasor, measured, ...
            temporalCoherence, data, options, halfRow, halfX);
    else
        [speed, quality, diagnostic] = gradient_map(phasor, measured, ...
            temporalCoherence, data, options, halfRow, halfX);
    end
    valid = isfinite(speed);
    quality(~valid) = 0;
    displaySpeed = smooth_supported(speed, quality, valid, data, options.smoothing_mm);
    diagnostic.temporal_coherence = temporalCoherence;
    diagnostic.input_phasor = inputPhasor;
    diagnostic.amplitude_reference = referenceAmplitude;
    diagnostic.directional_filter = directionalDiagnostic;
    diagnostic.window_samples = [2*halfRow+1, 2*halfX+1];
    diagnostic.time_sample_count = sum(selected);
    % Record a scalar span; no frequency-bin snapping is performed.
    diagnostic.time_cycles = options.frequency_hz*(max(data.t_s(selected))-min(data.t_s(selected)));
    diagnostic.spatial_sampling_speed_floor_m_s = 2*options.frequency_hz*max([mean(diff(data.x_m)),mean(diff(data.row_m))]);
    diagnostic.spatial_alias_interpretation = "Near-Nyquist estimated slopes are rejected; already aliased input cannot be identified from this map alone.";
    diagnostic.quality_interpretation = "empirical harmonic/model/support score; not statistical uncertainty";
    fullWindow=false(size(measured));
    fullWindow(1+halfRow:size(measured,1)-halfRow,1+halfX:size(measured,2)-halfX)=true;
    supported=measured & data.analysis_mask & fullWindow & diagnostic.support_fraction>=options.min_support_fraction;
    fitted=supported & isfinite(diagnostic.fit_error) & diagnostic.fit_error<=options.fit_error_max;
    diagnostic.qc_stage_counts=struct('input_valid',nnz(data.valid_mask), ...
        'temporal_valid',temporalValidCount,'amplitude_valid',nnz(measured), ...
        'analysis_centers',nnz(measured & data.analysis_mask), ...
        'full_window_centers',nnz(measured & data.analysis_mask & fullWindow), ...
        'window_support_valid',nnz(supported),'model_fit_valid',nnz(fitted), ...
        'accepted',nnz(valid));
    diagnostic.window_fits_data=any(fullWindow,'all');
    diagnostic.maximum_window_support_fraction=max(diagnostic.support_fraction,[],'all');
    diagnostic.analysis_mask=data.analysis_mask;
    diagnostic.no_valid_reason="";
    if ~any(valid,'all')
        if ~any(data.valid_mask,'all'), diagnostic.no_valid_reason="no measured input support";
        elseif temporalValidCount==0, diagnostic.no_valid_reason="no harmonic temporal support at the supplied frequency/time interval";
        elseif ~any(measured,'all'), diagnostic.no_valid_reason="no selected wavefield above the amplitude gate";
        elseif ~any(measured & data.analysis_mask,'all'), diagnostic.no_valid_reason="no measured output centres inside analysis_mask";
        elseif ~diagnostic.window_fits_data, diagnostic.no_valid_reason="requested spatial window does not fit the measured grid";
        elseif ~any(supported,'all'), diagnostic.no_valid_reason="insufficient measured support inside the requested local window";
        elseif ~any(fitted,'all'), diagnostic.no_valid_reason="local phase/correlation model does not fit supported windows";
        else, diagnostic.no_valid_reason="supported fits rejected by speed range, spatial aliasing or wavelength identifiability";
        end
    end
    if data.plane_type=="bmode" && options.method~="reverberant"
        diagnostic.speed_scope="lateral phase speed omega/abs(kx); depth rows pool independently offset phase; oblique bulk propagation gives a projection";
    else
        diagnostic.speed_scope="in-plane phase speed or supplied diffuse-field model speed";
    end
    result = struct('speed_m_s', speed, 'display_speed_m_s', displaySpeed, ...
        'quality', quality, 'valid_mask', valid, 'phasor', phasor, ...
        'amplitude', amplitude, 'diagnostics', diagnostic, 'options', options);
end

function [data, options] = resolve_inputs(data, options)
    required = {'motion','x_m','row_m','t_s','valid_mask','plane_type'};
    if ~isstruct(data) || ~isscalar(data) || ~all(isfield(data,required)) || ...
            ~isnumeric(data.motion) || ~isreal(data.motion) || ndims(data.motion) ~= 3
        error('OCE:LocalSpeed:InvalidData','motion must be real [row,x,time] with physical axes and measured valid_mask.');
    end
    shape = size(data.motion);
    if shape(2) < 3 || shape(3) < 8
        error('OCE:LocalSpeed:InsufficientSamples','At least 3 x samples and 8 time samples are required.');
    end
    names = {'row_m','x_m','t_s'};
    for dimension = 1:3
        values = data.(names{dimension});
        if ~isnumeric(values) || ~isreal(values) || ~isvector(values) || ...
                numel(values) ~= shape(dimension) || any(~isfinite(values)) || any(diff(values(:)) <= 0)
            error('OCE:LocalSpeed:InvalidAxes','Axes must match motion and increase in metres/seconds.');
        end
        data.(names{dimension}) = double(values(:));
    end
    if ~islogical(data.valid_mask) || ~isequal(size(data.valid_mask),shape(1:2))
        error('OCE:LocalSpeed:InvalidMask','valid_mask must be logical [row,x].');
    end
    if ~isfield(data,'analysis_mask'), data.analysis_mask=true(shape(1:2)); end
    if ~islogical(data.analysis_mask) || ~isequal(size(data.analysis_mask),shape(1:2))
        error('OCE:LocalSpeed:InvalidAnalysisMask','analysis_mask must be logical [row,x] and selects output centres only.');
    end
    data.plane_type = string(data.plane_type);
    if ~isscalar(data.plane_type) || ~any(data.plane_type == ["enface","bmode"])
        error('OCE:LocalSpeed:InvalidPlane','plane_type must be enface or bmode.');
    end
    if ~isstruct(options) || ~isscalar(options) || ~isfield(options,'frequency_hz')
        error('OCE:LocalSpeed:InvalidOptions','A scalar options struct and physical frequency_hz are required.');
    end
    defaults = struct('method',"phase_gradient",'time_start_s',data.t_s(1), ...
        'time_end_s',data.t_s(end),'window_x_mm',1,'window_row_mm',1, ...
        'speed_range_m_s',[0.2 15],'min_coherence',0.45, ...
        'min_amplitude_fraction',0.03,'min_support_fraction',0.6, ...
        'smoothing_mm',0,'direction_deg',0,'directional_halfwidth_deg',30, ...
        'reverb_model',"scalar2d",'reverb_lag_mm',0.6,'fit_error_max',0.3);
    fields = fieldnames(defaults);
    for index=1:numel(fields)
        if ~isfield(options,fields{index}), options.(fields{index}) = defaults.(fields{index}); end
    end
    options.method = string(options.method); options.reverb_model = string(options.reverb_model);
    if ~isscalar(options.method) || ~any(options.method == ["phase_gradient","directional_phase","reverberant"]) || ...
            ~isscalar(options.reverb_model) || ~any(options.reverb_model == ["scalar2d","shear3d"])
        error('OCE:LocalSpeed:InvalidMethod','Unknown speed method or reverberant physical model.');
    end
    scalarFields = {'frequency_hz','time_start_s','time_end_s','window_x_mm', ...
        'window_row_mm','min_coherence','min_amplitude_fraction','min_support_fraction', ...
        'smoothing_mm','direction_deg','directional_halfwidth_deg','reverb_lag_mm','fit_error_max'};
    for index=1:numel(scalarFields)
        value = options.(scalarFields{index});
        if ~isnumeric(value) || ~isreal(value) || ~isscalar(value) || ~isfinite(value)
            error('OCE:LocalSpeed:InvalidOptions','%s must be a finite real scalar.',scalarFields{index});
        end
    end
    if options.frequency_hz <= 0 || options.frequency_hz >= 0.5/max(diff(data.t_s)) || ...
            options.time_end_s <= options.time_start_s || options.window_x_mm <= 0 || ...
            options.window_row_mm < 0 || options.smoothing_mm < 0 || options.reverb_lag_mm <= 0 || ...
            options.directional_halfwidth_deg <= 0 || options.directional_halfwidth_deg >= 90 || options.fit_error_max <= 0
        error('OCE:LocalSpeed:InvalidOptions','Invalid frequency, interval, spatial window, fit limit or directed sector.');
    end
    for name = ["min_coherence","min_amplitude_fraction","min_support_fraction"]
        if options.(name) < 0 || options.(name) > 1
            error('OCE:LocalSpeed:InvalidOptions','Quality/support fractions must lie in [0,1].');
        end
    end
    range = options.speed_range_m_s;
    if ~isnumeric(range) || ~isreal(range) || numel(range) ~= 2 || ...
            any(~isfinite(range)) || range(1) <= 0 || range(2) <= range(1)
        error('OCE:LocalSpeed:InvalidOptions','speed_range_m_s must be increasing positive [minimum maximum].');
    end
    for dimension=1:3
        axis = data.(names{dimension});
        if numel(axis) > 1 && max(abs(diff(axis)-mean(diff(axis)))) > 1e-6*mean(diff(axis))
            error('OCE:LocalSpeed:NonuniformSampling','Current map estimators require uniformly sampled physical axes.');
        end
    end
    selected = data.t_s >= options.time_start_s & data.t_s <= options.time_end_s;
    if sum(selected) < 8 || options.frequency_hz*(max(data.t_s(selected))-min(data.t_s(selected))) < 1
        error('OCE:LocalSpeed:InsufficientCycles','Select at least 8 samples spanning one physical excitation cycle.');
    end
    if data.plane_type == "enface" && shape(1) < 3 || options.method == "reverberant" && shape(1) < 5
        error('OCE:LocalSpeed:InsufficientRows','Enface needs at least 3 rows; reverberant autocorrelation needs at least 5.');
    end
end

function [phasor, coherence] = harmonic_projection(motion, time, frequency)
    shape = size(motion); signal = reshape(double(motion),[],shape(3))';
    finite = all(isfinite(signal),1); signal(:,~finite)=0;
    tau = time(:)-mean(time);
    design = [ones(size(tau)), tau/max(abs(tau)), cos(2*pi*frequency*tau), sin(2*pi*frequency*tau)];
    weights = 0.5-0.5*cos(2*pi*(0:numel(tau)-1)'/(numel(tau)-1));
    coefficients = (design.*sqrt(weights)) \ (signal.*sqrt(weights));
    residual = signal-design*coefficients;
    trend = design(:,1:2)*( (design(:,1:2).*sqrt(weights)) \ (signal.*sqrt(weights)) );
    unexplained = sum(weights.*residual.^2,1);
    total = sum(weights.*(signal-trend).^2,1);
    coherence = sqrt(max(0,min(1,1-unexplained./max(realmin,total))));
    phasor = coefficients(3,:)-1i*coefficients(4,:);
    phasor(~finite)=NaN; coherence(~finite)=0;
    phasor = reshape(phasor,shape(1:2)); coherence = reshape(coherence,shape(1:2));
end

function [filtered, diagnostic] = directional_filter(phasor, measured, data, options)
    [nr,nc] = size(phasor); nx=2^nextpow2(2*nc);
    if data.plane_type == "enface", ny=2^nextpow2(2*nr); else, ny=nr; end
    % Finite-aperture zero padding spreads uniform motion into nonzero k.
    % Remove its measured spatial mean before selecting a propagating sector.
    % B-mode rows remain independent because mode shapes may change polarity.
    if data.plane_type == "enface"
        commonMotion=sum(phasor,'all')/max(1,nnz(measured));
        phasor(measured)=phasor(measured)-commonMotion;
    else
        commonMotion=sum(phasor,2)./max(1,sum(measured,2));
        phasor=phasor-commonMotion.*measured;
    end
    kx = 2*pi*ifftshift((-floor(nx/2):ceil(nx/2)-1)/(nx*mean(diff(data.x_m))));
    if data.plane_type == "enface"
        ky = 2*pi*ifftshift((-floor(ny/2):ceil(ny/2)-1)'/(ny*mean(diff(data.row_m))));
    else, ky = zeros(ny,1); end
    [Kx,Ky] = meshgrid(kx,ky);
    physicalAngle = atan2d(-Ky,-Kx);
    difference = abs(mod(physicalAngle-options.direction_deg+180,360)-180);
    angular = zeros(size(Kx)); inside=difference < options.directional_halfwidth_deg;
    angular(inside)=0.5*(1+cos(pi*difference(inside)/options.directional_halfwidth_deg));
    radial = hypot(Kx,Ky); omega=2*pi*options.frequency_hz;
    minK=omega/options.speed_range_m_s(2); maxK=omega/options.speed_range_m_s(1);
    pass = radial >= 0.7*minK & radial <= 1.3*maxK;
    transfer = angular.*pass;
    if data.plane_type == "enface"
        spectrum=fft2(phasor,ny,nx); recovered=ifft2(spectrum.*transfer);
    else
        spectrum=fft(phasor,nx,2); recovered=ifft(spectrum.*transfer,[],2);
    end
    filtered = recovered(1:nr,1:nc);
    diagnostic = struct('propagation_direction_deg',options.direction_deg, ...
        'halfwidth_deg',options.directional_halfwidth_deg, ...
        'removed_common_motion_phasor',commonMotion, ...
        'common_motion_interpretation',"measured spatial mean removed before zero padding; per depth row in B-mode", ...
        'retained_spectral_energy_fraction',sum(abs(spectrum.*transfer).^2,'all')/max(realmin,sum(abs(spectrum).^2,'all')), ...
        'sign_convention',"real(P exp(i omega t)); Fourier sector points opposite physical propagation");
end

function [speed,quality,diagnostic] = gradient_map(phasor, mask, coherence, data, options, hr, hx)
    [nr,nc]=size(phasor); speed=NaN(nr,nc); quality=zeros(nr,nc);
    kxMap=speed; kyMap=speed; rmseMap=speed; supportMap=zeros(nr,nc); alias=false(nr,nc);
    expected=(2*hr+1)*(2*hx+1); omega=2*pi*options.frequency_hz;
    dx=mean(diff(data.x_m));
    if nr>1, dr=mean(diff(data.row_m)); else, dr=0; end
    for row=1+hr:nr-hr
        ri=row-hr:row+hr;
        for col=1+hx:nc-hx
            if ~mask(row,col) || ~data.analysis_mask(row,col), continue; end
            ci=col-hx:col+hx; m=mask(ri,ci); support=sum(m,'all')/expected;
            supportMap(row,col)=support;
            if support<options.min_support_fraction, continue; end
            p=phasor(ri,ci); weights=abs(p); weights(~m)=0; p(~m)=0;
            cap=median(weights(m)); weights=min(weights,3*cap);
            x=data.x_m(ci)'-data.x_m(col); r=data.row_m(ri)-data.row_m(row);
            [X,R]=meshgrid(x,r);
            [kx,ky,rmse,spatialCoherence,ok]=circular_fit(p,m,weights,X,R,dx,dr,data.plane_type);
            kxMap(row,col)=kx; kyMap(row,col)=ky; rmseMap(row,col)=rmse;
            alias(row,col)= abs(kx*dx)>=0.9*pi || (data.plane_type=="enface" && abs(ky*dr)>=0.9*pi);
            candidate=omega/hypot(kx,ky);
            if ok && ~alias(row,col) && rmse<=options.fit_error_max && spatialCoherence>=options.min_coherence && ...
                    candidate>=options.speed_range_m_s(1) && candidate<=options.speed_range_m_s(2)
                speed(row,col)=candidate;
                quality(row,col)=spatialCoherence*coherence(row,col)*support;
            end
        end
    end
    diagnostic=struct('phase_gradient_x_rad_m',kxMap,'phase_gradient_row_rad_m',kyMap, ...
        'fit_error',rmseMap,'fit_error_units',"rad RMS circular phase", ...
        'support_fraction',supportMap,'spatial_alias_rejected',alias, ...
        'spatial_fit',"local amplitude-weighted circular robust regression; no global unwrap", ...
        'interpretation',"phase velocity of the locally selected/dominant mode; interference can bias it");
end

function [kx,ky,rmse,coherence,ok] = circular_fit(p,m,w,X,R,dx,dr,plane)
    kx=NaN; ky=0; rmse=NaN; coherence=0; ok=false;
    horizontal=m(:,1:end-1)&m(:,2:end);
    pair=p(:,2:end).*conj(p(:,1:end-1)); pairWeight=sqrt(w(:,2:end).*w(:,1:end-1));
    if sum(horizontal,'all')<2, return; end
    kx=robust_pair_slope(angle(pair(horizontal)),pairWeight(horizontal),dx);
    if plane=="enface"
        vertical=m(1:end-1,:)&m(2:end,:);
        pair=p(2:end,:).*conj(p(1:end-1,:)); pairWeight=sqrt(w(2:end,:).*w(1:end-1,:));
        if sum(vertical,'all')<2, return; end
        ky=robust_pair_slope(angle(pair(vertical)),pairWeight(vertical),dr);
        design=[ones(sum(m,'all'),1),X(m),R(m)];
        scale=max([max(abs(X(m))),max(abs(R(m))),realmin]);
        normalized=design; normalized(:,2:3)=design(:,2:3)/scale;
        if rcond(normalized'*(normalized.*w(m)))<1e-8, return; end
    end
    for iteration=1:5
        dephased=p.*exp(-1i*(kx*X+ky*R));
        if plane=="bmode"
            intercept=angle(sum(w.*dephased,2));
        else, intercept=angle(sum(w.*dephased,'all')); end
        residual=angle(dephased.*exp(-1i*intercept)); residual(~m)=0;
        robust=w.*min(1,0.45./max(abs(residual),realmin));
        if plane=="enface"
            step=(normalized.*sqrt(robust(m))) \ (residual(m).*sqrt(robust(m)));
            kx=kx+step(2)/scale; ky=ky+step(3)/scale;
        else
            % Each depth row has its own intercept (mode-shape polarity).
            rowWeight=sum(robust,2); xMean=sum(robust.*X,2)./max(realmin,rowWeight);
            centered=X-xMean; denominator=sum(robust.*centered.^2,'all');
            if denominator<=realmin, return; end
            kx=kx+sum(robust.*centered.*residual,'all')/denominator;
        end
    end
    dephased=p.*exp(-1i*(kx*X+ky*R));
    if plane=="bmode", intercept=angle(sum(w.*dephased,2));
    else, intercept=angle(sum(w.*dephased,'all')); end
    residual=angle(dephased.*exp(-1i*intercept)); residual(~m)=0;
    rmse=sqrt(sum(w.*residual.^2,'all')/sum(w,'all'));
    coherence=abs(sum(w.*exp(1i*residual),'all'))/sum(w,'all');
    ok=isfinite(kx)&&isfinite(ky)&&isfinite(rmse);
end

function slope=robust_pair_slope(phases,weights,spacing)
    center=angle(sum(weights.*exp(1i*phases)));
    for iteration=1:4
        residual=angle(exp(1i*(phases-center)));
        robust=weights.*min(1,0.35./max(realmin,abs(residual)));
        center=center+sum(robust.*residual)/max(realmin,sum(robust));
    end
    slope=center/spacing;
end

function [speed,quality,diagnostic] = reverberant_map(p,mask,coherence,data,options,hr,hx)
    [nr,nc]=size(p); speed=NaN(nr,nc); quality=zeros(nr,nc); errorMap=speed;
    if hr<2 || hx<2
        error('OCE:LocalSpeed:ReverbWindow','Reverberant windows must span at least 5 samples in both spatial axes.');
    end
    dx=mean(diff(data.x_m)); dr=mean(diff(data.row_m)); lagStep=max(dx,dr);
    maxLag=min([options.reverb_lag_mm*1e-3, hx*dx, hr*dr]);
    lagSpan=maxLag/lagStep;
    % Equal physical spacings can differ by an ULP after endpoint subtraction.
    % Do not drop an exactly resolved radial lag through floating-point floor.
    nbin=floor(lagSpan+16*eps(lagSpan));
    if nbin<3
        error('OCE:LocalSpeed:ReverbLag','Reverberant fitting requires at least 3 resolved nonzero radial lags.');
    end
    radius=(1:nbin)*lagStep; corrSum=zeros(nr,nc,nbin); count=zeros(nr,nc,nbin);
    sectorCount=zeros(nr,nc,nbin,4); kernel=ones(2*hr+1,2*hx+1);
    [kernelX,kernelRow]=meshgrid(-hx:hx,-hr:hr);
    omega=2*pi*options.frequency_hz;
    kGrid=logspace(log10(omega/options.speed_range_m_s(2)),log10(omega/options.speed_range_m_s(1)),160);
    templateSum=zeros(nbin,numel(kGrid)); templateWeight=zeros(nbin,1); offsetGeometry=[];
    % Sample circles rather than every grid offset: dense axial sampling in
    % B-mode must not implicitly overweight the depth direction or require
    % thousands of redundant correlations. Exact realized lag is retained.
    offsets=[];
    for lag=radius
        theta=(0:23)'*2*pi/24;
        offsets=[offsets; round(lag*sin(theta)/dr),round(lag*cos(theta)/dx)]; %#ok<AGROW>
    end
    offsets=unique(offsets,'rows');
    p(~mask)=0; energy=abs(p).^2;
    for offsetIndex=1:size(offsets,1)
            oy=offsets(offsetIndex,1); ox=offsets(offsetIndex,2);
            distance=hypot(ox*dx,oy*dr); bin=round(distance/lagStep);
            if abs(oy)>hr || abs(ox)>hx || bin<1 || bin>nbin || abs(distance-radius(bin))>0.35*lagStep, continue; end
            % Both endpoints of every pair remain in the stated local
            % window. Without this intersection, the effective aperture
            % silently expands by the lag, blurring material boundaries.
            pairKernel=double(abs(kernelRow+oy)<=hr & abs(kernelX+ox)<=hx);
            shifted=circshift(p,[oy ox]); shiftedMask=circshift(mask,[oy ox]);
            if oy>0, shiftedMask(1:oy,:)=false; elseif oy<0, shiftedMask(end+oy+1:end,:)=false; end
            if ox>0, shiftedMask(:,1:ox)=false; elseif ox<0, shiftedMask(:,end+ox+1:end)=false; end
            pairMask=mask&shiftedMask;
            numerator=conv2(real(p.*conj(shifted)).*pairMask,pairKernel,'same');
            energyA=conv2(energy.*pairMask,pairKernel,'same');
            energyB=conv2(abs(shifted).^2.*pairMask,pairKernel,'same');
            pairs=conv2(double(pairMask),pairKernel,'same');
            correlation=numerator./max(realmin,sqrt(energyA.*energyB));
            usable=pairs>=max(4,0.15*sum(pairKernel,'all'));
            correlation(~usable)=0; pairs(~usable)=0;
            corrSum(:,:,bin)=corrSum(:,:,bin)+correlation.*pairs;
            count(:,:,bin)=count(:,:,bin)+pairs;
            sector=1+floor(mod(atan2d(oy*dr,ox*dx),180)/45);
            sectorCount(:,:,bin,sector)=sectorCount(:,:,bin,sector)+pairs;
            geometryWeight=sum(pairKernel,'all');
            templateSum(bin,:)=templateSum(bin,:)+geometryWeight*offset_kernel(distance*kGrid,options.reverb_model,data.plane_type,(oy*dr/distance)^2);
            templateWeight(bin)=templateWeight(bin)+geometryWeight;
            offsetGeometry(end+1,:)=[bin,distance,(oy*dr/distance)^2,geometryWeight]; %#ok<AGROW>
    end
    correlations=corrSum./max(realmin,count);
    support=conv2(double(mask),kernel,'same')/numel(kernel);
    fullWindow=false(nr,nc); fullWindow(1+hr:nr-hr,1+hx:nc-hx)=true;
    candidateMask=mask&data.analysis_mask&fullWindow&support>=options.min_support_fraction;
    coverage=sum(sectorCount>0,4)/4;
    theoretical=templateSum./max(realmin,templateWeight);
    boundaryRejected=false(nr,nc); identifiable=false(nr,nc);
    for index=find(candidateMask)'
        [row,col]=ind2sub([nr,nc],index);
        observed=reshape(correlations(row,col,:),[],1); weight=reshape(count(row,col,:),[],1);
        angular=reshape(coverage(row,col,:),[],1);
        usable=weight>0 & angular>=0.75;
        if sum(usable)<3, continue; end
        weight(~usable)=0; weight=weight/max(realmin,sum(weight));
        cost=sum(weight.*(observed-theoretical).^2,1); [~,best]=min(cost);
        if best==1 || best==numel(kGrid), boundaryRejected(index)=true; continue; end
        fit=@(k) sum(weight.*(observed-discrete_radial_kernel(k,nbin,offsetGeometry,options.reverb_model,data.plane_type)).^2);
        k=fminbnd(fit,kGrid(best-1),kGrid(best+1),optimset('Display','off','TolX',1e-5));
        fitError=sqrt(fit(k)); errorMap(index)=fitError;
        % A nearly flat correlation cannot resolve wavelength. At least
        % 0.15 predicted decorrelation and resolved spatial sampling required.
        curve=discrete_radial_kernel(k,nbin,offsetGeometry,options.reverb_model,data.plane_type);
        identifiable(index)=max(1-curve(usable))>=0.15 && k*max(dx,dr)<0.9*pi;
        if fitError<=options.fit_error_max && identifiable(index)
            speed(index)=omega/k;
            quality(index)=coherence(index)*support(index)*max(0,1-fitError/options.fit_error_max)*mean(angular(usable));
        end
    end
    diagnostic=struct('fit_error',errorMap,'fit_error_units',"RMS normalized real autocorrelation", ...
        'support_fraction',support,'radial_lag_m',radius,'autocorrelation',correlations, ...
        'angular_coverage_fraction',coverage,'fit_range_boundary_rejected',boundaryRejected, ...
        'wavelength_identifiable',identifiable,'reverb_model',options.reverb_model, ...
        'realized_lag_geometry',offsetGeometry, ...
        'correlation_aperture',"both pair endpoints inside the reported local window", ...
        'template_sampling',"exact realized radii and axial-component angles weighted by full pair-window geometry; irregular missing support can change empirical angular weights", ...
        'kernel',kernel_name(options.reverb_model,data.plane_type), ...
        'interpretation',"requires stationary diffuse isotropic field; local fitting does not prove that premise");
end

function value=discrete_radial_kernel(k,nbin,geometry,model,plane)
    values=offset_kernel(geometry(:,2)*k,model,plane,geometry(:,3));
    numerator=accumarray(geometry(:,1),values.*geometry(:,4),[nbin 1]);
    denominator=accumarray(geometry(:,1),geometry(:,4),[nbin 1]);
    value=numerator./max(realmin,denominator);
end

function value=offset_kernel(q,model,plane,axialFractionSquared)
    if model=="scalar2d" || plane=="enface"
        value=reverb_kernel(q,model,plane); return;
    end
    % A diffuse 3-D transverse field's axial covariance at an individual
    % XZ lag. Uniform angular integration recovers .75*(j0+j1/q), but
    % discrete/anisotropic grids need the actual angle of every lag.
    j0=ones(size(q)); j1OverQ=ones(size(q))/3; nonzero=abs(q)>1e-3;
    z=q(nonzero); j0(nonzero)=sin(z)./z;
    j1OverQ(nonzero)=(sin(z)./z.^2-cos(z)./z)./z;
    z=q(~nonzero); j0(~nonzero)=1-z.^2/6+z.^4/120;
    j1OverQ(~nonzero)=1/3-z.^2/30+z.^4/840;
    value=1.5*((1-axialFractionSquared).*j0+(3*axialFractionSquared-1).*j1OverQ);
end

function value=reverb_kernel(q,model,plane)
    if model=="scalar2d", value=besselj(0,q); return; end
    j0=ones(size(q)); j1OverQ=ones(size(q))/3;
    nonzero=abs(q)>1e-3; z=q(nonzero);
    j0(nonzero)=sin(z)./z;
    j1OverQ(nonzero)=(sin(z)./z.^2-cos(z)./z)./z;
    z=q(~nonzero); j0(~nonzero)=1-z.^2/6+z.^4/120;
    j1OverQ(~nonzero)=1/3-z.^2/30+z.^4/840;
    if plane=="enface", value=1.5*(j0-j1OverQ);
    else, value=0.75*(j0+j1OverQ); end
end

function name=kernel_name(model,plane)
    if model=="scalar2d", name="J0(k r), planar scalar diffuse field";
    elseif plane=="enface", name="1.5 [j0(k r) - j1(k r)/(k r)], axial component in XY";
    else, name="0.75 [j0(k r) + j1(k r)/(k r)], axial component in XZ"; end
end

function display=smooth_supported(speed,quality,valid,data,widthMm)
    display=speed;
    if widthMm<=0 || ~any(valid,'all'), return; end
    sx=widthMm*1e-3/mean(diff(data.x_m));
    if numel(data.row_m)>1, sr=widthMm*1e-3/mean(diff(data.row_m)); else, sr=0; end
    [X,R]=meshgrid(-ceil(3*sx):ceil(3*sx),-ceil(3*sr):ceil(3*sr));
    kernel=exp(-0.5*(X/max(realmin,sx)).^2-0.5*(R/max(realmin,sr)).^2);
    values=speed; values(~valid)=0; weights=quality; weights(~valid)=0;
    display=conv2(values.*weights,kernel,'same')./max(realmin,conv2(weights,kernel,'same'));
    display(~valid)=NaN;
end
