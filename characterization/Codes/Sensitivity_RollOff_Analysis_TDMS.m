%% Sensitivity_RollOff_Analysis.m
% Sensibilidad y roll-off del OCT de 1310 nm. Cada archivo "<d>um.tdms" es el
% espejo (atenuado con un filtro ND) en la posición <d> um del micrómetro.
%
%   SNR           = 20*log10( pico |FFT| / sigma_ruido )     (|FFT| es amplitud)
%   Sensibilidad  = SNR + atenuación ida y vuelta del ND (potencia, 10*OD por paso)
%
% El ruido sigma se mide en el mismo bin de profundidad que el pico, pero en las
% OTRAS mediciones (donde el espejo está lejos): desviación estándar de |FFT| a
% lo largo de las A-lines. Así se usa ruido real a esa profundidad y se eliminan
% los artefactos fijos (fuga del DC, patrón de la cámara).
%
% Estructura TDMS: grupo "Acquisition", canal "Raw_B_scans" (int16),
% nPix x nLines muestras concatenadas (2048 px por A-line).

clear; close all; clc;

%% ======================= LINEALIZACIÓN EN K =============================
usarLinealK      = true;       % remuestrea el espectro a k uniforme antes de la FFT
lambdaIni_nm     = 1262.13;    % longitud de onda en el píxel 1 [nm]
lambdaFin_nm     = 1470.01;    % longitud de onda en el píxel nPix [nm] (lineal en píxel)
metodoInterpK    = 'spline';   % 'spline', 'pchip', 'linear' (interp1)

%% ======================= ATENUACIÓN (FILTRO ND) =========================
filtroND         = 'NENIR506A-C';
OD_filtro        = 1.02;       % densidad óptica a 1310 nm (nominal 0.6; ~1.02 medido a 1310 nm)
pasesFiltro      = 2;          % 2 = el haz cruza el filtro de ida y de vuelta
atenuacion_dB    = 10*OD_filtro*pasesFiltro;   % atenuación total en potencia [dB]

%% ======================= PARÁMETROS DE USUARIO ==========================
carpeta          = '';       % carpeta con los .tdms ('' = elegirla con un diálogo)
archivoCalib     = '';       % Penetration_resultados.mat con el px/um. '' = buscarlo en
                             % ../Penetration de la carpeta elegida; si no está, se pide con
                             % un diálogo (Cancelar = calibrar con esta misma carpeta)
nPix             = 2048;     % píxeles por A-line (cámara)
nFFT             = 8192;     % puntos de la FFT (zero-padding)
usarHanning      = true;     % true: ventana Hanning. Sin ventana, la fuga fluctuante del DC
                             % sube el ruido 7-10 dB en las primeras profundidades
promediarALines  = true;     % true : señal = promedio de los picos de todas las A-lines
                             % false: señal = pico de la A-line indiceALine
indiceALine      = 40;
pxMinBusqueda    = 25;       % ignora bins cercanos al DC al buscar el pico
pxMaxBusqueda    = 4000;     % ignora el artefacto cerca de Nyquist (bin 4096)

semiBandaRuido   = 25;       % bins a cada lado del pico usados para estimar el ruido
exclusionRuido   = 200;      % sólo usa mediciones cuyo espejo esté a > este # de bins

caidaObjetivo_dB = -10;      % nivel de caída a marcar
rollOffDe        = 'senal';  % 'senal': roll-off = caída del pico (lo que modela el espectrómetro)
                             % 'sensibilidad': roll-off = caída de la sensibilidad (SNR local);
                             %   el ruido medido también baja con z, así que cae menos
zmaxLibre       = false;    % ajuste teórico: false = zmax fijo por la calibración

%% ============================ LECTURA ===================================
if isempty(carpeta)
    carpeta = uigetdir(fullfile(fileparts(mfilename('fullpath')), '..'), ...
        'Selecciona la carpeta con las mediciones de Sensibilidad / Roll-off (*um.tdms)');
    if isequal(carpeta, 0), error('No se seleccionó ninguna carpeta.'); end
end
fprintf('Carpeta de mediciones: %s\n', carpeta);
if isempty(archivoCalib)
    archivoCalib = fullfile(carpeta, '..', 'Penetration', 'Penetration_resultados.mat');
    if ~isfile(archivoCalib)
        [f, p] = uigetfile('*.mat', 'Selecciona Penetration_resultados.mat (Cancelar = calibración local)', ...
            fullfile(carpeta, '..'));
        if isequal(f, 0), archivoCalib = ''; else, archivoCalib = fullfile(p, f); end
    end
end
archivos = dir(fullfile(carpeta, '*um.tdms'));
if isempty(archivos), error('No se encontraron archivos *um.tdms en %s', carpeta); end
dMic = zeros(numel(archivos),1);
for k = 1:numel(archivos)
    tok = regexp(archivos(k).name, '^([\d\.]+)um\.tdms$', 'tokens', 'once');
    dMic(k) = str2double(tok{1});
end
[dMic, orden] = sort(dMic);
archivos = archivos(orden);
nMed = numel(archivos);

nHalf  = nFFT/2;
pxAxis = (0:nHalf-1).';                 % bin 0 = DC
if usarHanning
    win = hannWin(nPix);
else
    win = ones(nPix, 1);
end

lam  = linspace(lambdaIni_nm, lambdaFin_nm, nPix).';
kPix = flipud(2*pi ./ lam);                          % ascendente
kU   = linspace(kPix(1), kPix(end), nPix).';         % malla uniforme en k
if usarLinealK
    linK = @(S) interp1(kPix, flipud(S), kU, metodoInterpK);
else
    linK = @(S) S;
end

fprintf('Leyendo %d mediciones...\n', nMed);
Aline = cell(nMed,1);                   % |FFT| de cada A-line: nHalf x nLines
Amed  = zeros(nHalf, nMed);             % promedio de |FFT| (para detectar picos y graficar)
nLines = zeros(nMed,1);
for k = 1:nMed
    raw = tdmsread(fullfile(carpeta, archivos(k).name), ...
        'ChannelGroupName', "Acquisition", 'ChannelNames', "Raw_B_scans");
    x = double(raw{1}.Raw_B_scans);
    nLines(k) = floor(numel(x)/nPix);
    M = reshape(x(1:nLines(k)*nPix), nPix, nLines(k));
    S = linK(M - mean(M,1)) .* win;     % quita DC, lineal en k, ventana
    F = abs(fft(S, nFFT));
    Aline{k} = F(1:nHalf, :);
    Amed(:,k) = mean(Aline{k}, 2);
end
if ~promediarALines && indiceALine > min(nLines)
    error('indiceALine = %d supera el número de A-lines (%d).', indiceALine, min(nLines));
end
fprintf('A-lines por medición: %s | Hanning: %s | ND %s: OD %.2f x %d pases = %.1f dB\n', ...
    mat2str(unique(nLines).'), string(usarHanning), filtroND, OD_filtro, pasesFiltro, atenuacion_dB);

%% ======================= DETECCIÓN DE PICOS =============================
pkPx = zeros(nMed,1);  pkIdx = zeros(nMed,1);
rango = (pxMinBusqueda:pxMaxBusqueda) + 1;
for k = 1:nMed
    [pkPx(k), pkIdx(k)] = buscarPico(pxAxis, Amed(:,k), rango);
end
% Validación robusta: los picos deben seguir una recta vs el micrómetro
tolPx = 20;  semiBusq = 50;
[I, J] = find(triu(true(nMed), 1));
m0 = median((pkPx(J) - pkPx(I)) ./ (dMic(J) - dMic(I)));
pr = [m0, median(pkPx - m0*dMic)];
ok = abs(pkPx - polyval(pr, dMic)) < tolPx;
for it = 1:5
    pr = polyfit(dMic(ok), pkPx(ok), 1);
    okNuevo = abs(pkPx - polyval(pr, dMic)) < tolPx;
    if isequal(okNuevo, ok), break; end
    ok = okNuevo;
end
for k = find(~ok).'
    c = round(polyval(pr, dMic(k))) + 1;
    r = max(rango(1), c-semiBusq) : min(rango(end), c+semiBusq);
    [pkPx(k), pkIdx(k)] = buscarPico(pxAxis, Amed(:,k), r);
    fprintf('Aviso: pico de %s re-buscado cerca de px %d (máximo global no era el espejo)\n', ...
        archivos(k).name, c-1);
end

%% ======================= CALIBRACIÓN DE PROFUNDIDAD =====================
pLocal = polyfit(dMic, pkPx, 1);
if isfile(archivoCalib)
    C = load(archivoCalib, 'pxPorUm');
    pxPorUm = C.pxPorUm;
    fuenteCal = archivoCalib;
else
    pxPorUm = pLocal(1);
    fuenteCal = 'ajuste local (no se encontró Penetration_resultados.mat)';
end
umPorPx = 1/pxPorUm;
zReal   = pkPx * umPorPx;                              % profundidad desde el DC [um]
zmax_um = (nHalf - 1) * umPorPx;                       % profundidad máxima (Nyquist)
fprintf('\n=== Calibración ===\n');
fprintf('  %.5f px/um (%.4f um/px) desde %s\n', pxPorUm, umPorPx, fuenteCal);
fprintf('  Pendiente local de esta carpeta: %.5f px/um (diferencia %.2f %%)\n', ...
    pLocal(1), 100*(pLocal(1)/pxPorUm - 1));
fprintf('  Profundidad máxima z_max = %.1f um\n', zmax_um);

%% ========================= SEÑAL, RUIDO, SNR ============================
senal = zeros(nMed,1);  sigma = zeros(nMed,1);  pisoMedio = zeros(nMed,1);
nFuentes = zeros(nMed,1);
for k = 1:nMed
    i = pkIdx(k);
    % Señal: pico de cada A-line (máximo en +-2 bins del pico promedio)
    v = max(Aline{k}(i-2:i+2, :), [], 1);
    if promediarALines, senal(k) = mean(v); else, senal(k) = v(indiceALine); end

    % Ruido: mismo rango de bins en las mediciones con el espejo lejos
    b = max(2, i-semiBandaRuido) : min(nHalf, i+semiBandaRuido);
    otras = find(abs(pkIdx - i) > exclusionRuido);
    varTot = 0; medTot = 0;
    for q = otras.'
        A = Aline{q}(b, :);
        varTot = varTot + mean(var(A, 0, 2));   % varianza temporal por bin
        medTot = medTot + mean(A(:));
    end
    sigma(k)     = sqrt(varTot / numel(otras));
    pisoMedio(k) = medTot / numel(otras);
    nFuentes(k)  = numel(otras);
end
SNR_dB  = 20*log10(senal ./ sigma);
Sens_dB = SNR_dB + atenuacion_dB;

%% ============================ ROLL-OFF ==================================
zmm = zReal/1000;
Senal_dB = 20*log10(senal);
switch lower(rollOffDe)
    case 'senal',        RO_dB = Senal_dB - Senal_dB(1);   etRO = 'Señal (pico)';
    case 'sensibilidad', RO_dB = Sens_dB  - Sens_dB(1);    etRO = 'Sensibilidad';
    otherwise, error('rollOffDe debe ser ''senal'' o ''sensibilidad''.');
end
SensN_dB = Sens_dB - Sens_dB(1);
pLin     = polyfit(zmm, RO_dB, 1);                     % dB/mm (del roll-off elegido)
pLinSens = polyfit(zmm, Sens_dB, 1);
pLinSen  = polyfit(zmm, Senal_dB, 1);
[~, iCaida] = min(abs(RO_dB - caidaObjetivo_dB));
zCruce = NaN;
j = find(RO_dB <= caidaObjetivo_dB, 1);
if ~isempty(j) && j > 1
    zCruce = interp1(RO_dB(j-1:j), zReal(j-1:j), caidaObjetivo_dB);
end

% Modelo teórico del espectrómetro (Hu, Pan & Rollins, Appl. Opt. 46, 2007):
%   R(z) = sinc^2(zeta) * exp(-w^2 zeta^2 / (2 ln2)),  zeta = (pi/2) z/zmax
%   w = resolución espectral / separación entre píxeles. R está en potencia.
modeloRO = @(p, z) p(1) + 10*log10(sincZ(pi/2*z/p(3)).^2 .* ...
                   exp(-p(2)^2 * (pi/2*z/p(3)).^2 / (2*log(2))));
if zmaxLibre
    p0 = [0, 1, zmax_um];
    fobj = @(p) sum((RO_dB - modeloRO(p, zReal)).^2);
else
    p0 = [0, 1];
    fobj = @(p) sum((RO_dB - modeloRO([p zmax_um], zReal)).^2);
end
opts = optimset('Display', 'off', 'MaxFunEvals', 1e4, 'MaxIter', 1e4);
pT = fminsearch(fobj, p0, opts);
if ~zmaxLibre, pT = [pT zmax_um]; end
pT(2) = abs(pT(2));
zFino = linspace(0, pT(3), 1000).';
roTeo = modeloRO(pT, zFino);
rmsTeo = rms(RO_dB - modeloRO(pT, zReal));
z6dB  = interp1(roTeo - pT(1), zFino, -6, 'linear', NaN);
z10dB = interp1(roTeo - pT(1), zFino, caidaObjetivo_dB, 'linear', NaN);

[sMax, iMax] = max(Sens_dB);
fprintf('\n=== Sensibilidad (SNR con ruido local + ND) ===\n');
fprintf('  Máxima: %.1f dB  (%s, z = %.0f um)\n', sMax, archivos(iMax).name, zReal(iMax));
fprintf('  Primera medición: %.1f dB (SNR %.1f dB + ND %.1f dB)\n', Sens_dB(1), SNR_dB(1), atenuacion_dB);
fprintf('  Pendiente: sensibilidad %.2f dB/mm | señal %.2f dB/mm\n', pLinSens(1), pLinSen(1));
fprintf('\n=== Roll-off (%s) ===\n', etRO);
fprintf('  Pendiente lineal: %.2f dB/mm\n', pLin(1));
fprintf('  %g dB (rel. a la 1a medición): más cercana %s (%.1f dB, z = %.0f um)\n', ...
    caidaObjetivo_dB, archivos(iCaida).name, RO_dB(iCaida), zReal(iCaida));
if ~isnan(zCruce), fprintf('  Cruce interpolado a %g dB: z = %.0f um\n', caidaObjetivo_dB, zCruce); end
fprintf('  Ajuste teórico: omega = %.3f, z_max = %.0f um%s, RMS = %.2f dB\n', ...
    pT(2), pT(3), string(ifelse(zmaxLibre, ' (libre)', ' (fijo)')), rmsTeo);
fprintf('  Modelo: -6 dB en z = %.0f um, %g dB en z = %.0f um\n', z6dB, caidaObjetivo_dB, z10dB);

T = table(string({archivos.name}).', dMic, zReal, pkPx, Senal_dB, 20*log10(sigma), ...
          SNR_dB, Sens_dB, SensN_dB, RO_dB, nFuentes, ...
    'VariableNames', {'Archivo','Micrometro_um','Profundidad_um','Pico_px','Senal_dB', ...
                      'Ruido_sigma_dB','SNR_dB','Sensibilidad_dB','Sens_rel_dB', ...
                      'RollOff_dB','N_med_ruido'});
fprintf('\n=== Resultados por medición ===\n');
disp(T);

%% ============================== GRÁFICAS ================================
cmap  = turbo(nMed);
zAxis = pxAxis * umPorPx;

% 1) A-scans en escala de SNR (0 dB = sigma de ruido)
figure('Name','A-scans (SNR)','Color','w'); hold on;
sigmaRef = median(sigma);
for k = 1:nMed
    plot(zAxis, 20*log10(Amed(:,k)/sigmaRef), 'Color', [cmap(k,:) 0.7]);
end
plot(zReal, 20*log10(senal/sigmaRef), 'k.', 'MarkerSize', 14);
xlabel('Profundidad [\mum]'); ylabel('20 log_{10}(|FFT| / \sigma_{ruido}) [dB]');
title('A-scans promediadas (|FFT|) normalizadas al ruido');
xlim([0 zAxis(end)]); grid on; box on;
colormap(cmap); cb = colorbar; cb.Label.String = 'Lectura micrómetro [\mum]';
clim([dMic(1) dMic(end)]);

% 2) Roll-off (relativo a la primera medición)
figure('Name','Roll-off','Color','w');
plot(zReal, RO_dB, 'o', 'MarkerFaceColor', [0 0.45 0.74], 'MarkerSize', 7); hold on;
plot(zFino, polyval(pLin, zFino/1000), 'k--', 'LineWidth', 1);
plot(zFino, roTeo, 'r-', 'LineWidth', 1.5);
yline(caidaObjetivo_dB, 'm--', sprintf('%g dB', caidaObjetivo_dB), 'LineWidth', 1.2);
plot(zReal(iCaida), RO_dB(iCaida), 'mo', 'MarkerSize', 13, 'LineWidth', 2);
if ~isnan(zCruce), xline(zCruce, 'm:', sprintf('%.0f \\mum', zCruce)); end
xlabel('Profundidad [\mum]'); ylabel(sprintf('%s relativa [dB]', etRO));
title(sprintf('Roll-off (%s): %.2f dB/mm  |  modelo \\omega = %.2f, -6 dB en %.0f \\mum', ...
    etRO, pLin(1), pT(2), z6dB));
legend('Medido', sprintf('Lineal (%.2f dB/mm)', pLin(1)), 'Modelo teórico', ...
       'Location', 'southwest');
xlim([0 max(zReal)*1.1]); grid on;

% 2b) Sensibilidad absoluta
figure('Name','Sensibilidad','Color','w');
plot(zReal, Sens_dB, 'o-', 'MarkerFaceColor', [0.85 0.33 0.1], 'LineWidth', 1.3); hold on;
plot(zReal, polyval(pLinSens, zmm), 'k--');
xlabel('Profundidad [\mum]'); ylabel('Sensibilidad [dB]');
title(sprintf('Sensibilidad = SNR + %.1f dB (ND %s)  |  máx %.1f dB', ...
    atenuacion_dB, filtroND, sMax));
grid on;

% 3) Señal, ruido y SNR
figure('Name','Señal y ruido','Color','w');
tiledlayout(2,1);
nexttile;
plot(zReal, 20*log10(senal), 'o-', 'LineWidth', 1.3); hold on;
plot(zReal, 20*log10(sigma), 's-', 'LineWidth', 1.3);
plot(zReal, 20*log10(pisoMedio), '^--');
ylabel('20 log_{10}|FFT| [dB]'); legend('Señal (pico)', '\sigma ruido', 'Media del piso', ...
    'Location', 'east'); grid on; title('Señal y ruido');
nexttile;
plot(zReal, SNR_dB, 'o-', 'LineWidth', 1.3);
xlabel('Profundidad [\mum]'); ylabel('SNR [dB]'); grid on;

%% ============================== GUARDAR =================================
writetable(T, fullfile(carpeta, 'Sensitivity_RollOff_resultados.csv'));
save(fullfile(carpeta, 'Sensitivity_RollOff_resultados.mat'), 'T', 'pxPorUm', 'umPorPx', ...
    'pLin', 'pLinSens', 'pLinSen', 'rollOffDe', 'pT', 'zCruce', 'z6dB', 'z10dB', 'iCaida', 'atenuacion_dB', 'OD_filtro', ...
    'pasesFiltro', 'usarHanning', 'promediarALines', 'indiceALine', 'usarLinealK', ...
    'lambdaIni_nm', 'lambdaFin_nm', 'nFFT', 'nPix');
fprintf('\nResultados guardados en Sensitivity_RollOff_resultados.csv / .mat\n');

%% ======================== FUNCIONES LOCALES =============================
function w = hannWin(N)
    w = 0.5*(1 - cos(2*pi*(0:N-1).'/(N-1)));
end

% Máximo dentro de 'rango' (índices MATLAB) con refinamiento parabólico en dB
function [px, i] = buscarPico(x, y, rango)
    [~, i] = max(y(rango));
    i = rango(i);
    v = 20*log10(y(i-1:i+1));
    px = x(i) + 0.5*(v(1)-v(3)) / (v(1)-2*v(2)+v(3));
end

% sin(x)/x
function y = sincZ(x)
    y = ones(size(x));
    nz = x ~= 0;
    y(nz) = sin(x(nz)) ./ x(nz);
end

function out = ifelse(c, a, b)
    if c, out = a; else, out = b; end
end
