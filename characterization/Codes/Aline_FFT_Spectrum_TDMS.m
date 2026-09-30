%% Aline_FFT_Spectrum.m
% Muestra una figura por cada archivo TDMS de la carpeta Spectrum.
% En cada figura:
%   - Arriba: una A-line cruda (sin quitar DC, sin ventana y sin filtrar).
%   - Abajo : la FFT de esa misma A-line, tras quitar DC, linealizar en k
%             y aplicar opcionalmente una ventana Hann. El eje de profundidad
%             usa la calibracion px/um guardada por Penetration_Analysis.m.
%
% Estructura TDMS esperada: grupo "Acquisition", canal "Raw_B_scans",
% con A-lines de 2048 muestras concatenadas.

clear; close all; clc;

%% ======================= PARAMETROS DE USUARIO =========================
carpeta = 'C:\Users\proyecto.pi1081\Desktop\1310 OCT\Data\Spectrum';
archivoCalibracion = '';   % '' = localizar el Penetration_resultados.mat mas reciente

nPix        = 2048;       % muestras de camara por A-line
nFFT        = 8192;       % puntos de FFT (incluye zero-padding)
indiceALine = 40;         % A-line que se muestra de cada archivo

% Calibracion espectral. Las longitudes de onda se expresan en micrometros.
lambdaIni_um  = 1.26234;
lambdaFin_um  = 1.47108;
usarLinealK   = true;     % recomendado antes de la FFT de OCT
metodoInterpK = 'spline'; % 'spline', 'pchip' o 'linear'
usarHanning   = false;

% Visualizacion de la FFT.
mostrarFFT_dB           = true;  % true: amplitud normalizada en dB
mostrarSoloSegmentoPico = false; % CAMBIAR A true para ver solo el pico mayor
semiAnchoSegmento_um    = 100;   % intervalo mostrado: pico +/- este valor [um]
profundidadMinPico_um   = 75;    % evita seleccionar residuos cercanos al DC

% Opcional: guardar cada figura como PNG dentro de Spectrum/Figuras_Aline_FFT.
guardarFiguras = false;

%% ======================= ARCHIVOS Y EJES ===============================
if ~isfolder(carpeta)
    error('No existe la carpeta: %s', carpeta);
end

archivos = dir(fullfile(carpeta, '**', '*.tdms'));
if isempty(archivos)
    error('No se encontraron archivos .tdms en %s', carpeta);
end
archivos = ordenarArchivosSpectrum(archivos);

if numel(archivos) ~= 11
    warning('Se esperaban 11 archivos TDMS, pero se encontraron %d. Se procesaran todos.', ...
        numel(archivos));
end

lambda_um = linspace(lambdaIni_um, lambdaFin_um, nPix).';
kPix = flipud(2*pi ./ lambda_um);                % [rad/um], orden ascendente
kUniforme = linspace(kPix(1), kPix(end), nPix).';

% Usa la relacion experimental pixel/micrometro de Penetration_Analysis.
[archivoCalibracion, umPorPx] = cargarCalibracion(archivoCalibracion, carpeta, ...
    nFFT, nPix, lambdaIni_um, lambdaFin_um);
nHalf = nFFT/2;
z_um = (0:nHalf-1).' * umPorPx;

if usarHanning
    n = (0:nPix-1).';
    ventana = 0.5 - 0.5*cos(2*pi*n/(nPix-1));
else
    ventana = ones(nPix, 1);
end

if guardarFiguras
    carpetaSalida = fullfile(carpeta, 'Figuras_Aline_FFT');
    if ~isfolder(carpetaSalida), mkdir(carpetaSalida); end
end

%% ======================= LECTURA Y FIGURAS =============================
fprintf('Procesando %d archivos de %s\n', numel(archivos), carpeta);
fprintf('Calibracion: %s (%.6f um/px)\n', archivoCalibracion, umPorPx);

for iArchivo = 1:numel(archivos)
    ruta = fullfile(archivos(iArchivo).folder, archivos(iArchivo).name);
    raw = tdmsread(ruta, 'ChannelGroupName', "Acquisition", ...
        'ChannelNames', "Raw_B_scans");
    x = double(raw{1}.Raw_B_scans(:));

    nALines = floor(numel(x)/nPix);
    if nALines < 1
        warning('%s no contiene una A-line completa y se omitira.', archivos(iArchivo).name);
        continue;
    end
    if indiceALine > nALines
        error('%s solo contiene %d A-lines; indiceALine = %d no existe.', ...
            archivos(iArchivo).name, nALines, indiceALine);
    end

    M = reshape(x(1:nPix*nALines), nPix, nALines);
    alineCruda = M(:, indiceALine);

    % La FFT procede de la misma A-line cruda mostrada en el panel superior.
    espectro = alineCruda - mean(alineCruda);
    if usarLinealK
        espectro = interp1(kPix, flipud(espectro), kUniforme, metodoInterpK);
    end
    F = abs(fft(espectro .* ventana, nFFT));
    F = F(1:nHalf);

    rangoPico = find(z_um >= profundidadMinPico_um);
    [~, iLocal] = max(F(rangoPico));
    iPico = rangoPico(iLocal);
    zPico_um = z_um(iPico);

    if mostrarFFT_dB
        fftGrafica = 10*log10(max(F, eps));
        fftGrafica = fftGrafica - max(fftGrafica);
        etiquetaFFT = 'Normalized FFT amplitude [dB] 20*log10';
    else
        fftGrafica = F;
        etiquetaFFT = '|FFT| [a.u.]';
    end

    fig = figure('Color', 'w', 'Name', archivos(iArchivo).name, ...
        'NumberTitle', 'off');
    tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

    ax1 = nexttile(tl);
    plot(ax1, lambda_um, alineCruda, 'Color', [0.05 0.35 0.70], 'LineWidth', 1);
    grid(ax1, 'on');
    xlabel(ax1, 'Wavelength [\mum]');
    ylabel(ax1, 'Raw intensity [counts]');
    title(ax1, 'Raw A-line');
    xlim(ax1, [lambda_um(1), lambda_um(end)]);

    ax2 = nexttile(tl);
    plot(ax2, z_um, fftGrafica, 'Color', [0.80 0.20 0.12], 'LineWidth', 1);
    hold(ax2, 'on');
    plot(ax2, zPico_um, fftGrafica(iPico), 'ko', 'MarkerFaceColor', [1.00 0.75 0.10]);
    grid(ax2, 'on');
    xlabel(ax2, 'Depth [\mum]');
    ylabel(ax2, etiquetaFFT);
    title(ax2, sprintf('A-line FFT - highest peak at %.1f \\mum', zPico_um));

    if mostrarSoloSegmentoPico
        limiteIzq = max(z_um(1), zPico_um - semiAnchoSegmento_um);
        limiteDer = min(z_um(end), zPico_um + semiAnchoSegmento_um);
        xlim(ax2, [limiteIzq, limiteDer]);
    else
        xlim(ax2, [z_um(1), z_um(end)]);
    end

    sgtitle(tl, archivos(iArchivo).name, 'Interpreter', 'none', 'FontWeight', 'bold');

    if guardarFiguras
        [~, nombreBase] = fileparts(archivos(iArchivo).name);
        exportgraphics(fig, fullfile(carpetaSalida, [nombreBase '.png']), ...
            'Resolution', 200);
    end

    fprintf('  %-24s %3d A-lines | pico = %8.1f um\n', ...
        archivos(iArchivo).name, nALines, zPico_um);
end

fprintf('Listo: se generaron %d figuras individuales.\n', numel(archivos));

%% ======================= FUNCION LOCAL =================================
function archivos = ordenarArchivosSpectrum(archivos)
% Orden: PSF_0, PSF_500, ..., ReferenceClosed, SampleClosed y otros.
    n = numel(archivos);
    grupo = 4*ones(n,1);
    valor = zeros(n,1);
    for k = 1:n
        nombre = archivos(k).name;
        tok = regexp(nombre, '^PSF_([\d.]+)(?:um)?\.tdms$', ...
            'tokens', 'once', 'ignorecase');
        if ~isempty(tok)
            grupo(k) = 1;
            valor(k) = str2double(tok{1});
        elseif strcmpi(nombre, 'ReferenceClosed.tdms')
            grupo(k) = 2;
        elseif strcmpi(nombre, 'SampleClosed.tdms')
            grupo(k) = 3;
        end
    end
    [~, orden] = sortrows([grupo, valor], [1 2]);
    archivos = archivos(orden);
end

function [ruta, umPorPx] = cargarCalibracion(ruta, carpetaDatos, nFFT, nPix, lambdaIni_um, lambdaFin_um)
% Localiza y valida la calibracion generada por Penetration_Analysis.m.
    if isempty(ruta)
        candidatos = [dir(fullfile(carpetaDatos, 'Penetration_resultados.mat')); ...
            dir(fullfile(fileparts(carpetaDatos), 'Characterization', ...
            'Penetration*', 'Penetration_resultados.mat'))];
        if isempty(candidatos)
            error(['No se encontro Penetration_resultados.mat. Ejecute primero ' ...
                'Penetration_Analysis.m o indique archivoCalibracion.']);
        end
        [~, iMasReciente] = max([candidatos.datenum]);
        ruta = fullfile(candidatos(iMasReciente).folder, candidatos(iMasReciente).name);
    end
    if ~isfile(ruta)
        error('No existe el archivo de calibracion: %s', ruta);
    end

    C = load(ruta);
    if isfield(C, 'umPorPx')
        umPorPxCal = C.umPorPx;
    elseif isfield(C, 'pxPorUm')
        umPorPxCal = 1/C.pxPorUm;
    else
        error('%s no contiene umPorPx ni pxPorUm.', ruta);
    end
    if isfield(C, 'nFFT')
        umPorPx = umPorPxCal * C.nFFT/nFFT;
    else
        umPorPx = umPorPxCal;
        warning('La calibracion no contiene nFFT; se supone que corresponde a nFFT = %d.', nFFT);
    end
    if ~isscalar(umPorPx) || ~isfinite(umPorPx) || umPorPx <= 0
        error('La relacion umPorPx de la calibracion no es valida.');
    end
    if isfield(C, 'nPix') && C.nPix ~= nPix
        warning('La calibracion usa nPix = %d, pero este script usa nPix = %d.', C.nPix, nPix);
    end
    if isfield(C, 'lambdaIni_nm') && isfield(C, 'lambdaFin_nm')
        tol_nm = 0.1;
        if abs(C.lambdaIni_nm - 1000*lambdaIni_um) > tol_nm || ...
                abs(C.lambdaFin_nm - 1000*lambdaFin_um) > tol_nm
            warning(['El rango espectral (%.2f-%.2f nm) difiere del usado en la ' ...
                'calibracion (%.2f-%.2f nm).'], 1000*lambdaIni_um, 1000*lambdaFin_um, ...
                C.lambdaIni_nm, C.lambdaFin_nm);
        end
    end
end
