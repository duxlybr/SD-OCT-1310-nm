function test_local_speed_estimators(~)
%TEST_LOCAL_SPEED_ESTIMATORS Controlled new opt-in map/model physics and QC.
    rng(441,'twister');
    f=1000; c=2; x=(0:40)*50e-6; row=(0:30)*50e-6; t=(0:79)*50e-6;
    [X,Y]=meshgrid(x,row); theta=32;
    phase=-2*pi*f/c*(X*cosd(theta)+Y*sind(theta));
    data=struct('motion',cos(phase+reshape(2*pi*f*t,1,1,[])), ...
        'x_m',x,'row_m',row,'t_s',t,'valid_mask',true(size(X)),'plane_type',"enface");
    options=struct('frequency_hz',f,'window_x_mm',0.5,'window_row_mm',0.5, ...
        'speed_range_m_s',[0.7 5],'min_coherence',0.7,'fit_error_max',0.3);
    result=oce.dispersion.estimateLocalSpeedMap(data,options);
    assert(nnz(result.valid_mask)>300);
    assert(max(abs(result.speed_m_s(result.valid_mask)/c-1))<1e-10);
    assert(all(result.quality(result.valid_mask)>0.99));
    noisy=data; noisy.motion=noisy.motion+0.65*randn(size(noisy.motion));
    noiseResult=oce.dispersion.estimateLocalSpeedMap(noisy,options);
    assert(nnz(noiseResult.valid_mask)>250);
    assert(median(abs(noiseResult.speed_m_s(noiseResult.valid_mask)/c-1))<0.04);
    % Harmonic LS is exact for a noninteger-cycle record plus DC/drift.
    data.t_s=(0:69)*50e-6;
    data.motion=cos(phase+reshape(2*pi*f*data.t_s,1,1,[]))+ ...
        reshape(2+100*data.t_s,1,1,[]);
    result=oce.dispersion.estimateLocalSpeedMap(data,options);
    assert(max(abs(result.speed_m_s(result.valid_mask)/c-1))<1e-9);
    % A measured hole remains absent even when display smoothing is requested.
    data.valid_mask(14:17,18:22)=false; options.smoothing_mm=0.15;
    result=oce.dispersion.estimateLocalSpeedMap(data,options);
    assert(all(isnan(result.speed_m_s(~data.valid_mask))));
    assert(all(isnan(result.display_speed_m_s(~result.valid_mask))));
    assert(all(result.quality(~result.valid_mask)==0));
    % B-mode is lateral phase speed with independent depth-row polarity.
    bmode=data; bmode.plane_type="bmode"; bmode.valid_mask(:)=true;
    rowPolarity=ones(numel(row),1); rowPolarity(17:end)=-1;
    bmode.motion=rowPolarity.*cos(-2*pi*f/c*X+reshape(2*pi*f*data.t_s,1,1,[]));
    options.smoothing_mm=0; result=oce.dispersion.estimateLocalSpeedMap(bmode,options);
    assert(nnz(result.valid_mask)>300);
    assert(max(abs(result.speed_m_s(result.valid_mask)/c-1))<1e-10);
    % Strong reflected wave biases a single-mode fit; a directed sector
    % isolates propagation. A larger FOV provides actual k resolution.
    x=(0:120)*50e-6; row=(0:60)*50e-6; [X,Y]=meshgrid(x,row);
    direct=exp(-1i*2*pi*f/c*X); reflected=0.8*exp(1i*2*pi*f/c*X+0.6i);
    data.motion=real((direct+reflected).*reshape(exp(1i*2*pi*f*t),1,1,[]));
    data.x_m=x; data.row_m=row; data.t_s=t; data.valid_mask=true(size(X));
    options.method="directional_phase"; options.direction_deg=0;
    options.window_x_mm=0.8; options.window_row_mm=0.5;
    options.min_coherence=0.5; options.fit_error_max=0.45;
    result=oce.dispersion.estimateLocalSpeedMap(data,options);
    interior=result.valid_mask & X>1e-3 & X<5e-3 & Y>0.5e-3 & Y<2.5e-3;
    assert(nnz(interior)>500);
    assert(median(abs(result.speed_m_s(interior)/c-1))<0.08);
    % A finite-aperture uniform oscillation must not become a traveling wave
    % through spectral leakage. Retain the measured amplitude as QC reference.
    uniform=data;
    uniform.motion=repmat(reshape(cos(2*pi*f*t),1,1,[]),numel(row),numel(x),1);
    result=oce.dispersion.estimateLocalSpeedMap(uniform,options);
    assert(~any(result.valid_mask,'all'));
    rng(7401,'twister'); uniform.motion=uniform.motion+0.2*randn(size(uniform.motion));
    result=oce.dispersion.estimateLocalSpeedMap(uniform,options);
    assert(~any(result.valid_mask,'all'));
    % Out-of-band or spatially unresolved speed is not extrapolated.
    options.method="phase_gradient"; options.speed_range_m_s=[3 5];
    result=oce.dispersion.estimateLocalSpeedMap(bmode,options);
    assert(~any(result.valid_mask,'all'));
    assert_identifier('OCE:LocalSpeed:InsufficientCycles',@() ...
        oce.dispersion.estimateLocalSpeedMap(data,struct('frequency_hz',f,'time_end_s',1e-4)));
    assert_identifier('OCE:LocalSpeed:InvalidOptions',@() ...
        oce.dispersion.estimateLocalSpeedMap(data,struct('frequency_hz',10000)));
    assert_reverberant();
    assert_axial_bulk_reverberant();
    assert_young_models();
    assert_bmode_support_diagnostics();
    assert_multi_excitation_consensus();
    assert_phase_derivative_2d();
    assert_raw_unwrap_before_estimation();
end

function assert_phase_derivative_2d()
    f=1000; c=2; x=(0:76)*80e-6; z=(0:40)*60e-6; t=(0:59)*50e-6;
    [X,Z]=meshgrid(x,z); theta=35; k=2*pi*f/c;
    field=exp(-1i*k*(X*cosd(theta)+Z*sind(theta)));
    data=struct('motion',real(field.*reshape(exp(1i*2*pi*f*t),1,1,[])), ...
        'x_m',x,'row_m',z,'t_s',t,'valid_mask',true(size(X)),'plane_type',"bmode");
    options=struct('method',"phase_derivative_2d",'frequency_hz',f, ...
        'window_x_mm',.8,'window_row_mm',.6,'pd_geometry',"in_plane", ...
        'speed_range_m_s',[.8 5],'min_coherence',.7,'unwrap_method',"sequential");
    % A known oblique bulk plane wave requires both spatial derivatives.
    full=oce.dispersion.estimateLocalSpeedMap(data,options);
    assert(nnz(full.valid_mask)>1500);
    assert(max(abs(full.speed_m_s(full.valid_mask)/c-1))<1e-9);
    assert(max(abs(full.diagnostics.phase_derivative_row_rad_m(full.valid_mask)+k*sind(theta)))<1e-6);
    options.pd_geometry="lateral";
    projected=oce.dispersion.estimateLocalSpeedMap(data,options);
    assert(max(abs(projected.speed_m_s(projected.valid_mask)/(c/cosd(theta))-1))<1e-9);
    assert(all(projected.diagnostics.phase_derivative_row_rad_m(projected.valid_mask)==0));
    % A curved phase front with amplitude variation tests the derivative at
    % the window centre, independently of the plane-wave implementation.
    options.pd_geometry="in_plane"; data.plane_type="enface";
    ax=1.1e5; az=.8e5;
    phase=-k*X-.3*k*Z-ax*X.^2-az*Z.^2;
    field=(1+300*X+250*Z).*exp(1i*phase);
    data.motion=real(field.*reshape(exp(1i*2*pi*f*t),1,1,[]));
    truth=2*pi*f./hypot(k+2*ax*X,.3*k+2*az*Z);
    curved=oce.dispersion.estimateLocalSpeedMap(data,options);
    assert(nnz(curved.valid_mask)>1500);
    assert(max(abs(curved.speed_m_s(curved.valid_mask)./truth(curved.valid_mask)-1))<1e-8);
    % Wrong unwrap branches must remain visible in unwrapped residuals; no
    % missing measurement is filled by modal unwrapping or display smoothing.
    data.valid_mask(18:22,35:39)=false; options.smoothing_mm=.1;
    holed=oce.dispersion.estimateLocalSpeedMap(data,options);
    assert(all(isnan(holed.speed_m_s(~data.valid_mask))));
    assert(all(isnan(holed.diagnostics.unwrapped_modal_phase_rad(~data.valid_mask))));
    assert(all(isnan(holed.display_speed_m_s(~holed.valid_mask))));
    % A missing vertical stripe separates two unknown unwrap pistons. The
    % opposite component cannot provide support to a near-stripe estimate.
    split=data; split.valid_mask(:)=true; split.valid_mask(:,39)=false;
    split.motion=real(exp(-1i*k*X).*reshape(exp(1i*2*pi*f*t),1,1,[]));
    options.min_support_fraction=.8;
    separated=oce.dispersion.estimateLocalSpeedMap(split,options);
    assert(~any(separated.valid_mask(:,38)) && ~any(separated.valid_mask(:,40)));
    assert(nnz(separated.valid_mask)>1000);
    assert(max(abs(separated.speed_m_s(separated.valid_mask)/c-1))<1e-9);
    options.pd_geometry="depth";
    assert_identifier('OCE:LocalSpeed:InvalidOptions',@()oce.dispersion.estimateLocalSpeedMap(data,options));
end

function assert_raw_unwrap_before_estimation()
    rng(142,'twister'); f=1000; c=2.3; x=(0:56)*80e-6; z=(0:6)*20e-6;
    t=(0:69)*25e-6; [X,Z]=meshgrid(x,z); %#ok<ASGLU>
    offset=2*pi*rand(size(X))-pi;
    phase=3.8*cos(-2*pi*f/c*X+reshape(2*pi*f*t,1,1,[]))+offset;
    data=struct('raw_phase_rad',angle(exp(1i*phase)), ...
        'x_m',x,'row_m',z,'t_s',t,'valid_mask',true(size(X)),'plane_type',"bmode");
    options=struct('method',"phase_derivative_2d",'frequency_hz',f, ...
        'window_x_mm',.8,'window_row_mm',0,'speed_range_m_s',[.8 5], ...
        'min_coherence',.7,'unwrap_iterations',5,'raw_unwrap_dimensions',3);
    % Optical wrapping is deliberately severe, but temporal adjacent phase
    % steps are resolved. Static scatterer phase differs at every pixel.
    for method=["sequential","least_squares_dct","tie_dct"]
        options.unwrap_method=method;
        result=oce.dispersion.estimateLocalSpeedMap(data,options);
        assert(nnz(result.valid_mask)>250);
        assert(median(abs(result.speed_m_s(result.valid_mask)/c-1))<1e-7);
        assert(result.diagnostics.raw_unwrap.performed);
        assert(result.diagnostics.raw_unwrap.method==method);
        assert(result.diagnostics.processing_order(1)=="raw unwrap when supplied");
        if method=="tie_dct"
            assert(result.diagnostics.raw_unwrap.iterations_executed==5);
            assert(result.diagnostics.modal_unwrap.iterations_executed==5);
        end
    end
    % A raw input cannot silently compete with an existing processed signal.
    bad=data; bad.motion=phase;
    assert_identifier('OCE:LocalSpeed:InvalidData',@()oce.dispersion.estimateLocalSpeedMap(bad,options));
    options.unwrap_iterations=2.5;
    assert_identifier('OCE:LocalSpeed:InvalidOptions',@()oce.dispersion.estimateLocalSpeedMap(data,options));
    options.unwrap_iterations=0;
    assert_identifier('OCE:LocalSpeed:InvalidOptions',@()oce.dispersion.estimateLocalSpeedMap(data,options));
end

function assert_bmode_support_diagnostics()
    f=1000; x=(0:60)*80e-6; row=(0:24)*20e-6; t=(0:39)*50e-6;
    [X,Z]=meshgrid(x,row); speed=2*ones(size(X)); speed(Z>0.24e-3)=3;
    % Two physical layers can have different lateral speed, independent
    % phase offset/polarity and attenuation. Zero depth pooling preserves
    % them; a B-mode fit must never treat their offsets as vertical k.
    field=exp(-1i*2*pi*f*X./speed).*exp(1i*45000*Z).*exp(-2500*Z);
    data=struct('motion',real(field.*reshape(exp(1i*2*pi*f*t),1,1,[])), ...
        'x_m',x,'row_m',row,'t_s',t,'valid_mask',true(size(X)),'plane_type',"bmode");
    opt=struct('frequency_hz',f,'window_x_mm',0.8,'window_row_mm',0, ...
        'speed_range_m_s',[.8 5],'min_coherence',.7);
    estimate=oce.dispersion.estimateLocalSpeedMap(data,opt);
    assert(nnz(estimate.valid_mask)>1000);
    assert(max(abs(estimate.speed_m_s(estimate.valid_mask)./speed(estimate.valid_mask)-1))<1e-9);
    assert(all(estimate.diagnostics.phase_gradient_row_rad_m(estimate.valid_mask)==0));
    assert(estimate.diagnostics.window_samples(1)==1);
    assert(estimate.diagnostics.qc_stage_counts.accepted==nnz(estimate.valid_mask));
    assert(contains(estimate.diagnostics.speed_scope,"lateral phase speed"));
    % Output centres are independent of measured support. A one-pixel ROI
    % retains every measured neighbour and the exact unrestricted estimate.
    centre=[12 31]; unrestricted=estimate;
    data.analysis_mask=false(size(X)); data.analysis_mask(centre(1),centre(2))=true;
    restricted=oce.dispersion.estimateLocalSpeedMap(data,opt);
    assert(nnz(restricted.valid_mask)==1);
    assert(abs(restricted.speed_m_s(centre(1),centre(2))-unrestricted.speed_m_s(centre(1),centre(2)))<1e-12);
    assert(isequaln(restricted.phasor,unrestricted.phasor));
    assert(restricted.diagnostics.support_fraction(centre(1),centre(2))==1);
    assert(restricted.diagnostics.qc_stage_counts.analysis_centers==1);
    bad=data; bad.analysis_mask=double(bad.analysis_mask);
    assert_identifier('OCE:LocalSpeed:InvalidAnalysisMask',@()oce.dispersion.estimateLocalSpeedMap(bad,opt));
    data=rmfield(data,'analysis_mask');
    opt.window_row_mm=2;
    estimate=oce.dispersion.estimateLocalSpeedMap(data,opt);
    assert(~any(estimate.valid_mask,'all') && ~estimate.diagnostics.window_fits_data);
    assert(contains(estimate.diagnostics.no_valid_reason,"does not fit"));
    opt.window_row_mm=.08; data.valid_mask(:)=false; data.valid_mask(12,:)=true;
    estimate=oce.dispersion.estimateLocalSpeedMap(data,opt);
    assert(~any(estimate.valid_mask,'all'));
    assert(contains(estimate.diagnostics.no_valid_reason,"insufficient measured support"));
end

function assert_multi_excitation_consensus()
    rng(491,'twister'); f=1000; c=2; x=(0:52)*80e-6; row=(0:44)*80e-6;
    t=(0:39)*50e-6; [X,Y]=meshgrid(x,row);
    acquisitions=cell(8,1);
    local=struct('frequency_hz',f,'window_x_mm',.64,'window_row_mm',.64, ...
        'speed_range_m_s',[.5 6],'min_coherence',.6,'min_support_fraction',.65);
    for excitation=1:8
        angle=45*(excitation-1); trueSpeed=c;
        if excitation==8, trueSpeed=4; end % coherent but physically wrong outlier
        % Arbitrary gain and temporal origin should not privilege one source.
        field=(.2+excitation)*exp(1i*2*pi*rand-1i*2*pi*f/trueSpeed*(X*cosd(angle)+Y*sind(angle)));
        motion=real(field.*reshape(exp(1i*2*pi*f*t),1,1,[]));
        acquisitions{excitation}=struct('motion',motion,'x_m',x,'row_m',row, ...
            't_s',t,'valid_mask',true(size(X)),'plane_type',"enface");
        acquisitions{excitation}.valid_mask(19:22,25:28)=false;
    end
    options=struct('local_options',local,'min_consensus_count',3, ...
        'min_consensus_fraction',.5,'max_relative_slowness_deviation',.2);
    result=oce.dispersion.estimateMultiExcitationSpeedMap(acquisitions,options);
    assert(nnz(result.valid_mask)>1000);
    assert(max(abs(result.speed_m_s(result.valid_mask)/c-1))<1e-9);
    assert(all(result.consensus_count(result.valid_mask)==7));
    assert(~any(result.inlier_mask(:,:,8),'all'));
    assert(all(isnan(result.speed_m_s(19:22,25:28)),'all'));
    % A permutation leaves both the consensus and reconstructed measurement.
    order=[8 4 2 6 1 7 3 5]; permuted=oce.dispersion.estimateMultiExcitationSpeedMap(acquisitions(order),options);
    assert(isequal(permuted.valid_mask,result.valid_mask));
    assert(max(abs(permuted.speed_m_s(result.valid_mask)-result.speed_m_s(result.valid_mask)))<1e-10);
    % Opposite temporal phase never cancels independent speed estimates.
    flipped=acquisitions;
    for excitation=2:2:8, flipped{excitation}.motion=-flipped{excitation}.motion; end
    phaseFlipped=oce.dispersion.estimateMultiExcitationSpeedMap(flipped,options);
    assert(isequal(phaseFlipped.valid_mask,result.valid_mask));
    assert(max(abs(phaseFlipped.speed_m_s(result.valid_mask)-result.speed_m_s(result.valid_mask)))<1e-10);
    noisy=acquisitions;
    for excitation=1:8
        signal=noisy{excitation}.motion;
        noisy{excitation}.motion=signal+0.5*std(signal,0,'all')*randn(size(signal));
    end
    noisyResult=oce.dispersion.estimateMultiExcitationSpeedMap(noisy,options);
    assert(nnz(noisyResult.valid_mask)>.9*nnz(result.valid_mask));
    assert(median(abs(noisyResult.speed_m_s(noisyResult.valid_mask)/c-1))<.02);
    % Two equally sized incompatible modes can put an even-sample median
    % in an unmeasured gap. Four c=2 plus four c=3 must not invent c=2.4.
    bimodal=acquisitions;
    for excitation=1:8
        splitSpeed=2+(excitation>4);
        bimodal{excitation}.motion=cos(-2*pi*f/splitSpeed*X+reshape(2*pi*f*t,1,1,[]));
    end
    ambiguous=oce.dispersion.estimateMultiExcitationSpeedMap(bimodal,options);
    assert(~any(ambiguous.valid_mask,'all'));
    assert(nnz(ambiguous.diagnostics.ambiguous_consensus_mask)>1000);
    % Eight mutually incompatible valid speeds do not manufacture consensus.
    conflicted=acquisitions;
    for excitation=1:8
        incompatible=.65*1.4^(excitation-1);
        conflicted{excitation}.motion=cos(-2*pi*f/incompatible*X+reshape(2*pi*f*t,1,1,[]));
    end
    conflict=oce.dispersion.estimateMultiExcitationSpeedMap(conflicted,options);
    assert(~any(conflict.valid_mask,'all'));
    % Insufficient independent measurements and uniform/null fields remain NaN.
    absent=acquisitions;
    for excitation=4:8, absent{excitation}.valid_mask(:)=false; end
    insufficient=oce.dispersion.estimateMultiExcitationSpeedMap(absent,options);
    assert(~any(insufficient.valid_mask,'all'));
    null=acquisitions;
    for excitation=1:8
        null{excitation}.motion=repmat(reshape(cos(2*pi*f*t),1,1,[]),numel(row),numel(x),1);
    end
    rejected=oce.dispersion.estimateMultiExcitationSpeedMap(null,options);
    assert(~any(rejected.valid_mask,'all'));
    mismatched=acquisitions; mismatched{2}.x_m=x+2e-6;
    assert_identifier('OCE:MultiSpeed:GeometryMismatch',@() ...
        oce.dispersion.estimateMultiExcitationSpeedMap(mismatched,options));
    wrongFrequency=repmat({local},8,1); wrongFrequency{3}.frequency_hz=1100;
    options.local_options=wrongFrequency;
    assert_identifier('OCE:MultiSpeed:FrequencyMismatch',@() ...
        oce.dispersion.estimateMultiExcitationSpeedMap(acquisitions,options));
end

function assert_axial_bulk_reverberant()
    % Independent superposition of 3-D transverse plane waves: axial
    % polarization weight sqrt(1-nz^2), sampled in XY and XZ separately.
    % This protects the physically different axial-component kernels.
    rng(621,'twister'); f=1000; c=2; x=(0:100)*80e-6;
    [X,Y]=meshgrid(x,x); fieldXY=zeros(size(X)); fieldXZ=fieldXY;
    for wave=1:512
        nz=2*rand-1; theta=2*pi*rand; transverse=sqrt(1-nz^2);
        nx=transverse*cos(theta); ny=transverse*sin(theta); phase=2*pi*rand;
        fieldXY=fieldXY+transverse*exp(1i*(2*pi*f/c*(nx*X+ny*Y)+phase));
        fieldXZ=fieldXZ+transverse*exp(1i*(2*pi*f/c*(nx*X+nz*Y)+phase));
    end
    t=(0:39)*50e-6;
    options=struct('method',"reverberant",'reverb_model',"shear3d", ...
        'frequency_hz',f,'window_x_mm',4,'window_row_mm',4, ...
        'reverb_lag_mm',1.4,'fit_error_max',0.2,'speed_range_m_s',[0.5 5]);
    for plane=["enface","bmode"]
        if plane=="enface", field=fieldXY; else, field=fieldXZ; end
        data=struct('motion',real(field.*reshape(exp(1i*2*pi*f*t),1,1,[])), ...
            'x_m',x,'row_m',x,'t_s',t,'valid_mask',true(size(X)),'plane_type',plane);
        result=oce.dispersion.estimateLocalSpeedMap(data,options);
        assert(nnz(result.valid_mask)>2000);
        assert(median(abs(result.speed_m_s(result.valid_mask)/c-1))<0.06);
        if plane=="enface", assert(contains(result.diagnostics.kernel,"axial component in XY"));
        else, assert(contains(result.diagnostics.kernel,"axial component in XZ")); end
    end
end

function assert_reverberant()
    rng(41,'twister'); f=1000; c=1; x=(0:96)*50e-6; row=(0:48)*100e-6;
    [X,Y]=meshgrid(x,row); phasor=zeros(size(X));
    for wave=1:180
        theta=2*pi*wave/180;
        phasor=phasor+exp(1i*(2*pi*f/c*(X*cos(theta)+Y*sin(theta))+2*pi*rand));
    end
    t=(0:39)*50e-6;
    data=struct('motion',real(phasor.*reshape(exp(1i*2*pi*f*t),1,1,[])), ...
        'x_m',x,'row_m',row,'t_s',t,'valid_mask',true(size(X)),'plane_type',"enface");
    options=struct('method',"reverberant",'frequency_hz',f,'window_x_mm',2.4, ...
        'window_row_mm',2.4,'reverb_lag_mm',0.8,'fit_error_max',0.16, ...
        'speed_range_m_s',[0.5 3],'reverb_model',"scalar2d");
    result=oce.dispersion.estimateLocalSpeedMap(data,options);
    assert(nnz(result.valid_mask)>600);
    assert(median(abs(result.speed_m_s(result.valid_mask)/c-1))<0.06);
    assert(result.diagnostics.reverb_model=="scalar2d");
    assert(size(result.diagnostics.realized_lag_geometry,2)==4);
    % A uniform harmonic field has no resolvable wavelength: no filled map.
    data.motion=repmat(reshape(cos(2*pi*f*t),1,1,[]),numel(row),numel(x),1);
    result=oce.dispersion.estimateLocalSpeedMap(data,options);
    assert(~any(result.valid_mask,'all'));
    % Exactly three physical lags must survive axis roundoff. The requested
    % window includes three neighbours on each side of its centre.
    coarseX=(0:20)*200e-6; coarseRow=(0:16)*200e-6*(1+2*eps);
    [CX,~]=meshgrid(coarseX,coarseRow);
    coarse=struct('motion',cos(-2*pi*f/c*CX+reshape(2*pi*f*t,1,1,[])), ...
        'x_m',coarseX,'row_m',coarseRow,'t_s',t, ...
        'valid_mask',true(size(CX)),'plane_type',"enface");
    options.window_x_mm=1.2; options.window_row_mm=1.2; options.reverb_lag_mm=.6;
    result=oce.dispersion.estimateLocalSpeedMap(coarse,options);
    assert(isequal(result.diagnostics.window_samples,[7 7]));
    assert(~isempty(result.diagnostics.realized_lag_geometry));
end

function assert_young_models()
    rho=1030; nu=0.49; E=9000; cs=sqrt(E/(2*rho*(1+nu)));
    option=struct('model',"bulk_shear",'density_kg_m3',rho,'poisson_ratio',nu);
    result=oce.elastography.invertYoungModulus([cs NaN;0 cs],option);
    assert(max(abs(result.young_pa(result.valid_mask)/E-1))<1e-12);
    assert(nnz(result.valid_mask)==2);
    % Independent cubic check for exact Rayleigh ratio.
    beta=(1-2*nu)/(2*(1-nu)); rootsValue=roots([1 -8 24-16*beta -16*(1-beta)]);
    rayleigh=sqrt(real(rootsValue(abs(imag(rootsValue))<1e-10 & real(rootsValue)>0 & real(rootsValue)<1)));
    option.model="rayleigh"; result=oce.elastography.invertYoungModulus(cs*rayleigh,option);
    assert(abs(result.young_pa/E-1)<1e-9);
    % Thin inversion round trip and explicit invalidation outside kh gate.
    h=0.3e-3; f=300; omega=2*pi*f;
    cp=(E*omega^2*h^2/(12*(1-nu^2)*rho))^0.25;
    option.model="lamb_a0_thin"; option.thickness_m=h; option.frequency_hz=f; option.max_kh=1;
    result=oce.elastography.invertYoungModulus(cp,option);
    assert(abs(result.young_pa/E-1)<1e-12);
    option.max_kh=0.01; result=oce.elastography.invertYoungModulus(cp,option);
    assert(~result.valid_mask && isnan(result.young_pa));
    % Exact free-A0: independently solve cross-product Rayleigh-Lamb for
    % cp at known E, then invert. Moderate kh avoids the trivial zero root.
    option.model="lamb_a0_free"; option.frequency_hz=1200; option.thickness_m=0.6e-3;
    omega=2*pi*option.frequency_hz; cl=cs/sqrt(beta);
    residual=@(v) exact_free_a0_residual(v,omega,option.thickness_m,cs,cl);
    cp=fzero(residual,[0.15*cs 0.999*rayleigh*cs]);
    result=oce.elastography.invertYoungModulus(cp,option);
    assert(abs(result.young_pa/E-1)<1e-7);
    result=oce.elastography.invertYoungModulus(cp,struct());
    assert(~result.valid_mask && isnan(result.young_pa));
    assert_identifier('OCE:Young:InvalidMaterial',@() ...
        oce.elastography.invertYoungModulus(cs,struct('poisson_ratio',0.5)));
end

function residual=exact_free_a0_residual(cp,omega,h,cs,cl)
    k=omega/cp; alpha=sqrt(k^2-(omega/cl)^2); gamma=sqrt(k^2-(omega/cs)^2);
    residual=4*k^2*alpha*gamma*tanh(gamma*h/2)-(k^2+gamma^2)^2*tanh(alpha*h/2);
end

function assert_identifier(expected,callback)
    try, callback(); catch exception
        assert(strcmp(exception.identifier,expected),'Unexpected error %s.',exception.identifier); return;
    end
    error('OCE:Tests:ExpectedError','Expected %s.',expected);
end
