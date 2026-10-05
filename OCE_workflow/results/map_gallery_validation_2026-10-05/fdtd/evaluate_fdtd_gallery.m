function report=evaluate_fdtd_gallery(caseFile, galleryDirectory)
%EVALUATE_FDTDGALLERY Map physical FDTD cases with a complete far-field ROI.
% This observational Results harness does not change scientific production.
% Required fixture contract (cases cell/struct): label, data motion plane,
% model='lamb_a0_free'|'rayleigh', frequency_hz, thickness_m, density_kg_m3,
% poisson_ratio, source_center_m=[x y], background_wavelength_m,
% truth_young_pa [row,x]. Optional: farfield_roi, inclusion_mask,
% boundary_exclusion_m (default 0.15 mm at the exported crop border).
% Only selected two-panel PNG maps are written to galleryDirectory. Raw maps,
% comparisons and evaluation tables remain beside the input fixture.

    if nargin<1, caseFile=fullfile(fileparts(mfilename('fullpath')),'fdtd_gallery_cases.mat'); end
    if nargin<2
        workflowRoot=fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
        galleryDirectory=fullfile(workflowRoot,'results','Speed_Young_Maps');
    end
    assert(isfile(caseFile),'FDTD fixture is not available: %s',caseFile);
    loaded=load(caseFile,'cases'); cases=loaded.cases;
    if ~iscell(cases), cases=num2cell(cases); end
    outputDirectory=fileparts(caseFile);
    if ~isfolder(galleryDirectory), mkdir(galleryDirectory); end
    records=cell(0,1); products=cell(numel(cases),1);
    methods=["phase_gradient","directional_phase"]; windows=[0.9 1.2 1.5];
    chosenMethods=struct('lamb_a0_free',"directional_phase",'rayleigh',"phase_gradient"); chosenWindow=1.2;
    homogeneousAccepted=struct('lamb_a0_free',false,'rayleigh',false);
    diagnosticDirectory=fullfile(outputDirectory,'diagnostic_maps');
    if ~isfolder(diagnosticDirectory), mkdir(diagnosticDirectory); end
    for caseIndex=1:numel(cases)
        current=normalize_case(cases{caseIndex}); data=current.data;
        chosenMethod=chosenMethods.(current.model);
        [X,Y]=meshgrid(double(data.x_m),double(data.row_m));
        lambda=current.background_wavelength_m;
        % The excitation is a Y-extended line. Distance from its nearest
        % X edge avoids treating Y displacement as distance from that line.
        sourceDistance=max(0,abs(X-current.source_center_m(1))-current.source_support_halfwidth_m);
        physicalFar=sourceDistance>=2*lambda;
        boundaryMargin=current.boundary_exclusion_m;
        boundaryFar=X>=min(data.x_m)+boundaryMargin & X<=max(data.x_m)-boundaryMargin & ...
            Y>=min(data.row_m)+boundaryMargin & Y<=max(data.row_m)-boundaryMargin;
        baseMask=logical(data.valid_mask)&physicalFar&boundaryFar&current.farfield_roi;
        data.valid_mask=baseMask;
        products{caseIndex}=struct('label',current.label,'metadata',rmfield(current,'data'), ...
            'source_distance_m',sourceDistance,'physical_farfield_mask',physicalFar, ...
            'input_farfield_mask',baseMask,'methods',struct());
        for width=windows
            dx=mean(diff(double(data.x_m))); dy=mean(diff(double(data.row_m)));
            px=width*1e-3/(2*dx); py=width*1e-3/(2*dy);
            hx=max(1,floor(px+16*eps(px))); hy=floor(py+16*eps(py));
            kernel=ones(2*hy+1,2*hx+1);
            completeWindow=conv2(double(baseMask),kernel,'same')>=numel(kernel)-1e-9;
            for method=methods
                if current.model=="lamb_a0_free", speedRange=[0.5 2.8]; else, speedRange=[0.6 4]; end
                opts=struct('method',method,'frequency_hz',current.frequency_hz, ...
                    'window_x_mm',width,'window_row_mm',width, ...
                    'speed_range_m_s',speedRange, ...
                    'min_coherence',0.65,'min_amplitude_fraction',0.06, ...
                    'min_support_fraction',0.95,'smoothing_mm',0, ...
                    'direction_deg',0,'directional_halfwidth_deg',30, ...
                    'fit_error_max',0.22);
                started=tic; speed=oce.dispersion.estimateLocalSpeedMap(data,opts); elapsed=toc(started);
                % Full-window far-field acceptance guarantees all endpoints
                % used by the local fit, not just its central pixel, are
                % at least two background wavelengths from the source.
                accepted=speed.valid_mask&completeWindow;
                speed.valid_mask=accepted; speed.speed_m_s(~accepted)=NaN;
                speed.display_speed_m_s(~accepted)=NaN; speed.quality(~accepted)=0;
                inversionOptions=struct('model',current.model,'frequency_hz',current.frequency_hz, ...
                    'thickness_m',current.thickness_m,'density_kg_m3',current.density_kg_m3, ...
                    'poisson_ratio',current.poisson_ratio);
                young=oce.elastography.invertYoungModulus(speed,inversionOptions);
                suffix=sprintf('w%03d',round(width*1000)); field=char(method+"_"+suffix);
                products{caseIndex}.methods.(field)=struct('speed',speed,'young',young, ...
                    'complete_window_farfield_mask',completeWindow,'runtime_s',elapsed);
                row=summarize_case(current,speed,young,completeWindow,baseMask,method,width,sourceDistance);
                row.publication_disposition="comparison_only";
                if method==chosenMethod && abs(width-chosenWindow)<1e-12
                    homogeneous=~any(current.inclusion_mask,'all');
                    if homogeneous
                        homogeneousAccepted.(current.model)=isfinite(row.background_modulus_residual_median_pct) && ...
                            row.background_modulus_residual_median_pct<=10;
                    end
                    inclusionCoreAccepted=homogeneous || ...
                        (isfinite(row.pure_inclusion_modulus_residual_median_pct) && ...
                        row.pure_inclusion_modulus_residual_median_pct<=20);
                    if homogeneousAccepted.(current.model) && inclusionCoreAccepted
                        row.publication_disposition="gallery_homogeneous_model_passed_10pct";
                        destination=fullfile(galleryDirectory,char("fdtd_"+current.label+"_speed_young.png"));
                    else
                        if ~homogeneousAccepted.(current.model)
                            row.publication_disposition="diagnostic_only_homogeneous_model_not_passed_10pct";
                        else
                            row.publication_disposition="diagnostic_only_inclusion_core_discrepancy_over_20pct_or_undefined";
                        end
                        destination=fullfile(diagnosticDirectory,char("fdtd_"+current.label+"_speed_young.png"));
                    end
                    render_pair(destination,current,data,speed,young,completeWindow,sourceDistance);
                end
                records{end+1}=row; %#ok<AGROW>
                fprintf('%s %s window %.1fmm accepted%d backgroundE %.3gkPa inclusionE %.3gkPa\n', ...
                    current.label,method,width,nnz(accepted),row.background_young_median_kpa,row.inclusion_young_median_kpa);
            end
        end
    end
    report=struct2table(vertcat(records{:}));
    writetable(report,fullfile(outputDirectory,'fdtd_gallery_metrics.csv'));
    save(fullfile(outputDirectory,'fdtd_gallery_products.mat'),'products','report','-v7.3');
    write_notes(outputDirectory,report,chosenMethods,chosenWindow);
    selection=table(["lamb_a0_free";"rayleigh"], ...
        [chosenMethods.lamb_a0_free;chosenMethods.rayleigh],repmat(chosenWindow,2,1), ...
        ["sector +X suppresses reflected/secondary plate components; exploratory comparison"; ...
        "full local gradient retains curved/scattered surface-wave components; exploratory comparison"], ...
        'VariableNames',{'wave_model','selected_method','window_mm','selection_reason'});
    writetable(selection,fullfile(outputDirectory,'method_selection_by_wave_family.csv'));
end

function current=normalize_case(current)
    aliases={'f_hz','frequency_hz';'rho','density_kg_m3';'nu','poisson_ratio';'lambda_bg_m','background_wavelength_m'};
    for index=1:size(aliases,1)
        if ~isfield(current,aliases{index,2}) && isfield(current,aliases{index,1})
            current.(aliases{index,2})=current.(aliases{index,1});
        end
    end
    needed={'label','data','model','frequency_hz','thickness_m','density_kg_m3', ...
        'poisson_ratio','source_center_m','background_wavelength_m','truth_young_pa'};
    assert(all(isfield(current,needed)),'Incomplete FDTD gallery fixture contract.');
    % scipy MAT export preserves Python integer types (rho=1000). Normalize
    % physical metadata to floating SI at this fixture trust boundary.
    for scalarName=["frequency_hz","thickness_m","density_kg_m3","poisson_ratio","background_wavelength_m"]
        current.(scalarName)=double(current.(scalarName));
    end
    current.label=string(current.label); current.model=string(current.model);
    if current.model=="lamb_a0", current.model="lamb_a0_free"; end
    assert(any(current.model==["lamb_a0_free","rayleigh"]),'Fixture model must be free-plate A0 or Rayleigh.');
    current.data.plane_type=string(current.data.plane_type);
    current.data.valid_mask=logical(current.data.valid_mask);
    assert(any(isfinite(current.data.motion(:)) & current.data.motion(:)~=0), ...
        'FDTD exported motion is identically zero: verify harmonic CPU snapshot copying before interpreting propagation.');
    shape=size(current.data.valid_mask);
    if ~isfield(current,'farfield_roi'), current.farfield_roi=true(shape); end
    current.farfield_roi=logical(current.farfield_roi);
    if ~isfield(current,'boundary_exclusion_m'), current.boundary_exclusion_m=0.15e-3; end
    if ~isfield(current,'source_width_m'), current.source_width_m=0; end
    if ~isfield(current,'source_support_halfwidth_m')
        % Source width is Gaussian FWHM, not support width. The unchanged
        % simulator injects only S>1e-3, so the conservative X half extent
        % is FWHM*sqrt(log(1000)/(4*log(2))) (Y-centered maximum support).
        current.source_support_halfwidth_m=current.source_width_m*sqrt(log(1000)/(4*log(2)));
    end
    if ~isfield(current,'inclusion_mask')
        finite=current.truth_young_pa(isfinite(current.truth_young_pa));
        baseline=min(finite); current.inclusion_mask=current.truth_young_pa>1.1*baseline;
    end
    current.inclusion_mask=logical(current.inclusion_mask);
    assert(isequal(size(current.truth_young_pa),shape) && isequal(size(current.farfield_roi),shape),'Truth/ROI dimensions mismatch.');
    assert(numel(current.source_center_m)==2 && current.background_wavelength_m>0,'Invalid source/wavelength metadata.');
end

function row=summarize_case(current,speed,young,completeWindow,baseMask,method,width,distance)
    accepted=young.valid_mask; inclusion=current.inclusion_mask;
    bg=accepted&~inclusion; inc=accepted&inclusion;
    materialKernel=ones(speed.diagnostics.window_samples);
    inclusionFootprint=conv2(double(inclusion),materialKernel,'same');
    pureBackground=bg&inclusionFootprint==0;
    pureInclusion=inc&inclusionFootprint>=numel(materialKernel)-1e-9;
    trueBg=current.truth_young_pa(~inclusion&isfinite(current.truth_young_pa));
    trueInc=current.truth_young_pa(inclusion&isfinite(current.truth_young_pa));
    row=struct('case_name',current.label,'wave_model',current.model,'method',method, ...
        'window_mm',width,'window_row_samples',speed.diagnostics.window_samples(1), ...
        'window_x_samples',speed.diagnostics.window_samples(2), ...
        'frequency_hz',current.frequency_hz,'background_wavelength_mm',current.background_wavelength_m*1000, ...
        'solver_final_convergence_relative',convergence_value(current), ...
        'input_farfield_pixels',nnz(baseMask),'complete_fit_window_pixels',nnz(completeWindow), ...
        'accepted_pixels',nnz(accepted),'coverage_complete_farfield_pct',100*nnz(accepted)/max(1,nnz(completeWindow)), ...
        'background_pixels',nnz(bg),'inclusion_pixels',nnz(inc), ...
        'background_speed_median_m_s',finite_stat(speed.speed_m_s(bg),'median'), ...
        'inclusion_speed_median_m_s',finite_stat(speed.speed_m_s(inc),'median'), ...
        'background_young_median_kpa',finite_stat(young.young_pa(bg)/1000,'median'), ...
        'inclusion_young_median_kpa',finite_stat(young.young_pa(inc)/1000,'median'), ...
        'background_truth_young_kpa',finite_stat(trueBg/1000,'median'), ...
        'inclusion_truth_young_kpa',finite_stat(trueInc/1000,'median'), ...
        'background_modulus_residual_median_pct',NaN,'inclusion_modulus_residual_median_pct',NaN, ...
        'pure_background_fit_window_pixels',nnz(pureBackground), ...
        'pure_inclusion_fit_window_pixels',nnz(pureInclusion), ...
        'pure_background_young_median_kpa',finite_stat(young.young_pa(pureBackground)/1000,'median'), ...
        'pure_inclusion_young_median_kpa',finite_stat(young.young_pa(pureInclusion)/1000,'median'), ...
        'pure_background_modulus_residual_median_pct',NaN, ...
        'pure_inclusion_modulus_residual_median_pct',NaN, ...
        'minimum_accepted_center_distance_in_bg_wavelengths',finite_stat(distance(accepted)/current.background_wavelength_m,'min'), ...
        'minimum_fit_endpoint_distance_in_bg_wavelengths',NaN, ...
        'modulus_interpretation',"apparent conditional modulus; heterogeneous local inversion need not equal material E");
    if any(bg,'all'), row.background_modulus_residual_median_pct=100*median(abs(young.young_pa(bg)./current.truth_young_pa(bg)-1)); end
    if any(inc,'all'), row.inclusion_modulus_residual_median_pct=100*median(abs(young.young_pa(inc)./current.truth_young_pa(inc)-1)); end
    if any(pureBackground,'all'), row.pure_background_modulus_residual_median_pct=100*median(abs(young.young_pa(pureBackground)./current.truth_young_pa(pureBackground)-1)); end
    if any(pureInclusion,'all'), row.pure_inclusion_modulus_residual_median_pct=100*median(abs(young.young_pa(pureInclusion)./current.truth_young_pa(pureInclusion)-1)); end
    footprint=conv2(double(accepted),ones(speed.diagnostics.window_samples),'same')>0;
    if any(footprint,'all')
        row.minimum_fit_endpoint_distance_in_bg_wavelengths=min(distance(footprint))/current.background_wavelength_m;
        assert(row.minimum_fit_endpoint_distance_in_bg_wavelengths>=2-1e-10,'Near-field fit endpoint accepted.');
    end
end

function render_pair(destination,current,data,speed,young,completeWindow,distance)
    figureHandle=figure('Visible','off','Color','w','Position',[60 60 1320 560]);
    cleanup=onCleanup(@()close(figureHandle)); %#ok<NASGU>
    tiled=tiledlayout(figureHandle,1,2,'Padding','compact','TileSpacing','compact');
    x=double(data.x_m)*1000; y=double(data.row_m)*1000;
    phaseSpeed=current.frequency_hz*current.background_wavelength_m;
    axesSpeed=nexttile(tiled); draw_map(axesSpeed,x,y,speed.speed_m_s,'Velocidad de fase','m/s',[.5 1.6]*phaseSpeed);
    axesYoung=nexttile(tiled);
    if any(current.inclusion_mask,'all'), titleYoung='Young aparente'; else, titleYoung='Young segun modelo'; end
    draw_map(axesYoung,x,y,young.young_pa/1000,titleYoung,'kPa',[0 30]);
    for axesHandle=[axesSpeed axesYoung]
        hold(axesHandle,'on');
        if any(current.inclusion_mask,'all')
            contour(axesHandle,x,y,double(current.inclusion_mask),[.5 .5],'w--','LineWidth',1.3);
        end
        contour(axesHandle,x,y,distance/current.background_wavelength_m,[2 2], ...
            'Color',[.35 .35 .35],'LineStyle',':','LineWidth',1);
        hold(axesHandle,'off');
    end
    coverage=100*nnz(speed.valid_mask)/max(1,nnz(completeWindow));
    if current.model=="lamb_a0_free", modelName='Lamb A0, placa libre'; else, modelName='Rayleigh, semiespacio'; end
    if any(current.inclusion_mask,'all')
        inclusionE=median(current.truth_young_pa(current.inclusion_mask))/1000;
        materialName=sprintf('inclusion cilindrica %.0f kPa',inclusionE);
    else
        materialName=sprintf('medio homogeneo %.0f kPa',median(current.truth_young_pa,'all')/1000);
    end
    if speed.options.method=="directional_phase", methodName='sector +X'; else, methodName='gradiente local'; end
    title(tiled,sprintf('%s | %s | %s | soporte lejano %.1f %%', ...
        modelName,materialName,methodName,coverage),'Interpreter','none','FontSize',14,'FontWeight','bold');
    firstLine=sprintf('f = %.0f Hz | ventana %.2f mm | extremos del ajuste a >= 2 longitudes de onda de la fuente | sin rellenar huecos', ...
        current.frequency_hz,speed.options.window_x_mm);
    convergence=convergence_value(current);
    if isfinite(convergence) && convergence>0.005
        subtitle(tiled,{firstLine,sprintf('Cambio armonico final %.2f %%: no alcanzo criterio estacionario de 0.5 %%',100*convergence)},'FontSize',10);
    else
        subtitle(tiled,firstLine,'FontSize',10);
    end
    exportgraphics(figureHandle,destination,'Resolution',180);
end

function value=convergence_value(current)
    value=NaN;
    if isfield(current,'record_info') && isfield(current.record_info,'convergencia_rel')
        value=double(current.record_info.convergencia_rel);
    elseif isfield(current.data,'metadata') && isfield(current.data.metadata,'solver_convergence_relative')
        value=double(current.data.metadata.solver_convergence_relative);
    end
end

function draw_map(axesHandle,x,y,values,heading,units,range)
    imageHandle=imagesc(axesHandle,x,y,values); imageHandle.AlphaData=isfinite(values);
    axesHandle.Color=[.92 .92 .92]; axesHandle.YDir='normal'; axis(axesHandle,'image');
    xlabel(axesHandle,'X (mm)'); ylabel(axesHandle,'Y (mm)'); title(axesHandle,heading);
    colormap(axesHandle,turbo(256)); clim(axesHandle,range); bar=colorbar(axesHandle); bar.Label.String=units;
end

function value=finite_stat(values,operation)
    values=values(isfinite(values));
    if isempty(values), value=NaN;
    elseif strcmp(operation,'median'), value=median(values); else, value=min(values); end
end

function write_notes(directory,report,methods,width)
    fid=fopen(fullfile(directory,'fdtd_gallery_findings.md'),'w','n','UTF-8');
    cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
    fprintf(fid,'# Mapas FDTD de velocidad y Young\n\n');
    fprintf(fid,'Metodos de galeria por familia: Lamb A0 = %s; Rayleigh = %s; ventana comun %.1f mm. ',methods.lamb_a0_free,methods.rayleigh,width);
    fprintf(fid,'Se conservan las %d comparaciones de phase_gradient/directional_phase y ventanas 0.9/1.2/1.5 mm fuera de la galeria. ',height(report));
    fprintf(fid,'La eleccion es exploratoria a partir de los primeros cuatro casos y se mantiene para homogeneo/inclusion de cada familia; no constituye validacion independiente held-out ni optimalidad general. ');
    fprintf(fid,'El sector puede suprimir componentes secundarios de placa y tambien recortar ondas de superficie curvadas/dispersadas. No se ajustaron ventanas, umbrales ni mascaras con ground truth de E.\n\n');
    if height(report)>24
        fprintf(fid,'El quinto forward Rayleigh con inclusion blanda de 6 kPa se genero despues de fijar PG para la familia Rayleigh. ');
        fprintf(fid,'Se aplican el mismo metodo, ventana, umbrales y gates, independientemente del resultado: es una comprobacion adicional, no una validacion estadistica completa.\n\n');
    end
    fprintf(fid,'Publicacion automatica de galeria requiere residual mediano E <= 10 %% en el caso homogeneo correspondiente con esa configuracion fija. ');
    fprintf(fid,'Los casos que no pasan se renderizan solamente en diagnostic_maps; su inclusion correspondiente tampoco se publica. ');
    fprintf(fid,'Un residual homogeneo de 10-20 %% requiere revision adicional; > 20 %% descarta el candidato para esta galeria.\n\n');
    fprintf(fid,'Ademas, la inclusion requiere discrepancia mediana de E <= 20 %% en ventanas enteramente dentro de su nucleo. ');
    fprintf(fid,'Este es un criterio observacional fijado para seleccionar candidatos de esta galeria, no un umbral universal de exactitud del algoritmo o del modelo.\n\n');
    fprintf(fid,'Cada extremo de cada ventana de ajuste esta a al menos dos longitudes de onda de fondo del borde X mas cercano de la fuente lineal; ');
    fprintf(fid,'se excluyen bordes antes de filtrar. El campo lejano se expresa en longitudes de onda de fondo, sin afirmar que desaparece el campo dispersado por la inclusion.\n\n');
    fprintf(fid,'En FDTD heterogeneo, E material es conocido pero no existe una velocidad local unica exacta impuesta a cada pixel. ');
    fprintf(fid,'La inversion local produce Young aparente; los residuales frente a E constitutivo son una discrepancia diagnostica, no una prueba de ground truth de velocidad.\n\n');
    fprintf(fid,'| Caso | Metodo | Ventana mm | Cobertura %% | E fondo kPa | E inclusion kPa | Residual fondo %% | Residual inclusion %% | Min extremo/lambda |\n|---|---|---:|---:|---:|---:|---:|---:|---:|\n');
    for index=1:height(report)
        row=report(index,:); fprintf(fid,'| %s | %s | %.1f | %.1f | %.2f | %.2f | %.1f | %.1f | %.2f |\n', ...
            row.case_name,row.method,row.window_mm,row.coverage_complete_farfield_pct, ...
            row.background_young_median_kpa,row.inclusion_young_median_kpa, ...
            row.background_modulus_residual_median_pct,row.inclusion_modulus_residual_median_pct, ...
            row.minimum_fit_endpoint_distance_in_bg_wavelengths);
    end
end
