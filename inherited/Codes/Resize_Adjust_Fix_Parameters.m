function [OCE_system] = Resize_Adjust_Fix_Parameters (measurement,OCT_system,OCE_system)
%% Reading Data (just N repetitions to be fast)

N = 100; %Number of repetitions (just be low)
hann_rep_mat = double(repmat(hann(OCT_system.spec_len),1,N)); % hann: Ventana de Hann (Hanning)
%se crea una matriz que repite la ventana de Hann del tamaño de la data, datos en el dominio del tiempo 
Intensity_Matrix = double(zeros(OCE_system.DepthSize,...
                            OCE_system.NumLateralPos)); % se crea una matriz de zeros del tamaño de depthsize(row) * Numlateralpos(col)
                                                                                         
for pos = 1:OCE_system.NumLateralPos % Numlateralpos = 800 
    %se itera sobre cada posición lateral
    
    pos_raw_fringes = measurement.rawdata(:,1:N,pos); %para cada posición se extraen los datos
    
%   linear_k_fringes = double(interp1(OCE_system.k_space,single(pos_raw_fringes),...
%                                       OCE_system.k_space_linear,'linear'));
    linear_k_fringes = pos_raw_fringes;                              
    linear_k_fringes = double(linear_k_fringes(:,:)-repmat(median(linear_k_fringes,2),1,N)); %se normalizan los datos restando la mediana    
    %linear_k_fringes = double(linear_k_fringes-smooth(mean(linear_k_fringes,2),0.1,'lowess')); 
    fft_1 = fft(hann_rep_mat.*linear_k_fringes); %se realiza la FFT, aplica el filtro de hanning a la data linear_k_fringes
    
    Intensity_Matrix(:,pos) = mean(abs(fft_1(1:OCE_system.DepthSize,:)),2);%se calcula la intensidad como la media del valor absoluto de la FFT

    %pos
    
end 
% Para no considerar el primer meridiano
%Intensity_Matrix(:,1:100)=0;
% Intensity_Matrix=Intensity_Matrix(:,101:end);% con esto no considero el primer meridiano que esta cortado por el piezo
% Para no considerar la mitad de los meridianos
% for i=1:8 % 8 meridianos (num clusters)
%     if i==1
%        Intensity_Matrix(:,1:50)=Intensity_Matrix(:,1:50);
%     elseif i==2
%        Intensity_Matrix(:,51:100)=Intensity_Matrix(:,101:150);
%     elseif i==3
%        Intensity_Matrix(:,101:150)=Intensity_Matrix(:,201:250);
%     elseif i==4
%        Intensity_Matrix(:,151:200)=Intensity_Matrix(:,301:350);
%     elseif i==5
%        Intensity_Matrix(:,201:250)=Intensity_Matrix(:,401:450);
%     elseif i==6
%        Intensity_Matrix(:,251:300)=Intensity_Matrix(:,501:550);
%     elseif i==7
%        Intensity_Matrix(:,301:350)=Intensity_Matrix(:,601:650);
%     else 
%        Intensity_Matrix(:,351:400)=Intensity_Matrix(:,701:750);
%     end
% end

disp('Read data just N repetitions ok')
% figure
% imagesc(20*log10(Intensity_Matrix));

%% Resizing image alonz z, and fixing jump

%se pasa la matriz de intensidad a una escala logarítmica y se normaliza usando el valor máximo
Bmode_IntLog = 20*log10(Intensity_Matrix);
MaxVal = max(Bmode_IntLog(:));
Bmode_IntLog_Norm = Bmode_IntLog/MaxVal;

[Bmode_IntLog_Norm_Adj,Params] = immodify1(Bmode_IntLog_Norm); % ajustar la imagen y obtener parámetros de umbral de intensidad bajo y alto.
% intensidad en escala de grises
OCE_system.i_thresh_low = Params(1)*MaxVal; % lower intensity threshold
OCE_system.i_thresh_high = Params(2)*MaxVal; % upper intensity threshold

figure %se muestra la imagen B-mode utilizando una escala de grises, limitando la visualización a los umbrales definidos
imagesc(Bmode_IntLog);
clim([OCE_system.i_thresh_low OCE_system.i_thresh_high])
title('Crop regions along depth')
colormap(gray)       

h = imrect(gca,[-OCE_system.NumLateralPos/2,100,...
                2*OCE_system.NumLateralPos,OCE_system.DepthSize-200]); %permite al usuario seleccionar una región de interés en la imagen mediante un rectángulo
PosDepth = wait(h); %matriz 1x4

OCE_system.Cut_Depth_ini = round(PosDepth(2)); %Recorte de la Imagen y Ajuste del Tamaño
if OCE_system.Cut_Depth_ini <=0 
    OCE_system.Cut_Depth_ini = 1;
end

% determinan el rango de profundidad de la imagen que se conservará
OCE_system.Cut_Depth_end = round(PosDepth(2))+round(PosDepth(4));
OCE_system.NewDepthSize = OCE_system.Cut_Depth_end - OCE_system.Cut_Depth_ini + 1; %calcula el nuevo tamaño de la imagen después del recorte

% already_saved_flag = menu('Is there a jump?', 'Yes', 'No');
% 
% if already_saved_flag == 1
% 
%     figure
%     imagesc(Bmode_IntLog);
%     caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
%     title('Choose region to evaluate discontinuity')
%     colormap(gray)                       
%     h = imrect(gca,[OCE_system.NumLateralPos/2,-500,...
%                     50,OCE_system.DepthSize+1000]);
%     PosDiscont = wait(h);
% 
%     Cut_Lat_ini = round(PosDiscont(1));
%     Cut_Lat_end = round(PosDiscont(1))+round(PosDiscont(3));
%     Trans_ave = mean(Bmode_IntLog(:,Cut_Lat_ini:Cut_Lat_end),1);
%     [~,idx_max] = max(abs(diff(Trans_ave)));
%     OCE_system.Jump_Lat_pos = idx_max + Cut_Lat_ini -1;
% else
%     OCE_system.Jump_Lat_pos = 0;
% end

OCE_system.Jump_Lat_pos = 0;

Bmode_IntLog([1:OCE_system.Cut_Depth_ini-1,...
                       OCE_system.Cut_Depth_end+1:OCE_system.DepthSize],:)=[]; %se eliminan las Filas fuera de rango y se ajusta la Imagen
 
% [m, n] = size(Bmode_IntLog);                   
% Bmode_IntLog_Norm_Adj_Fix = zeros(m,n);  
% Bmode_IntLog_Norm_Adj_Fix(:,1:(n-OCE_system.Jump_Lat_pos)) = Bmode_IntLog(:,OCE_system.Jump_Lat_pos+1:n);   
% Bmode_IntLog_Norm_Adj_Fix(:,(n-OCE_system.Jump_Lat_pos+1):n) = Bmode_IntLog(:,1:OCE_system.Jump_Lat_pos);                  

OCE_system.Bmode = Bmode_IntLog;

figure
imagesc(OCE_system.Bmode);
clim([OCE_system.i_thresh_low OCE_system.i_thresh_high])
colormap(gray)    
%se muestra la imagen final 
disp('Resizing image ok')
end