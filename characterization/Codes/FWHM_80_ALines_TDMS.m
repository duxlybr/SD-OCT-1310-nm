function [resultado, parametrosSistema] = FWHM_80_ALines_TDMS(archivoTDMS, archivoCalibracion)
%FWHM_80_ALINES_TDMS FWHM de una adquisicion TDMS, congruente con Penetration.
%
%   R = FWHM_80_ALines_TDMS()
%       Abre un dialogo para seleccionar el TDMS y localiza automaticamente
%       el Penetration_resultados.mat mas reciente (calibracion um/px).
%
%   R = FWHM_80_ALines_TDMS(archivoTDMS)
%   R = FWHM_80_ALines_TDMS(archivoTDMS, archivoCalibracion)
%   [R, P] = FWHM_80_ALines_TDMS(...)
%       P contiene la LUT de k-linearization y los coeficientes de dispersion
%       listos para transferir al sistema de adquisicion.
%
% 1) Medicion "como Penetration": usa los parametros de OCT_Parametros.m y
%    las funciones de OCT_Comun.m, las mismas que Penetration_Analysis_TDMS.m.
%    FWHM_ajuste_um y FWHM_datos_um coinciden con las columnas del mismo
%    nombre en Penetration_resultados para ese archivo. Es el valor a vigilar
%    durante el ajuste fino.
% 2) Optimizacion (opcional): sugiere lambdaIni_nm / lambdaFin_nm (modelo
%    lineal en pixel de Penetration; se copian a OCT_Parametros.m) y despues,
%    con esos valores fijos, los coeficientes de dispersion D2 y D3 para el
%    sistema de adquisicion. Penetration no compensa dispersion.

if nargin < 1, archivoTDMS = ''; end
if nargin < 2, archivoCalibracion = ''; end

P = OCT_Parametros();      % mismo procesamiento que Penetration_Analysis_TDMS.m

%% Opciones de este script
nALinesEsperadas = 80;     % solo informativo: se usan todas las A-lines, como en Penetration
optimizar = true;          % false: solo la medicion como Penetration

% La PSF solo depende del cociente lambdaFin/lambdaIni: escalar ambos por el
% mismo factor produce exactamente la misma FFT. Por eso se optimiza un solo
% grado de libertad (el ancho de banda) manteniendo fija un ancla:
%   'centro' : (lambdaIni+lambdaFin)/2 constante
%   'inicio' : lambdaIni constante
%   'fin'    : lambdaFin constante
anclaLambda = 'centro';
limiteCambioAncho_nm = 100;  % |cambio de lambdaFin-lambdaIni| maximo

% Etapa 1: lambdaIni/lambdaFin sin dispersion. Etapa 2: D2 y D3 con esos
% lambdas fijos. Los pasos se expresan como error de fase maximo [rad]; para
% el ancho de banda se convierten a nm segun la profundidad del pico. El
% objetivo es el FWHM directo de OCT_Comun (el mismo de Penetration).
pasosFase_rad = [50 10 5 2 1 0.5 0.2 0.1];
limiteDispersion_rad = 200;
% El error de fase de la linealizacion crece con la profundidad: cerca del
% retardo cero lambdaIni/lambdaFin no son observables y el pico se mezcla con
% el termino DC. Por debajo de estos umbrales se omite cada etapa.
profundidadMinK_um = 500;          % etapa 1 (lambdaIni/lambdaFin)
profundidadMinDispersion_um = 150; % etapa 2 (D2, D3)
semiBusquedaPico = 80;    % evita que el optimizador salte a otro reflector
limiteTeoricoFWHM_um = 8.49;   % candidatos mas estrechos se descartan (espurios)
limiteSuperiorFWHM_um = 18.00; % candidatos mas anchos se descartan
guardarParametros = true;

if isempty(archivoTDMS)
    carpetaInicial = 'C:\Users\proyecto.pi1081\Desktop\1310 OCT\Data\Spectrum';
    [nombre, carpeta] = uigetfile('*.tdms', ...
        'Select one TDMS acquisition', carpetaInicial);
    if isequal(nombre, 0), error('No se selecciono ningun archivo.'); end
    archivoTDMS = fullfile(carpeta, nombre);
end
archivoTDMS = char(archivoTDMS);
if ~isfile(archivoTDMS), error('No existe el archivo: %s', archivoTDMS); end

%% Calibracion um/px
[archivoCalibracion, C] = cargarCalibracion(archivoCalibracion, archivoTDMS);
umPorPx = umPorPxCalibracion(C, P, archivoCalibracion);
limiteTeoricoFWHM_px = limiteTeoricoFWHM_um/umPorPx;
limiteSuperiorFWHM_px = limiteSuperiorFWHM_um/umPorPx;

%% Lectura (todas las A-lines, como Penetration)
M = OCT_Comun.leerTDMS(archivoTDMS, P.nPix);
nLines = size(M, 2);
if nLines ~= nALinesEsperadas
    warning('%s contiene %d A-lines (se esperaban %d); se usan todas, como en Penetration.', ...
        archivoTDMS, nLines, nALinesEsperadas);
end
nHalf = P.nFFT/2;
pxAxis = (0:nHalf-1).';
z_um = pxAxis * umPorPx;
rango = OCT_Comun.rangoBusqueda(P, nHalf);

%% 1) Medicion como Penetration_Analysis_TDMS.m
[Aabs, Arect] = OCT_Comun.ascan(M, P);
[pkPx, pkIdx, pkAmp, prominencia_dB] = OCT_Comun.buscarPicoReflector(pxAxis, Aabs, rango);
if ~(prominencia_dB >= 15)
    warning(['No se encontro un reflector claro: el pico a %.0f um solo sobresale %.1f dB ' ...
        'de su entorno. El FWHM puede corresponder a ruido.'], pkPx*umPorPx, prominencia_dB);
end
med = OCT_Comun.medirPico(pxAxis, Arect, pkIdx, P);
profundidad_um = pkPx*umPorPx;
fwhmAjuste_um = med.fwhmPx*umPorPx;
fwhmDatos_um = med.fwhmDatosPx*umPorPx;
R2 = med.ajuste.R2;

%% 2) Optimizacion de lambdaIni/lambdaFin y dispersion
% Parametros optimizados: x = [cambio de ancho de banda (nm), D2 (rad), D3 (rad)]
aLambdas = @(x) rangoEspectral(P.lambdaIni_nm, P.lambdaFin_nm, x(1), anclaLambda);
rangoRef = max(rango(1), pkIdx-semiBusquedaPico):min(rango(end), pkIdx+semiBusquedaPico);
evaluar = @(x) evaluarCandidato(M, P, aLambdas(x), x(2:3), pxAxis, rangoRef, ...
    limiteTeoricoFWHM_px, limiteSuperiorFWHM_px);

% Un cambio de 1 nm en el ancho de banda desplaza el remuestreo como mucho
% dp pixeles (en el centro; los extremos no se mueven) y produce un error de
% fase 2*pi*f*dp, con f = pico/nFFT ciclos por muestra.
pf0 = pixelFuenteK(P.nPix, P.lambdaIni_nm, P.lambdaFin_nm);
lam1 = aLambdas([1 0 0]);
pf1 = pixelFuenteK(P.nPix, lam1(1), lam1(2));
radPorNm = 2*pi*(pkPx/P.nFFT)*max(abs(pf1-pf0));
pasosAncho_nm = pasosFase_rad(:)/radPorNm;
pasosCero = zeros(numel(pasosFase_rad), 1);
limites = [limiteCambioAncho_nm limiteDispersion_rad limiteDispersion_rad];

optimizarK = optimizar && profundidad_um >= profundidadMinK_um;
optimizarDisp = optimizar && profundidad_um >= profundidadMinDispersion_um;
pasosEtapaK = [pasosAncho_nm pasosCero pasosCero];
pasosEtapaD = [pasosCero pasosFase_rad(:) pasosFase_rad(:)];
if ~optimizarK, pasosEtapaK = zeros(0, 3); end
if ~optimizarDisp, pasosEtapaD = zeros(0, 3); end

fprintf('\nPeak depth: %.1f um\n', profundidad_um);
fprintf('\n=== Stage 1: k-linearization (lambdaIni/lambdaFin, anchor = %s) ===\n', ...
    anclaLambda);
if ~optimizar
    fprintf('  Skipped: optimizar = false.\n');
elseif ~optimizarK
    fprintf(['  Skipped: peak at %.0f um < %.0f um. At this depth lambdaIni/' ...
        'lambdaFin are not observable\n  (+/-%.0f nm of bandwidth changes the ' ...
        'phase by only %.2f rad). OCT_Parametros lambdas retained.\n'], ...
        profundidad_um, profundidadMinK_um, limiteCambioAncho_nm, ...
        radPorNm*limiteCambioAncho_nm);
end
[xK, fwhmK, histK] = busquedaPatron(evaluar, [0 0 0], med.fwhmDatosPx, ...
    pasosEtapaK, limites, "k-linearization", 0, aLambdas);
fprintf('\n=== Stage 2: dispersion compensation (D2, D3) ===\n');
if ~optimizar
    fprintf('  Skipped: optimizar = false.\n');
elseif ~optimizarDisp
    fprintf(['  Skipped: peak at %.0f um < %.0f um overlaps the DC term. ' ...
        'Zero dispersion correction retained.\n'], profundidad_um, ...
        profundidadMinDispersion_um);
end
[xOpt, ~, histD] = busquedaPatron(evaluar, xK, fwhmK, ...
    pasosEtapaD, limites, "dispersion", height(histK)-1, aLambdas);
if optimizar && (~optimizarK || ~optimizarDisp)
    warning(['The mirror is too close to zero delay (%.0f um) for a full ' ...
        'optimization.\nMove it to at least %.0f um (k-linearization) / %.0f um ' ...
        '(dispersion) and acquire again.'], profundidad_um, ...
        profundidadMinK_um, profundidadMinDispersion_um);
end
historial = [histK; histD];

lambdasOpt = aLambdas(xOpt);
coefDispersion = xOpt(2:3);
PK = P;
PK.lambdaIni_nm = lambdasOpt(1);
PK.lambdaFin_nm = lambdasOpt(2);
% Mismas mediciones (directa + ajuste) que Penetration con los valores optimos
[AabsK, ArectK] = OCT_Comun.ascan(M, PK);
[~, pkIdxK] = OCT_Comun.buscarPico(pxAxis, AabsK, rangoRef);
medK = OCT_Comun.medirPico(pxAxis, ArectK, pkIdxK, PK);
[AabsKD, ArectKD] = OCT_Comun.ascan(M, PK, coefDispersion);
[~, pkIdxKD] = OCT_Comun.buscarPico(pxAxis, AabsKD, rangoRef);
medKD = OCT_Comun.medirPico(pxAxis, ArectKD, pkIdxKD, PK);

fwhmAjusteK_um = medK.fwhmPx*umPorPx;
fwhmDatosK_um = medK.fwhmDatosPx*umPorPx;
fwhmAjusteKD_um = medKD.fwhmPx*umPorPx;
fwhmDatosKD_um = medKD.fwhmDatosPx*umPorPx;
mejoraFWHM_pct = 100*(fwhmAjuste_um-fwhmAjusteKD_um)/fwhmAjuste_um;
if ~optimizar
    estadoOptimizacion = "Not optimized: optimizar = false";
elseif ~optimizarDisp
    estadoOptimizacion = "Not optimized: peak too close to zero delay";
elseif ~optimizarK
    estadoOptimizacion = "Dispersion only: peak too shallow for k-linearization";
elseif all(abs(xOpt) < 1e-12)
    estadoOptimizacion = "OCT_Parametros lambdas retained; zero dispersion correction";
else
    estadoOptimizacion = "Optimized lambdaIni/lambdaFin and dispersion correction";
end

%% Resultado
[~, nombreArchivo, extension] = fileparts(archivoTDMS);
nombreCompleto = [nombreArchivo extension];
parametrosSistema = construirParametrosSistema(P.nPix, PK.lambdaIni_nm, ...
    PK.lambdaFin_nm, coefDispersion, P.metodoInterpK, archivoTDMS, archivoCalibracion);
parametrosSistema.kLinearization.lambdaIniOCTParametros_nm = P.lambdaIni_nm;
parametrosSistema.kLinearization.lambdaFinOCTParametros_nm = P.lambdaFin_nm;
parametrosSistema.kLinearization.ancla = string(anclaLambda);
% Sin optimizacion no se sobrescriben parametros guardados previamente.
guardarParametros = guardarParametros && optimizarDisp;
if guardarParametros
    % Resultados en una carpeta con el nombre del archivo procesado.
    parametrosSistema = guardarParametrosSistema(parametrosSistema, ...
        fullfile(fileparts(archivoTDMS), nombreArchivo), nombreArchivo);
end
resultado = table(string(nombreCompleto), nLines, profundidad_um, pkPx, ...
    10*log10(pkAmp), string(P.modeloAjuste), fwhmAjuste_um, fwhmDatos_um, R2, ...
    P.lambdaIni_nm, P.lambdaFin_nm, PK.lambdaIni_nm, PK.lambdaFin_nm, ...
    fwhmAjusteK_um, fwhmDatosK_um, coefDispersion(1), coefDispersion(2), ...
    parametrosSistema.dispersion.D2_um2, parametrosSistema.dispersion.D3_um3, ...
    fwhmAjusteKD_um, fwhmDatosKD_um, mejoraFWHM_pct, umPorPx, ...
    estadoOptimizacion, string(archivoCalibracion), ...
    'VariableNames', {'Archivo','Numero_ALines','Profundidad_um','Pico_px', ...
    'Intensidad_dB','Modelo','FWHM_ajuste_um','FWHM_datos_um','R2', ...
    'LambdaIni_nm','LambdaFin_nm','LambdaIni_optimo_nm','LambdaFin_optimo_nm', ...
    'FWHM_ajuste_lambdaOpt_um','FWHM_datos_lambdaOpt_um', ...
    'Disp_D2_rad','Disp_D3_rad','Disp_D2_um2','Disp_D3_um3', ...
    'FWHM_ajuste_conDispersion_um','FWHM_datos_conDispersion_um', ...
    'Mejora_FWHM_ajuste_pct','umPorPx','EstadoOptimizacion','ArchivoCalibracion'});
resultado.Properties.UserData.HistorialOptimizacion = historial;
resultado.Properties.UserData.ParametrosSistema = parametrosSistema;
resultado.Properties.UserData.OCT_Parametros = P;

fprintf('\n=== FWHM: %s ===\n', nombreCompleto);
fprintf('Calibration       : %s (%.4f um/px)\n', archivoCalibracion, umPorPx);
fprintf('A-lines           : %d\n', nLines);
fprintf('\nAs Penetration_Analysis_TDMS.m (OCT_Parametros: %.2f-%.2f nm, no dispersion)\n', ...
    P.lambdaIni_nm, P.lambdaFin_nm);
fprintf('  Depth           : %.1f um (peak %.2f px, %.1f dB above its surroundings)\n', ...
    profundidad_um, pkPx, prominencia_dB);
fprintf('  FWHM_ajuste_um  : %.3f um (%s, R^2 = %.5f)\n', fwhmAjuste_um, ...
    P.modeloAjuste, R2);
fprintf('  FWHM_datos_um   : %.3f um (direct half-maximum)\n', fwhmDatos_um);
if optimizar
    fprintf('\nOptimized k-linearization (anchor = %s)\n', anclaLambda);
    fprintf('  lambdaIni_nm    : %.3f -> %.3f nm\n', P.lambdaIni_nm, PK.lambdaIni_nm);
    fprintf('  lambdaFin_nm    : %.3f -> %.3f nm\n', P.lambdaFin_nm, PK.lambdaFin_nm);
    fprintf('  OCT_Parametros.m: P.lambdaIni_nm = %.2f; P.lambdaFin_nm = %.2f;\n', ...
        PK.lambdaIni_nm, PK.lambdaFin_nm);
    fprintf('  FWHM ajuste / datos : %.3f / %.3f um\n', fwhmAjusteK_um, fwhmDatosK_um);
    fprintf('\n+ Dispersion compensation (acquisition system only)\n');
    fprintf('  Normalized      : D2 = %+.3f rad, D3 = %+.3f rad\n', ...
        coefDispersion(1), coefDispersion(2));
    fprintf('  Physical        : D2 = %+.6g um^2, D3 = %+.6g um^3\n', ...
        parametrosSistema.dispersion.D2_um2, parametrosSistema.dispersion.D3_um3);
    fprintf('  FWHM ajuste / datos : %.3f / %.3f um (%.2f %% vs Penetration)\n', ...
        fwhmAjusteKD_um, fwhmDatosKD_um, mejoraFWHM_pct);
end
fprintf('\nOptimization      : %s\n\n', estadoOptimizacion);
if guardarParametros
    fprintf('Defaults MAT      : %s\n', parametrosSistema.export.matFile);
    fprintf('K LUT CSV         : %s\n\n', parametrosSistema.export.csvFile);
end

%% Figura
fig = figure('Color', 'w', 'Name', ['FWHM - ' nombreCompleto], ...
    'NumberTitle', 'off', 'Position', [50 50 1450 850]);
tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% A-scans normalizados al pico (10*log10, como las graficas de Penetration)
ax1 = nexttile(tl, [1 2]);
plot(ax1, z_um, 10*log10(max(Aabs, eps)) - 10*log10(pkAmp), ...
    'Color', [0.05 0.35 0.70], 'LineWidth', 1);
hold(ax1, 'on');
if optimizarDisp
    plot(ax1, z_um, 10*log10(max(AabsKD, eps)) - 10*log10(max(AabsKD(rangoRef))), ...
        '--', 'Color', [0.85 0.33 0.10], 'LineWidth', 1);
end
plot(ax1, profundidad_um, 0, 'o', 'Color', [0.85 0.20 0.10], ...
    'MarkerFaceColor', [1.00 0.75 0.10]);
xlabel(ax1, 'Depth [\mum]');
ylabel(ax1, 'Normalized intensity [dB]');
title(ax1, sprintf('A-scan (%d A-lines) - peak at %.0f \\mum', nLines, profundidad_um));
leyenda = {sprintf('OCT\\_Parametros: %.2f-%.2f nm', P.lambdaIni_nm, P.lambdaFin_nm)};
if optimizarDisp
    leyenda{end+1} = sprintf('Optimized: %.2f-%.2f nm + dispersion', ...
        PK.lambdaIni_nm, PK.lambdaFin_nm);
end
legend(ax1, [leyenda {'Peak'}], 'Location', 'best');
grid(ax1, 'on');

% Pico y ajuste exactamente como Penetration (A-scan sin ventana)
ax2 = nexttile(tl);
s = med.ajuste;
xf = linspace(s.xw(1), s.xw(end), 800).';
plot(ax2, s.xw*umPorPx, s.yw, '.', 'Color', [0.35 0.35 0.35], 'MarkerSize', 8);
hold(ax2, 'on');
plot(ax2, xf*umPorPx, OCT_Comun.modeloPico(s.p, xf, s.modelo), 'r-', 'LineWidth', 1.5);
hm = s.p(1)/2 + s.p(4);
plot(ax2, (s.p(2) + [-1 1]*s.p(3)/2)*umPorPx, [hm hm], 'g-', 'LineWidth', 2);
entradas = {'Mean |FFT|', sprintf('%s fit', s.modelo), 'Fit FWHM'};
if optimizarDisp
    sKD = medKD.ajuste;
    xfKD = linspace(sKD.xw(1), sKD.xw(end), 800).';
    plot(ax2, xfKD*umPorPx, OCT_Comun.modeloPico(sKD.p, xfKD, sKD.modelo), '--', ...
        'Color', [0.85 0.33 0.10], 'LineWidth', 1.2);
    entradas{end+1} = sprintf('Optimized fit (%.2f \\mum)', fwhmAjusteKD_um);
end
xlim(ax2, [s.xw(1) s.xw(end)]*umPorPx);
xlabel(ax2, 'Depth [\mum]');
ylabel(ax2, '|FFT| [a.u.]');
title(ax2, sprintf('As Penetration: %s FWHM = %.2f \\mum (direct %.2f \\mum)', ...
    s.modelo, fwhmAjuste_um, fwhmDatos_um));
legend(ax2, entradas, 'Location', 'best');
grid(ax2, 'on');

ax3 = nexttile(tl);
fwhmHist_um = historial.FWHM_px*umPorPx;
validosHist = isfinite(fwhmHist_um);
plot(ax3, historial.Iteracion(validosHist), fwhmHist_um(validosHist), ...
    'o-', 'Color', [0.10 0.45 0.20], 'MarkerFaceColor', [0.45 0.80 0.45], ...
    'LineWidth', 1.8, 'MarkerSize', 7);
hold(ax3, 'on');
yline(ax3, limiteTeoricoFWHM_um, 'r--', ...
    sprintf('Lower limit: %.2f \\mum', limiteTeoricoFWHM_um), ...
    'LineWidth', 1.3, 'LabelHorizontalAlignment', 'left');
yline(ax3, limiteSuperiorFWHM_um, '--', ...
    sprintf('Upper limit: %.2f \\mum', limiteSuperiorFWHM_um), ...
    'Color', [0.90 0.45 0.05], 'LineWidth', 1.3, ...
    'LabelHorizontalAlignment', 'left');
if height(histD) > 1
    xline(ax3, histD.Iteracion(1), ':', 'Dispersion stage', ...
        'Color', [0.3 0.3 0.3], 'LineWidth', 1.2, ...
        'LabelVerticalAlignment', 'middle');
end
xlabel(ax3, 'Optimization iteration');
ylabel(ax3, 'Direct FWHM [\mum]');
title(ax3, 'K-linearization + dispersion convergence');
grid(ax3, 'on');
ylim(ax3, [0.95*min(limiteTeoricoFWHM_um, min(fwhmHist_um(validosHist))), ...
    1.05*max(limiteSuperiorFWHM_um, max(fwhmHist_um(validosHist)))]);
resumen = sprintf(['Penetration: %.3f \\mum\n\\lambda_{ini} = %.2f nm\n' ...
    '\\lambda_{fin} = %.2f nm\nD_2 = %+.3f rad\nD_3 = %+.3f rad\n' ...
    'Optimized: %.3f \\mum'], fwhmAjuste_um, PK.lambdaIni_nm, ...
    PK.lambdaFin_nm, coefDispersion(1), coefDispersion(2), fwhmAjusteKD_um);
% El recuadro se coloca en la mitad vertical opuesta a la curva final.
limY = ylim(ax3);
if (fwhmHist_um(end)-limY(1))/diff(limY) > 0.5
    posY = 0.10; alineY = 'bottom';
else
    posY = 0.96; alineY = 'top';
end
text(ax3, 0.98, posY, resumen, 'Units', 'normalized', ...
    'HorizontalAlignment', 'right', 'VerticalAlignment', alineY, ...
    'FontSize', 12, 'FontWeight', 'bold', 'BackgroundColor', 'w', ...
    'EdgeColor', [0.4 0.4 0.4], 'Margin', 7);

set([ax1 ax2 ax3], 'FontSize', 12, 'LineWidth', 1);
title(ax1, ax1.Title.String, 'FontSize', 14);
title(ax2, ax2.Title.String, 'FontSize', 14);
title(ax3, ax3.Title.String, 'FontSize', 14);
sgtitle(tl, nombreCompleto, 'Interpreter', 'none', 'FontWeight', 'bold', ...
    'FontSize', 16);
drawnow;

if nargout == 0
    assignin('base', 'FWHM_resultado', resultado);
    assignin('base', 'OCT_parametros_sistema', parametrosSistema);
end
end

function umPorPx = umPorPxCalibracion(C, P, archivoCalibracion)
% um/px de Penetration_resultados.mat, verificado contra OCT_Parametros.
    if isfield(C, 'umPorPx')
        umPorPx = C.umPorPx;
    elseif isfield(C, 'pxPorUm')
        umPorPx = 1/C.pxPorUm;
    else
        error('%s no contiene umPorPx ni pxPorUm.', archivoCalibracion);
    end
    if ~isscalar(umPorPx) || ~isfinite(umPorPx) || umPorPx <= 0
        error('La calibracion contiene una relacion umPorPx no valida.');
    end
    if isfield(C, 'nFFT') && C.nFFT ~= P.nFFT
        umPorPx = umPorPx*C.nFFT/P.nFFT;
        warning('La calibracion usa nFFT = %d y OCT_Parametros nFFT = %d; um/px reescalado.', ...
            C.nFFT, P.nFFT);
    end
    if isfield(C, 'nPix') && C.nPix ~= P.nPix
        warning('La calibracion usa nPix = %d y OCT_Parametros nPix = %d.', C.nPix, P.nPix);
    end
    if isfield(C, 'lambdaIni_nm') && isfield(C, 'lambdaFin_nm') && ...
            (abs(C.lambdaIni_nm-P.lambdaIni_nm) > 0.005 || ...
            abs(C.lambdaFin_nm-P.lambdaFin_nm) > 0.005)
        warning(['%s se calculo con lambda = %.2f-%.2f nm, pero OCT_Parametros.m usa ' ...
            '%.2f-%.2f nm. El FWHM se mide con OCT_Parametros; vuelva a ejecutar ' ...
            'Penetration_Analysis_TDMS.m para actualizar la calibracion um/px.'], ...
            archivoCalibracion, C.lambdaIni_nm, C.lambdaFin_nm, P.lambdaIni_nm, ...
            P.lambdaFin_nm);
    end
end

function [x, fwhmMejor, historial] = busquedaPatron(evaluar, x0, fwhmInicial, ...
        pasos, limites, etapa, iter0, aLambdas)
% Busqueda de patron multirresolucion. pasos es nNiveles x nParametros; las
% columnas con paso 0 quedan fijas. En cada nivel se repiten barridos
% coordinados hasta que ninguno mejora el FWHM; dentro de una coordenada se
% sigue avanzando mientras la direccion mejore.
    maxBarridosPorNivel = 25;
    tolMejoraPx = 1e-6;
    x = x0;
    fwhmMejor = evaluar(x0);
    if isnan(fwhmMejor), fwhmMejor = inf; end
    activos = find(any(pasos ~= 0, 1));

    lam = aLambdas(x);
    etapaHist = etapa; iterHist = iter0; nivelHist = 0;
    lIniHist = lam(1); lFinHist = lam(2); d2Hist = x(2); d3Hist = x(3);
    fwhmHist = fwhmInicial; validosHist = 1; mejoraHist = false;
    fprintf(['  Start: lambda = %.3f-%.3f nm, D2 = %+.3f rad, D3 = %+.3f rad, ' ...
        'FWHM = %.4f px\n'], lam, x(2:3), fwhmInicial);

    iter = iter0;
    for nivel = 1:size(pasos,1)
        for barrido = 1:maxBarridosPorNivel
            fwhmAntes = fwhmMejor;
            nValidos = 0;
            for j = activos
                for signo = [-1 1]
                    avanzo = false;
                    while true
                        candidato = x;
                        candidato(j) = candidato(j) + signo*pasos(nivel,j);
                        if abs(candidato(j)) > limites(j)+1e-12, break; end
                        fwhm = evaluar(candidato);
                        if ~isnan(fwhm), nValidos = nValidos+1; end
                        if ~isnan(fwhm) && fwhm < fwhmMejor-tolMejoraPx
                            x = candidato;
                            fwhmMejor = fwhm;
                            avanzo = true;
                        else
                            break;
                        end
                    end
                    if avanzo, break; end % no explorar el sentido opuesto
                end
            end

            iter = iter+1;
            huboMejora = fwhmMejor < fwhmAntes-tolMejoraPx;
            lam = aLambdas(x);
            etapaHist(end+1,1) = etapa; %#ok<AGROW>
            iterHist(end+1,1) = iter; %#ok<AGROW>
            nivelHist(end+1,1) = nivel; %#ok<AGROW>
            lIniHist(end+1,1) = lam(1); %#ok<AGROW>
            lFinHist(end+1,1) = lam(2); %#ok<AGROW>
            d2Hist(end+1,1) = x(2); %#ok<AGROW>
            d3Hist(end+1,1) = x(3); %#ok<AGROW>
            fwhmHist(end+1,1) = fwhmMejor; %#ok<AGROW>
            validosHist(end+1,1) = nValidos; %#ok<AGROW>
            mejoraHist(end+1,1) = huboMejora; %#ok<AGROW>
            if huboMejora
                fprintf(['  Iter %2d (level %d, sweep %d): lambda = %.3f-%.3f nm, ' ...
                    'D2 = %+.3f, D3 = %+.3f rad, FWHM = %.4f px (%d valid)\n'], ...
                    iter, nivel, barrido, lam, x(2:3), fwhmMejor, nValidos);
            else
                fprintf(['  Iter %2d (level %d, sweep %d): no valid improvement ' ...
                    '(%d valid candidates).\n'], iter, nivel, barrido, nValidos);
                break;
            end
        end
    end
    historial = table(etapaHist, iterHist, nivelHist, lIniHist, lFinHist, ...
        d2Hist, d3Hist, fwhmHist, validosHist, mejoraHist, ...
        'VariableNames', {'Etapa','Iteracion','Nivel','LambdaIni_nm', ...
        'LambdaFin_nm','Disp_D2_rad','Disp_D3_rad','FWHM_px', ...
        'CandidatosValidos','MejoraEncontrada'});
end

function fwhm = evaluarCandidato(M, P, lambdas, coefDisp, pxAxis, rangoRef, ...
        fwhmMinimoPx, fwhmMaximoPx)
% FWHM directo de OCT_Comun (el de Penetration) con los lambdas y la
% dispersion del candidato, o NaN si no es valido o sale del rango fisico.
    fwhm = NaN;
    if ~(lambdas(1) > 0 && lambdas(2) > lambdas(1)), return; end
    P.lambdaIni_nm = lambdas(1);
    P.lambdaFin_nm = lambdas(2);
    [Aabs, Arect] = OCT_Comun.ascan(M, P, coefDisp);
    if any(~isfinite(Arect)), return; end
    [~, pkIdx] = OCT_Comun.buscarPico(pxAxis, Aabs, rangoRef);
    m = OCT_Comun.medirFWHMDirecto(pxAxis, Arect, pkIdx, P);
    if isfinite(m.fwhmDatosPx) && m.fwhmDatosPx >= fwhmMinimoPx && ...
            m.fwhmDatosPx <= fwhmMaximoPx
        fwhm = m.fwhmDatosPx;
    end
end

function lambdas = rangoEspectral(lambdaIni0_nm, lambdaFin0_nm, dAncho_nm, ancla)
% [lambdaIni lambdaFin] tras cambiar el ancho de banda en dAncho_nm,
% manteniendo fija el ancla indicada.
    switch lower(ancla)
        case 'centro'
            centro = (lambdaIni0_nm+lambdaFin0_nm)/2;
            ancho = (lambdaFin0_nm-lambdaIni0_nm) + dAncho_nm;
            lambdas = [centro-ancho/2, centro+ancho/2];
        case 'inicio'
            lambdas = [lambdaIni0_nm, lambdaFin0_nm+dAncho_nm];
        case 'fin'
            lambdas = [lambdaIni0_nm-dAncho_nm, lambdaFin0_nm];
        otherwise
            error('anclaLambda debe ser ''centro'', ''inicio'' o ''fin''.');
    end
end

function pixelFuente = pixelFuenteK(nPix, lambdaIni_nm, lambdaFin_nm)
% Pixel fraccional (base 0) de la camara que corresponde a cada muestra
% uniforme en k (orden ascendente de k). Muestra j de la salida = S(pixelFuente(j)).
    pixel = (0:nPix-1).';
    kAsc = flipud(2*pi ./ linspace(lambdaIni_nm, lambdaFin_nm, nPix).');
    kUniforme = linspace(kAsc(1), kAsc(end), nPix).';
    pixelFuente = interp1(kAsc, flipud(pixel), kUniforme, 'pchip');
    pixelFuente([1 end]) = [nPix-1 0];
end

function P = construirParametrosSistema(nPix, lambdaIni_nm, lambdaFin_nm, ...
        coefDisp, metodoInterpK, archivoTDMS, archivoCalibracion)
% Reune la LUT de k-linearization y la fase de dispersion con las mismas
% convenciones usadas en OCT_Comun.ascan.
    lambda_nm = linspace(lambdaIni_nm, lambdaFin_nm, nPix).';
    t = (0:nPix-1).'/(nPix-1);
    kCamara_radum = 2*pi ./ (lambda_nm*1e-3);          % orden de camara
    kAsc = flipud(kCamara_radum);
    kUniforme_radum = linspace(kAsc(1), kAsc(end), nPix).';
    pixelFuente = pixelFuenteK(nPix, lambdaIni_nm, lambdaFin_nm);

    k0_radum = (kUniforme_radum(1)+kUniforme_radum(end))/2;
    semiRangoK_radum = (kUniforme_radum(end)-kUniforme_radum(1))/2;
    fase_rad = OCT_Comun.faseDispersion(nPix, coefDisp);

    P = struct();
    P.descripcion = ['Parametros de procesamiento OCT: k-linearization y ' ...
        'compensacion numerica de dispersion optimizadas por FWHM_80_ALines_TDMS.m'];
    P.fecha = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    P.archivoTDMS = string(archivoTDMS);
    P.archivoCalibracion = string(archivoCalibracion);
    P.nPix = nPix;
    P.lambdaIni_nm = lambdaIni_nm;
    P.lambdaFin_nm = lambdaFin_nm;

    K = struct();
    K.lambdaIni_nm = lambdaIni_nm;
    K.lambdaFin_nm = lambdaFin_nm;
    K.definicion = ['lambda = linspace(lambdaIni_nm, lambdaFin_nm, nPix); ' ...
        'k = 2*pi/lambda; remuestreo a k uniforme (como Penetration_Analysis_TDMS.m)'];
    K.metodoInterpolacion = string(metodoInterpK);
    K.lambdaPixel_nm = lambda_nm;
    K.kPixel_radum = kCamara_radum;
    K.kUniforme_radum = kUniforme_radum;
    K.pixelFuente = pixelFuente;
    K.kPolynomialNormalized = polyfit(t, kCamara_radum, 3);
    K.kPolynomialDefinicion = 'k(t) = polyval(p, t) [rad/um], t = pixel/(nPix-1)';
    P.kLinearization = K;

    D = struct();
    D.D2_rad = coefDisp(1);
    D.D3_rad = coefDisp(2);
    D.k0_radum = k0_radum;
    D.semiRangoK_radum = semiRangoK_radum;
    D.D2_um2 = coefDisp(1)/semiRangoK_radum^2;
    D.D3_um3 = coefDisp(2)/semiRangoK_radum^3;
    D.definicion = ['S_corr(k) = S_a(k) .* exp(-1i*phi(k)), S_a = hilbert(S_lin)/2 ' ...
        '(senal analitica); phi = D2_rad*q^2 + D3_rad*q^3 = D2_um2*(k-k0)^2 + ' ...
        'D3_um3*(k-k0)^3, q = (k-k0)/semiRangoK'];
    D.fase_rad = fase_rad;
    P.dispersion = D;

    P.export = struct('matFile', "", 'csvFile', "");
end

function P = guardarParametrosSistema(P, carpeta, nombreBase)
% Guarda los parametros en MAT (struct completo) y la LUT en CSV.
    if ~isfolder(carpeta), mkdir(carpeta); end
    P.export.matFile = string(fullfile(carpeta, [nombreBase '_OCT_parametros.mat']));
    P.export.csvFile = string(fullfile(carpeta, [nombreBase '_K_LUT.csv']));

    K = P.kLinearization;
    D = P.dispersion;
    muestra = (0:P.nPix-1).';
    LUT = table(muestra, K.lambdaPixel_nm, K.kPixel_radum, K.kUniforme_radum, ...
        K.pixelFuente, D.fase_rad, cos(D.fase_rad), -sin(D.fase_rad), ...
        'VariableNames', {'Indice', 'LambdaPixel_nm', 'kPixel_radum', ...
        'kUniforme_radum', 'PixelFuente', 'FaseDispersion_rad', ...
        'CompReal', 'CompImag'});

    parametrosSistema = P;
    kLUT_pixelFuente = K.pixelFuente;
    lambdaIni_nm = K.lambdaIni_nm;
    lambdaFin_nm = K.lambdaFin_nm;
    coefDispersion_rad = [D.D2_rad D.D3_rad];
    coefDispersion_fisicos = [D.D2_um2 D.D3_um3];
    faseDispersion_rad = D.fase_rad;
    save(P.export.matFile, 'parametrosSistema', 'kLUT_pixelFuente', ...
        'lambdaIni_nm', 'lambdaFin_nm', 'coefDispersion_rad', ...
        'coefDispersion_fisicos', 'faseDispersion_rad');
    writetable(LUT, P.export.csvFile);
end

function [ruta, C] = cargarCalibracion(ruta, archivoTDMS)
    if isempty(ruta)
        candidatos = [];
        carpeta = fileparts(archivoTDMS);
        for nivel = 1:4
            nuevos = [dir(fullfile(carpeta, 'Penetration_resultados.mat')); ...
                dir(fullfile(carpeta, 'Characterization', 'Penetration*', ...
                'Penetration_resultados.mat'))];
            if ~isempty(nuevos)
                if isempty(candidatos)
                    candidatos = nuevos;
                else
                    candidatos = [candidatos; nuevos]; %#ok<AGROW>
                end
            end
            carpetaPadre = fileparts(carpeta);
            if strcmp(carpetaPadre, carpeta), break; end
            carpeta = carpetaPadre;
        end
        if isempty(candidatos)
            error(['No se encontro Penetration_resultados.mat. Ejecute primero ' ...
                'Penetration_Analysis_TDMS.m o indique archivoCalibracion.']);
        end
        rutas = string(arrayfun(@(d) fullfile(d.folder,d.name), candidatos, ...
            'UniformOutput', false));
        [~, unicos] = unique(lower(rutas), 'stable');
        candidatos = candidatos(unicos);
        [~, iMasReciente] = max([candidatos.datenum]);
        ruta = fullfile(candidatos(iMasReciente).folder, candidatos(iMasReciente).name);
    end
    ruta = char(ruta);
    if ~isfile(ruta), error('No existe el archivo de calibracion: %s', ruta); end
    C = load(ruta);
end
