function [loaded_phases] = MotionAnalysisBorder(Cplx_Matrix, Border, Options)
    % Calcula las fases de desplazamiento o velocidad de partículas a lo largo de un borde en Cplx_Matrix
    
    % Obtener dimensiones de la matriz de datos
    [m, n, o] = size(Cplx_Matrix);

    % Ajustar Border para que no exceda los límites de la matriz
    Border = min(Border, n);

    % Extraer opciones
    Delta = Options.Delta;
    loaded_phases = [];

    if Options.MotionType == 1  % Desplazamiento
        
        loaded_phases = zeros(m, o);
        
        for ii = 1:m
            if ~isnan(Border(ii))
                % Asegurar que los índices están dentro del rango
                start_idx = max(1, Border(ii));
                end_idx = min(n, Border(ii) + Delta);

                % Calcular fase sin smoothing
                data_slice = squeeze(Cplx_Matrix(ii, start_idx:end_idx, :));
                raw_phases = -angle(mean(data_slice, 2));

                if isempty(Options.SmoothingWinPer) % Sin suavizado
                    loaded_phases(ii, :) = raw_phases';
                else % Con suavizado
                    loaded_phases(ii, :) = smooth(raw_phases, Options.SmoothingWinPer, 'lowess')';
                end
            else
                loaded_phases(ii, :) = NaN;
            end
            ii
        end

    elseif Options.MotionType == 2  % Velocidad de partículas
        
        loaded_phases = zeros(m, o-1);

        if isempty(Options.LoupasAxialWin)  % Sin Loupas
            
            for ii = 1:m
                if ~isnan(Border(ii))
                    % Asegurar que los índices están dentro del rango
                    start_idx = max(1, Border(ii));
                    end_idx = min(n, Border(ii) + Delta);

                    % Calcular fase y su diferencia
                    data_slice = squeeze(Cplx_Matrix(ii, start_idx:end_idx, :));
                    raw_phases = -angle(mean(data_slice, 2));
                    raw_phases_Diff = diff(unwrap(raw_phases), 1, 1);

                    if isempty(Options.SmoothingWinPer) % Sin suavizado
                        loaded_phases(ii, :) = raw_phases_Diff';
                    else % Con suavizado
                        loaded_phases(ii, :) = smooth(raw_phases_Diff, Options.SmoothingWinPer, 'lowess')';
                    end
                else
                    loaded_phases(ii, :) = NaN;
                end
                ii
            end

        else  % Con Loupas
            
            for ii = 1:m
                raw_phases_Diff = Loupas2D_Fast(squeeze(Cplx_Matrix(ii, :, :)), Options.LoupasAxialWin);
                max_index = size(raw_phases_Diff, 1);

                if ~isnan(Border(ii)) && (Border(ii) - round(Options.LoupasAxialWin/2) >= 1) && ...
                   (Border(ii) - round(Options.LoupasAxialWin/2) <= max_index)
                    
                    % Ajustar los índices dentro del rango válido
                    start_idx = max(1, min(max_index, Border(ii) - round(Options.LoupasAxialWin/2)));
                    end_idx = max(start_idx, min(max_index, start_idx + Delta));

                    % Calcular la media en la ventana válida
                    raw_phases_Diff_line = mean(raw_phases_Diff(start_idx:end_idx, :), 1);

                    if isempty(Options.SmoothingWinPer) % Sin suavizado
                        loaded_phases(ii, :) = raw_phases_Diff_line;
                    else % Con suavizado
                        loaded_phases(ii, :) = smooth(raw_phases_Diff_line, Options.SmoothingWinPer, 'lowess')';
                    end
                else
                    loaded_phases(ii, :) = NaN;
                end
                ii
            end
        end
    end

    disp('Cálculo de desplazamiento de fase completado.');
end