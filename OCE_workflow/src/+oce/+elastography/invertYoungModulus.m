function result = invertYoungModulus(speed, options)
%INVERTYOUNGMODULUS Conditional elastic-model inversion, never mode detection.
% SPEED is a numeric SI speed map or estimateLocalSpeedMap's result struct.
% OPTIONS.model: none (default), bulk_shear, rayleigh, lamb_a0_thin, or
% lamb_a0_free. All are homogeneous isotropic purely elastic models; density
% and Poisson ratio are user assumptions, not quantities estimated by OCT.
% Lamb uses PHASE velocity, total plate thickness and excitation frequency.
% lamb_a0_free solves the exact traction-free antisymmetric Rayleigh-Lamb
% branch below the Rayleigh speed. Fluid loading, curvature, pre-stress,
% anisotropy and viscoelasticity require another forward model. Single-
% frequency inversion cannot establish which physical model is appropriate.
% Rayleigh secular equation and the antisymmetric free-plate equation use
% standard isotropic elastodynamics; A0 thin is the Kirchhoff flexural limit.

    if nargin<2, options=struct(); end
    if isstruct(speed) && isscalar(speed) && isfield(speed,'speed_m_s')
        if isfield(speed,'valid_mask'), measured=speed.valid_mask; else, measured=isfinite(speed.speed_m_s); end
        values=speed.speed_m_s;
    else, values=speed; measured=isfinite(values); end
    if ~isnumeric(values) || ~isreal(values) || ~ismatrix(values) || ...
            ~islogical(measured) || ~isequal(size(measured),size(values))
        error('OCE:Young:InvalidSpeed','Speed must be a real SI map, optionally with its logical measured valid_mask.');
    end
    if ~isstruct(options) || ~isscalar(options)
        error('OCE:Young:InvalidOptions','Options must be a scalar struct.');
    end
    defaults=struct('model',"none",'density_kg_m3',1000,'poisson_ratio',0.495, ...
        'thickness_m',NaN,'frequency_hz',NaN,'max_kh',0.6);
    names=fieldnames(defaults);
    for index=1:numel(names)
        if ~isfield(options,names{index}), options.(names{index})=defaults.(names{index}); end
    end
    options.model=string(options.model);
    if ~isscalar(options.model) || ~any(options.model==["none","bulk_shear","rayleigh","lamb_a0_thin","lamb_a0_free"])
        error('OCE:Young:InvalidModel','Unknown conditional Young inversion model.');
    end
    if ~isnumeric(options.density_kg_m3) || ~isreal(options.density_kg_m3) || ~isscalar(options.density_kg_m3) || ...
            ~isfinite(options.density_kg_m3) || options.density_kg_m3<=0 || ...
            ~isnumeric(options.poisson_ratio) || ~isreal(options.poisson_ratio) || ~isscalar(options.poisson_ratio) || ...
            ~isfinite(options.poisson_ratio) || options.poisson_ratio<=-1 || options.poisson_ratio>=0.5
        error('OCE:Young:InvalidMaterial','Density must be positive; elastic Poisson ratio must lie strictly in (-1,0.5).');
    end
    young=NaN(size(values)); valid=measured&isfinite(values)&values>0;
    kh=NaN(size(values)); ratio=NaN(size(values)); modelGate=true(size(values));
    a0AsymptoticUsed=false(size(values));
    assumption="homogeneous isotropic linear purely elastic medium; assumed density and Poisson ratio";
    warningText="Conditional apparent modulus: a speed map does not identify the wave mode or boundary conditions.";
    if options.model=="none"
        valid(:)=false;
        assumption="no mechanical model selected";
        warningText="Young modulus is unavailable until a physical wave model is explicitly selected.";
    elseif options.model=="bulk_shear"
        young(valid)=2*options.density_kg_m3*(1+options.poisson_ratio)*double(values(valid)).^2;
        assumption=assumption+"; input speed is bulk transverse/shear speed";
    elseif options.model=="rayleigh"
        ratioRayleigh=rayleigh_ratio(options.poisson_ratio);
        ratio(valid)=ratioRayleigh;
        young(valid)=2*options.density_kg_m3*(1+options.poisson_ratio)*(double(values(valid))/ratioRayleigh).^2;
        assumption=assumption+"; Rayleigh wave on an elastic traction-free half-space";
    else
        if ~isnumeric(options.frequency_hz) || ~isreal(options.frequency_hz) || ~isscalar(options.frequency_hz) || ...
                ~isfinite(options.frequency_hz) || options.frequency_hz<=0 || ...
                ~isnumeric(options.thickness_m) || ~isreal(options.thickness_m) || ...
                ~(isscalar(options.thickness_m) || isequal(size(options.thickness_m),size(values))) || ...
                any(~isfinite(options.thickness_m),'all') || any(options.thickness_m<=0,'all')
            error('OCE:Young:InvalidPlate','A0 inversion needs positive excitation frequency and total plate thickness in metres.');
        end
        thickness=double(options.thickness_m)+zeros(size(values)); omega=2*pi*options.frequency_hz;
        kh(valid)=omega*thickness(valid)./double(values(valid));
        assumption=assumption+"; fundamental antisymmetric A0 PHASE velocity in a flat traction-free free plate; no fluid or tension";
        if options.model=="lamb_a0_thin"
            if ~isnumeric(options.max_kh) || ~isreal(options.max_kh) || ~isscalar(options.max_kh) || ...
                    ~isfinite(options.max_kh) || options.max_kh<=0
                error('OCE:Young:InvalidThinGate','max_kh must be a finite positive explicit thin-plate applicability threshold.');
            end
            modelGate=kh<=options.max_kh;
            valid=valid&modelGate;
            young(valid)=12*(1-options.poisson_ratio^2)*options.density_kg_m3* ...
                double(values(valid)).^4./(omega^2*thickness(valid).^2);
            warningText=warningText+" Thin-plate kh gate is an engineering limit, not a universal accuracy guarantee; group speed would produce a different result.";
        else
            ratioRayleigh=rayleigh_ratio(options.poisson_ratio);
            beta=(1-2*options.poisson_ratio)/(2*(1-options.poisson_ratio));
            for index=find(valid)'
                K=kh(index)/2;
                if K<0.005
                    % Exact root tends to the Kirchhoff branch; use its
                    % asymptotic limit when double-precision cancellation
                    % prevents evaluation. Relative correction is O((kh)^2).
                    ratio(index)=kh(index)/sqrt(6*(1-options.poisson_ratio));
                    a0AsymptoticUsed(index)=true;
                else
                    secular=@(v) a0_secular(v,K,beta);
                    ratio(index)=fzero(secular,[0 ratioRayleigh],optimset('Display','off','TolX',1e-10));
                end
                young(index)=2*options.density_kg_m3*(1+options.poisson_ratio)*(double(values(index))/ratio(index))^2;
            end
            warningText=warningText+" Exact free-plate A0 dispersion is conditional on the selected branch and known thickness; fluid loading is not included.";
        end
    end
    valid=valid&isfinite(young)&young>0; young(~valid)=NaN;
    result=struct('young_pa',young,'valid_mask',valid,'options',options, ...
        'assumptions',assumption,'warning',warningText,'warnings',warningText, ...
        'diagnostics',struct('kh',kh,'phase_to_shear_speed_ratio',ratio, ...
        'model_applicability_mask',modelGate,'a0_small_kh_asymptotic_used',a0AsymptoticUsed, ...
        'modulus_interpretation',"conditional apparent elastic Young modulus; no experimental ground truth"));
end

function ratio=rayleigh_ratio(nu)
    beta=(1-2*nu)/(2*(1-nu));
    secular=@(s) s.^3-8*s.^2+(24-16*beta)*s-16*(1-beta);
    ratio=sqrt(fzero(secular,[0 1],optimset('Display','off','TolX',1e-12)));
end

function residual=a0_secular(v,K,beta)
    % Hyperbolic sub-shear Rayleigh-Lamb A0 secular equation. Log form
    % removes tangent poles, and division by v^2 removes its spurious
    % zero-frequency root without accepting p=q=0 as a material solution.
    if v==0
        if K<1e-3, correction=2*K^2/3-14*K^4/45;
        elseif K>350, correction=1;
        else, correction=1-2*K/sinh(2*K); end
        residual=0.5*(1-beta)*correction; return;
    end
    s=v^2; alpha=sqrt(1-beta*s); gamma=sqrt(1-s);
    residual=(log(tanh(gamma*K))-log(tanh(alpha*K))+ ...
        0.5*log1p(-beta*s)+0.5*log1p(-s)-2*log1p(-s/2))/s;
end
