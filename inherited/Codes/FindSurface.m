function [Border] = FindSurface(Bmode,OCE_system,OCT_system)
%detectar el borde de una estructura en una imagen B-mode
% utilizando un perfil extraído de la imagen para cada posición lateral y analizando picos en el perfil para determinar las características del borde
% Los resultados se almacenan en una estructura Border, que incluye el índice del borde, su profundidad en milímetros y la intensidad del borde detectado
IniDepth = 10; %Define la profundidad inicial

PeakThresMult = OCE_system.PeakThresMult; %Multiplicador para el umbral de detección de picos
PeakThresWinSize = OCE_system.PeakThresWinSize; %Tamaño de la ventana para el cálculo del umbral de detección de picos
axial_pixel_res = OCT_system.axial_pixel_res;%Resolución axial del píxel en el sistema OCT

Bmode1=20*log10(medfilt2(Bmode,[3 3],'symmetric')); %medfilt2 realiza un filtrado de mediana de la imagen Bmode para reducir el ruido
% Obtengo una nueva imagen Bmode


for ii=1:OCE_system.NumLateralPos % bucle que itera sobre el número de posiciones laterales

    Profile = Bmode1(IniDepth:end,ii); %Para cada posición lateral ii, extrae un perfil de la imagen B-mode 
    % comenzando desde la profundidad inicial (IniDepth) hasta el final de la imagen en esa columna (ii)

    %Thres = mean(Profile(1:PeakThresWinSize))+std(Profile(1:PeakThresWinSize))*PeakThresMult;
    Thres = mean(Profile(1:PeakThresWinSize))+PeakThresMult; %Calcula el umbral de detección de picos
    %Thres = PeakThresMult;
    
    [pks, locs] = findpeaks(Profile,'MinPeakHeight',Thres,'NPeaks',1);  
    %Utiliza la función findpeaks para encontrar picos en el perfil que sean más altos que el umbral calculado (Thres)
    % La opción 'NPeaks', 1 indica que solo se busca el pico más alto
    if isempty(locs) %si no se encuentran picos se asignan valores NaN
        Border.Idx(ii) = NaN;
        Border.DepthPos(ii) = NaN;
        Border.Inten(ii) = NaN;
    else
        Border.Idx(ii) = locs(1)+IniDepth; %indice del borde
        Border.DepthPos(ii) = (locs(1)-1+IniDepth)*axial_pixel_res*1e-3; % in mm profundidad en mm
        Border.Inten(ii) = 20*log10(Bmode(locs(1)+IniDepth,ii));%intensidad del borde
    end 
    %ii    
end
disp('Borde de la estructura ok')
end
