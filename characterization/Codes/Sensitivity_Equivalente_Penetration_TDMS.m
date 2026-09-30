%% Sensitivity_Equivalente_Penetration.m
% Genera los datos de sensibilidad / roll-off que se habrían medido con el
% filtro ND a partir de una adquisición de Penetration (sin ND), usando como
% referencia el par Penetration (diafragmas cerrados, sin ND) <-> Sensitivity_RollOff
% (diafragmas abiertos + ND). La diferencia medida entre ambos incluye el ND y
% la apertura de los diafragmas (~ -20.4 + 16 dB), así que la carpeta objetivo
% debe adquirirse con la misma configuración que la Penetration de referencia.
%
% 1) Las tres carpetas se procesan igual (k lineal, ventana, |FFT| por A-line).
% 2) Para cada profundidad de Sensitivity_RollOff se compara con Penetration
%    (interpolada a la misma z):
%       dSenal(z) = Senal_SR(z) - Senal_P(z)      (efecto del ND sobre la señal)
%       dRuido(z) = Ruido_SR(z) - Ruido_P(z)      (el ruido también depende de la
%                                                 potencia de muestra)
%    y se ajusta cada diferencia con una recta (o constante) en z.
% 3) Se aplica a la carpeta objetivo (p. ej. Penetration_3):
%       Senal_eq = Senal_obj + dSenal(z),  Ruido_eq = Ruido_obj + dRuido(z)
%       SNR_eq   = Senal_eq - Ruido_eq,    Sens_eq  = SNR_eq + atenuación ND
% 4) Se calcula el roll-off igual que en Sensitivity_RollOff_Analysis.m.
%
% Validación: aplicar la misma transformación a Penetration debe reproducir
% Sensitivity_RollOff; se reporta el error RMS.

clear; close all; clc;

%% ======================= LINEALIZACIÓN EN K =============================
usarLinealK      = true;       % remuestrea el espectro a k uniforme antes de la FFT
lambdaIni_nm     = 1262.34;    % longitud de onda en el píxel 1 [nm]
lambdaFin_nm     = 1471.08;    % longitud de onda en el píxel nPix [nm] (lineal en píxel)
metodoInterpK    = 'spline';   % 'spline', 'pchip', 'linear' (interp1)

%% ======================= ATENUACIÓN (FILTRO ND) =========================
filtroND         = 'NENIR506A-C';
OD_filtro        = 1.02;       % densidad óptica a 1310 nm
pasesFiltro      = 2;          % ida y vuelta
atenuacion_dB    = 10*OD_filtro*pasesFiltro;

%% ======================= CARPETAS ======================================
% '' = elegir con un diálogo
carpetaPen       = '';         % Penetration de referencia (sin ND)
carpetaSens      = '';         % Sensitivity_RollOff de referencia (con ND)
carpetaObjetivo  = '';         % Penetration a convertir (p. ej. Penetration_3)

%% ======================= PARÁMETROS DE USUARIO ==========================
nPix             = 2048;
nFFT             = 8192;
usarHanning      = true;       % igual que Sensitivity_RollOff_Analysis.m
pxMinBusqueda    = 25;
pxMaxBusqueda    = 4000;
semiBandaRuido   = 25;         % bins a cada lado del pico para estimar el ruido
exclusionRuido   = 200;        % sólo mediciones con el espejo a > este # de bins
modeloDelta      = 'lineal';   % 'lineal' o 'constante': cómo varían dSenal y dRuido con z
caidaObjetivo_dB = -10;
rollOffDe        = 'senal';    % 'senal' o 'sensibilidad' (igual que en el script de roll-off)
zmaxLibre        = false;

%% ======================= SELECCIÓN DE CARPETAS ==========================
raiz = fullfile(fileparts(mfilename('fullpath')), '..');
carpetaPen      = elegirCarpeta(carpetaPen,      raiz, 'Penetration de REFERENCIA (sin ND)');
carpetaSens     = elegirCarpeta(carpetaSens,     raiz, 'Sensitivity_RollOff de REFERENCIA (con ND)');
carpetaObjetivo = elegirCarpeta(carpetaObjetivo, raiz, 'Penetration a CONVERTIR (p. ej. Penetration_3)');
[~, nomObj] = fileparts(carpetaObjetivo);

%% ============================ PROCESADO =================================
cfg = struct('nPix', nPix, 'nFFT', nFFT, 'usarHanning', usarHanning, ...
    'usarLinealK', usarLinealK, 'lambdaIni_nm', lambdaIni_nm, 'lambdaFin_nm', lambdaFin_nm, ...
    'metodoInterpK', metodoInterpK, 'pxMinBusqueda', pxMinBusqueda, ...
    'pxMaxBusqueda', pxMaxBusqueda, 'semiBandaRuido', semiBandaRuido, ...
    'exclusionRuido', exclusionRuido);
P   = procesarCarpeta(carpetaPen,      cfg);
SR  = procesarCarpeta(carpetaSens,     cfg);
OBJ = procesarCarpeta(carpetaObjetivo, cfg);

%% ===================== TRANSFORMACIÓN P -> SR ===========================
% Penetration interpolada a las profundidades de Sensitivity_RollOff
% (se permite extrapolar hasta tolExtrap um fuera del rango de Penetration)
tolExtrap = 100;
enRango = SR.z >= min(P.z) - tolExtrap & SR.z <= max(P.z) + tolExtrap;
zR  = SR.z(enRango);
Pi  = @(y, z) interp1(P.z, y, z, 'pchip', 'extrap');
dS  = SR.senal_dB(enRango) - Pi(P.senal_dB, zR);
dN  = SR.ruido_dB(enRango) - Pi(P.ruido_dB, zR);
switch lower(modeloDelta)
    case 'lineal',    grado = 1;
    case 'constante', grado = 0;
    otherwise, error('modeloDelta debe ser ''lineal'' o ''constante''.');
end
pS = polyfit(zR/1000, dS, grado);
pN = polyfit(zR/1000, dN, grado);

% Validación: Penetration transformada vs Sensitivity_RollOff medida
valSen  = Pi(P.senal_dB, zR) + polyval(pS, zR/1000);
valRui  = Pi(P.ruido_dB, zR) + polyval(pN, zR/1000);
valSens = valSen - valRui + atenuacion_dB;
errSens = valSens - SR.sens_dB(enRango, atenuacion_dB);

fprintf('\n=== Transformación Penetration -> Sensitivity_RollOff (%d profundidades) ===\n', numel(zR));
fprintf('  dSeñal: media %.2f dB, std %.2f dB  | modelo %s: %s\n', mean(dS), std(dS), ...
    modeloDelta, polyStr(pS));
fprintf('  dRuido: media %.2f dB, std %.2f dB  | modelo %s: %s\n', mean(dN), std(dN), ...
    modeloDelta, polyStr(pN));
fprintf('  dSNR  : media %.2f dB\n', mean(dS - dN));
fprintf('  Atenuación del ND (OD %.2f x %d): %.1f dB -> diafragmas cerrados en Penetration: %.1f dB\n', ...
    OD_filtro, pasesFiltro, atenuacion_dB, atenuacion_dB + mean(dS));
fprintf('  Validación (Penetration transformada vs SR medida): RMS sensibilidad = %.2f dB\n', rms(errSens));

%% =================== DATOS EQUIVALENTES DEL OBJETIVO ====================
fueraRango = OBJ.z < min(zR) - tolExtrap | OBJ.z > max(zR) + tolExtrap;
if any(fueraRango)
    fprintf('Aviso: %d medición(es) de %s fuera del rango de la referencia; se extrapola.\n', ...
        nnz(fueraRango), nomObj);
end
eqSen   = OBJ.senal_dB + polyval(pS, OBJ.z/1000);
eqRui   = OBJ.ruido_dB + polyval(pN, OBJ.z/1000);
eqSNR   = eqSen - eqRui;
eqSens  = eqSNR + atenuacion_dB;
eqSensN = eqSens - eqSens(1);
switch lower(rollOffDe)
    case 'senal',        RO = eqSen - eqSen(1);  etRO = 'Señal (pico)';
    case 'sensibilidad', RO = eqSensN;           etRO = 'Sensibilidad';
    otherwise, error('rollOffDe debe ser ''senal'' o ''sensibilidad''.');
end
% Lo mismo para la referencia SR medida (para comparar en las gráficas)
srSens = SR.sens_dB(true(size(SR.z)), atenuacion_dB);
switch lower(rollOffDe)
    case 'senal',        RO_SR = SR.senal_dB - SR.senal_dB(1);
    case 'sensibilidad', RO_SR = srSens - srSens(1);
end

% Roll-off del objetivo
zmm   = OBJ.z/1000;
pLin  = polyfit(zmm, RO, 1);
pLinS = polyfit(zmm, eqSens, 1);
pLinR = polyfit(SR.z/1000, RO_SR, 1);
[~, iCaida] = min(abs(RO - caidaObjetivo_dB));
zCruce = cruce(RO, OBJ.z, caidaObjetivo_dB);
zCruceSR = cruce(RO_SR, SR.z, caidaObjetivo_dB);
zmax_um = (nFFT/2 - 1) / OBJ.pxPorUm;
[pT, roTeoFn] = ajustarRollOff(OBJ.z, RO, zmax_um, zmaxLibre);
zFino = linspace(0, pT(3), 1000).';
roTeo = roTeoFn(zFino);
z6dB  = interp1(roTeo - pT(1), zFino, -6, 'linear', NaN);
z10dB = interp1(roTeo - pT(1), zFino, caidaObjetivo_dB, 'linear', NaN);
[pTSR, roTeoFnSR] = ajustarRollOff(SR.z, RO_SR, (nFFT/2 - 1) / SR.pxPorUm, zmaxLibre);

fprintf('\n=== Sensibilidad equivalente de %s ===\n', nomObj);
[sMax, iMax] = max(eqSens);
fprintf('  Máxima: %.1f dB (%s, z = %.0f um)  | SR medida: %.1f dB\n', sMax, ...
    OBJ.archivos{iMax}, OBJ.z(iMax), max(srSens));
fprintf('  Pendiente: sensibilidad %.2f dB/mm | señal %.2f dB/mm\n', pLinS(1), ...
    polyfit(zmm, eqSen, 1)*[1;0]);
fprintf('\n=== Roll-off (%s) ===            %-14s  %-14s\n', etRO, nomObj, 'SR medida');
fprintf('  Pendiente lineal [dB/mm]       %-14.2f  %-14.2f\n', pLin(1), pLinR(1));
fprintf('  Cruce %g dB [um]              %-14.0f  %-14.0f\n', caidaObjetivo_dB, zCruce, zCruceSR);
fprintf('  Modelo omega                   %-14.3f  %-14.3f\n', pT(2), pTSR(2));
fprintf('  Modelo -6 dB [um]              %-14.0f\n', z6dB);
fprintf('  %g dB más cercano: %s (%.1f dB, z = %.0f um)\n', caidaObjetivo_dB, ...
    OBJ.archivos{iCaida}, RO(iCaida), OBJ.z(iCaida));

T = table(string(OBJ.archivos), OBJ.d, OBJ.z, OBJ.pkPx, eqSen, eqRui, eqSNR, eqSens, ...
          eqSensN, RO, OBJ.senal_dB, OBJ.ruido_dB, ...
    'VariableNames', {'Archivo','Micrometro_um','Profundidad_um','Pico_px','Senal_dB', ...
                      'Ruido_sigma_dB','SNR_dB','Sensibilidad_dB','Sens_rel_dB', ...
                      'RollOff_dB','Senal_sinND_dB','Ruido_sinND_dB'});
fprintf('\n=== Datos equivalentes (con ND) de %s ===\n', nomObj);
disp(T);

%% ============================== GRÁFICAS ================================
cP = [0.47 0.67 0.19]; cSR = [0 0.45 0.74]; cO = [0.85 0.33 0.10];

% 1) Transformación P -> SR
figure('Name','Transformación P -> SR','Color','w');
tiledlayout(2,1);
nexttile;
plot(P.z, P.senal_dB, '.-', 'Color', cP); hold on;
plot(SR.z, SR.senal_dB, 'o-', 'Color', cSR, 'MarkerFaceColor', cSR);
plot(zR, valSen, 'k+', 'MarkerSize', 8);
plot(P.z, P.ruido_dB, '.--', 'Color', cP);
plot(SR.z, SR.ruido_dB, 's--', 'Color', cSR);
ylabel('20 log_{10}|FFT| [dB]'); grid on;
legend('Señal P', 'Señal SR', 'P transformada', 'Ruido P', 'Ruido SR', 'Location', 'eastoutside');
title('Referencia: Penetration (sin ND) vs Sensitivity\_RollOff (con ND)');
nexttile;
zz = linspace(min(zR), max(zR), 100);
plot(zR, dS, 'o', 'Color', cSR, 'MarkerFaceColor', cSR); hold on;
plot(zz, polyval(pS, zz/1000), '-', 'Color', cSR);
plot(zR, dN, 's', 'Color', cO, 'MarkerFaceColor', cO);
plot(zz, polyval(pN, zz/1000), '-', 'Color', cO);
xlabel('Profundidad [\mum]'); ylabel('SR - P [dB]'); grid on;
legend('\Delta señal', 'ajuste', '\Delta ruido', 'ajuste', 'Location', 'eastoutside');

% 2) Roll-off equivalente vs SR medida
figure('Name','Roll-off equivalente','Color','w');
plot(OBJ.z, RO, 'o', 'Color', cO, 'MarkerFaceColor', cO, 'MarkerSize', 8); hold on;
plot(SR.z, RO_SR, 's', 'Color', cSR, 'MarkerFaceColor', cSR);
plot(zFino, roTeo, '-', 'Color', cO, 'LineWidth', 1.5);
zf2 = linspace(0, max(SR.z)*1.05, 500).';
plot(zf2, roTeoFnSR(zf2), '-', 'Color', cSR, 'LineWidth', 1);
yline(caidaObjetivo_dB, 'm--', sprintf('%g dB', caidaObjetivo_dB), 'LineWidth', 1.2);
if ~isnan(zCruce), xline(zCruce, ':', sprintf('%.0f \\mum', zCruce), 'Color', cO); end
xlabel('Profundidad [\mum]'); ylabel(sprintf('%s relativa [dB]', etRO));
title(sprintf('Roll-off (%s): %s %.2f dB/mm  vs  SR medida %.2f dB/mm', ...
    etRO, strrep(nomObj,'_','\_'), pLin(1), pLinR(1)));
legend(sprintf('%s equivalente', strrep(nomObj,'_','\_')), 'SR medida', ...
    sprintf('Modelo %s (\\omega=%.2f)', strrep(nomObj,'_','\_'), pT(2)), ...
    sprintf('Modelo SR (\\omega=%.2f)', pTSR(2)), 'Location', 'southwest');
xlim([0 max([OBJ.z; SR.z])*1.1]); grid on;

% 3) Sensibilidad absoluta
figure('Name','Sensibilidad equivalente','Color','w');
plot(OBJ.z, eqSens, 'o-', 'Color', cO, 'MarkerFaceColor', cO, 'LineWidth', 1.3); hold on;
plot(SR.z, srSens, 's-', 'Color', cSR, 'MarkerFaceColor', cSR);
plot(zR, valSens, 'k+', 'MarkerSize', 8);
xlabel('Profundidad [\mum]'); ylabel('Sensibilidad [dB]'); grid on;
legend(sprintf('%s equivalente', strrep(nomObj,'_','\_')), 'SR medida', ...
    sprintf('P transformada (RMS %.2f dB)', rms(errSens)), 'Location', 'southwest');
title(sprintf('Sensibilidad = SNR + %.1f dB (ND %s)', atenuacion_dB, filtroND));

%% ============================== GUARDAR =================================
nomCsv = fullfile(carpetaObjetivo, 'Sensitivity_RollOff_equivalente.csv');
writetable(T, nomCsv);
save(fullfile(carpetaObjetivo, 'Sensitivity_RollOff_equivalente.mat'), 'T', 'pS', 'pN', ...
    'modeloDelta', 'pLin', 'pLinS', 'pT', 'zCruce', 'z6dB', 'z10dB', 'atenuacion_dB', ...
    'OD_filtro', 'pasesFiltro', 'carpetaPen', 'carpetaSens', 'carpetaObjetivo', ...
    'usarHanning', 'usarLinealK', 'lambdaIni_nm', 'lambdaFin_nm', 'rollOffDe');
fprintf('\nResultados guardados en %s (.csv / .mat)\n', nomCsv(1:end-4));

%% ======================== FUNCIONES LOCALES =============================
function c = elegirCarpeta(c, raiz, texto)
    if isempty(c)
        c = uigetdir(raiz, ['Selecciona la carpeta: ' texto]);
        if isequal(c, 0), error('No se seleccionó la carpeta: %s', texto); end
    end
    fprintf('%-45s %s\n', [texto ':'], c);
end

% Lee todos los *um.tdms de una carpeta y devuelve señal y ruido por medición
function R = procesarCarpeta(carpeta, cfg)
    fs = dir(fullfile(carpeta, '*um.tdms'));
    if isempty(fs), error('No se encontraron archivos *um.tdms en %s', carpeta); end
    d = zeros(numel(fs),1);
    for k = 1:numel(fs)
        tok = regexp(fs(k).name, '^([\d\.]+)um\.tdms$', 'tokens', 'once');
        d(k) = str2double(tok{1});
    end
    [d, o] = sort(d);  fs = fs(o);  n = numel(fs);

    nHalf = cfg.nFFT/2;  pxAxis = (0:nHalf-1).';
    if cfg.usarHanning, win = hannWin(cfg.nPix); else, win = ones(cfg.nPix,1); end
    lam  = linspace(cfg.lambdaIni_nm, cfg.lambdaFin_nm, cfg.nPix).';
    kPix = flipud(2*pi ./ lam);
    kU   = linspace(kPix(1), kPix(end), cfg.nPix).';

    A = cell(n,1);  Amed = zeros(nHalf, n);
    for k = 1:n
        raw = tdmsread(fullfile(carpeta, fs(k).name), ...
            'ChannelGroupName', "Acquisition", 'ChannelNames', "Raw_B_scans");
        x = double(raw{1}.Raw_B_scans);
        nL = floor(numel(x)/cfg.nPix);
        M = reshape(x(1:nL*cfg.nPix), cfg.nPix, nL);
        S = M - mean(M,1);
        if cfg.usarLinealK, S = interp1(kPix, flipud(S), kU, cfg.metodoInterpK); end
        F = abs(fft(S .* win, cfg.nFFT));
        A{k} = F(1:nHalf, :);
        Amed(:,k) = mean(A{k}, 2);
    end

    % Picos con validación robusta (Theil-Sen + re-búsqueda)
    rango = (cfg.pxMinBusqueda:cfg.pxMaxBusqueda) + 1;
    pkPx = zeros(n,1);  pkIdx = zeros(n,1);
    for k = 1:n, [pkPx(k), pkIdx(k)] = buscarPico(pxAxis, Amed(:,k), rango); end
    if n >= 3
        [I, J] = find(triu(true(n), 1));
        m0 = median((pkPx(J) - pkPx(I)) ./ (d(J) - d(I)));
        pr = [m0, median(pkPx - m0*d)];
        ok = abs(pkPx - polyval(pr, d)) < 20;
        for it = 1:5
            pr = polyfit(d(ok), pkPx(ok), 1);
            okN = abs(pkPx - polyval(pr, d)) < 20;
            if isequal(okN, ok), break; end
            ok = okN;
        end
        for k = find(~ok).'
            c = round(polyval(pr, d(k))) + 1;
            r = max(rango(1), c-50) : min(rango(end), c+50);
            [pkPx(k), pkIdx(k)] = buscarPico(pxAxis, Amed(:,k), r);
        end
    end
    pr = polyfit(d, pkPx, 1);

    % Señal (media de los picos por A-line) y ruido (sigma temporal en las otras mediciones)
    senal = zeros(n,1);  sigma = zeros(n,1);
    for k = 1:n
        i = pkIdx(k);
        senal(k) = mean(max(A{k}(i-2:i+2, :), [], 1));
        b = max(2, i-cfg.semiBandaRuido) : min(nHalf, i+cfg.semiBandaRuido);
        otras = find(abs(pkIdx - i) > cfg.exclusionRuido);
        v = 0;
        for q = otras.', v = v + mean(var(A{q}(b,:), 0, 2)); end
        sigma(k) = sqrt(v / numel(otras));
    end

    R.archivos = {fs.name}.';
    R.d        = d;
    R.pkPx     = pkPx;
    R.pxPorUm  = pr(1);
    R.z        = pkPx / pr(1);
    R.senal_dB = 20*log10(senal);
    R.ruido_dB = 20*log10(sigma);
    R.sens_dB  = @(sel, att) R.senal_dB(sel) - R.ruido_dB(sel) + att;
    fprintf('  %-22s %2d mediciones, %.5f px/um\n', [fileparts_name(carpeta) ':'], n, pr(1));
end

function s = fileparts_name(c)
    [~, s] = fileparts(c);
end

function [px, i] = buscarPico(x, y, rango)
    [~, i] = max(y(rango));
    i = rango(i);
    v = 20*log10(y(i-1:i+1));
    px = x(i) + 0.5*(v(1)-v(3)) / (v(1)-2*v(2)+v(3));
end

function w = hannWin(N)
    w = 0.5*(1 - cos(2*pi*(0:N-1).'/(N-1)));
end

function z = cruce(y, zz, nivel)
    z = NaN;
    j = find(y <= nivel, 1);
    if ~isempty(j) && j > 1, z = interp1(y(j-1:j), zz(j-1:j), nivel); end
end

% Modelo de roll-off del espectrómetro (Hu, Pan & Rollins, Appl. Opt. 46, 2007)
function [pT, fn] = ajustarRollOff(z, y, zmax, zmaxLibre)
    modelo = @(p, z) p(1) + 10*log10(sincZ(pi/2*z/p(3)).^2 .* ...
                     exp(-p(2)^2 * (pi/2*z/p(3)).^2 / (2*log(2))));
    opts = optimset('Display', 'off', 'MaxFunEvals', 1e4, 'MaxIter', 1e4);
    if zmaxLibre
        pT = fminsearch(@(p) sum((y - modelo(p, z)).^2), [0 1 zmax], opts);
    else
        pT = [fminsearch(@(p) sum((y - modelo([p zmax], z)).^2), [0 1], opts) zmax];
    end
    pT(2) = abs(pT(2));
    fn = @(zz) modelo(pT, zz);
end

function y = sincZ(x)
    y = ones(size(x));
    nz = x ~= 0;
    y(nz) = sin(x(nz)) ./ x(nz);
end

function s = polyStr(p)
    if numel(p) == 1
        s = sprintf('%.2f dB', p);
    else
        s = sprintf('%.2f %+.3f*z[mm] dB', p(2), p(1));
    end
end
