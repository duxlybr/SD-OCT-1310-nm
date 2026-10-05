%% Physical variable-rigidity Kirchhoff-Love plate, thin flexural A0 limit
% No prescribed phase or local-speed construction: the global sparse PDE
% responds to E(x,y) through D inside the bending-moment divergence.
outputRoot=fileparts(mfilename('fullpath'));
workflowRoot=fileparts(fileparts(fileparts(outputRoot)));
cd(workflowRoot);startup;
galleryRoot=fullfile(workflowRoot,'results','Speed_Young_Maps');
if ~isfolder(galleryRoot),mkdir(galleryRoot);end
if exist('gallery_render_only','var') && gallery_render_only
    load(fullfile(outputRoot,'physical_lamb_plate_maps.mat'),'physics','maps');
else
physics=struct('density_kg_m3',1000,'poisson_ratio',.495,'thickness_m',.0002, ...
    'frequency_hz',60,'background_young_pa',12000,'inclusion_young_pa',24000, ...
    'inclusion_radius_lambda',2,'domain_half_x_lambda',12,'domain_half_y_lambda',10, ...
    'absorber_start_x_lambda',9,'absorber_start_y_lambda',7.5, ...
    'absorber_strength',2,'source_x_lambda',-8,'source_half_y_lambda',7, ...
    'source_sigma_x_lambda',.07,'map_half_lambda',4,'source_clearance_lambda',2, ...
    'window_lambda',.5,'noise_snr_db',35,'noise_seed',20261005);
omega=2*pi*physics.frequency_hz;
Db=physics.background_young_pa*physics.thickness_m^3/(12*(1-physics.poisson_ratio^2));
k=(physics.density_kg_m3*physics.thickness_m*omega^2/Db)^.25;
physics.lambda_background_m=2*pi/k;
fprintf('Plate: lambda %.6f mm, kh %.6f, cphase %.6f m/s\n', ...
    physics.lambda_background_m*1000,k*physics.thickness_m,omega/k);
assert(k*physics.thickness_m<.3,'Gallery:ThinPlate','Chosen forward is the thin flexural limit.');
solutions=struct([]);
for ppw=[18 24]
    for contrast=[1 2 .5]
        cachedFile=fullfile(outputRoot,sprintf('physical_plate_ppw%d_contrast%s.mat',ppw,contrast_tag(contrast)));
        if isfile(cachedFile)
            previous=load(cachedFile,'solution','physics');
            assert(isequal(previous.physics,physics),'Gallery:CacheChanged','Cached forward parameters must match exactly.');
            solution=previous.solution;
            fprintf('Reusing identical physical PDE ppw%d contrast%g...\n',ppw,contrast);
        else
            fprintf('Solving plate ppw%d contrast%g...\n',ppw,contrast);
            solution=solve_plate(physics,ppw,contrast);
        end
        fprintf('PDE residual %.3g, %d unknowns, elapsed %.1f s\n', ...
            solution.relative_residual,numel(solution.field_m),solution.seconds);
        if isempty(solutions),solutions=solution;else,solutions(end+1)=solution;end %#ok<SAGROW>
        save(cachedFile,'solution','physics','-v7.3');
    end
end
% Geometry-only extraction precedes estimation. It excludes the source by
% 2 lambda and the sponge by >=2 lambda. The displayed map is farther inside.
records=struct([]);maps=struct([]);
for index=1:numel(solutions)
    solution=solutions(index);
    [data,truth,displayMask,coreMask,backgroundMask]=make_motion(solution,physics);
    options=struct('method',"directional_phase",'frequency_hz',physics.frequency_hz, ...
        'time_start_s',data.t_s(1),'time_end_s',data.t_s(end), ...
        'window_x_mm',physics.window_lambda*physics.lambda_background_m*1000, ...
        'window_row_mm',physics.window_lambda*physics.lambda_background_m*1000, ...
        'direction_deg',0,'directional_halfwidth_deg',45,'min_coherence',.65, ...
        'min_support_fraction',.9,'min_amplitude_fraction',.04,'fit_error_max',.22, ...
        'speed_range_m_s',[.12 .7],'smoothing_mm',0);
    result=oce.dispersion.estimateLocalSpeedMap(data,options);
    youngOptions=struct('model',"lamb_a0_thin",'density_kg_m3',physics.density_kg_m3, ...
        'poisson_ratio',physics.poisson_ratio,'thickness_m',physics.thickness_m, ...
        'frequency_hz',physics.frequency_hz,'max_kh',.6);
    young=oce.elastography.invertYoungModulus(result,youngOptions);
    assert(all(isnan(result.speed_m_s(~result.valid_mask)),'all') && ...
        all(isnan(young.young_pa(~young.valid_mask)),'all'),'Gallery:NaNFilled','NaN must be preserved.');
    subsets={displayMask,coreMask,backgroundMask};names=["display_full","inclusion_core","background_far"];
    for regionIndex=1:numel(subsets)
        region=subsets{regionIndex};valid=region&result.valid_mask;ev=region&young.valid_mask;
        c=result.speed_m_s(valid);E=young.young_pa(ev);
        relc=100*(c-truth.speed_m_s(valid))./truth.speed_m_s(valid);
        rele=100*(E-truth.young_pa(ev))./truth.young_pa(ev);
        record=struct('points_per_wavelength',solution.ppw,'contrast_ratio',solution.contrast, ...
            'region',names(regionIndex),'total_pixel_count',nnz(region),'accepted_pixel_count',nnz(valid), ...
            'coverage_fraction',nnz(valid)/nnz(region),'speed_median_m_s',median_or_nan(c), ...
            'speed_median_bias_pct',median_or_nan(relc),'speed_median_abs_error_pct',median_or_nan(abs(relc)), ...
            'young_median_kpa',median_or_nan(E)/1000,'young_median_bias_pct',median_or_nan(rele), ...
            'young_median_abs_error_pct',median_or_nan(abs(rele)), ...
            'pde_relative_residual',solution.relative_residual,'solve_seconds',solution.seconds);
        if isempty(records),records=record;else,records(end+1)=record;end %#ok<SAGROW>
    end
    map=struct('data',data,'truth',truth,'display_mask',displayMask,'core_mask',coreMask, ...
        'background_mask',backgroundMask,'result',result,'young',young,'options',options, ...
        'young_options',youngOptions,'ppw',solution.ppw,'contrast',solution.contrast, ...
        'forward_relative_residual',solution.relative_residual);
    if isempty(maps),maps=map;else,maps(end+1)=map;end %#ok<SAGROW>
    fprintf('Estimated ppw%d contrast%g: displayed support %.2f%%\n', ...
        solution.ppw,solution.contrast,100*nnz(displayMask&result.valid_mask)/nnz(displayMask));
end
writetable(struct2table(records),fullfile(outputRoot,'physical_lamb_plate_metrics.csv'));
refinement=refinement_checks(solutions,maps,physics);
writetable(struct2table(refinement),fullfile(outputRoot,'physical_lamb_plate_refinement.csv'));
provenance=struct('model',"Kirchhoff-Love variable-rigidity thin flexural Lamb A0 limit", ...
    'phase_generated_from_speed',false,'forward',"Sparse global plate bending-moment divergence equation with complex sponge outside measurement region", ...
    'mask_policy',"Predeclared geometry; source clearance >=2 background wavelengths, sponge clearance >=2 wavelengths; display [-4,4] lambda", ...
    'ground_truth',"Constitutive E(x,y) and local homogeneous thin-plate dispersion reference; a scattered field need not have one local wavenumber at every pixel", ...
    'smoothing_mm',0,'invalid_pixel_filling',false,'noise_seed',physics.noise_seed);
save(fullfile(outputRoot,'physical_lamb_plate_maps.mat'),'physics','maps','records','refinement','provenance','-v7.3');
end
for contrast=[2 .5]
    selected=maps([maps.ppw]==24 & [maps.contrast]==contrast);
    if contrast==2,tag='simulation_lamb_plate_physical_inclusion';else,tag='simulation_lamb_plate_soft_inclusion';end
    for kind=["speed","young"]
        render_map(selected,physics,kind,fullfile(galleryRoot,tag+"_"+kind+".png"),false);
        render_map(selected,physics,kind,fullfile(outputRoot,tag+"_"+kind+"_error_diagnostic.png"),true);
    end
end
disp('PHYSICAL_LAMB_PLATE_GALLERY_FINISHED');

function solution=solve_plate(p,ppw,contrast)
    timer=tic;lambda=p.lambda_background_m;dx=lambda/ppw;
    nx=round(2*p.domain_half_x_lambda*ppw)-1;
    ny=round(2*p.domain_half_y_lambda*ppw)-1;
    x=((1:nx)-(nx+1)/2)'*dx;y=((1:ny)-(ny+1)/2)'*dx;
    [X,Y]=meshgrid(x,y);radius=p.inclusion_radius_lambda*lambda;
    E=p.background_young_pa*ones(ny,nx);E(hypot(X,Y)<=radius)=p.background_young_pa*contrast;
    D=E*p.thickness_m^3/(12*(1-p.poisson_ratio^2));
    ex=ones(nx,1);ey=ones(ny,1);
    Lx=spdiags([ex -2*ex ex],-1:1,nx,nx)/dx^2;
    Ly=spdiags([ey -2*ey ey],-1:1,ny,ny)/dx^2;
    Gx=spdiags([-ex ex],[-1 1],nx,nx)/(2*dx);
    Gy=spdiags([-ey ey],[-1 1],ny,ny)/(2*dx);
    Bxx=kron(Lx,speye(ny));Byy=kron(speye(nx),Ly);Bxy=kron(Gx,Gy);
    stiffness=spdiags(D(:),0,nx*ny,nx*ny);nu=p.poisson_ratio;
    K=Bxx'*stiffness*Bxx+Byy'*stiffness*Byy+ ...
        nu*(Bxx'*stiffness*Byy+Byy'*stiffness*Bxx)+2*(1-nu)*Bxy'*stiffness*Bxy;
    rampX=max(0,(abs(X)/lambda-p.absorber_start_x_lambda)/ ...
        (p.domain_half_x_lambda-p.absorber_start_x_lambda));
    rampY=max(0,(abs(Y)/lambda-p.absorber_start_y_lambda)/ ...
        (p.domain_half_y_lambda-p.absorber_start_y_lambda));
    loss=p.absorber_strength*(rampX.^3+rampY.^3);
    mass=p.density_kg_m3*p.thickness_m;omega=2*pi*p.frequency_hz;
    A=K+spdiags(mass*omega^2*(-1+1i*loss(:)),0,nx*ny,nx*ny);
    % Smooth finite line pressure; its ends lie >=3 lambda outside the map.
    pressure=exp(-.5*((X-p.source_x_lambda*lambda)/(p.source_sigma_x_lambda*lambda)).^2).* ...
        exp(-(Y/(p.source_half_y_lambda*lambda)).^12);
    field=reshape(A\pressure(:),ny,nx);
    relativeResidual=norm(A*field(:)-pressure(:))/norm(pressure(:));
    assert(relativeResidual<1e-6,'Gallery:PlateResidual','Sparse plate residual exceeds tolerance.');
    % Linear displacement amplitude normalization scales force consistently.
    scale=1e-7/max(abs(field(:)));field=field*scale;pressure=pressure*scale;
    solution=struct('x_m',x,'y_m',y,'field_m',field,'young_pa',E,'rigidity_n_m',D, ...
        'absorber_loss',loss,'source_pressure_pa',pressure,'relative_residual',relativeResidual, ...
        'ppw',ppw,'contrast',contrast,'dx_m',dx,'seconds',toc(timer), ...
        'boundary_closure',"Zero exterior displacement in centered difference energy; artificial exterior boundary screened by complex mass sponge", ...
        'operator',"Bxx'' D Bxx + Byy'' D Byy + nu(Bxx'' D Byy+Byy'' D Bxx)+2(1-nu)Bxy'' D Bxy - rho*h*omega^2 + i*rho*h*omega^2*loss");
end

function [data,truth,displayMask,coreMask,backgroundMask]=make_motion(s,p)
    lambda=p.lambda_background_m;
    % Retain the full admissible far-field footprint before spatial filtering.
    xi=find(s.x_m>=(p.source_x_lambda+p.source_clearance_lambda)*lambda & s.x_m<=7*lambda);
    yi=find(abs(s.y_m)<=5.5*lambda);
    field=s.field_m(yi,xi);x=s.x_m(xi);y=s.y_m(yi);[X,Y]=meshgrid(x,y);
    t=(0:180)'/(30*p.frequency_hz);
    signal=real(reshape(field,[],1)*exp(1i*2*pi*p.frequency_hz*t'));
    rng(p.noise_seed+100*s.ppw+s.contrast,'twister');
    noiseStd=sqrt(mean(signal.^2,'all'))*10^(-p.noise_snr_db/20);
    motion=reshape(single(signal+noiseStd*randn(size(signal))),numel(y),numel(x),numel(t));
    data=struct('motion',motion,'x_m',x,'row_m',y,'t_s',t,'valid_mask',true(size(field)), ...
        'plane_type',"enface",'metadata',struct('model',"physical variable-rigidity Kirchhoff-Love plate", ...
        'source_clearance_lambda',p.source_clearance_lambda,'sponge_clearance_lambda',2, ...
        'thickness_m',p.thickness_m,'noise_snr_db',p.noise_snr_db));
    E=s.young_pa(yi,xi);D=s.rigidity_n_m(yi,xi);omega=2*pi*p.frequency_hz;
    speed=omega./(p.density_kg_m3*p.thickness_m*omega^2./D).^.25;
    truth=struct('young_pa',E,'speed_m_s',speed,'rigidity_n_m',D);
    displayMask=abs(X)<=p.map_half_lambda*lambda & abs(Y)<=p.map_half_lambda*lambda;
    radius=p.inclusion_radius_lambda*lambda;
    % Exclude one window width from the interface for regional accuracy;
    % these truth-derived regions affect metrics only, never measurement QC.
    coreMask=displayMask & hypot(X,Y)<radius-p.window_lambda*lambda;
    backgroundMask=displayMask & hypot(X,Y)>radius+p.window_lambda*lambda;
end

function checks=refinement_checks(solutions,maps,p)
    checks=struct([]);
    for contrast=[1 2 .5]
        coarse=solutions([solutions.ppw]==18 & [solutions.contrast]==contrast);
        fine=solutions([solutions.ppw]==24 & [solutions.contrast]==contrast);
        [X,Y]=meshgrid(coarse.x_m,coarse.y_m);
        reference=interp2(fine.x_m,fine.y_m,fine.field_m,X,Y,'linear');
        mask=abs(X)<=p.map_half_lambda*p.lambda_background_m & ...
            abs(Y)<=p.map_half_lambda*p.lambda_background_m;
        % Complex scale removes the arbitrary consistent force normalization;
        % it does not remove phase gradients or spatial differences.
        scale=(reference(mask)'*coarse.field_m(mask))/(reference(mask)'*reference(mask));
        difference=norm(coarse.field_m(mask)-scale*reference(mask))/norm(coarse.field_m(mask));
        a=maps([maps.ppw]==18 & [maps.contrast]==contrast);
        b=maps([maps.ppw]==24 & [maps.contrast]==contrast);
        cv=a.result.speed_m_s(a.display_mask&a.result.valid_mask);
        fv=b.result.speed_m_s(b.display_mask&b.result.valid_mask);
        record=struct('contrast_ratio',contrast,'coarse_ppw',18,'fine_ppw',24, ...
            'complex_field_relative_l2_after_global_scale',difference, ...
            'coarse_speed_median_m_s',median_or_nan(cv),'fine_speed_median_m_s',median_or_nan(fv), ...
            'median_speed_change_pct',100*(median_or_nan(fv)/median_or_nan(cv)-1), ...
            'interpretation',"Finite-difference refinement diagnostic; constitutive interface staircasing also changes, no convergence claim from two meshes alone");
        if isempty(checks),checks=record;else,checks(end+1)=record;end %#ok<SAGROW>
    end
end

function render_map(map,p,kind,path,includeError)
    xs=any(map.display_mask,1);ys=any(map.display_mask,2);
    x=map.data.x_m(xs)*1000;y=map.data.row_m(ys)*1000;
    if strcmp(kind,'speed')
        truth=map.truth.speed_m_s(ys,xs);estimate=map.result.speed_m_s(ys,xs);
        label='Velocidad de fase (m/s)';range=[.20 .40];heading='Velocidad de fase';
        Db=p.background_young_pa*p.thickness_m^3/(12*(1-p.poisson_ratio^2));
        omega=2*pi*p.frequency_hz;
        cb=omega/(p.density_kg_m3*p.thickness_m*omega^2/Db)^.25;
        expected=sprintf('Fondo → inclusión: %.3f → %.3f m/s',cb,cb*map.contrast^.25);
    else
        truth=map.truth.young_pa(ys,xs)/1000;estimate=map.young.young_pa(ys,xs)/1000;
        label='Young (kPa)';range=[4 28];heading='Young · inversión flexural A0 delgada';
        expected=sprintf('Material constitutivo: 12 → %g kPa; espesor conocido 0.20 mm',12*map.contrast);
    end
    valid=isfinite(estimate);error=100*(estimate-truth)./truth;
    if includeError,nPanels=3;figWidth=1800;else,nPanels=2;figWidth=1450;end
    fig=figure('Visible','off','Color','w','Position',[20 20 figWidth 850]);
    cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
    layout=tiledlayout(fig,1,nPanels,'Padding','compact','TileSpacing','compact');
    layout.Units='normalized';layout.OuterPosition=[.015 .21 .97 .76];
    if map.contrast>1,caseLabel="inclusión rígida";else,caseLabel="inclusión blanda";end
    title(layout,"Simulación física · placa Kirchhoff–Love · "+caseLabel+" · "+heading, ...
        'FontSize',17,'FontWeight','bold','Interpreter','none');
    subtitle(layout,expected+" | f = 60 Hz | Lamb A0 en límite flexural delgado",'FontSize',13,'Interpreter','none');
    arrays={truth,estimate,error};titles={'Referencia constitutiva / dispersión local','Estimación direccional · sin suavizado','Error relativo sobre píxeles aceptados'};
    for i=1:nPanels
        ax=nexttile(layout);im=imagesc(ax,x,y,arrays{i});im.AlphaData=isfinite(arrays{i});
        ax.Color=[.88 .88 .88];axis(ax,'image');xlabel(ax,'x (mm)');ylabel(ax,'y (mm)');ax.FontSize=11;
        title(ax,titles{i},'FontSize',13,'Interpreter','none');cb=colorbar(ax);
        if i<3,clim(ax,range);colormap(ax,parula(256));cb.Label.String=label;
        else,clim(ax,[-40 40]);colormap(ax,blue_white_red());cb.Label.String='Error (%)';end
    end
    coverage=100*nnz(valid)/numel(valid);
    rel=error(valid);
    footer={sprintf('Soporte aceptado %.3f%%; error absoluto mediano %.2f%%. Gris = rechazado; sin relleno ni suavizado.',coverage,median_or_nan(abs(rel))), ...
        sprintf('Forward: derivadas de momentos con D(x,y) real; fuente lineal y esponja fuera del mapa. Residual %.2g; malla 24 puntos/λ.', ...
        map.forward_relative_residual), ...
        sprintf('ρ = 1000 kg/m³, ν = 0.495; ventana %.2f mm, dirección 0° ±45°, SNR temporal 35 dB.',map.options.window_x_mm), ...
        'La inclusión produce refracción, reflexión e interferencia; la fase local cerca del borde no equivale siempre al material local.', ...
        'Validación de este forward delgado: excluye fluido, viscosidad, tensión, curvatura y calibración OCT; no representa ground truth experimental.'};
    annotation(fig,'textbox',[.035 .015 .94 .16],'String',footer,'FontSize',11,'Interpreter','none','EdgeColor','none');
    exportgraphics(fig,path,'Resolution',150,'BackgroundColor','white');
end

function value=contrast_tag(contrast)
    value=strrep(sprintf('%.2g',contrast),'.','p');
end

function v=median_or_nan(x)
    if isempty(x),v=NaN;else,v=median(x);end
end

function map=blue_white_red()
    n=128;map=[linspace(.2,1,n)' linspace(.35,1,n)' ones(n,1); ...
        ones(n,1) linspace(1,.25,n)' linspace(1,.2,n)'];
end
