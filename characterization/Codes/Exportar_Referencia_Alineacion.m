function R = Exportar_Referencia_Alineacion(archivoTDMS, archivoSalida, archivoCalibracion)
%EXPORTAR_REFERENCIA_ALINEACION Referencia espectral para el monitor de alineacion.
%
%   Exportar_Referencia_Alineacion()
%       Usa Penetration_3/15um.tdms (la mejor alineacion) y escribe
%       OCT_GUI/config/alineacion_referencia.json, que lee el monitor en vivo
%       de la GUI Python (run_alignment_live.bat).
%
%   Exportar_Referencia_Alineacion(archivoTDMS, archivoSalida, archivoCalibracion)
%
% El JSON contiene el espectro medio crudo, los parametros de procesamiento
% de OCT_Parametros.m, la calibracion um/px y los indicadores calculados aqui
% con OCT_Comun (para comprobar que Python reproduce los mismos valores).

if nargin < 1 || isempty(archivoTDMS)
    archivoTDMS = ['C:\Users\proyecto.pi1081\Desktop\1310 OCT\Data\' ...
        'Characterization\Penetration_3\15um.tdms'];
end
if nargin < 2 || isempty(archivoSalida)
    archivoSalida = 'C:\Users\proyecto.pi1081\Desktop\OCT_GUI\config\alineacion_referencia.json';
end
if nargin < 3 || isempty(archivoCalibracion)
    archivoCalibracion = fullfile(fileparts(archivoTDMS), 'Penetration_resultados.mat');
end

P = OCT_Parametros();
binsEnvolvente = 6;
pxCociente = [600 1300];

C = load(archivoCalibracion);
umPorPx = C.umPorPx;
if isfield(C, 'nFFT') && C.nFFT ~= P.nFFT, umPorPx = umPorPx*C.nFFT/P.nFFT; end

M = OCT_Comun.leerTDMS(archivoTDMS, P.nPix);
espectro = mean(M, 2);

% Envolvente: paso bajo del espectro medio (elimina las franjas del espejo)
X = fft(espectro);
mascara = zeros(size(X));
mascara([1:binsEnvolvente+1, end-binsEnvolvente+1:end]) = 1;
env = real(ifft(X.*mascara));
envN = env/max(env);
cociente = env(pxCociente(1)+1)/env(pxCociente(2)+1);
borde50 = [find(envN >= 0.5, 1), find(envN >= 0.5, 1, 'last')] - 1;

% FWHM limitado por el espectro
lam = linspace(P.lambdaIni_nm, P.lambdaFin_nm, P.nPix).';
kPix = flipud(2*pi ./ lam);
kU = linspace(kPix(1), kPix(end), P.nPix).';
e = max(env - min(env), 0);
ek = interp1(kPix, flipud(e), kU, 'spline');
E = fftshift(abs(fft(ek, P.nFFT)));
x = (-P.nFFT/2:P.nFFT/2-1).';
fwhmEspectro_um = OCT_Comun.fwhmDirecto(x, E, P.nFFT/2+1)*umPorPx;

% PSF del espejo, como Penetration_Analysis_TDMS.m
nHalf = P.nFFT/2;
pxAxis = (0:nHalf-1).';
[Aabs, Arect] = OCT_Comun.ascan(M, P);
[pkPx, pkIdx] = OCT_Comun.buscarPico(pxAxis, Aabs, OCT_Comun.rangoBusqueda(P, nHalf));
m = OCT_Comun.medirPico(pxAxis, Arect, pkIdx, P);

R = struct();
R.version = 1;
R.descripcion = 'Referencia espectral para Alineacion del espectrometro (OCT_GUI)';
R.creado = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
R.archivo_tdms = archivoTDMS;
R.archivo_calibracion = archivoCalibracion;
R.n_alines = size(M, 2);
R.procesamiento = struct('lambda_ini_nm', P.lambdaIni_nm, 'lambda_fin_nm', P.lambdaFin_nm, ...
    'metodo_interp_k', P.metodoInterpK, 'n_pix', P.nPix, 'n_fft', P.nFFT, ...
    'um_por_px', umPorPx, 'px_min_busqueda', P.pxMinBusqueda, ...
    'px_max_busqueda', P.pxMaxBusqueda, 'modelo_ajuste', P.modeloAjuste, ...
    'ancho_ventana', P.anchoVentana, 'ventana_auto_adapt', P.ventanaAutoAdapt, ...
    'bins_envolvente', binsEnvolvente, 'px_cociente', pxCociente);
R.espectro_medio = espectro.';
R.indicadores_matlab = struct('cociente', cociente, 'borde50_px', borde50, ...
    'fwhm_espectro_um', fwhmEspectro_um, 'max_cuentas', max(M(:)), ...
    'profundidad_um', pkPx*umPorPx, 'fwhm_ajuste_um', m.fwhmPx*umPorPx, ...
    'fwhm_datos_um', m.fwhmDatosPx*umPorPx);

carpeta = fileparts(archivoSalida);
if ~isfolder(carpeta), mkdir(carpeta); end
fid = fopen(archivoSalida, 'w', 'n', 'UTF-8');
if fid < 0, error('No se puede escribir %s', archivoSalida); end
fwrite(fid, jsonencode(R, 'PrettyPrint', true), 'char');
fclose(fid);
fprintf('Referencia escrita en %s\n', archivoSalida);
fprintf('  cociente px%d/px%d = %.4f | bordes 50%% = %d-%d px | FWHM espectro = %.3f um\n', ...
    pxCociente, cociente, borde50, fwhmEspectro_um);
fprintf('  espejo a %.1f um: FWHM ajuste %.3f um, directo %.3f um\n', ...
    pkPx*umPorPx, m.fwhmPx*umPorPx, m.fwhmDatosPx*umPorPx);
end
