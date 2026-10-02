classdef OCT_Comun
%OCT_COMUN Procesamiento compartido de la caracterizacion del SD-OCT 1310 nm.
%   Penetration_Analysis_TDMS.m y FWHM_80_ALines_TDMS.m usan estas funciones
%   para generar el A-scan y medir el pico, de modo que un mismo archivo TDMS
%   produce el mismo FWHM en ambos scripts. Los parametros vienen de
%   OCT_Parametros.m.
%
%   M = OCT_Comun.leerTDMS(archivo, nPix)
%   [Aabs, Arect] = OCT_Comun.ascan(M, P)            % como Penetration
%   [Aabs, Arect] = OCT_Comun.ascan(M, P, [D2 D3])   % + compensacion de dispersion
%   rango = OCT_Comun.rangoBusqueda(P, nHalf)
%   [px, i, amp] = OCT_Comun.buscarPico(x, y, rango)          % maximo absoluto
%   [px, i, amp, prom_dB] = OCT_Comun.buscarPicoReflector(x, y, rango) % reflector (no la cola del DC)
%   m = OCT_Comun.medirFWHMDirecto(pxAxis, Arect, pkIdx, P) % solo FWHM directo
%   m = OCT_Comun.medirPico(pxAxis, Arect, pkIdx, P)        % FWHM directo + ajuste

    methods (Static)
        function M = leerTDMS(archivo, nPix)
        % A-lines del canal Acquisition/Raw_B_scans como columnas (nPix x nLines).
            raw = tdmsread(archivo, 'ChannelGroupName', "Acquisition", ...
                'ChannelNames', "Raw_B_scans");
            x = double(raw{1}.Raw_B_scans(:));
            nLines = floor(numel(x)/nPix);
            if nLines < 1
                error('%s no contiene una A-line completa de %d muestras.', archivo, nPix);
            end
            M = reshape(x(1:nLines*nPix), nPix, nLines);
        end

        function [Aabs, Arect] = ascan(M, P, coefDisp)
        % |FFT| (lado positivo) con la ventana de P (Aabs) y sin ventana (Arect).
        % Quita DC por A-line, linealiza en k y, si se indica, compensa la
        % dispersion con phi = D2*q^2 + D3*q^3 (q en [-1, 1] sobre k uniforme).
            if nargin < 3, coefDisp = [0 0]; end
            if ~P.promediarALines
                if P.indiceALine > size(M,2)
                    error('indiceALine = %d no existe (%d A-lines).', ...
                        P.indiceALine, size(M,2));
                end
                S = M(:, P.indiceALine);             % una sola A-line
            elseif P.promedioAntesFFT
                S = mean(M, 2);                      % promedio de A-lines
            else
                S = M;                               % se promedia |FFT| despues
            end
            S = S - mean(S,1);                       % quita DC
            if P.usarLinealK
                lam  = linspace(P.lambdaIni_nm, P.lambdaFin_nm, P.nPix).';
                kPix = flipud(2*pi ./ lam);          % ascendente
                kU   = linspace(kPix(1), kPix(end), P.nPix).';
                S = interp1(kPix, flipud(S), kU, P.metodoInterpK);
            end
            if any(coefDisp ~= 0)
                % Sobre la senal real la imagen espejo recibiria el doble de
                % fase y se ensancharia sobre el pico y el piso de ruido.
                S = OCT_Comun.senalAnalitica(S) .* ...
                    exp(-1i*OCT_Comun.faseDispersion(P.nPix, coefDisp));
            end
            if P.usarHanning
                win = OCT_Comun.hannWin(P.nPix);
            else
                win = ones(P.nPix, 1);
            end
            nHalf = P.nFFT/2;
            F  = mean(abs(fft(S .* win, P.nFFT)), 2);
            Fr = mean(abs(fft(S, P.nFFT)), 2);
            Aabs  = F(1:nHalf);
            Arect = Fr(1:nHalf);
        end

        function rango = rangoBusqueda(P, nHalf)
        % Indices MATLAB donde se busca el pico (excluye DC y Nyquist).
            pxMin = max(1, P.pxMinBusqueda);
            pxMax = min(nHalf-2, P.pxMaxBusqueda);
            if pxMin >= pxMax
                error('El intervalo de búsqueda del pico no es válido.');
            end
            rango = (pxMin:pxMax) + 1;
        end

        function m = medirFWHMDirecto(pxAxis, Arect, pkIdx, P)
        % Re-localiza el pico en +-5 bins del A-scan SIN ventana y mide el
        % FWHM directo (media altura absoluta, sin linea base).
            nHalf = numel(pxAxis);
            iMin = max(1, P.pxMinBusqueda) + 1;  % la ventana nunca incluye el DC
            r = max(iMin, pkIdx-5) : min(nHalf-1, pkIdx+5);
            [m.pkPx, m.pkIdx, m.pkAmp] = OCT_Comun.buscarPico(pxAxis, Arect, r);
            m.fwhmDatosPx = OCT_Comun.fwhmDirecto(pxAxis, Arect, m.pkIdx);
        end

        function m = medirPico(pxAxis, Arect, pkIdx, P)
        % FWHM sobre el A-scan SIN ventana: FWHM directo (medirFWHMDirecto) y
        % ajuste de P.modeloAjuste en una ventana centrada en el pico.
            iMin = max(1, P.pxMinBusqueda) + 1;  % la ventana nunca incluye el DC
            m = OCT_Comun.medirFWHMDirecto(pxAxis, Arect, pkIdx, P);

            n = P.anchoVentana;
            if P.ventanaAutoAdapt && isfinite(m.fwhmDatosPx)
                n = max(n, ceil(3*m.fwhmDatosPx));
            end
            [xw, yw] = OCT_Comun.ventanaPico(pxAxis, Arect, m.pkIdx, n, iMin);
            fwhmSemilla = m.fwhmDatosPx;
            if ~isfinite(fwhmSemilla), fwhmSemilla = max(2, P.anchoVentana/10); end
            p = OCT_Comun.ajustarPico(xw, yw, P.modeloAjuste, ...
                [m.pkAmp, m.pkPx, fwhmSemilla, 0]);
            m.ajuste = struct('modelo', P.modeloAjuste, 'p', p, 'xw', xw, 'yw', yw, ...
                'R2', OCT_Comun.calcR2(yw, OCT_Comun.modeloPico(p, xw, P.modeloAjuste)));
            m.fwhmPx = p(3);
        end

        function w = hannWin(N)
            w = 0.5*(1 - cos(2*pi*(0:N-1).'/(N-1)));
        end

        function [px, i, amp] = buscarPico(x, y, rango)
        % Maximo dentro de 'rango' (indices MATLAB) con refinamiento parabolico en dB
            [amp, i] = max(y(rango));
            i = rango(i);
            v = 10*log10(max(y(i-1:i+1), eps));
            den = v(1)-2*v(2)+v(3);
            if den == 0
                px = x(i);
            else
                px = x(i) + 0.5*(v(1)-v(3)) / den;
            end
        end

        function [px, i, amp, prominencia_dB] = buscarPicoReflector(x, y, rango)
        % Pico del reflector dentro de 'rango': maximo local verdadero (ambos
        % vecinos mas bajos) con la mayor prominencia sobre el piso local
        % (mediana de 20-200 bins a cada lado). La cola del DC decrece desde el
        % borde de la busqueda y no es un maximo local, aunque su amplitud
        % supere a la del espejo; buscarPico la tomaba por el reflector.
            w = 20; W = 200; n = numel(y);
            r = rango(rango > 1 & rango < n);
            r = r(:);
            cand = r(y(r) >= y(r-1) & y(r) > y(r+1));
            if isempty(cand)
                [px, i, amp] = OCT_Comun.buscarPico(x, y, rango);
                prominencia_dB = NaN;
                return;
            end
            prom = zeros(size(cand));
            for c = 1:numel(cand)
                k = cand(c);
                vecinos = [max(1,k-W):max(1,k-w), min(n,k+w):min(n,k+W)];
                prom(c) = y(k) / median(y(vecinos));
            end
            [pm, mejor] = max(prom);
            [px, i, amp] = OCT_Comun.buscarPico(x, y, cand(mejor));   % refinamiento parabolico
            prominencia_dB = 20*log10(pm);
        end

        function [xw, yw] = ventanaPico(x, y, i, n, iMin)
            i0 = max(iMin, i - floor(n/2));
            i1 = min(numel(x), i0 + n - 1);
            i0 = max(iMin, i1 - n + 1);
            xw = x(i0:i1); yw = y(i0:i1);
        end

        function y = modeloPico(p, x, modelo)
        % Modelos parametrizados directamente con el FWHM: p = [A, x0, FWHM, C]
            u = (x - p(2)) / abs(p(3));
            switch lower(char(modelo))
                case 'gauss', y = p(1)*exp(-4*log(2)*u.^2) + p(4);
                case 'sinc',  y = p(1)*abs(OCT_Comun.sincN(2*0.603355*u)) + p(4); % |sinc| = 0.5 en u=+-0.5
                otherwise, error('Modelo no reconocido: %s', modelo);
            end
        end

        function y = sincN(x)
            y = ones(size(x));
            nz = x ~= 0;
            y(nz) = sin(pi*x(nz)) ./ (pi*x(nz));
        end

        function p = ajustarPico(xw, yw, modelo, p0)
            if nargin < 4 || isempty(p0)
                [A, i] = max(yw);
                C = min(yw);
                above = find(yw - C >= (A - C)/2);
                F = max(xw(above(end)) - xw(above(1)), 2);
                p0 = [A - C, xw(i), F, C];
            end
            % Limites fisicos: A>0, centro dentro de la ventana, 1 px <= FWHM <= 3*ventana, C>=0
            anchoW = xw(end) - xw(1);
            lb = [0,        xw(1),   1,          0];
            ub = [2*max(yw), xw(end), 3*anchoW,  max(yw)];
            p0 = min(max(p0, lb), ub);
            sse = @(p) sum((yw - OCT_Comun.modeloPico(p, xw, modelo)).^2) + ...
                1e30*any(p < lb | p > ub);
            opts = optimset('MaxFunEvals', 2e4, 'MaxIter', 2e4, 'TolX', 1e-6, ...
                'TolFun', 1e-8, 'Display', 'off');
            p = fminsearch(sse, p0, opts);
        end

        function r2 = calcR2(y, yf)
            sst = sum((y - mean(y)).^2);
            if sst == 0, r2 = NaN; else, r2 = 1 - sum((y - yf).^2) / sst; end
        end

        function f = fwhmDirecto(x, y, i)
        % FWHM directo sobre |FFT| lineal, con interpolacion en los cruces de media altura
            h = y(i)/2;
            L = i; while L > 1 && y(L) > h, L = L - 1; end
            R = i; while R < numel(y) && y(R) > h, R = R + 1; end
            if L == i || R == i || L == 1 || R == numel(y)
                f = NaN;
                return;
            end
            xL = interp1(y([L L+1]), x([L L+1]), h);
            xR = interp1(y([R-1 R]), x([R-1 R]), h);
            f = xR - xL;
        end

        function Sa = senalAnalitica(S)
        % Senal analitica por columnas (equivalente a hilbert(S)/2, sin toolbox):
        % |FFT| del lado positivo coincide con la de la senal real.
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
        % Fase sobre el eje k uniforme (orden ascendente), q = (k-k0)/(Dk/2).
            q = linspace(-1, 1, nPix).';
            fase = coefDisp(1)*q.^2 + coefDisp(2)*q.^3;
        end
    end
end
