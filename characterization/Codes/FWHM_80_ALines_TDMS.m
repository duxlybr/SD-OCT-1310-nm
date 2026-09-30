function [resultado, parametrosSistema] = FWHM_80_ALines(archivoTDMS, archivoCalibracion)
%FWHM_80_ALINES Mide el FWHM de una adquisicion TDMS de 80 A-lines.
%
%   R = FWHM_80_ALines()
%       Abre un dialogo para seleccionar el TDMS y localiza automaticamente
%       el Penetration_resultados.mat mas reciente.
%
%   R = FWHM_80_ALines(archivoTDMS)
%   R = FWHM_80_ALines(archivoTDMS, archivoCalibracion)
%   [R, P] = FWHM_80_ALines(...)
%       P contiene la LUT de k-linearization y los coeficientes de dispersion
%       listos para transferir al sistema de adquisicion.
%
% La k-linearization usa el mismo modelo que Penetration_Analysis.m
% (lambda lineal en pixel entre lambdaIni_nm y lambdaFin_nm) y entrega los
% valores optimos de lambdaIni_nm / lambdaFin_nm. Despues, con esos valores
% fijos, se optimizan los coeficientes de dispersion D2 y D3.
%
% La deteccion del pico usa ventana Hann. El FWHM se mide sobre la FFT sin
% ventana para no ensanchar artificialmente la PSF. Se promedia |FFT| de las
% 80 A-lines, lo que evita cancelaciones causadas por deriva de fase.

if nargin < 1, archivoTDMS = ''; end
if nargin < 2, archivoCalibracion = ''; end

nALinesObjetivo = 1;
pxMinBusqueda = 25;       % excluye residuos cercanos al DC
semiVentanaAjuste = 100;  % bins a cada lado del pico
metodoInterpK = 'spline';

% Linealizacion en k con el mismo modelo que Penetration_Analysis.m:
%   lambda(pixel) = linspace(lambdaIni_nm, lambdaFin_nm, nPix), k = 2*pi/lambda
% La PSF solo depende del cociente lambdaFin/lambdaIni: escalar ambos por el
% mismo factor produce exactamente la misma FFT. Por eso se optimiza un solo
% grado de libertad (el ancho de banda) manteniendo fija un ancla:
%   'centro' : (lambdaIni+lambdaFin)/2 constante
%   'inicio' : lambdaIni constante
%   'fin'    : lambdaFin constante
anclaLambda = 'centro';
limiteCambioAncho_nm = 100;  % |cambio de lambdaFin-lambdaIni| maximo

% Etapa 1: se optimizan lambdaIni/lambdaFin sin dispersion (valores validos
% para Penetration_Analysis.m y Aline_FFT_Spectrum.m, que no compensan
% dispersion). Etapa 2: con esos lambdas fijos se optimizan D2 y D3.
% Los pasos se expresan como error de fase maximo [rad]; para el ancho de
% banda se convierten a nm segun la profundidad del pico.
pasosFase_rad = [20 10 5 2 1 0.5 0.2 0.1];
limiteDispersion_rad = 100;
% El error de fase de la linealizacion crece con la profundidad: cerca del
% retardo cero lambdaIni/lambdaFin no son observables y el pico se mezcla con
% el termino DC. Por debajo de estos umbrales se omite cada etapa.
profundidadMinK_um = 500;          % etapa 1 (lambdaIni/lambdaFin)
profundidadMinDispersion_um = 150; % etapa 2 (D2, D3)
semiBusquedaPico = 80;    % evita que el optimizador salte a otro reflector
limiteTeoricoFWHM_um = 8.49; % resolución axial mínima permitida por el espectro
limiteSuperiorFWHM_um = 16.00; % FWHM máximo aceptable
guardarParametros = true;

if isempty(archivoTDMS)
    carpetaInicial = 'C:\Users\proyecto.pi1081\Desktop\1310 OCT\Data\Spectrum';
    [nombre, carpeta] = uigetfile('*.tdms', ...
        'Select one TDMS acquisition containing 80 A-lines', carpetaInicial);
    if isequal(nombre, 0), error('No se selecciono ningun archivo.'); end
    archivoTDMS = fullfile(carpeta, nombre);
end
archivoTDMS = char(archivoTDMS);
if ~isfile(archivoTDMS), error('No existe el archivo: %s', archivoTDMS); end

%% Calibracion y parametros de adquisicion
[archivoCalibracion, C] = cargarCalibracion(archivoCalibracion, archivoTDMS);
nPix = obtenerCampo(C, 'nPix', 2048);
nFFT = obtenerCampo(C, 'nFFT', 8192);
lambdaIniCal_nm = obtenerCampo(C, 'lambdaIni_nm', 1263.88);
lambdaFinCal_nm = obtenerCampo(C, 'lambdaFin_nm', 1466.52);

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
limiteTeoricoFWHM_px = limiteTeoricoFWHM_um/umPorPx;
limiteSuperiorFWHM_px = limiteSuperiorFWHM_um/umPorPx;

%% Lectura de las 80 A-lines
raw = tdmsread(archivoTDMS, 'ChannelGroupName', "Acquisition", ...
    'ChannelNames', "Raw_B_scans");
x = double(raw{1}.Raw_B_scans(:));
nALinesDisponibles = floor(numel(x)/nPix);
if nALinesDisponibles < nALinesObjetivo
    error('%s contiene %d A-lines; se necesitan %d.', ...
        archivoTDMS, nALinesDisponibles, nALinesObjetivo);
end
if nALinesDisponibles > nALinesObjetivo
    warning('%s contiene %d A-lines; se usaran las primeras %d.', ...
        archivoTDMS, nALinesDisponibles, nALinesObjetivo);
end
M = reshape(x(1:nPix*nALinesDisponibles), nPix, nALinesDisponibles);
M = M(:, 1:nALinesObjetivo);

%% Preprocesamiento y optimizacion iterativa de k-linearization
S = M - mean(M, 1);
n = (0:nPix-1).';
ventanaHann = 0.5 - 0.5*cos(2*pi*n/(nPix-1));
nHalf = floor(nFFT/2);
pxAxis = (0:nHalf-1).';
z_um = pxAxis * umPorPx;

Qinicial = procesarConKDispersion(S, ventanaHann, nFFT, lambdaIniCal_nm, ...
    lambdaFinCal_nm, [0 0], metodoInterpK, pxMinBusqueda, semiVentanaAjuste, [], ...
    semiBusquedaPico);
if ~Qinicial.valido || ~isfinite(Qinicial.fwhmDirectoPx)
    error('No se pudo medir un FWHM inicial valido.');
end

% Parametros optimizados: x = [cambio de ancho de banda (nm), D2 (rad), D3 (rad)]
aLambdas = @(x) rangoEspectral(lambdaIniCal_nm, lambdaFinCal_nm, x(1), anclaLambda);
evaluar = @(x) evaluarCandidato(S, ventanaHann, nFFT, aLambdas(x), x(2:3), ...
    metodoInterpK, pxMinBusqueda, semiVentanaAjuste, Qinicial.iPicoHann, ...
    semiBusquedaPico, limiteTeoricoFWHM_px, limiteSuperiorFWHM_px);

% Un cambio de 1 nm en el ancho de banda desplaza el remuestreo como mucho
% dp pixeles (en el centro; los extremos no se mueven) y produce un error de
% fase 2*pi*f*dp, con f = pico/nFFT ciclos por muestra.
pf0 = pixelFuenteK(nPix, lambdaIniCal_nm, lambdaFinCal_nm);
lam1 = aLambdas([1 0 0]);
pf1 = pixelFuenteK(nPix, lam1(1), lam1(2));
radPorNm = 2*pi*(Qinicial.picoPx/nFFT)*max(abs(pf1-pf0));
pasosAncho_nm = pasosFase_rad(:)/radPorNm;
pasosCero = zeros(numel(pasosFase_rad), 1);
limites = [limiteCambioAncho_nm limiteDispersion_rad limiteDispersion_rad];

profundidadPicoInicial_um = Qinicial.picoPx*umPorPx;
optimizarK = profundidadPicoInicial_um >= profundidadMinK_um;
optimizarDisp = profundidadPicoInicial_um >= profundidadMinDispersion_um;
pasosEtapaK = [pasosAncho_nm pasosCero pasosCero];
pasosEtapaD = [pasosCero pasosFase_rad(:) pasosFase_rad(:)];
if ~optimizarK, pasosEtapaK = zeros(0, 3); end
if ~optimizarDisp, pasosEtapaD = zeros(0, 3); end

fprintf('\nPeak depth with calibration lambdas: %.1f um\n', profundidadPicoInicial_um);
fprintf('\n=== Stage 1: k-linearization (lambdaIni/lambdaFin, anchor = %s) ===\n', ...
    anclaLambda);
if ~optimizarK
    fprintf(['  Skipped: peak at %.0f um < %.0f um. At this depth lambdaIni/' ...
        'lambdaFin are not observable\n  (+/-%.0f nm of bandwidth changes the ' ...
        'phase by only %.2f rad). Calibration lambdas retained.\n'], ...
        profundidadPicoInicial_um, profundidadMinK_um, limiteCambioAncho_nm, ...
        radPorNm*limiteCambioAncho_nm);
end
[xK, fwhmK, histK] = busquedaPatron(evaluar, [0 0 0], Qinicial.fwhmDirectoPx, ...
    pasosEtapaK, limites, "k-linearization", 0, aLambdas);
fprintf('\n=== Stage 2: dispersion compensation (D2, D3) ===\n');
if ~optimizarDisp
    fprintf(['  Skipped: peak at %.0f um < %.0f um overlaps the DC term. ' ...
        'Zero dispersion correction retained.\n'], profundidadPicoInicial_um, ...
        profundidadMinDispersion_um);
end
[xOpt, ~, histD] = busquedaPatron(evaluar, xK, fwhmK, ...
    pasosEtapaD, limites, "dispersion", height(histK)-1, aLambdas);
if ~optimizarK || ~optimizarDisp
    warning(['The mirror is too close to zero delay (%.0f um) for a full ' ...
        'optimization.\nMove it to at least %.0f um (k-linearization) / %.0f um ' ...
        '(dispersion) and acquire again.'], profundidadPicoInicial_um, ...
        profundidadMinK_um, profundidadMinDispersion_um);
end
historial = [histK; histD];

lambdasOpt = aLambdas(xOpt);
lambdaIni_nm = lambdasOpt(1);
lambdaFin_nm = lambdasOpt(2);
coefDispersion = xOpt(2:3);
QsoloK = procesarConKDispersion(S, ventanaHann, nFFT, lambdaIni_nm, lambdaFin_nm, ...
    [0 0], metodoInterpK, pxMinBusqueda, semiVentanaAjuste, ...
    Qinicial.iPicoHann, semiBusquedaPico);
Q = procesarConKDispersion(S, ventanaHann, nFFT, lambdaIni_nm, lambdaFin_nm, ...
    coefDispersion, metodoInterpK, pxMinBusqueda, semiVentanaAjuste, ...
    Qinicial.iPicoHann, semiBusquedaPico);
if Q.fwhmDirectoPx < limiteTeoricoFWHM_px || ...
        Q.fwhmDirectoPx > limiteSuperiorFWHM_px
    error(['No se encontró una linealización válida con FWHM entre %.2f y %.2f um. ' ...
        'El mejor resultado disponible fue %.3f um.'], limiteTeoricoFWHM_um, ...
        limiteSuperiorFWHM_um, Q.fwhmDirectoPx*umPorPx);
end
Fhann = Q.Fhann;
picoPxHann = Q.picoPxHann;
picoPx = Q.picoPx;
xw = Q.xw;
yw = Q.yw;
fwhmDirectoPx = Q.fwhmDirectoPx;
xIzqPx = Q.xIzqPx;
xDerPx = Q.xDerPx;
nivelMitad = Q.nivelMitad;

%% Ajuste final del pico optimizado, sin ventana
p0Fwhm = fwhmDirectoPx;
if ~isfinite(p0Fwhm), p0Fwhm = 10; end
[~, iPicoLocal] = min(abs(xw-picoPx));
semiVentanaFit = max(8, ceil(2.5*fwhmDirectoPx));
idxFit = max(1,iPicoLocal-semiVentanaFit):min(numel(xw),iPicoLocal+semiVentanaFit);
xFitDatos = xw(idxFit);
yFitDatos = yw(idxFit);
nBordeFit = max(2, round(0.15*numel(yFitDatos)));
baseline0 = median([yFitDatos(1:nBordeFit); yFitDatos(end-nBordeFit+1:end)]);
p0 = [max(yFitDatos)-baseline0, picoPx, p0Fwhm, max(0,baseline0)];
pGauss = ajustarModelo(xFitDatos, yFitDatos, p0, 'gauss');
pSinc = ajustarModelo(xFitDatos, yFitDatos, p0, 'sinc');
R2Gauss = calcularR2(yFitDatos, modeloPico(pGauss, xFitDatos, 'gauss'));
R2Sinc = calcularR2(yFitDatos, modeloPico(pSinc, xFitDatos, 'sinc'));
if R2Sinc > R2Gauss
    p = pSinc; modeloElegido = "sinc"; R2 = R2Sinc;
else
    p = pGauss; modeloElegido = "gauss"; R2 = R2Gauss;
end

fwhmAjustePx = abs(p(3));
fwhmAjuste_um = fwhmAjustePx * umPorPx;
fwhmDirecto_um = fwhmDirectoPx * umPorPx;
pico_um = picoPx * umPorPx;
fwhmInicialPx = Qinicial.fwhmDirectoPx;
fwhmInicial_um = fwhmInicialPx * umPorPx;
mejoraFWHM_pct = 100*(fwhmInicialPx-fwhmDirectoPx)/fwhmInicialPx;
fwhmSoloK_um = QsoloK.fwhmDirectoPx * umPorPx;
if ~optimizarDisp
    estadoOptimizacion = "Not optimized: peak too close to zero delay";
elseif ~optimizarK
    estadoOptimizacion = "Dispersion only: peak too shallow for k-linearization";
elseif all(abs(xOpt) < 1e-12)
    estadoOptimizacion = "Calibration lambdas retained; zero dispersion correction";
else
    estadoOptimizacion = "Optimized lambdaIni/lambdaFin and dispersion correction applied";
end
ajusteConfiable = fwhmAjuste_um >= limiteTeoricoFWHM_um && R2 >= 0.9;
if ~ajusteConfiable
    warning(['The %s fit is not reliable (FWHM = %.2f um, R^2 = %.3f). ' ...
        'Use the direct FWHM.'], modeloElegido, fwhmAjuste_um, R2);
end

%% Resultado y figura
[~, nombreArchivo, extension] = fileparts(archivoTDMS);
nombreCompleto = [nombreArchivo extension];
parametrosSistema = construirParametrosSistema(nPix, lambdaIni_nm, lambdaFin_nm, ...
    coefDispersion, metodoInterpK, archivoTDMS, archivoCalibracion);
parametrosSistema.kLinearization.lambdaIniCalibracion_nm = lambdaIniCal_nm;
parametrosSistema.kLinearization.lambdaFinCalibracion_nm = lambdaFinCal_nm;
parametrosSistema.kLinearization.ancla = string(anclaLambda);
% Sin optimizacion no se sobrescriben parametros guardados previamente.
guardarParametros = guardarParametros && optimizarDisp;
if guardarParametros
    parametrosSistema = guardarParametrosSistema(parametrosSistema, ...
        fileparts(archivoTDMS), nombreArchivo);
end
resultado = table(string(nombreCompleto), nALinesObjetivo, picoPx, pico_um, ...
    fwhmInicialPx, fwhmInicial_um, fwhmSoloK_um, fwhmAjustePx, fwhmAjuste_um, ...
    fwhmDirectoPx, fwhmDirecto_um, mejoraFWHM_pct, ...
    lambdaIniCal_nm, lambdaFinCal_nm, lambdaIni_nm, lambdaFin_nm, ...
    coefDispersion(1), coefDispersion(2), ...
    parametrosSistema.dispersion.D2_um2, parametrosSistema.dispersion.D3_um3, ...
    limiteTeoricoFWHM_um, limiteSuperiorFWHM_um, modeloElegido, R2, umPorPx, ...
    estadoOptimizacion, string(archivoCalibracion), ...
    'VariableNames', {'Archivo','Numero_ALines','Pico_px','Pico_um', ...
    'FWHM_inicial_px','FWHM_inicial_um','FWHM_soloK_um','FWHM_ajuste_px', ...
    'FWHM_ajuste_um','FWHM_directo_px','FWHM_directo_um','Mejora_FWHM_pct', ...
    'LambdaIni_calibracion_nm','LambdaFin_calibracion_nm', ...
    'LambdaIni_optimo_nm','LambdaFin_optimo_nm', ...
    'Disp_D2_rad','Disp_D3_rad','Disp_D2_um2','Disp_D3_um3', ...
    'LimiteInferior_um','LimiteSuperior_um','ModeloAjuste','R2','umPorPx', ...
    'EstadoOptimizacion','ArchivoCalibracion'});
resultado.Properties.UserData.HistorialOptimizacion = historial;
resultado.Properties.UserData.ParametrosSistema = parametrosSistema;

fprintf('\n=== FWHM from 80 A-lines ===\n');
fprintf('File              : %s\n', archivoTDMS);
fprintf('Calibration       : %s\n', archivoCalibracion);
fprintf('Theoretical limit : %.3f um (%.3f px)\n', ...
    limiteTeoricoFWHM_um, limiteTeoricoFWHM_px);
fprintf('Upper FWHM limit  : %.3f um (%.3f px)\n', ...
    limiteSuperiorFWHM_um, limiteSuperiorFWHM_px);
fprintf('\nk-linearization (lambda linear in pixel, anchor = %s)\n', anclaLambda);
fprintf('  lambdaIni_nm    : %.3f -> %.3f nm\n', lambdaIniCal_nm, lambdaIni_nm);
fprintf('  lambdaFin_nm    : %.3f -> %.3f nm\n', lambdaFinCal_nm, lambdaFin_nm);
fprintf('  Bandwidth       : %.3f -> %.3f nm\n', lambdaFinCal_nm-lambdaIniCal_nm, ...
    lambdaFin_nm-lambdaIni_nm);
fprintf('  Penetration_Analysis.m : lambdaIni_nm = %.2f; lambdaFin_nm = %.2f;\n', ...
    lambdaIni_nm, lambdaFin_nm);
fprintf('  Aline_FFT_Spectrum.m   : lambdaIni_um = %.5f; lambdaFin_um = %.5f;\n', ...
    lambdaIni_nm/1000, lambdaFin_nm/1000);
fprintf('\nDispersion (applied after k-linearization)\n');
fprintf('  Normalized      : D2 = %+.3f rad, D3 = %+.3f rad\n', ...
    coefDispersion(1), coefDispersion(2));
fprintf('  Physical        : D2 = %+.6g um^2, D3 = %+.6g um^3\n', ...
    parametrosSistema.dispersion.D2_um2, parametrosSistema.dispersion.D3_um3);
fprintf('\nDirect FWHM\n');
fprintf('  Calibration lambdas     : %.3f px = %.3f um\n', fwhmInicialPx, fwhmInicial_um);
fprintf('  Optimized lambdas       : %.3f px = %.3f um\n', ...
    QsoloK.fwhmDirectoPx, fwhmSoloK_um);
fprintf('  + dispersion correction : %.3f px = %.3f um\n', ...
    fwhmDirectoPx, fwhmDirecto_um);
fprintf('  Total improvement       : %.2f %%\n', mejoraFWHM_pct);
fprintf('%-8s fit FWHM    : %.3f px = %.3f um (R^2 = %.5f)%s\n', ...
    char(modeloElegido), fwhmAjustePx, fwhmAjuste_um, R2, ...
    repmat(' <- UNRELIABLE', 1, ~ajusteConfiable));
fprintf('Peak depth        : %.2f um\n', pico_um);
fprintf('Optimization      : %s\n\n', estadoOptimizacion);
if guardarParametros
    fprintf('Defaults MAT      : %s\n', parametrosSistema.export.matFile);
    fprintf('K LUT CSV         : %s\n\n', parametrosSistema.export.csvFile);
end

fig = figure('Color', 'w', 'Name', ['FWHM - ' nombreCompleto], ...
    'NumberTitle', 'off', 'Position', [50 50 1450 850]);
tl = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

ax1 = nexttile(tl, [1 2]);
% Normalizado al pico del reflector (0 dB), no al residuo de DC.
fft_dB = 20*log10(max(Fhann, eps));
fft_dB = fft_dB - interp1(pxAxis, fft_dB, picoPxHann);
fftInicial_dB = 20*log10(max(Qinicial.Fhann, eps));
fftInicial_dB = fftInicial_dB - interp1(pxAxis, fftInicial_dB, Qinicial.picoPxHann);
plot(ax1, z_um, fftInicial_dB, '--', 'Color', [0.55 0.55 0.55], 'LineWidth', 1);
hold(ax1, 'on');
plot(ax1, z_um, fft_dB, 'Color', [0.05 0.35 0.70], 'LineWidth', 1);
plot(ax1, picoPxHann*umPorPx, interp1(pxAxis, fft_dB, picoPxHann), ...
    'o', 'Color', [0.85 0.20 0.10], 'MarkerFaceColor', [1.00 0.75 0.10]);
xlabel(ax1, 'Depth [\mum]');
ylabel(ax1, 'Normalized FFT amplitude [dB]');
title(ax1, sprintf('Iterative k-linearization: FWHM improvement %.1f%%', mejoraFWHM_pct));
legend(ax1, sprintf('Calibration: %.2f-%.2f nm', lambdaIniCal_nm, lambdaFinCal_nm), ...
    sprintf('Optimized: %.2f-%.2f nm + dispersion', lambdaIni_nm, lambdaFin_nm), ...
    'Optimized peak', 'Location', 'best');
grid(ax1, 'on');

ax2 = nexttile(tl);
plot(ax2, xw*umPorPx, yw, '.', 'Color', [0.35 0.35 0.35], 'MarkerSize', 8);
hold(ax2, 'on');
xf = linspace(xFitDatos(1), xFitDatos(end), 800).';
plot(ax2, xf*umPorPx, modeloPico(p, xf, modeloElegido), 'r-', 'LineWidth', 1.5);
if isfinite(fwhmDirectoPx)
    plot(ax2, [xIzqPx xDerPx]*umPorPx, [nivelMitad nivelMitad], ...
        'g-', 'LineWidth', 2);
end
xlabel(ax2, 'Depth [\mum]');
ylabel(ax2, '|FFT| [a.u.]');
title(ax2, sprintf('Unwindowed peak: %s FWHM = %.2f \\mum', ...
    modeloElegido, fwhmAjuste_um));
legend(ax2, 'Mean |FFT|', [char(modeloElegido) ' fit'], 'Direct half-maximum', ...
    'Location', 'best');
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
resumen = sprintf(['Optimal parameters\n\\lambda_{ini} = %.2f nm\n' ...
    '\\lambda_{fin} = %.2f nm\nD_2 = %+.3f rad\nD_3 = %+.3f rad\n' ...
    'Final FWHM = %.3f \\mum\nImprovement = %.2f%%'], lambdaIni_nm, ...
    lambdaFin_nm, coefDispersion(1), coefDispersion(2), fwhmDirecto_um, ...
    mejoraFWHM_pct);
% El recuadro se coloca en la mitad vertical opuesta a la curva final.
limY = ylim(ax3);
if (fwhmDirecto_um-limY(1))/diff(limY) > 0.5
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

function valor = obtenerCampo(S, nombre, valorDefault)
    if isfield(S, nombre), valor = S.(nombre); else, valor = valorDefault; end
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

function fwhm = evaluarCandidato(S, ventanaHann, nFFT, lambdas, coefDisp, ...
        metodoInterpK, pxMinBusqueda, semiVentanaAjuste, iPicoReferencia, ...
        semiBusquedaPico, fwhmMinimoPx, fwhmMaximoPx)
% FWHM directo del candidato, o NaN si no es valido o sale del rango fisico.
    Q = procesarConKDispersion(S, ventanaHann, nFFT, lambdas(1), lambdas(2), ...
        coefDisp, metodoInterpK, pxMinBusqueda, semiVentanaAjuste, ...
        iPicoReferencia, semiBusquedaPico);
    fwhm = Q.fwhmDirectoPx;
    if ~Q.valido || ~isfinite(fwhm) || fwhm < fwhmMinimoPx || fwhm > fwhmMaximoPx
        fwhm = NaN;
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

function Sa = senalAnalitica(S)
% Senal analitica por columnas (equivalente a hilbert(S), sin toolbox). Se
% conservan solo las frecuencias positivas, escaladas por 2 para que |FFT|
% del lado positivo coincida con la de la senal real.
    n = size(S,1);
    h = zeros(n,1);
    h(1) = 1;
    if mod(n,2) == 0
        h(2:n/2) = 2;
        h(n/2+1) = 1;
    else
        h(2:(n+1)/2) = 2;
    end
    Sa = ifft(fft(S).*h)/2;
end

function fase = faseDispersion(nPix, coefDisp)
% Fase de compensacion sobre el eje k uniforme (orden ascendente), con
% q = (k-k0)/(Dk/2) en [-1, 1]. Se aplica como S .* exp(-1i*fase).
    q = linspace(-1, 1, nPix).';
    fase = coefDisp(1)*q.^2 + coefDisp(2)*q.^3;
end

function Q = procesarConKDispersion(S, ventanaHann, nFFT, lambdaIni_nm, ...
        lambdaFin_nm, coefDisp, metodoInterpK, pxMinBusqueda, ...
        semiVentanaAjuste, iPicoReferencia, semiBusquedaPico)
% Linealiza en k como Penetration_Analysis.m (lambda lineal en pixel),
% compensa la dispersion y mide FWHM.
    Q = struct('valido',false, 'Fhann',[], 'Frect',[], 'picoPxHann',NaN, ...
        'iPicoHann',NaN, 'picoPx',NaN, 'iPico',NaN, 'xw',[], 'yw',[], ...
        'fwhmDirectoPx',NaN, 'xIzqPx',NaN, 'xDerPx',NaN, 'nivelMitad',NaN, ...
        'fwhmRapidoPx',NaN, 'R2Rapido',NaN);
    nPix = size(S,1);
    if ~(lambdaIni_nm > 0 && lambdaFin_nm > lambdaIni_nm), return; end
    lambda_nm = linspace(lambdaIni_nm, lambdaFin_nm, nPix).';
    kPix = flipud(2*pi ./ lambda_nm);
    kUniforme = linspace(kPix(1), kPix(end), nPix).';
    try
        Slineal = interp1(kPix, flipud(S), kUniforme, metodoInterpK);
    catch
        return;
    end
    if any(~isfinite(Slineal(:))), return; end
    if any(coefDisp ~= 0)
        % La fase se aplica a la senal analitica: sobre la senal real, la
        % imagen espejo recibiria el doble de fase y se ensancharia sobre el
        % pico y el piso de ruido.
        Slineal = senalAnalitica(Slineal) .* exp(-1i*faseDispersion(nPix, coefDisp));
    end

    nHalf = floor(nFFT/2);
    Fhann = mean(abs(fft(Slineal .* ventanaHann, nFFT)), 2);
    Frect = mean(abs(fft(Slineal, nFFT)), 2);
    Fhann = Fhann(1:nHalf);
    Frect = Frect(1:nHalf);
    pxAxis = (0:nHalf-1).';

    if isempty(iPicoReferencia)
        rango = (max(1,pxMinBusqueda):nHalf-2) + 1;
    else
        rango = max(pxMinBusqueda+1, iPicoReferencia-semiBusquedaPico): ...
            min(nHalf-1, iPicoReferencia+semiBusquedaPico);
    end
    if numel(rango) < 3, return; end
    [picoPxHann, iPicoHann] = buscarPico(pxAxis, Fhann, rango);
    rangoRect = max(2,iPicoHann-5):min(nHalf-1,iPicoHann+5);
    [picoPx, iPico] = buscarPico(pxAxis, Frect, rangoRect);

    i0 = max(pxMinBusqueda+1, iPico-semiVentanaAjuste);
    i1 = min(nHalf-1, iPico+semiVentanaAjuste);
    xw = pxAxis(i0:i1);
    yw = Frect(i0:i1);
    [fwhm, xL, xR, h] = medirFWHMDirecto(xw, yw, iPico-i0+1);
    [fwhmRapido, r2Rapido] = ajusteGaussianoRapido(xw, yw, iPico-i0+1);
    Q = struct('valido',isfinite(fwhm), ...
        'Fhann',Fhann, 'Frect',Frect, ...
        'picoPxHann',picoPxHann, 'iPicoHann',iPicoHann, 'picoPx',picoPx, ...
        'iPico',iPico, 'xw',xw, 'yw',yw, 'fwhmDirectoPx',fwhm, ...
        'xIzqPx',xL, 'xDerPx',xR, 'nivelMitad',h, ...
        'fwhmRapidoPx',fwhmRapido, 'R2Rapido',r2Rapido);
end

function P = construirParametrosSistema(nPix, lambdaIni_nm, lambdaFin_nm, ...
        coefDisp, metodoInterpK, archivoTDMS, archivoCalibracion)
% Reune la LUT de k-linearization y la fase de dispersion con las mismas
% convenciones usadas en procesarConKDispersion.
    lambda_nm = linspace(lambdaIni_nm, lambdaFin_nm, nPix).';
    t = (0:nPix-1).'/(nPix-1);
    kCamara_radum = 2*pi ./ (lambda_nm*1e-3);          % orden de camara
    kAsc = flipud(kCamara_radum);
    kUniforme_radum = linspace(kAsc(1), kAsc(end), nPix).';
    pixelFuente = pixelFuenteK(nPix, lambdaIni_nm, lambdaFin_nm);

    k0_radum = (kUniforme_radum(1)+kUniforme_radum(end))/2;
    semiRangoK_radum = (kUniforme_radum(end)-kUniforme_radum(1))/2;
    fase_rad = faseDispersion(nPix, coefDisp);

    P = struct();
    P.descripcion = ['Parametros de procesamiento OCT: k-linearization y ' ...
        'compensacion numerica de dispersion optimizadas por FWHM_80_ALines.m'];
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
        'k = 2*pi/lambda; remuestreo a k uniforme (como Penetration_Analysis.m)'];
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
                'Penetration_Analysis.m o indique archivoCalibracion.']);
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

function [px, i] = buscarPico(x, y, rango)
    [~, q] = max(y(rango));
    i = rango(q);
    v = 20*log10(max(y(i-1:i+1), eps));
    den = v(1)-2*v(2)+v(3);
    if den == 0
        px = x(i);
    else
        px = x(i) + 0.5*(v(1)-v(3))/den;
    end
end

function [fwhm, r2] = ajusteGaussianoRapido(x, y, iPico)
% Ajuste cuadratico de log(y-baseline) para rechazar picos espurios estrechos.
    nBorde = max(3, round(0.1*numel(y)));
    baseline = median([y(1:nBorde); y(end-nBorde+1:end)]);
    yc = y-baseline;
    altura = yc(iPico);
    fwhm = NaN; r2 = NaN;
    if ~isfinite(altura) || altura <= 0, return; end
    umbral = 0.10*altura;
    L = iPico;
    while L > 1 && yc(L) > umbral, L = L-1; end
    R = iPico;
    while R < numel(y) && yc(R) > umbral, R = R+1; end
    ids = (L+1):(R-1);
    if numel(ids) < 5, return; end
    xc = x(ids)-x(iPico);
    logy = log(max(yc(ids), altura*1e-6));
    pr = polyfit(xc, logy, 2);
    if ~isfinite(pr(1)) || pr(1) >= 0, return; end
    logFit = polyval(pr, xc);
    sst = sum((logy-mean(logy)).^2);
    if sst <= 0, return; end
    r2 = 1-sum((logy-logFit).^2)/sst;
    fwhm = sqrt(-4*log(2)/pr(1));
end

function [fwhm, xL, xR, h] = medirFWHMDirecto(x, y, iPico)
    nBorde = max(3, round(0.1*numel(y)));
    baseline = median([y(1:nBorde); y(end-nBorde+1:end)]);
    h = baseline + (y(iPico)-baseline)/2;
    L = iPico;
    while L > 1 && y(L) > h, L = L-1; end
    R = iPico;
    while R < numel(y) && y(R) > h, R = R+1; end
    if L == 1 || R == numel(y)
        fwhm = NaN; xL = NaN; xR = NaN;
        return;
    end
    xL = interpCruce(y(L), y(L+1), x(L), x(L+1), h);
    xR = interpCruce(y(R-1), y(R), x(R-1), x(R), h);
    fwhm = xR-xL;
end

function xh = interpCruce(y1, y2, x1, x2, h)
    if y2 == y1, xh = mean([x1 x2]); else, xh = x1+(h-y1)*(x2-x1)/(y2-y1); end
end

function p = ajustarModelo(x, y, p0, modelo)
    ancho = x(end)-x(1);
    lb = [0, x(1), 0.5, 0];
    ub = [2*max(y), x(end), ancho, max(y)];
    p0 = min(max(p0, lb), ub);
    objetivo = @(q) sum((y-modeloPico(q,x,modelo)).^2) + ...
        1e30*any(q < lb | q > ub);
    opciones = optimset('Display','off', 'MaxIter',2e4, 'MaxFunEvals',2e4, ...
        'TolX',1e-7, 'TolFun',1e-9);
    p = fminsearch(objetivo, p0, opciones);
end

function y = modeloPico(p, x, modelo)
    u = (x-p(2))/abs(p(3));
    switch lower(char(modelo))
        case 'gauss'
            y = p(1)*exp(-4*log(2)*u.^2) + p(4);
        case 'sinc'
            y = p(1)*abs(sincNormalizada(2*0.603355*u)) + p(4);
        otherwise
            error('Modelo no reconocido: %s', modelo);
    end
end

function y = sincNormalizada(x)
    y = ones(size(x));
    nz = x ~= 0;
    y(nz) = sin(pi*x(nz))./(pi*x(nz));
end

function r2 = calcularR2(y, yf)
    sst = sum((y-mean(y)).^2);
    if sst == 0, r2 = NaN; else, r2 = 1-sum((y-yf).^2)/sst; end
end
