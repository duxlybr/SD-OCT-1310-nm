function Alineacion_Espectrometro_Live(objetivo, opts)
%ALINEACION_ESPECTROMETRO_LIVE Monitor en vivo para alinear el espectrometro.
%
%   Alineacion_Espectrometro_Live()
%       Pide la carpeta donde LabVIEW guarda las adquisiciones y vigila el
%       TDMS mas reciente. Cada vez que cambia (archivo nuevo o sobrescrito)
%       lo procesa y compara su espectro con el de la referencia (por defecto
%       Penetration_3/15um.tdms, la mejor alineacion).
%
%   Alineacion_Espectrometro_Live(carpeta)
%   Alineacion_Espectrometro_Live(archivoTDMS)        % vigila un solo archivo
%   Alineacion_Espectrometro_Live(..., 'Referencia', archivo, ...
%       'Calibracion', mat, 'Periodo_s', 0.5, 'UnaVez', false, 'DuracionMax_s', inf)
%
% Indicadores (cuanto mas cerca de la referencia, mejor):
%   - Cociente px600/px1300 de la envolvente del espectro: mide si el lado
%     azul (px 300-1000) llega con la misma intensidad relativa que el rojo.
%   - Desviacion RMS entre las envolventes normalizadas (px 200-2000).
%   - Bordes al 50 % de la envolvente sobre la camara.
%   - FWHM limitado por el espectro: |FFT| de la envolvente linealizada en k.
%     No depende de la posicion del espejo ni de la dispersion; es lo que el
%     espectro permite como maximo.
%   - FWHM del espejo medido exactamente como Penetration_Analysis_TDMS.m
%     (OCT_Parametros.m + OCT_Comun.m). Depende de la profundidad.
%   - Cuentas maximas (el sensor satura en 4095).
%
% Cerrar la ventana termina el monitor. "Usar como referencia" fija la
% adquisicion actual como nueva referencia; "Reiniciar historial" borra la
% tendencia.

arguments
    objetivo = ''
    opts.Referencia = ['C:\Users\proyecto.pi1081\Desktop\1310 OCT\Data\' ...
        'Characterization\Penetration_3\15um.tdms']
    opts.Calibracion = ''      % '' = Penetration_resultados.mat junto a la referencia
    opts.Periodo_s = 0.5       % intervalo de sondeo de la carpeta
    opts.UnaVez = false        % true: procesa la adquisicion mas reciente y termina
    opts.DuracionMax_s = inf   % para pruebas
end

P = OCT_Parametros();
binsEnvolvente = 6;        % bins (FFT nativa) del filtro paso bajo de la envolvente
pxCociente = [600 1300];   % pixeles del cociente azul/rojo
rangoRMS = 200:2000;       % pixeles donde se compara la forma
saturacion = 4095;         % sensor de 12 bits
tolCociente = 0.03;        % +- tolerancia para considerar alcanzado el objetivo
tolRMS_pct = 3;
nHistorial = 200;

if isempty(objetivo)
    objetivo = uigetdir('C:\Users\proyecto.pi1081\Desktop\1310 OCT\Data', ...
        'Carpeta donde se guardan las adquisiciones TDMS');
    if isequal(objetivo, 0), error('No se selecciono ninguna carpeta.'); end
end
objetivo = char(objetivo);
if ~isfolder(objetivo) && ~isfile(objetivo)
    error('No existe: %s', objetivo);
end

%% Calibracion um/px y referencia
archivoCal = opts.Calibracion;
if isempty(archivoCal)
    archivoCal = fullfile(fileparts(opts.Referencia), 'Penetration_resultados.mat');
end
if ~isfile(archivoCal)
    error('No existe la calibracion %s (indique ''Calibracion'').', archivoCal);
end
C = load(archivoCal);
umPorPx = C.umPorPx;
if isfield(C, 'nFFT') && C.nFFT ~= P.nFFT, umPorPx = umPorPx*C.nFFT/P.nFFT; end

lam = linspace(P.lambdaIni_nm, P.lambdaFin_nm, P.nPix).';
kPix = flipud(2*pi ./ lam);
kU = linspace(kPix(1), kPix(end), P.nPix).';
nHalf = P.nFFT/2;
pxAxis = (0:nHalf-1).';
rangoPico = OCT_Comun.rangoBusqueda(P, nHalf);
procesar = @(archivo) analizar(archivo, P, binsEnvolvente, kPix, kU, umPorPx, ...
    pxAxis, rangoPico, pxCociente);

ref = procesar(opts.Referencia);
ref.nombre = string(opts.Referencia);

%% Figura
fig = figure('Color', 'w', 'Name', 'Alineacion del espectrometro (live)', ...
    'NumberTitle', 'off', 'Position', [40 40 1500 900]);
panel = uipanel(fig, 'Units', 'normalized', 'Position', [0 0.06 1 0.94], ...
    'BorderType', 'none', 'BackgroundColor', 'w');
uicontrol(fig, 'Style', 'pushbutton', 'String', 'Usar como referencia', ...
    'Units', 'normalized', 'Position', [0.01 0.01 0.14 0.04], 'FontSize', 11, ...
    'Callback', @(~,~) setappdata(fig, 'accion', "referencia"));
uicontrol(fig, 'Style', 'pushbutton', 'String', 'Reiniciar historial', ...
    'Units', 'normalized', 'Position', [0.16 0.01 0.12 0.04], 'FontSize', 11, ...
    'Callback', @(~,~) setappdata(fig, 'accion', "historial"));
lblEstado = uicontrol(fig, 'Style', 'text', 'String', 'Esperando adquisicion...', ...
    'Units', 'normalized', 'Position', [0.30 0.01 0.69 0.04], 'FontSize', 11, ...
    'HorizontalAlignment', 'left', 'BackgroundColor', 'w');
setappdata(fig, 'accion', "");

tl = tiledlayout(panel, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
axEnv = nexttile(tl, [1 2]);
axAbs = nexttile(tl);
axPSF = nexttile(tl);
axHist = nexttile(tl);
axTxt = nexttile(tl);
axis(axTxt, 'off');

H = struct('n', 0, 'cociente', [], 'rms', [], 'fwhmEsp', [], 'fwhmAj', []);
ultimaFirma = "";
firmaPendiente = "";
actual = [];
t0 = tic;

fprintf('Vigilando: %s\nReferencia: %s\n', objetivo, opts.Referencia);
fprintf('Cierre la ventana para terminar.\n');
while isvalid(fig) && toc(t0) < opts.DuracionMax_s
    accion = getappdata(fig, 'accion');
    if accion ~= ""
        setappdata(fig, 'accion', "");
        if accion == "referencia" && ~isempty(actual)
            ref = actual;
            H = struct('n', 0, 'cociente', [], 'rms', [], 'fwhmEsp', [], 'fwhmAj', []);
        elseif accion == "historial"
            H = struct('n', 0, 'cociente', [], 'rms', [], 'fwhmEsp', [], 'fwhmAj', []);
        end
        if ~isempty(actual), dibujar(); end
    end

    [archivo, firma] = archivoMasReciente(objetivo);
    % Se procesa solo cuando el archivo dejo de cambiar entre dos sondeos
    % consecutivos, para no leer un TDMS que LabVIEW aun esta escribiendo.
    if firma ~= "" && firma ~= ultimaFirma
        if firma == firmaPendiente
            try
                actual = procesar(archivo);
                actual.nombre = string(archivo);
                ultimaFirma = firma;
                H.n = H.n + 1;
                H.cociente(end+1) = actual.cociente;
                H.rms(end+1) = rmsDiferencia(actual, ref, rangoRMS);
                H.fwhmEsp(end+1) = actual.fwhmEspectro_um;
                H.fwhmAj(end+1) = actual.fwhmAjuste_um;
                if numel(H.cociente) > nHistorial
                    H.cociente(1) = []; H.rms(1) = []; H.fwhmEsp(1) = []; H.fwhmAj(1) = [];
                end
                dibujar();
                fprintf('[%s] %s | cociente %.3f (obj %.3f) | RMS %.1f %% | FWHM esp %.2f um | FWHM %.2f um\n', ...
                    char(datetime('now', 'Format', 'HH:mm:ss')), archivo, actual.cociente, ...
                    ref.cociente, H.rms(end), actual.fwhmEspectro_um, actual.fwhmAjuste_um);
                if opts.UnaVez, break; end
            catch err
                % Archivo incompleto o bloqueado: se reintenta en el siguiente sondeo.
                if isvalid(fig)
                    lblEstado.String = sprintf('No se pudo leer %s (%s). Reintentando...', ...
                        archivo, err.message);
                end
            end
        end
        firmaPendiente = firma;
    end
    pause(opts.Periodo_s);
end

    function dibujar()
        if ~isvalid(fig), return; end
        px = (0:P.nPix-1).';
        rmsActual = rmsDiferencia(actual, ref, rangoRMS);

        % Envolvente normalizada: actual vs referencia
        cla(axEnv);
        area(axEnv, px, ref.envN, 'FaceColor', [0.75 0.85 1.0], 'EdgeColor', 'none');
        hold(axEnv, 'on');
        hRef = plot(axEnv, px, ref.envN, 'Color', [0 0.45 0.74], 'LineWidth', 2);
        hAct = plot(axEnv, px, actual.envN, 'Color', [0.85 0.33 0.10], 'LineWidth', 2);
        for q = pxCociente
            xline(axEnv, q, ':', sprintf('px %d', q), 'Color', [0.3 0.3 0.3]);
        end
        plot(axEnv, pxCociente, actual.envN(pxCociente+1), 'o', 'MarkerSize', 9, ...
            'MarkerFaceColor', [0.85 0.33 0.10], 'MarkerEdgeColor', 'k');
        plot(axEnv, pxCociente, ref.envN(pxCociente+1), 's', 'MarkerSize', 9, ...
            'MarkerFaceColor', [0 0.45 0.74], 'MarkerEdgeColor', 'k');
        yline(axEnv, 0.5, 'k:');
        hold(axEnv, 'off');
        xlim(axEnv, [0 P.nPix-1]); ylim(axEnv, [0 1.1]); grid(axEnv, 'on');
        xlabel(axEnv, 'Camera pixel'); ylabel(axEnv, 'Normalized envelope');
        legend(axEnv, [hRef hAct], {sprintf('Reference: %s', nombreCorto(ref.nombre)), ...
            sprintf('Current: %s', nombreCorto(actual.nombre))}, ...
            'Location', 'northeast', 'Interpreter', 'none');
        title(axEnv, sprintf(['Spectrum shape on the camera  |  px%d/px%d = %.3f ' ...
            '(target %.3f)  |  RMS difference = %.1f %%'], pxCociente, ...
            actual.cociente, ref.cociente, rmsActual));

        % Cuentas absolutas y saturacion
        cla(axAbs);
        plot(axAbs, px, ref.espectro, 'Color', [0 0.45 0.74 0.35]);
        hold(axAbs, 'on');
        plot(axAbs, px, actual.espectro, 'Color', [0.85 0.33 0.10 0.6]);
        plot(axAbs, px, actual.env, 'Color', [0.85 0.33 0.10], 'LineWidth', 2);
        plot(axAbs, px, ref.env, 'Color', [0 0.45 0.74], 'LineWidth', 2);
        yline(axAbs, saturacion, 'r--', 'Saturation', 'LabelHorizontalAlignment', 'left');
        hold(axAbs, 'off');
        xlim(axAbs, [0 P.nPix-1]); ylim(axAbs, [0 1.05*saturacion]); grid(axAbs, 'on');
        xlabel(axAbs, 'Camera pixel'); ylabel(axAbs, 'Counts');
        title(axAbs, sprintf('Mean spectrum (max %d counts)', round(actual.maxCuentas)));

        % PSF como Penetration
        cla(axPSF);
        s = actual.ajuste;
        xf = linspace(s.xw(1), s.xw(end), 600).';
        plot(axPSF, s.xw*umPorPx, s.yw, 'k.', 'MarkerSize', 8);
        hold(axPSF, 'on');
        plot(axPSF, xf*umPorPx, OCT_Comun.modeloPico(s.p, xf, s.modelo), 'r-', 'LineWidth', 1.5);
        hm = s.p(1)/2 + s.p(4);
        plot(axPSF, (s.p(2) + [-1 1]*s.p(3)/2)*umPorPx, [hm hm], 'g-', 'LineWidth', 2);
        hold(axPSF, 'off');
        xlim(axPSF, [s.xw(1) s.xw(end)]*umPorPx); grid(axPSF, 'on');
        xlabel(axPSF, 'Depth [\mum]'); ylabel(axPSF, '|FFT| [a.u.]');
        title(axPSF, sprintf('Mirror at %.0f \\mum: %s FWHM = %.2f \\mum (direct %.2f)', ...
            actual.profundidad_um, s.modelo, actual.fwhmAjuste_um, actual.fwhmDatos_um));

        % Tendencia
        cla(axHist);
        yyaxis(axHist, 'left');
        cla(axHist);
        plot(axHist, 1:numel(H.cociente), H.cociente, 'o-', 'LineWidth', 1.5, ...
            'MarkerFaceColor', 'auto');
        yline(axHist, ref.cociente, '--', 'Target', 'LabelHorizontalAlignment', 'left');
        ylabel(axHist, sprintf('px%d/px%d', pxCociente));
        yyaxis(axHist, 'right');
        cla(axHist);
        plot(axHist, 1:numel(H.fwhmEsp), H.fwhmEsp, 's-', 'LineWidth', 1.5);
        yline(axHist, ref.fwhmEspectro_um, ':', 'Target', 'LabelHorizontalAlignment', 'right');
        ylabel(axHist, 'Spectrum-limited FWHM [\mum]');
        xlabel(axHist, 'Acquisition'); grid(axHist, 'on');
        title(axHist, 'Trend (latest on the right)');

        % Panel de indicadores
        cla(axTxt); axis(axTxt, 'off');
        filas = {
            'Blue/red ratio',      sprintf('%.3f', actual.cociente),  sprintf('%.3f', ref.cociente), ...
                abs(actual.cociente-ref.cociente) <= tolCociente;
            'Shape RMS diff.',     sprintf('%.1f %%', rmsActual),     sprintf('< %.0f %%', tolRMS_pct), ...
                rmsActual <= tolRMS_pct;
            '50 % edges [px]',     sprintf('%d - %d', actual.borde50), sprintf('%d - %d', ref.borde50), ...
                all(abs(actual.borde50-ref.borde50) <= 30);
            'Spectrum-lim. FWHM',  sprintf('%.2f um', actual.fwhmEspectro_um), ...
                sprintf('%.2f um', ref.fwhmEspectro_um), ...
                actual.fwhmEspectro_um <= ref.fwhmEspectro_um*1.02;
            'Max counts',          sprintf('%d', round(actual.maxCuentas)), sprintf('< %d', saturacion), ...
                actual.maxCuentas < 0.97*saturacion;
            };
        text(axTxt, 0.00, 0.97, 'Indicator', 'FontWeight', 'bold', 'FontSize', 13);
        text(axTxt, 0.45, 0.97, 'Current', 'FontWeight', 'bold', 'FontSize', 13);
        text(axTxt, 0.72, 0.97, 'Target', 'FontWeight', 'bold', 'FontSize', 13);
        for r = 1:size(filas, 1)
            y = 0.97 - 0.15*r;
            if filas{r,4}, c = [0.10 0.55 0.10]; else, c = [0.80 0.15 0.10]; end
            text(axTxt, 0.00, y, filas{r,1}, 'FontSize', 13);
            text(axTxt, 0.45, y, filas{r,2}, 'FontSize', 15, 'FontWeight', 'bold', 'Color', c);
            text(axTxt, 0.72, y, filas{r,3}, 'FontSize', 13, 'Color', [0.3 0.3 0.3]);
        end
        if ~isempty(actual.aviso)
            text(axTxt, 0.00, 0.03, actual.aviso, 'FontSize', 11, 'Color', [0.80 0.15 0.10]);
        end

        lblEstado.String = sprintf('%s  |  %s  |  updates: %d', ...
            char(datetime('now', 'Format', 'HH:mm:ss')), actual.nombre, H.n);
        drawnow limitrate;
    end
end

function R = analizar(archivo, P, binsEnvolvente, kPix, kU, umPorPx, pxAxis, ...
        rangoPico, pxCociente)
% Envolvente del espectro, FWHM limitado por el espectro y PSF como Penetration.
    M = OCT_Comun.leerTDMS(archivo, P.nPix);
    R.espectro = mean(M, 2);
    R.maxCuentas = max(M(:));

    % Envolvente: paso bajo del espectro medio (elimina las franjas del espejo)
    X = fft(R.espectro);
    mascara = zeros(size(X));
    mascara([1:binsEnvolvente+1, end-binsEnvolvente+1:end]) = 1;
    R.env = real(ifft(X.*mascara));
    R.envN = R.env/max(R.env);
    R.cociente = R.env(pxCociente(1)+1)/R.env(pxCociente(2)+1);
    R.borde50 = [find(R.envN >= 0.5, 1), find(R.envN >= 0.5, 1, 'last')] - 1;

    % FWHM limitado por el espectro: |FFT| de la envolvente linealizada en k
    e = max(R.env - min(R.env), 0);
    ek = interp1(kPix, flipud(e), kU, 'spline');
    E = fftshift(abs(fft(ek, P.nFFT)));
    x = (-P.nFFT/2:P.nFFT/2-1).';
    R.fwhmEspectro_um = OCT_Comun.fwhmDirecto(x, E, P.nFFT/2+1)*umPorPx;

    % PSF del espejo, igual que Penetration_Analysis_TDMS.m
    [Aabs, Arect] = OCT_Comun.ascan(M, P);
    [pkPx, pkIdx] = OCT_Comun.buscarPico(pxAxis, Aabs, rangoPico);
    m = OCT_Comun.medirPico(pxAxis, Arect, pkIdx, P);
    R.profundidad_um = pkPx*umPorPx;
    R.fwhmAjuste_um = m.fwhmPx*umPorPx;
    R.fwhmDatos_um = m.fwhmDatosPx*umPorPx;
    R.ajuste = m.ajuste;

    % Las franjas deben estar por encima del filtro de la envolvente
    R.aviso = '';
    binNativo = pkPx*P.nPix/P.nFFT;
    if binNativo < 1.7*binsEnvolvente
        R.aviso = sprintf(['Mirror too close to zero delay (%.0f um): fringes leak ' ...
            'into the envelope. Move it to >= %.0f um.'], R.profundidad_um, ...
            1.7*binsEnvolvente*P.nFFT/P.nPix*umPorPx);
    end
    if R.maxCuentas >= 0.97*4095
        R.aviso = strtrim([R.aviso ' Saturated: reduce power.']);
    end
end

function d = rmsDiferencia(A, B, rango)
    d = 100*sqrt(mean((A.envN(rango+1) - B.envN(rango+1)).^2));
end

function [archivo, firma] = archivoMasReciente(objetivo)
% TDMS mas reciente (o el archivo indicado) y su firma (nombre, fecha, tamano).
    archivo = ''; firma = "";
    if isfile(objetivo)
        d = dir(objetivo);
    else
        d = dir(fullfile(objetivo, '*.tdms'));
    end
    if isempty(d), return; end
    [~, i] = max([d.datenum]);
    archivo = fullfile(d(i).folder, d(i).name);
    firma = string(sprintf('%s|%.10f|%d', archivo, d(i).datenum, d(i).bytes));
end

function s = nombreCorto(ruta)
    [carpeta, nombre, ext] = fileparts(char(ruta));
    [~, sub] = fileparts(carpeta);
    s = [sub '/' nombre ext];
end
