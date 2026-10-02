%% Penetration_Analysis.m
% Calibración de profundidad (pixel/um), caída de 10 dB y FWHM por medición
% para el OCT de 1310 nm. Procesa todos los archivos TDMS sin exigir un
% formato de nombre. Para calibrar, obtiene la posición del primer/ultimo
% número del nombre o de un CSV explícito (véase PARAMETROS DE ARCHIVOS).
%
% Estructura TDMS: grupo "Acquisition", canal "Raw_B_scans" (int16),
% nPix x nLines muestras concatenadas (2048 px por A-line).

clear; close all; clc;

%% ================= PROCESAMIENTO COMPARTIDO (OCT_Parametros.m) =========
% La linealización en k (lambdaIni_nm / lambdaFin_nm), la FFT, el promedio de
% A-lines, la búsqueda del pico y el ajuste del FWHM se configuran en
% OCT_Parametros.m, el mismo archivo que usa FWHM_80_ALines_TDMS.m. Así ambos
% scripts dan el mismo FWHM para un mismo TDMS.
cfg = OCT_Parametros();
usarLinealK      = cfg.usarLinealK;
lambdaIni_nm     = cfg.lambdaIni_nm;
lambdaFin_nm     = cfg.lambdaFin_nm;
metodoInterpK    = cfg.metodoInterpK;
nPix             = cfg.nPix;
nFFT             = cfg.nFFT;
usarHanning      = cfg.usarHanning;
promediarALines  = cfg.promediarALines;
indiceALine      = cfg.indiceALine;
promedioAntesFFT = cfg.promedioAntesFFT;
pxMinBusqueda    = cfg.pxMinBusqueda;
pxMaxBusqueda    = cfg.pxMaxBusqueda;
modeloAjuste     = cfg.modeloAjuste;
anchoVentana     = cfg.anchoVentana;
ventanaAutoAdapt = cfg.ventanaAutoAdapt;

%% ======================= PARÁMETROS DE USUARIO ==========================
carpeta          = '';       % carpeta con los .tdms ('' = elegirla con un diálogo)
dMicrometroRef   = 0;       % lectura del micrómetro de la primera medición [um]
pxRef            = 72;       % posición real (px, FFT de nFFT) de esa medición
anclarReferencia = false;     % true: recta forzada a pasar por (28 um, 50 px)
                             % false: ajuste lineal libre
ajusteManual     = false;    % false (default): ajuste automático
                             % true : abre GUI para ajustar a mano los parámetros
caidaObjetivo_dB = -10;      % nivel de caída a marcar

%% ======================= PARAMETROS DE ARCHIVOS =========================
patronArchivos          = '*.tdms'; % se procesan todos los TDMS encontrados
archivoPosiciones       = '';       % CSV opcional: columnas Archivo, Micrometro_um
extraerPosicionNombre   = true;     % acepta números en cualquier parte del nombre
usarUltimoNumeroNombre  = true;     % true: usa el último número; false: el primero
procesarSinPosicion     = true;     % se analizan, pero no se usan para calibrar

%% ============================ LECTURA ===================================
if isempty(carpeta)
    carpeta = uigetdir(fullfile(fileparts(mfilename('fullpath')), '..'), ...
        'Selecciona la carpeta con las mediciones de Penetration (*.tdms)');
    if isequal(carpeta, 0), error('No se seleccionó ninguna carpeta.'); end
end
fprintf('Carpeta de mediciones: %s\n', carpeta);
archivos = dir(fullfile(carpeta, patronArchivos));
if isempty(archivos), error('No se encontraron archivos %s en %s', patronArchivos, carpeta); end

% Orden alfabético estable antes de resolver las posiciones.
[~, ordenNombre] = sort(lower(string({archivos.name})));
archivos = archivos(ordenNombre);
[dMic, fuentePosicion] = resolverPosiciones(archivos, carpeta, archivoPosiciones, ...
    extraerPosicionNombre, usarUltimoNumeroNombre);
esCalibracion = isfinite(dMic);
if ~procesarSinPosicion
    archivos = archivos(esCalibracion);
    dMic = dMic(esCalibracion);
    fuentePosicion = fuentePosicion(esCalibracion);
    esCalibracion = true(size(dMic));
end

% Primero las mediciones con posición, ordenadas por micrómetro; después el resto.
clavePos = dMic;
clavePos(~esCalibracion) = inf;
[~, orden] = sortrows([~esCalibracion, clavePos], [1 2]);
archivos = archivos(orden);
dMic = dMic(orden);
fuentePosicion = fuentePosicion(orden);
esCalibracion = esCalibracion(orden);
nMed = numel(archivos);
nCal = nnz(esCalibracion);
if numel(unique(dMic(esCalibracion))) < 2
    error(['Se necesitan al menos dos posiciones de micrometro distintas. ' ...
        'Incluya un numero en los nombres o use archivoPosiciones.']);
end
if any(~esCalibracion)
    fprintf(['Aviso: %d archivo(s) sin posición se procesarán y aparecerán en la tabla, ' ...
        'pero no se usarán para la calibración.\n'], nnz(~esCalibracion));
end
fprintf('%d archivos encontrados; %d se usarán para calibración.\n', nMed, nCal);

nHalf  = nFFT/2;
pxAxis = (0:nHalf-1).';                 % bin 0 = DC
Aabs   = zeros(nHalf, nMed);            % |FFT| (lineal) de cada medición, con ventana
Arect  = zeros(nHalf, nMed);            % |FFT| sin ventana: sólo para el FWHM
nLines = zeros(nMed,1);

% Malla uniforme en k (solo para la resolución teórica; el remuestreo lo hace
% OCT_Comun.ascan con lambda lineal en píxel -> k = 2*pi/lambda)
lam  = linspace(lambdaIni_nm, lambdaFin_nm, nPix).';
kPix = flipud(2*pi ./ lam);                          % ascendente
kU   = linspace(kPix(1), kPix(end), nPix).';         % malla uniforme en k

fprintf('Leyendo %d mediciones...\n', nMed);
for k = 1:nMed
    M = OCT_Comun.leerTDMS(fullfile(carpeta, archivos(k).name), nPix);
    nLines(k) = size(M, 2);
    if ~promediarALines && indiceALine > nLines(k)
        error('%s tiene %d A-lines; indiceALine = %d no existe.', ...
            archivos(k).name, nLines(k), indiceALine);
    end
    [Aabs(:,k), Arect(:,k)] = OCT_Comun.ascan(M, cfg);
end
fprintf('A-lines por medición: %s\n', mat2str(unique(nLines).'));
if ~promediarALines
    fprintf('Modo: solo A-line %d', indiceALine);
elseif promedioAntesFFT
    fprintf('Modo: promedio de A-lines antes de la FFT');
else
    fprintf('Modo: promedio de |FFT| (después de la FFT)');
end
fprintf(' | Hanning: %s (FWHM siempre sin ventana)\n', string(usarHanning));

%% ======================= DETECCIÓN DE PICOS =============================
pkPx  = zeros(nMed,1);   % posición del pico (sub-píxel, parabólica en dB)
pkIdx = zeros(nMed,1);   % índice MATLAB del bin máximo
pkAmp = zeros(nMed,1);
pxMinBusqueda = max(1, pxMinBusqueda);
pxMaxBusqueda = min(nHalf-2, pxMaxBusqueda);
if pxMinBusqueda >= pxMaxBusqueda
    error('El intervalo de búsqueda del pico no es válido.');
end
rango = (pxMinBusqueda:pxMaxBusqueda) + 1;
for k = 1:nMed
    % Reflector, no la cola del DC (que puede ser mas alta que un espejo profundo)
    [pkPx(k), pkIdx(k), pkAmp(k)] = OCT_Comun.buscarPicoReflector(pxAxis, Aabs(:,k), rango);
end
% Validación: sólo las mediciones con posición conocida deben seguir una
% recta vs el micrómetro. Los archivos auxiliares permanecen en el análisis.
tolPx = 20;  semiBusq = 50;
idxCal = find(esCalibracion);
dCal = dMic(idxCal);
pCal = pkPx(idxCal);
[I, J] = find(triu(true(nCal), 1));
den = dCal(J) - dCal(I);
pendientes = (pCal(J) - pCal(I)) ./ den;
pendientes = pendientes(isfinite(pendientes));
if isempty(pendientes)
    pr = polyfit(dCal, pCal, 1);
else
    m0 = median(pendientes);
    pr = [m0, median(pCal - m0*dCal)];
end
okCal = abs(pCal - polyval(pr, dCal)) < tolPx;
for it = 1:5
    if nnz(okCal) < 2, break; end
    pr = polyfit(dCal(okCal), pCal(okCal), 1);
    okNuevo = abs(pCal - polyval(pr, dCal)) < tolPx;
    if isequal(okNuevo, okCal), break; end
    okCal = okNuevo;
end
for q = find(~okCal).'
    k = idxCal(q);
    c = round(polyval(pr, dMic(k))) + 1;
    r = max(rango(1), c-semiBusq) : min(rango(end), c+semiBusq);
    [pkPx(k), pkIdx(k), pkAmp(k)] = OCT_Comun.buscarPico(pxAxis, Aabs(:,k), r);
    fprintf('Aviso: pico de %s re-buscado cerca de px %d (máximo global no era el espejo)\n', ...
        archivos(k).name, c-1);
end

%% ===================== CALIBRACIÓN PIXEL / um ===========================
% Recta: px = a*d + b  (d = lectura del micrómetro)
pLibre = polyfit(dMic(esCalibracion), pkPx(esCalibracion), 1);
if anclarReferencia
    a = (dMic(esCalibracion) - dMicrometroRef) \ ...
        (pkPx(esCalibracion) - pxRef);
    b = pxRef - a*dMicrometroRef;
else
    a = pLibre(1); b = pLibre(2);
end
if ~isfinite(a) || a <= 0
    error('La calibración produjo una relación px/um no válida: %.6g.', a);
end
pxPorUm = a;  umPorPx = 1/a;
zReal   = pkPx / pxPorUm;                 % profundidad real desde el DC [um]
res     = nan(nMed,1);
res(esCalibracion) = pkPx(esCalibracion) - (a*dMic(esCalibracion) + b);

fprintf('\n=== Calibración (FFT de %d puntos) ===\n', nFFT);
fprintf('  pixel/um = %.5f px/um   ->   %.4f um/px\n', pxPorUm, umPorPx);
fprintf('  Equivalente en %d px nativos: %.4f um/px\n', nPix, umPorPx*nFFT/nPix);
fprintf('  Ajuste libre: px = %.5f*d %+.2f  -> px(%g um) = %.1f (esperado %d)\n', ...
    pLibre(1), pLibre(2), dMicrometroRef, polyval(pLibre, dMicrometroRef), pxRef);
fprintf('  Residuo RMS del ajuste usado: %.2f px\n', rms(res(esCalibracion)));
fprintf('  Rango de imagen (0..%d px): %.1f um\n', nHalf-1, (nHalf-1)*umPorPx);
dzTeo = pi/(kU(end) - kU(1)) * 1e-3 * nPix/nFFT;   % um por bin (espejo, sin índice)
fprintf('  Teórico por rango espectral (%.2f-%.2f nm): %.4f um/px  (medido/teórico = %.3f)\n', ...
    lambdaIni_nm, lambdaFin_nm, dzTeo, umPorPx/dzTeo);

%% ========================== CAÍDA DE 10 dB ==============================
pk_dB  = 10*log10(pkAmp);
idxCal = find(esCalibracion);              % ya está ordenado por posición
iRef = idxCal(1);                          % menor lectura de micrómetro = 0 dB
pkN_dB = pk_dB - pk_dB(iRef);
[~, iCaidaLocal] = min(abs(pkN_dB(idxCal) - caidaObjetivo_dB));
iCaida = idxCal(iCaidaLocal);
zCruce = NaN;                             % cruce interpolado
j = find(pkN_dB(idxCal) <= caidaObjetivo_dB, 1);
if ~isempty(j) && j > 1
    par = idxCal(j-1:j);
    zCruce = interp1(pkN_dB(par), zReal(par), caidaObjetivo_dB);
end
fprintf('\n=== Caída de %g dB ===\n', caidaObjetivo_dB);
fprintf('  Medición más cercana: %s  (%.1f dB, z real = %.1f um)\n', ...
    archivos(iCaida).name, pkN_dB(iCaida), zReal(iCaida));
if ~isnan(zCruce), fprintf('  Cruce interpolado a %g dB: z = %.1f um\n', caidaObjetivo_dB, zCruce); end

%% ============================== AJUSTE ==================================
% El FWHM se mide sobre las A-scans SIN ventana (Arect) con OCT_Comun.medirPico
% (el mismo que usa FWHM_80_ALines_TDMS.m): re-localiza el pico en +-5 bins del
% encontrado arriba, mide el FWHM directo y ajusta modeloAjuste.
iMin = pxMinBusqueda + 1;                 % la ventana nunca incluye el DC
pkIdxR = zeros(nMed,1);
fwhmDatosPx = zeros(nMed,1);
ajustes = struct('modelo', [], 'p', [], 'xw', [], 'yw', [], 'R2', []);
ajustes = repmat(ajustes, nMed, 1);
for k = 1:nMed
    medicion = OCT_Comun.medirPico(pxAxis, Arect(:,k), pkIdx(k), cfg);
    pkIdxR(k) = medicion.pkIdx;
    fwhmDatosPx(k) = medicion.fwhmDatosPx;
    ajustes(k) = medicion.ajuste;
end
fwhmDatosUm = fwhmDatosPx * umPorPx;
if ajusteManual
    % Ventana fija de anchoVentana puntos, semilla = ajuste automático
    for k = 1:nMed
        [ajustes(k).xw, ajustes(k).yw] = OCT_Comun.ventanaPico(pxAxis, Arect(:,k), ...
            pkIdxR(k), anchoVentana, iMin);
    end
    ajustes = guiAjusteManual(ajustes, archivos, umPorPx);
end

fwhmPx      = arrayfun(@(s) s.p(3), ajustes);
fwhmUm      = fwhmPx * umPorPx;
R2          = [ajustes.R2].';
modelos     = string({ajustes.modelo}).';

T = table(string({archivos.name}).', dMic, fuentePosicion, esCalibracion, ...
          zReal, pkPx, pkN_dB, modelos, fwhmUm, fwhmDatosUm, R2, ...
    'VariableNames', {'Archivo','Micrometro_um','FuentePosicion','UsadoCalibracion', ...
                      'Profundidad_um','Pico_px','Intensidad_dB','Modelo', ...
                      'FWHM_ajuste_um','FWHM_datos_um','R2'});
fprintf('\n=== Resultados por medición ===\n');
disp(T);

%% ============================== GRÁFICAS ================================
cmap = turbo(max(nCal, 2));
zAxis = pxAxis * umPorPx;

% 1) Todas las A-scans normalizadas (0 dB = pico de la primera medición)
figure('Name','Normalized A-scans','Color','w');
hold on;
ref_dB = 10*log10(pkAmp(iRef));
for k = 1:nMed
    if esCalibracion(k)
        iColor = find(idxCal == k, 1);
        colorLinea = [cmap(iColor,:) 0.6];
    else
        colorLinea = [0.45 0.45 0.45 0.5];
    end
    plot(zAxis, 10*log10(max(Aabs(:,k), eps)) - ref_dB, 'Color', colorLinea);
end
plot(zReal(esCalibracion), pkN_dB(esCalibracion), 'k.', 'MarkerSize', 12);
plot(zReal(~esCalibracion), pkN_dB(~esCalibracion), 'x', 'Color', [0.3 0.3 0.3]);
plot(zReal(iCaida), pkN_dB(iCaida), 'ro', 'MarkerSize', 12, 'LineWidth', 2);
yline(caidaObjetivo_dB, 'r--', sprintf('%g dB', caidaObjetivo_dB), 'LineWidth', 1.5);
xlabel('Depth [\mum]'); ylabel('Normalized intensity [dB]');
title(sprintf('Normalized A-scans - closest to %g dB: %s (z = %.0f \\mum)', ...
    caidaObjetivo_dB, erase(archivos(iCaida).name,'.tdms'), zReal(iCaida)));
xlim([0 min(4200, zAxis(end))]);
ylim([-20 1]); grid on; box on;
colormap(cmap); cb = colorbar; cb.Label.String = 'Micrometer position [\mum]';
clim([min(dMic(esCalibracion)) max(dMic(esCalibracion))]);

% 2) Caída de intensidad del pico vs profundidad
figure('Name','Intensity roll-off','Color','w');
plot(zReal(esCalibracion), pkN_dB(esCalibracion), 'o-', 'LineWidth', 1.5); hold on;
plot(zReal(~esCalibracion), pkN_dB(~esCalibracion), 'x', 'Color', [0.3 0.3 0.3]);
plot(zReal(iCaida), pkN_dB(iCaida), 'ro', 'MarkerSize', 12, 'LineWidth', 2);
yline(caidaObjetivo_dB, 'r--', sprintf('%g dB', caidaObjetivo_dB), 'LineWidth', 1.5);
if ~isnan(zCruce), xline(zCruce, 'k:', sprintf('%.0f \\mum', zCruce)); end
xlabel('Depth [\mum]'); ylabel('Peak intensity [dB]');
title('Peak intensity roll-off with depth'); grid on;

% 3) Calibración pixel/um
figure('Name','Calibration','Color','w');
tiledlayout(2,1);
nexttile;
plot(dMic(esCalibracion), pkPx(esCalibracion), 'o', 'MarkerFaceColor', 'b'); hold on;
dd = linspace(min(dMic(esCalibracion)), max(dMic(esCalibracion)), 2);
plot(dd, a*dd + b, 'r-', 'LineWidth', 1.5);
plot(dMicrometroRef, pxRef, 'ks', 'MarkerSize', 10, 'LineWidth', 1.5);
xlabel('Micrometer position [\mum]'); ylabel(sprintf('Peak [px, FFT %d]', nFFT));
title(sprintf('%.5f px/\\mum  (%.4f \\mum/px)', pxPorUm, umPorPx));
legend('Peaks', 'Linear fit', sprintf('Reference (%g \\mum, %g px)', ...
    dMicrometroRef, pxRef), 'Location', 'northwest'); grid on;
nexttile;
stem(dMic(esCalibracion), res(esCalibracion), 'filled');
xlabel('Micrometer position [\mum]'); ylabel('Residual [px]'); grid on;

% 4) FWHM vs profundidad
figure('Name','FWHM','Color','w');
plot(zReal(esCalibracion), fwhmUm(esCalibracion), 'o-', 'LineWidth', 1.5); hold on;
plot(zReal(esCalibracion), fwhmDatosUm(esCalibracion), 's--');
plot(zReal(~esCalibracion), fwhmUm(~esCalibracion), 'x', 'Color', [0.3 0.3 0.3]);
xlabel('Depth [\mum]'); ylabel('FWHM [\mum]');
legend('Fit', 'Direct half-maximum', 'Files without position', 'Location', 'northwest');
title('Axial resolution (unwindowed FWHM) vs depth'); grid on;

% 5) Ajustes individuales
figure('Name','Fits by measurement','Color','w');
tl = tiledlayout('flow', 'TileSpacing', 'compact', 'Padding', 'compact');
title(tl, 'Peak fits by measurement (unwindowed FWHM)');
for k = 1:nMed
    nexttile;
    s = ajustes(k);
    xf = linspace(s.xw(1), s.xw(end), 400);
    plot(s.xw*umPorPx, s.yw, '.', 'Color', [0.4 0.4 0.4]); hold on;
    plot(xf*umPorPx, OCT_Comun.modeloPico(s.p, xf, s.modelo), 'r-', 'LineWidth', 1.2);
    title(sprintf('%s | %.1f \\mum', erase(archivos(k).name,'.tdms'), fwhmUm(k)), ...
        'FontSize', 7, 'FontWeight', 'normal');
    set(gca, 'FontSize', 6, 'YTick', []); axis tight;
end

%% ============================== GUARDAR =================================
writetable(T, fullfile(carpeta, 'Penetration_resultados.csv'));
save(fullfile(carpeta, 'Penetration_resultados.mat'), 'T', 'pxPorUm', 'umPorPx', ...
    'a', 'b', 'zCruce', 'iCaida', 'ajustes', 'nFFT', 'nPix', 'promedioAntesFFT', ...
    'promediarALines', 'indiceALine', 'usarHanning', 'usarLinealK', ...
    'lambdaIni_nm', 'lambdaFin_nm', 'patronArchivos', 'archivoPosiciones', ...
    'extraerPosicionNombre', 'usarUltimoNumeroNombre', 'metodoInterpK', ...
    'pxMinBusqueda', 'pxMaxBusqueda', 'modeloAjuste', 'anchoVentana', ...
    'ventanaAutoAdapt', 'cfg');
fprintf('\nResultados guardados en Penetration_resultados.csv / .mat\n');

%% ======================== FUNCIONES LOCALES =============================
function [dMic, fuente] = resolverPosiciones(archivos, carpeta, archivoCSV, extraerNombre, usarUltimo)
% Resuelve posiciones sin imponer un patrón al nombre del TDMS.
% Prioridad: número extraído del nombre < CSV (el CSV siempre sobrescribe).
    n = numel(archivos);
    dMic = nan(n,1);
    fuente = repmat("Sin posicion", n, 1);

    if extraerNombre
        for k = 1:n
            [~, base] = fileparts(archivos(k).name);
            tokens = regexp(base, '[-+]?\d+(?:[\.,]\d+)?', 'match');
            if ~isempty(tokens)
                if usarUltimo, token = tokens{end}; else, token = tokens{1}; end
                dMic(k) = str2double(strrep(token, ',', '.'));
                fuente(k) = "Nombre";
            end
        end
    end

    if isempty(archivoCSV)
        candidato = fullfile(carpeta, 'Posiciones_micrometro.csv');
        if isfile(candidato), archivoCSV = candidato; end
    elseif ~isfile(archivoCSV)
        error('No existe archivoPosiciones: %s', archivoCSV);
    end

    if ~isempty(archivoCSV)
        P = readtable(archivoCSV, 'VariableNamingRule', 'preserve');
        vars = string(P.Properties.VariableNames);
        iArchivo = find(strcmpi(vars, 'Archivo') | strcmpi(vars, 'File'), 1);
        iPos = find(strcmpi(vars, 'Micrometro_um') | strcmpi(vars, 'Position_um'), 1);
        if isempty(iArchivo) || isempty(iPos)
            error(['El CSV debe contener las columnas Archivo y Micrometro_um ' ...
                '(también se aceptan File y Position_um).']);
        end
        nombresCSV = string(P{:,iArchivo});
        posicionesCSV = P{:,iPos};
        if iscell(posicionesCSV) || isstring(posicionesCSV)
            posicionesCSV = str2double(strrep(string(posicionesCSV), ',', '.'));
        end
        for k = 1:n
            q = find(strcmpi(nombresCSV, archivos(k).name), 1);
            if ~isempty(q) && isfinite(posicionesCSV(q))
                dMic(k) = posicionesCSV(q);
                fuente(k) = "CSV";
            end
        end
    end
end

%% --------------------------- GUI manual ---------------------------------
function ajustes = guiAjusteManual(ajustes, archivos, umPorPx)
    nombres = erase(string({archivos.name}), '.tdms');
    fig = uifigure('Name', 'Manual fit', 'Position', [100 100 1150 620]);
    g = uigridlayout(fig, [1 2]); g.ColumnWidth = {'2x', '1x'};
    ax = uiaxes(g); grid(ax, 'on'); xlabel(ax, 'Depth [\mum]'); ylabel(ax, '|FFT|');
    pnl = uigridlayout(g, [12 3]);
    pnl.RowHeight = repmat({30}, 1, 12); pnl.ColumnWidth = {70, '1x', 80};

    uilabel(pnl, 'Text', 'Measurement');
    ddMed = uidropdown(pnl, 'Items', nombres, 'ItemsData', 1:numel(nombres));
    ddMed.Layout.Column = [2 3];
    uilabel(pnl, 'Text', 'Model');
    ddMod = uidropdown(pnl, 'Items', {'gauss', 'sinc'});
    ddMod.Layout.Column = [2 3];

    etiquetas = {'Amplitude', 'Center [px]', 'FWHM [px]', 'Offset'};
    sl = gobjects(1,4); ef = gobjects(1,4);
    for q = 1:4
        uilabel(pnl, 'Text', etiquetas{q});
        sl(q) = uislider(pnl, 'MajorTicks', [], 'MinorTicks', []);
        ef(q) = uieditfield(pnl, 'numeric', 'ValueDisplayFormat', '%.4g');
    end

    btnAuto = uibutton(pnl, 'Text', 'Auto-fit');  btnAuto.Layout.Column = [1 3];
    btnSig  = uibutton(pnl, 'Text', 'Save and next >');  btnSig.Layout.Column = [1 3];
    lblInfo = uilabel(pnl, 'Text', '', 'FontWeight', 'bold', 'FontSize', 14);
    lblInfo.Layout.Column = [1 3];
    lblR2 = uilabel(pnl, 'Text', '');  lblR2.Layout.Column = [1 3];
    btnFin = uibutton(pnl, 'Text', 'Finish', 'BackgroundColor', [0.85 0.95 0.85]);
    btnFin.Layout.Column = [1 3];

    st.aj = ajustes; st.p = []; st.k = 1;
    cargar(1);

    ddMed.ValueChangedFcn = @(~,~) cargar(ddMed.Value);
    ddMod.ValueChangedFcn = @(~,~) cambiarModelo();
    for q = 1:4
        sl(q).ValueChangingFcn = @(~,ev) setParam(q, ev.Value);
        sl(q).ValueChangedFcn  = @(src,~) setParam(q, src.Value);
        ef(q).ValueChangedFcn  = @(src,~) setParam(q, src.Value);
    end
    btnAuto.ButtonPushedFcn = @(~,~) autoAjuste();
    btnSig.ButtonPushedFcn  = @(~,~) guardarSiguiente();
    btnFin.ButtonPushedFcn  = @(~,~) terminar();
    fig.CloseRequestFcn     = @(~,~) terminar();

    uiwait(fig);
    ajustes = st.aj;
    delete(fig);

    function cargar(k)
        st.k = k; s = st.aj(k);
        ddMod.Value = s.modelo; st.p = s.p;
        A = max(s.yw); xr = [s.xw(1) s.xw(end)];
        lim = {[0 2*A], xr, [0.5 3*(xr(2)-xr(1))], [-0.5*A 0.5*A]};
        for r = 1:4
            sl(r).Limits = lim{r};
            st.p(r) = min(max(st.p(r), lim{r}(1)), lim{r}(2));
        end
        refrescar();
    end

    function setParam(q, v)
        v = min(max(v, sl(q).Limits(1)), sl(q).Limits(2));
        st.p(q) = v; refrescar();
    end

    function cambiarModelo()
        st.aj(st.k).modelo = ddMod.Value; refrescar();
    end

    function autoAjuste()
        s = st.aj(st.k);
        st.p = OCT_Comun.ajustarPico(s.xw, s.yw, ddMod.Value, st.p);
        refrescar();
    end

    function guardarSiguiente()
        guardar();
        if st.k < numel(st.aj)
            ddMed.Value = st.k + 1; cargar(st.k + 1);
        end
    end

    function guardar()
        s = st.aj(st.k);
        st.aj(st.k).modelo = ddMod.Value;
        st.aj(st.k).p = st.p;
        st.aj(st.k).R2 = OCT_Comun.calcR2(s.yw, OCT_Comun.modeloPico(st.p, s.xw, ddMod.Value));
    end

    function terminar()
        guardar(); uiresume(fig);
    end

    function refrescar()
        s = st.aj(st.k); m = ddMod.Value;
        for r = 1:4
            sl(r).Value = min(max(st.p(r), sl(r).Limits(1)), sl(r).Limits(2));
            ef(r).Value = st.p(r);
        end
        xf = linspace(s.xw(1), s.xw(end), 400);
        cla(ax);
        plot(ax, s.xw*umPorPx, s.yw, 'k.', 'MarkerSize', 10); hold(ax, 'on');
        plot(ax, xf*umPorPx, OCT_Comun.modeloPico(st.p, xf, m), 'r-', 'LineWidth', 1.5);
        hm = st.p(1)/2 + st.p(4);
        plot(ax, (st.p(2) + [-1 1]*st.p(3)/2)*umPorPx, [hm hm], 'g-', 'LineWidth', 2);
        hold(ax, 'off'); axis(ax, 'tight');
        title(ax, sprintf('%s  (%s)', nombres(st.k), m));
        lblInfo.Text = sprintf('FWHM = %.2f px = %.2f um', st.p(3), st.p(3)*umPorPx);
        lblR2.Text = sprintf('R^2 = %.4f', OCT_Comun.calcR2(s.yw, OCT_Comun.modeloPico(st.p, s.xw, m)));
    end
end
