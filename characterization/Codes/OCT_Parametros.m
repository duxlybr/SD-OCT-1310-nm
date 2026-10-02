function P = OCT_Parametros()
%OCT_PARAMETROS Parametros de procesamiento compartidos de la caracterizacion.
%   P = OCT_Parametros() devuelve la configuracion que usan a la vez
%   Penetration_Analysis_TDMS.m y FWHM_80_ALines_TDMS.m. Editar los valores
%   AQUI (una sola vez) garantiza que ambos scripts procesen el espectro y
%   midan el FWHM exactamente igual.

%% Linealizacion en k
P.usarLinealK   = true;      % remuestrea el espectro a k uniforme antes de la FFT
% Optimizados con FWHM_80_ALines_TDMS.m (Spectrum/FWHM.tdms, espejo a 4.05 mm,
% 2026-10-01); los mismos que la GUI Python (alli invertidos: 1466.61 -> 1263.79).
P.lambdaIni_nm  = 1263.79;   % longitud de onda en el pixel 1 [nm]
P.lambdaFin_nm  = 1466.61;   % longitud de onda en el pixel nPix [nm] (lineal en pixel)
P.metodoInterpK = 'spline';  % 'spline', 'pchip', 'linear' (interp1)

%% Adquisicion y FFT
P.nPix = 2048;               % pixeles por A-line (camara)
P.nFFT = 8192;               % puntos de la FFT (zero-padding)

%% A-scan
P.usarHanning      = false;  % ventana Hanning para picos y caida (el FWHM SIEMPRE sin ventana)
P.promediarALines  = true;   % true: promedia las A-lines; false: solo indiceALine
P.indiceALine      = 40;     % A-line usada cuando promediarALines = false
P.promedioAntesFFT = false;  % false: promedia |FFT| (inmune a deriva de fase)
                             % true : promedia los espectros antes de la FFT

%% Busqueda del pico y medicion del FWHM
P.pxMinBusqueda    = 25;     % ignora bins cercanos al DC
P.pxMaxBusqueda    = 4000;   % ignora el artefacto cerca de Nyquist
P.modeloAjuste     = 'gauss';% 'gauss' o 'sinc'
P.anchoVentana     = 100;    % puntos de la ventana de ajuste centrada en el pico
P.ventanaAutoAdapt = true;   % ventana = max(anchoVentana, 3*FWHM directo)
end
