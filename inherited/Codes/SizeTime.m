function [OCE_system] = SizeTime (measurement,OCT_system,OCE_system,N) %realiza el análisis de datos de imágenes para analizar el movimiento
%measurement: Estructura que contiene datos rawdata.
%OCT_system: Estructura con datos de OCT
%OCE_system: Estructura con datos de OCE
%N: Número de posiciones a analizar en la imagen

hann_rep_mat = double(repmat(hann(OCT_system.spec_len),1,OCE_system.NumMrept));
%crea una matriz de filtro Hanning 
%genera una ventana de Hanning de longitud OCT_system.spec_len y repmat la repite OCE_system.NumMrept veces

% Idx_depth = [OCE_system.Jump_Lat_pos+1:1:OCE_system.NumLateralPos,...
%              1:1:OCE_system.Jump_Lat_pos];
Min_angle = 0;
Max_angle = 0;
         
figure
subplot(2,1,1);
imagesc(OCE_system.Bmode);%muestra una imagen OCE_system.Bmode
clim([OCE_system.i_thresh_low OCE_system.i_thresh_high]) %limites de umbral bajo y alto para la grafica
colormap(gray)   
title(['Choose N = ',num2str(N),' positions to analyse motion']);

for ii = 1:N  % N posiciones de la imagen

    [x,y,button] = ginput(1); %seleccion de un punto, devuelve coord de (x,y) y button en 1
    X_pos = round(x);
    %X_pos_fix = Idx_depth(X_pos); %new pos after fix
    Y_pos = round(y);
    
    subplot(2,1,1);
    hold on 
    scatter(X_pos,Y_pos,'filled','red'); %crea un diagrama de dispersión con marcadores circulares en las ubicaciones especificadas por los vectores x e y
    hold off
    title(['Motion plot (rad) numer N = ',num2str(ii)]);
    
%     if strcmp(OCT_system.data_type,'uint16')
%         fid = fopen(fullfile(pathname,filenames(X_pos_fix).name));
%         pos_raw_fringes = int16(fread(fid,[OCT_system.spec_len,OCE_system.NumMrept]...
%                                  ,OCT_system.data_type,0,'b')-32768);
%         fclose(fid);
%     else
%         fid = fopen(fullfile(pathname,filenames(X_pos_fix).name));
%         pos_raw_fringes = int16(fread(fid,[OCT_system.spec_len,OCE_system.NumMrept]...
%                                  ,OCT_system.data_type,0,'b'));
%         fclose(fid);
%     end
    
%     linear_k_fringes = double(interp1(OCE_system.k_space,single(pos_raw_fringes),...
%                                       OCE_system.k_space_linear,'linear'));

    linear_k_fringes = measurement.rawdata(:,:,X_pos); %saco los datos del raw data en la Xpos indicada
                             
    %linear_k_fringes = double(linear_k_fringes-mean(linear_k_fringes,2)); 
    linear_k_fringes = double(linear_k_fringes- repmat(smooth(mean(linear_k_fringes,2),0.05,'lowess'),1,OCE_system.NumMrept)); 
    % smooth: Suavizar datos de respuesta, lowes: Regresión local con mínimos cuadrados lineales ponderados y un modelo polinomial de primer grado
    fft_1 = fft(hann_rep_mat.*linear_k_fringes); % aplico la fft a la data aplicando el filtro hann a linear k fringes 
    fft_1 = fft_1(1:OCE_system.DepthSize,:); % solo tomo la mitad de la imagen, no considero la imagen espejo                
    fft_2 = fft_1(OCE_system.Cut_Depth_ini:OCE_system.Cut_Depth_end,:); %recorto la profundidad de la imagen, nuevo tamaño depth ini-end
    
%     figure
%     plot(mean(abs(fft_2),2))
    
    raw_phases = 1*angle(fft_2(Y_pos,:)); %obtengo el angulo de phase(rad) de la fft en la Ypos indicada
    loaded_phases = unwrap(raw_phases(1:end));%corregir las discontinuidades en la fase sumando o restando múltiplos de 2pi
    
    %corrijo el angulo min y max
    if min(loaded_phases)<Min_angle
        Min_angle = min(loaded_phases);
    end
    if max(loaded_phases)>Max_angle
        Max_angle = max(loaded_phases);
    end
    
    %grafico la fase de la posicion indicada
    subplot(2,1,2);
    hold on 
    plot(loaded_phases);
    axis ([1 OCE_system.NumMrept Min_angle Max_angle])
    hold off
    
end


h = imrect(gca,[round(OCE_system.NumMrept/3),-1000,...
                round(OCE_system.NumMrept/3),2000]); %crea un objeto de selección rectangular con las coordenadas dadas
PosTime = wait(h); %el programa espera que se seleccione una región con el rectángulo interactivo
% una vez que se ha terminado devuelve las coordenadas [x, y, ancho, alto] del rectángulo seleccionado
title('Select time region to be analyzed');

OCE_system.Cut_Time_ini = round(PosTime(1));
OCE_system.Cut_Time_end = round(PosTime(1))+round(PosTime(3));
OCE_system.NewTimeSize = OCE_system.Cut_Time_end - OCE_system.Cut_Time_ini + 1; %calcula el tamaño de la nueva región de tiempo seleccionada

hold on %hago la gafica para los datos de loaded phases seleccionados
plot([OCE_system.Cut_Time_ini:OCE_system.Cut_Time_end],...
      loaded_phases(OCE_system.Cut_Time_ini:OCE_system.Cut_Time_end),'x',...
      'Color','black'); 
disp('Size time ok')
end




