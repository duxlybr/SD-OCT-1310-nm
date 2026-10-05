function window = tuneWaveSpeedMaps(source, initialOptions)
%TUNEWAVESPEEDMAPS Interactive local wave-speed and model-specific Young maps.
% source: BIN path, MAT path containing data, or validated motion-plane struct.
% Returns a nonblocking uifigure. UserData contains the latest accepted data,
% measured map and inversion; export includes settings and source provenance.
% Numerical algorithms belong to dispersion/elastography, not to this UI.
    if nargin < 1, source = []; end
    if nargin < 2, initialOptions = struct(); end
    data = []; rawData = []; speedResult = []; youngResult = []; busy = false;
    needsReload=false; loadedSource=''; rawUnwrapKey=[];
    window = uifigure('Name','OCE | Velocidad y modulo de Young', ...
        'Position',[50 40 1450 870]);
    main = uigridlayout(window,[2 2]);
    main.ColumnWidth = {355,'1x'}; main.RowHeight = {'1x',120};
    panel = uipanel(main,'Title','Parametros y supuestos');
    panel.Layout.Row = 1; panel.Layout.Column = 1;
    controls = uigridlayout(panel,[56 2]); controls.Scrollable = 'on';
    controls.ColumnWidth = {'1x',125}; controls.RowHeight = repmat({27},1,56);
    controls.Padding = [8 8 8 8]; controls.RowSpacing = 5;
    fields = struct(); row = 0;
    label('Archivo BIN / MAT');
    pathField = uieditfield(controls,'text','Value',''); span(pathField);
    choose = uibutton(controls,'Text','Seleccionar archivo','ButtonPushedFcn',@chooseFile); span(choose);
    dropdown('plane_type','Plano',{'auto','enface','bmode'},'auto');
    dropdown('phase_product','Entrada de fase',{'phase_increment','raw_wrapped'},'phase_increment');
    number('bmode_index','B-mode independiente',1,[1 Inf]);
    number('depth_offset_mm','Profundidad bajo superficie mm',0,[0 Inf]);
    number('depth_band_mm','Espesor del plano mm',0.04,[0.001 Inf]);
    number('depth_start_index','FFT inicio (indice)',1,[1 Inf]);
    number('depth_end_index','FFT final (indice)',700,[2 Inf]);
    number('surface_search_start_index','Superficie inicio (indice)',15,[1 Inf]);
    number('surface_search_end_index','Superficie final (indice)',500,[2 Inf]);
    dropdown('surface_method','Metodo superficie',{'inherited_threshold','max_in_search','manual_index'},'inherited_threshold');
    number('surface_index','Superficie manual (indice FFT)',100,[1 Inf]);
    number('surface_peak_threshold_db','Umbral borde sobre fondo dB',6,[-100 100]);
    number('max_phase_step_rad','Limite incremento rad (QC)',pi,[.001 Inf]);
    number('refractive_index','Indice de refraccion',1.4,[1 2]);
    number('line_rate_hz','A-line Hz (0 = encabezado)',0,[0 Inf]);
    number('intensity_floor_db','Mascara OCT dB relativos',-35,[-100 0]);
    number('coherence_threshold','Coherencia OCT minima',0.15,[0 1]);
    number('loupas_axial_window','Promedio axial (muestras)',3,[2 Inf]);
    number('lateral_stride','Paso posiciones X',1,[1 Inf]);
    number('raster_line_stride','Paso B-modes raster/polar',1,[1 Inf]);
    loadButton = uibutton(controls,'Text','Cargar / reconstruir plano', ...
        'ButtonPushedFcn',@loadSource); span(loadButton);
    previewButton = uibutton(controls,'Text','Revisar OCT y superficie', ...
        'ButtonPushedFcn',@previewSurface); span(previewButton);
    signalButton = uibutton(controls,'Text','Senal temporal / espectro: elegir punto', ...
        'ButtonPushedFcn',@previewSignal); span(signalButton);
    dropdown('method','Estimador',{'phase_derivative_2d','phase_gradient','directional_phase','reverberant'},'directional_phase');
    dropdown('unwrap_method','Unwrap crudo y modal',{'sequential','least_squares_dct','tie_dct'},'sequential');
    dropdown('raw_unwrap_domain','Unwrap optico: dominio',{'temporal','temporal_depth'},'temporal');
    number('unwrap_iterations','Iteraciones fijas TIE DCT',8,[1 10000]);
    dropdown('pd_geometry','Derivada: geometria',{'auto','lateral','in_plane'},'auto');
    number('pd_polynomial_order','Orden polinomio derivada',2,[1 2]);
    checkbox('directional_filter_enabled','Filtrar direccion antes de PD',false);
    number('frequency_hz','Frecuencia mecanica Hz',1000,[1 Inf]);
    number('time_start_ms','Tiempo inicio ms',0,[0 Inf]);
    number('time_end_ms','Tiempo final ms (0 = todo)',0,[0 Inf]);
    number('window_x_mm','Ventana X mm',1.2,[0.01 Inf]);
    number('window_row_mm','Ventana Y/Z mm (0 = por fila)',1.2,[0 Inf]);
    number('direction_deg','Direccion propagacion grados',0,[-180 180]);
    number('directional_halfwidth_deg','Semiancho angular grados',35,[1 89.9]);
    dropdown('reverb_model','Campo reverberante',{'scalar2d','shear3d'},'shear3d');
    number('reverb_lag_mm','Maximo retardo espacial mm',0.6,[0.01 Inf]);
    number('min_coherence','Coherencia temporal minima',0.5,[0 1]);
    number('min_amplitude_fraction','Amplitud relativa minima',0.08,[0 1]);
    number('min_support_fraction','Soporte valido minimo',0.8,[0 1]);
    number('fit_error_max','Error maximo ajuste',0.3,[0.001 Inf]);
    number('speed_min','Velocidad minima m/s',0.2,[0.001 Inf]);
    number('speed_max','Velocidad maxima m/s',10,[0.002 Inf]);
    number('smoothing_mm','Suavizado visual mm',0,[0 Inf]);
    dropdown('young_model','Modelo Young',{'none','bulk_shear','rayleigh','lamb_a0_thin','lamb_a0_free'},'none');
    number('density_kg_m3','Densidad kg/m3',1000,[1 Inf]);
    number('poisson_ratio','Poisson',0.49,[-0.99 0.49999]);
    number('thickness_mm','Espesor placa mm',0.5,[0.001 Inf]);
    number('max_kh','Limite kh Lamb delgado',0.5,[0.01 2]);
    plots = uigridlayout(main,[2 2]); plots.Layout.Row = 1; plots.Layout.Column = 2;
    axSpeed = uiaxes(plots); axYoung = uiaxes(plots);
    axQuality = uiaxes(plots); axAmplitude = uiaxes(plots);
    footer = uigridlayout(main,[2 3]); footer.Layout.Row = 2; footer.Layout.Column = [1 2];
    footer.RowHeight = {31,'1x'}; footer.ColumnWidth = {180,180,'1x'};
    computeButton = uibutton(footer,'Text','Recalcular mapas','ButtonPushedFcn',@compute);
    exportButton = uibutton(footer,'Text','Exportar MAT + PNG','ButtonPushedFcn',@exportSession);
    uilabel(footer,'Text','Young depende del modelo. Las regiones sin soporte quedan vacias.');
    status = uitextarea(footer,'Editable','off','Value',{'Seleccione y cargue un plano.'});
    status.Layout.Row = 2; status.Layout.Column = [1 3];
    for initialName = string(fieldnames(initialOptions))'
        if isfield(fields,initialName), fields.(initialName).Value = initialOptions.(initialName); end
    end
    if isstruct(source)
        if isfield(source,'wrapped_phase')
            rawData=source; fields.phase_product.Value='raw_wrapped'; data=finalizeRaw();
        else
            data=source;
        end
        pathField.Value = '<plano en memoria>'; loadedSource=pathField.Value; prepareData();
    elseif ~isempty(source)
        pathField.Value = char(source);
    end
    acquisitionNames={'plane_type','phase_product','bmode_index','depth_offset_mm','depth_band_mm', ...
        'depth_start_index','depth_end_index','surface_search_start_index', ...
        'surface_search_end_index','surface_method','surface_index','surface_peak_threshold_db', ...
        'max_phase_step_rad','refractive_index', ...
        'line_rate_hz','intensity_floor_db','coherence_threshold','loupas_axial_window', ...
        'lateral_stride','raster_line_stride'};
    for controlIndex=1:numel(acquisitionNames)
        fields.(acquisitionNames{controlIndex}).ValueChangedFcn=@markReload;
    end
    pathField.ValueChangedFcn=@markReload;
    if isstruct(source)
        for controlIndex=1:numel(acquisitionNames)
            fields.(acquisitionNames{controlIndex}).Enable='off';
        end
        pathField.Editable='off'; choose.Enable='off'; loadButton.Enable='off';
    end
    window.UserData = struct('data',data,'speed_result',[],'young_result',[]);
    if isstruct(source), compute(); end

    function label(text)
        row = row + 1; h = uilabel(controls,'Text',text); h.Layout.Row=row; h.Layout.Column=[1 2];
    end
    function span(h)
        row=row+1; h.Layout.Row=row; h.Layout.Column=[1 2];
    end
    function number(name,text,value,limits)
        row=row+1; h=uilabel(controls,'Text',text); h.Layout.Row=row; h.Layout.Column=1;
        fields.(name)=uieditfield(controls,'numeric','Value',value,'Limits',limits);
        fields.(name).Layout.Row=row; fields.(name).Layout.Column=2;
    end
    function dropdown(name,text,items,value)
        row=row+1; h=uilabel(controls,'Text',text); h.Layout.Row=row; h.Layout.Column=1;
        fields.(name)=uidropdown(controls,'Items',items,'Value',value);
        fields.(name).Layout.Row=row; fields.(name).Layout.Column=2;
    end
    function checkbox(name,text,value)
        row=row+1; h=uilabel(controls,'Text',text); h.Layout.Row=row; h.Layout.Column=1;
        fields.(name)=uicheckbox(controls,'Text','','Value',value);
        fields.(name).Layout.Row=row; fields.(name).Layout.Column=2;
    end
    function plane=finalizeRaw()
        key={fields.unwrap_method.Value,fields.unwrap_iterations.Value,fields.raw_unwrap_domain.Value};
        if isequal(key,rawUnwrapKey) && ~isempty(data),plane=data;return;end
        dimensions=3;
        if string(fields.raw_unwrap_domain.Value)=="temporal_depth",dimensions=[3 1];end
        rawMask=repmat(rawData.valid_mask,1,1,size(rawData.wrapped_phase,3)) & ...
            isfinite(rawData.wrapped_phase);
        unwrapped=oce.motion.unwrapPhase(rawData.wrapped_phase, ...
            struct('method',string(fields.unwrap_method.Value), ...
            'iterations',fields.unwrap_iterations.Value,'dimensions',dimensions,'valid_mask',rawMask));
        plane=oce.acquisition.finalizeUnwrappedWavePlane(rawData,unwrapped);
        rawUnwrapKey=key;
    end
    function chooseFile(~,~)
        [file,folder]=uigetfile({'*.bin;*.mat','Adquisicion BIN / plano MAT'},'Plano OCE');
        if isequal(file,0), return; end
        pathField.Value=fullfile(folder,file); markReload();
    end
    function markReload(~,~)
        needsReload=true;
        status.Value={'Parametros de entrada modificados. Pulse Cargar / reconstruir antes de recalcular.'};
    end
    function values = getValues()
        values=struct();
        for fieldName=string(fieldnames(fields))', values.(fieldName)=fields.(fieldName).Value; end
    end
    function setBusy(value,text)
        busy=value; state='on'; if value, state='off'; end
        computeButton.Enable=state; loadButton.Enable=state; exportButton.Enable=state;
        if isstruct(source), loadButton.Enable='off'; end
        if nargin>1, status.Value={text}; end
        drawnow;
    end
    function loadSource(~,~)
        if busy, return; end
        setBusy(true,'Reconstruyendo por bloques; conserve esta ventana abierta...');
        cleanup=onCleanup(@()setBusy(false));
        try
            p=pathField.Value; [~,~,extension]=fileparts(p);
            if strcmpi(extension,'.mat')
                loaded=load(p,'data');
                if ~isfield(loaded,'data'), error('El MAT debe contener la variable data.'); end
                candidate=loaded.data;
            else
                values=getValues(); opts=struct();
                for acquisitionName=string(acquisitionNames)
                    opts.(acquisitionName)=values.(acquisitionName);
                end
                opts.line_rate_hz=fields.line_rate_hz.Value;
                if opts.line_rate_hz==0, opts.line_rate_hz=[]; end
                if isfield(initialOptions,'OCTSystemOptions'), opts.OCTSystemOptions=initialOptions.OCTSystemOptions; end
                candidate=oce.acquisition.loadWaveMotionPlane(p,opts);
            end
            if isfield(candidate,'wrapped_phase')
                rawData=candidate; rawUnwrapKey=[]; data=finalizeRaw();
            else
                rawData=[]; rawUnwrapKey=[]; data=candidate;
            end
            loadedSource=p; needsReload=false; speedResult=[]; youngResult=[]; prepareData();
            window.UserData=struct('data',data,'speed_result',[],'young_result',[]);
            cla(axSpeed); cla(axYoung); cla(axQuality);
            imageMap(axAmplitude,data.structural_db,'OCT / soporte del plano','dB');
            status.Value={sprintf('Cargado: %s | %d x %d x %d muestras', ...
                string(data.plane_type),size(data.motion,1),size(data.motion,2),size(data.motion,3)), ...
                'Ajuste la frecuencia mecanica y pulse Recalcular.', ...
                'Raster: las fases entre posiciones requieren excitacion y disparos repetibles.'};
            if isfield(data,'metadata') && isfield(data.metadata,'notes')
                status.Value=[status.Value; cellstr(string(data.metadata.notes(:)))];
            end
        catch exception
            status.Value={exception.message}; uialert(window,exception.message,'Carga fallida');
        end
    end
    function prepareData()
        if isstruct(source), fields.plane_type.Value=char(data.plane_type); end
        if ~isfield(data,'structural_db'), data.structural_db=zeros(size(data.valid_mask)); end
        if isfield(data,'metadata') && isfield(data.metadata,'frequency_hz') && ...
                isscalar(data.metadata.frequency_hz) && isfinite(data.metadata.frequency_hz)
            fields.frequency_hz.Value=data.metadata.frequency_hz;
        end
        firstMs=max(0,data.t_s(1)*1000); lastMs=data.t_s(end)*1000;
        if fields.time_start_ms.Value<firstMs || fields.time_start_ms.Value>=lastMs
            fields.time_start_ms.Value=firstMs;
        end
        if fields.time_end_ms.Value==0 || fields.time_end_ms.Value>lastMs || ...
                fields.time_end_ms.Value<=fields.time_start_ms.Value
            fields.time_end_ms.Value=lastMs;
        end
        if string(data.plane_type)=="bmode" && ~isfield(initialOptions,'window_row_mm') && ...
                fields.window_row_mm.Value==1.2
            fields.window_row_mm.Value=0.12;
        end
        if isfield(data,'depth_offset_mm'), fields.depth_offset_mm.Value=data.depth_offset_mm; end
    end
    function compute(~,~)
        if busy, return; end
        if isempty(data), uialert(window,'Primero cargue un plano.','Sin datos'); return; end
        if needsReload, uialert(window,'Los parametros de entrada cambiaron. Vuelva a cargar el plano.','Reconstruccion pendiente'); return; end
        setBusy(true,'Estimando numero de onda y verificando soporte...');
        cleanup=onCleanup(@()setBusy(false));
        try
            if ~isempty(rawData), data=finalizeRaw(); end
            opts=getValues(); opts.speed_range_m_s=[opts.speed_min opts.speed_max];
            opts.time_start_s=opts.time_start_ms/1000;
            opts.time_end_s=opts.time_end_ms/1000;
            if opts.time_end_s==0, opts.time_end_s=data.t_s(end); end
            candidate=oce.dispersion.estimateLocalSpeedMap(data,opts);
            modulusOptions=struct('model',string(opts.young_model), ...
                'density_kg_m3',opts.density_kg_m3,'poisson_ratio',opts.poisson_ratio, ...
                'thickness_m',opts.thickness_mm/1000,'frequency_hz',opts.frequency_hz,'max_kh',opts.max_kh);
            modulus=oce.elastography.invertYoungModulus(candidate.speed_m_s,modulusOptions);
            speedResult=candidate; youngResult=modulus;
            window.UserData=struct('data',data,'speed_result',speedResult, ...
                'young_result',youngResult,'controls',opts,'modulus_options',modulusOptions, ...
                'source',loadedSource,'created_utc',char(datetime('now','TimeZone','UTC')));
            if ~isempty(rawData), window.UserData.raw_data=rawData; end
            speedTitle='Velocidad de fase (visualizacion)';
            if string(data.plane_type)=="bmode"
                speedTitle='Velocidad de fase lateral en B-scan';
                if string(candidate.options.method)=="phase_derivative_2d" && ...
                        string(candidate.options.pd_geometry)=="in_plane"
                    speedTitle='Velocidad de fase en plano XZ (bulk)';
                end
            end
            imageMap(axSpeed,speedResult.display_speed_m_s,speedTitle,'m/s');
            imageMap(axYoung,youngResult.young_pa/1000,'Young segun modelo','kPa');
            imageMap(axQuality,speedResult.quality,'Calidad (no intervalo de confianza)','0-1'); clim(axQuality,[0 1]);
            imageMap(axAmplitude,speedResult.amplitude,'Amplitud armonica','unidades de entrada');
            good=speedResult.valid_mask; c=speedResult.speed_m_s(good);
            med=NaN; if ~isempty(c), med=median(c,'omitnan'); end
            lines={sprintf('%s | f = %.4g Hz | cobertura %.1f%% | mediana %.3g m/s', ...
                opts.method,opts.frequency_hz,100*nnz(good)/numel(good),med), ...
                sprintf('Plano %s | profundidad configurada %.3g mm | Young: %s', ...
                string(data.plane_type),opts.depth_offset_mm,opts.young_model), ...
                'NaN = soporte insuficiente. Suavizado visual no se usa para calcular Young.'};
            if isfield(speedResult.diagnostics,'qc_stage_counts')
                qc=speedResult.diagnostics.qc_stage_counts;
                lines{end+1}=sprintf('Soporte entrada %d | armonico %d | amplitud %d | ventanas con soporte %d | aceptados %d', ...
                    qc.input_valid,qc.temporal_valid,qc.amplitude_valid,qc.window_support_valid,qc.accepted);
            end
            if ~isempty(rawData) || string(opts.method)=="phase_derivative_2d"
                lines{end+1}=sprintf('Unwrap %s | TIE iteraciones fijas %d | derivada %s', ...
                    opts.unwrap_method,opts.unwrap_iterations,opts.pd_geometry);
                if ~isempty(rawData),lines{end+1}=['Dominio optico: ' opts.raw_unwrap_domain];end
            end
            if ~any(good,'all') && isfield(speedResult.diagnostics,'no_valid_reason')
                lines{end+1}=char(speedResult.diagnostics.no_valid_reason);
            end
            if isfield(modulus,'warning'), lines{end+1}=char(join(string(modulus.warning),' ')); end
            status.Value=lines;
        catch exception
            status.Value={exception.message}; uialert(window,exception.message,'Estimacion fallida');
        end
    end
    function imageMap(ax,values,text,units)
        cla(ax); im=imagesc(ax,data.x_m*1000,data.row_m*1000,values);
        im.AlphaData=isfinite(values); ax.Color=[.88 .88 .88];
        ax.YDir='normal';
        if string(data.plane_type)=="bmode",axis(ax,'normal');else,axis(ax,'image');end
        title(ax,text,'Interpreter','none');
        xlabel(ax,'X (mm)'); yname='Y (mm)';
        if string(data.plane_type)=="bmode", yname='Profundidad (mm)'; ax.YDir='reverse'; end
        ylabel(ax,yname);
        finiteValues=values(isfinite(values));
        limits=[0 1];
        if ~isempty(finiteValues)
            lo=min(finiteValues); hi=max(finiteValues); scale=max(abs([lo hi]));
            if scale==0, scale=1; end
            if hi-lo<1e-6*scale, limits=mean([lo hi])+[-1 1]*0.05*scale;
            else, limits=[lo hi]; end
        end
        if strcmp(units,'0-1'), limits=[0 1]; end
        clim(ax,limits);
        cb=colorbar(ax); cb.Label.String=units; cb.Ticks=linspace(limits(1),limits(2),5);
        cb.TickLabels=compose('%.3g',cb.Ticks);
    end
    function previewSurface(~,~)
        if isempty(data) || ~isfield(data,'preview')
            uialert(window,'Cargue un BIN para revisar la superficie.','Sin previsualizacion'); return;
        end
        preview=data.preview;
        fig=figure('Name','Revision de superficie OCT','Color','w');
        ax=axes(fig); imagesc(ax,preview.x_m*1000,preview.depth_m*1000,preview.intensity_db);
        hold(ax,'on'); plot(ax,preview.x_m*1000,preview.surface_m*1000,'r-','LineWidth',1.5);
        ax.YDir='reverse'; xlabel(ax,'X (mm)'); ylabel(ax,'Profundidad FFT (mm)');
        title(ax,'Revise el borde rojo; ajuste el rango o indice manual y vuelva a cargar.');
        colorbar(ax);
    end
    function previewSignal(~,~)
        if isempty(data), uialert(window,'Cargue un plano primero.','Sin datos'); return; end
        fig=figure('Name','Explorar senal temporal OCE','Color','w');
        layout=tiledlayout(fig,2,2); mapAx=nexttile(layout,[2 1]);
        if isempty(speedResult), mapValues=data.structural_db;
        else, mapValues=speedResult.amplitude; end
        mapImage=imagesc(mapAx,data.x_m*1000,data.row_m*1000,mapValues);
        mapAx.YDir='normal'; xlabel(mapAx,'X (mm)'); ylabel(mapAx,'Y / profundidad (mm)');
        title(mapAx,'Pulse un punto para revisar su traza'); colorbar(mapAx);
        traceAx=nexttile(layout); spectrumAx=nexttile(layout);
        mapImage.ButtonDownFcn=@selectSignalPoint;
        candidates=find(data.valid_mask);
        if isempty(candidates), signalRow=1; signalCol=1;
        else
            [~,strongest]=max(mapValues(candidates));
            [signalRow,signalCol]=ind2sub(size(data.valid_mask),candidates(strongest));
        end
        renderSignal(signalRow,signalCol);
        function selectSignalPoint(~,~)
            point=mapAx.CurrentPoint;
            [~,signalCol]=min(abs(data.x_m-point(1,1)/1000));
            [~,signalRow]=min(abs(data.row_m-point(1,2)/1000));
            renderSignal(signalRow,signalCol);
        end
        function renderSignal(signalRow,signalCol)
            trace=reshape(double(data.motion(signalRow,signalCol,:)),[],1);
            plot(traceAx,data.t_s*1000,trace); grid(traceAx,'on');
            title(traceAx,sprintf('Fila %d, columna %d',signalRow,signalCol));
            xlabel(traceAx,'Tiempo (ms)'); ylabel(traceAx,'Movimiento (unidades de entrada)');
            xline(traceAx,fields.time_start_ms.Value,'r--');
            if fields.time_end_ms.Value>0, xline(traceAx,fields.time_end_ms.Value,'r--'); end
            centered=trace-mean(trace,'omitnan'); centered(~isfinite(centered))=0;
            nfft=2^nextpow2(max(256,numel(trace)*4));
            taper=0.5-0.5*cos(2*pi*(0:numel(trace)-1)'/(numel(trace)-1));
            spectrum=abs(fft(centered.*taper,nfft)); bins=1:floor(nfft/2)+1;
            frequency=(bins-1)'/(nfft*mean(diff(data.t_s)));
            plot(spectrumAx,frequency,spectrum(bins)); grid(spectrumAx,'on');
            xline(spectrumAx,fields.frequency_hz.Value,'r--');
            xlim(spectrumAx,[0 min(max(frequency),max(4000,fields.frequency_hz.Value*3))]);
            xlabel(spectrumAx,'Frecuencia (Hz)'); ylabel(spectrumAx,'Magnitud FFT');
            title(spectrumAx,sprintf('Resolucion real aproximada %.0f Hz',1/(data.t_s(end)-data.t_s(1))));
        end
    end
    function exportSession(~,~)
        if busy || isempty(speedResult), uialert(window,'Calcule un mapa primero.','Sin resultado'); return; end
        [file,folder]=uiputfile('*.mat','Guardar mapas, mascaras y parametros','OCE_local_maps.mat');
        if isequal(file,0), return; end
        session=window.UserData; destination=fullfile(folder,file);
        save(destination,'session','-v7.3');
        [~,stem]=fileparts(file);
        exportgraphics(axSpeed,fullfile(folder,[stem '_speed.png']),'Resolution',180);
        exportgraphics(axYoung,fullfile(folder,[stem '_young.png']),'Resolution',180);
        exportgraphics(axQuality,fullfile(folder,[stem '_quality.png']),'Resolution',180);
        status.Value={['Exportado: ' destination], ...
            'El MAT incluye datos de entrada, mapa sin suavizar, mascara, calidad y supuestos.'};
    end
end
