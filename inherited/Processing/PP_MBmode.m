clc; clear; close all;
%% Selecting folder
start_path = 'Data';
[filename,filepath,indx] = uigetfile('.bin','Choose OCE file (just one)');
disp('Selecting folder ok')

% Reading raw data
OCE_AcqType = 1; % MulMer = 1, Spiral = 2
measurement = oct2_readRawData(filename,filepath,OCE_AcqType);
% nBscansToRead It's for reading only a few (optional, all bscans are read by default)

% Input OCT parameters
OCT_system.NumAngles = measurement.ScanInfo.No_3Dscans; %number of angles performed in the measurement
OCT_system.center_wavelength = 1.300; % [µm] central wavelength of the OCT system
OCT_system.a_scan_rate = 200; % [kHz] defines the A-scan rate of the system (5us)
OCT_system.axial_pixel_res = 8.4; % [µm] axial resolution
OCT_system.x_scan_width = measurement.ScanInfo.Ver_scan_length_mm; % [mm] scan width on the X-axis, related to the vertical scan length
OCT_system.IDXrefrac = 1.4276; % refactive index of the sample

OCE_system = [];

% Measure size of data
OCE_system.NumLateralPos = measurement.ScanInfo.Bframes_in_3Dscan * OCT_system.NumAngles; % number of B-frames * number of angles = total number of lateral positions is obtained
OCE_system.NumMrept = measurement.ScanInfo.Alines_in_Bframe; % indicates how many A-lines have been captured in each Bframe
OCT_system.spec_len = measurement.ScanInfo.samples_in_Aline; % number of samples in each A-line, spectrum length
OCE_system.DepthSize =  measurement.ScanInfo.samples_in_Aline/2; % calculates the depth size using the number of samples in an A-line / 2

% Sizing data along z, adjusting contrast, fixing jump   

%ajustar y corregir parámetros relacionados con datos en el eje z
[OCE_system] = Resize_Adjust_Fix_Parameters(measurement,OCT_system,OCE_system);

% Sizing data along time

N = 3;
[OCE_system] = SizeTime (measurement,OCT_system,OCE_system,N);      
%realiza el análisis de datos de imágenes para analizar el movimiento

%% Create Folder
%tiene que existir una carpeta fuera de clinical data que sea 'Results'
pathname = [filepath filename];
kdata = strfind(pathname,'Data');
k = strfind(pathname,'\');
inik = find(k > kdata(end));
k = k(inik);

oldFolder = cd('Results');

for i=1:length(k)
    if i == length(k)
        Data_name = pathname(k(i)+1:end-4);
    else
        Data_name = pathname(k(i)+1:k(i+1)-1);
    end
    mkdir(Data_name);
    cd(Data_name);
end

% Reading

% [OCE_system_tmp] = Resize_Adjust_Fix_Parameters (pathname,OCT_system,OCE_system);
% OCE_system.Jump_Lat_pos = OCE_system_tmp.Jump_Lat_pos;

[Cplx_Matrix] = ReadCplx_Volume_BS (measurement,OCT_system,OCE_system);
%devuelve la matriz compleja reordenada y acotada
% numlat x depth x time


% Bmode
%Visualiza la imagen B-mode junto con el borde detectado, 
%ajustando el rango de visualización y realizando correcciones en los índices del borde para asegurar 
%que estén dentro de límites válidos

Xaxis = linspace(0,OCT_system.x_scan_width*OCT_system.NumAngles,OCE_system.NumLateralPos);%vector de 0 a 80 , 1x800double
%Xaxis = Xaxis*4.77/5.83;
%Zaxis = [0:1:OCE_system.NewDepthSize-1]'*OCT_system.axial_pixel_res*1e-3; 
Zaxis = (0:1:OCE_system.NewDepthSize-1)'*OCT_system.axial_pixel_res*1e-3;%creo un vector columna newdepthsize x 1, [0:axial pixel:newdepthsize]
Zaxis = Zaxis/OCT_system.IDXrefrac;% el vector anterior lo normalizo en distancias recorridas en el tejido IDXrefrac

Bmode = mean(abs(Cplx_Matrix(:,:,:)),3)';

OCE_system.PeakThresMult = 18;
OCE_system.PeakThresWinSize = 10; 
[Border] = FindSurface(Bmode,OCE_system,OCT_system); %detectar el borde de una estructura en una imagen B-mode

Border.Idx(end)= nan; %Se establece el último valor del índice (Border.Idx(end)) como NaN para evitar el uso de datos no válidos

%aplico filtro para suavizar los datos 
Border.Idx = medfilt2(Border.Idx,[1 7],'Symmetric');
Border.Idx = smooth(Border.Idx,0.005,'lowess');


%Bmode = mean(abs(Cplx_Matrix(:,:,:)),3)';
Bmode_IntLog = real(20*log10(Bmode)); %Convierte la imagen B-mode a una escala logarítmica en decibelios para visualización
% real() se usa para asegurar que se usa la parte real de los valores

figure
%Crea una figura y muestra la imagen B-mode en escala de grises
%Superpone la línea del borde detectado sobre la imagen
imagesc(Bmode_IntLog)
clim([OCE_system.i_thresh_low OCE_system.i_thresh_high])
colormap(gray)
hold on
plot(Border.Idx-4);

%Se ajustan los índices del borde para asegurar que se mantengan dentro de un rango válido
Border.Idx = Border.Idx - 4;
idx1 = find(Border.Idx < 20);
Border.Idx (idx1) = 20;
idx1 = find(Border.Idx>OCE_system.NewDepthSize-1-50);
Border.Idx (idx1) = OCE_system.NewDepthSize-1-50;

%Border.Idx([1:15,185:200])=100;

% tmp = Border.Idx;
% idx = (tmp>=size(Bmode_IntLog,1)-50)
% tmp(tmp>=size(Bmode_IntLog,1)-50) = size(Bmode_IntLog,1)-100;
% Border.Idx = tmp;
disp('B-mode border ok')


% Manual Selection of Border
%HACER SI NO SE HIZO EL PASO ANTERIOR

%permite al usuario seleccionar manualmente un borde en una imagen B-mode
%La selección se hace dibujando un polígono en la imagen, y el código
%utiliza esa selección para crear una máscara de 0 y 1
%el borde detectado se visualiza en la imagen original para ver el resultado de la selección manual

% Border.Idx = [];
% 
% figure
% himage= imagesc(Bmode_IntLog);
% clim([OCE_system.i_thresh_low OCE_system.i_thresh_high])
% colormap(gray)
% h = impoly(gca);
% PosTime = wait(h);
% BW = createMask(h,himage);
% 
% for i = 1:size(BW,2)
%     idx = find(BW(:,i) == 1);
%     Border.Idx(:,i) = idx(1); %Asigna el primer índice encontrado a Border.Idx(:, i)
%     % Esto asume que el primer índice en cada columna representa el borde en esa columna
% end
% 
% figure
% imagesc(Bmode_IntLog)
% clim([OCE_system.i_thresh_low OCE_system.i_thresh_high])
% colormap(gray)
% hold on
% plot(Border.Idx);


% Mask
%se encarga de crear y visualizar una máscara binaria para una imagen B-mode

%no se utiliza en el codigo
%   Jump = 400; 

% Bmode = mean(abs(Cplx_Matrix(:,:,:)),3)';
% Bmode_IntLog = real(20*log10(Bmode));
% Bmode_Filt = medfilt2(Bmode_IntLog,[5 5],'symmetric');
% Thres = 55;
% Bmode_Mask = Bmode_Filt>Thres;

Thres = 90; %umbral

% crea una máscara binaria donde los valores en Bmode_IntLog que son mayores que el umbral (Thres) 
% se establecen en 1 (verdadero), 
% y los valores que son menores o iguales al umbral se establecen en 0 (falso)
Bmode_Mask = Bmode_IntLog>Thres; %Bmode_IntLog es una escala logarítmica de la parte real de Bmode

% for i = 1:size(Bmode_Mask,2)
%     if ~isnan(Border.Idx(i))
%         Bmode_Mask(1:Border.Idx(i),i)=0;
%         Jump = Border1.Idx(i)-Border.Idx(i);
%         if Border.Idx(i)+Jump > size(Bmode_Mask,1)
%             Bmode_Mask(size(Bmode_Mask,1),i)=0;
%         else
%             Bmode_Mask(Border.Idx(i)+Jump:end,i)=0;
%         end
%     end
% end

figure
imagesc(Bmode_Mask) %Muestra la máscara binaria Bmode_Mask
title('B-mode mask');
disp('B-mode mask ok')
gcf = figure; %crea una nueva figura
%Visualización de la Imagen con Máscara
imagesc(Xaxis,Zaxis,Bmode_IntLog.*Bmode_Mask)
clim([OCE_system.i_thresh_low OCE_system.i_thresh_high]) %establece los limites
colormap(gray) %establece la imagen en escala de grises
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
title('B-mode image');
disp('B-mode image ok')
%axis equal
%axis([Xaxis(1) Xaxis(end) Zaxis(1) Zaxis(end)])
axis([0  Xaxis(end) 0 Zaxis(end)])
set(gca,'FontSize', 14);
%guarda la figura en formato .fig y .tif
saveas(gcf,'Bmode.fig');
saveas(gcf,'Bmode.tif');
disp('Save image with mask ok')

% Motion analysis

%Configuración de Opciones para el Análisis de Movimiento
Options.LineOrFrame = 2; % Line = 1, Frame = 2
Options.MotionType = 2; % Displacement = 1, particle velocity = 2;
Options.LoupasAxialWin = []; % 10 pixels along depth, if empty, no Loupas;
Options.SmoothingWinPer = 0.05;% [0.05]; % if empty, no smoothing %suavizado de datos

[loaded_phases] = MotionAnalysis(Cplx_Matrix,Border.Idx,Options);
%analiza el movimiento en la matriz de datos complejos (Cplx_Matrix) usando los índices de borde (Border.Idx) 
%y las opciones especificadas
% La función devuelve las fases del movimiento detectado

% Options.MotionType = 2; 
% Options.Delta = 5;
% Options.LoupasAxialWin = []; 
% Options.SmoothingWinPer = [0.05];
% [loaded_phases_Border] = MotionAnalysisBorder(Cplx_Matrix,round(Border.Idx),Options);

%Configuración y Análisis Adicional para Bordes
Options.MotionType = 2; % Displacement = 1, particle velocity = 2
Options.Delta = 10;
Options.LoupasAxialWin =20;% [20]; 
Options.SmoothingWinPer =0.05;% [0.05];
[loaded_phases_Border] = MotionAnalysisBorder(Cplx_Matrix,round(Border.Idx),Options);
%Llama a la función MotionAnalysisBorder para analizar el movimiento específicamente en las regiones de borde
%Esta función devuelve las fases de movimiento a lo largo de los bordes detectados (loaded_phases_Border)


loaded_phases_Border_Disp = cumsum(loaded_phases_Border,2); %cumsum: suma acumulativa

figure
imagesc(loaded_phases_Border')%muestra la imagen de la matriz transpuesta
%imagesc(loaded_phases_Border_Disp')
%imagesc(loaded_phases_Border)
title('loaded phases Border');
% Time filtering

%hago un filtrado en el dominio del tiempo
Ts = 1/(OCT_system.a_scan_rate*1000); %OCT_system.a_scan_rate 200kHz = 5us (tasa de escaneo) 
%se calcula el intervalo de muestreo en microsegundos

Line = squeeze(loaded_phases_Border(50,:));% extraigo una linea de loaded_phases_Border
FFT = fft(Line,2^12);% calculo la fft para analizar su contenido en frecuencia 
freq = linspace(0,1,2^12)/Ts;%creo un vector de frecuencias en base a la FFT

%Time = [0:Ts:(OCE_system.NewTimeSize-2)*Ts]*1e3;
Time = (0:Ts:(OCE_system.NewTimeSize-2)*Ts)*1e3;%creo un vector de tiempo en milisegundos


fig = figure;%creo una figura
plot(freq,abs(FFT))%ploteo la FFT en funcion de las frecuencias
grid on
ylabel('Magnitude (Arb.)');
xlabel('Frequency (Hz)');
title('FFT of the signal');
axis([0 8000 0 max(abs(FFT))*1.1])
h = imrect(gca,[1e3-200,-200,400,(max(abs(FFT))*1.1)+400]);% el usuario elige la sección acotada de frec 
position = wait(h); 
b = fir1(50,[position(1)*2*Ts (position(1)+position(3))*2*Ts]);%filtro FIR en base a las frecuencias acotadas por usuario 
delay = mean(grpdelay(b));%grpdelay Retardo promedio del filtro 
%guardo la figura de la FFT
saveas(fig,'Spectrum.fig');
saveas(fig,'Spectrum.tif');

%Aplicación del Filtro FIR y Procesamiento de Imágen
gcf = figure; %Crea una figura para visualizar la señal en el dominio del tiempo tanto en su forma cruda como filtrada
hold on
plot(Time,(Line),'DisplayName','Raw signal','LineWidth',1,'Color',[0 0 0])
plot(Time(1:end-delay),filter(b,1,Line(delay+1:end)),...
     'DisplayName','Filtered','LineWidth',1,'Color',[1 0 0])
grid on
ylabel('Particle velocity (Arb.)');
xlabel('time (ms)');
title('Time signal');
axis([Time(1) Time(end) min(Line)-0.005 max(Line)+0.005])
set(gca,'FontSize', 14);
legend(gca,'show');
saveas(gcf,'TimeProfile.fig');
saveas(gcf,'TimeProfile.tif');


%realizo el Procesamiento y Filtrado de Datos de Imágenes
Frames1 = loaded_phases;%cargo las fases
Frames1_border = loaded_phases_Border;%cargo las fases del borde
for j=1:size(loaded_phases_Border,1) %aplico el filtrado a cada frame de datos y de los datos del borde

    signal=squeeze(loaded_phases(j,:,:));
    signal_border=squeeze(loaded_phases_Border(j,:));
    if isnan(sum(signal_border(:))) %reemplazo los frame que tienen datos NaN por zeros
        Frames1(j,:,:) = zeros(size(signal));
        
        Frames1_border(j,:) = zeros(1,size(signal_border,2));
    else
       Frames1(j,:,:)=filter(b,1,signal')';
       Frames1_border(j,:) = filter(b,1,signal_border);
        %Frames1_border(j,:) = signal_border;
    end

    %j
end


%Frames1_Filt = medfilt3(Frames1,[7 3 5],'Symmetric');

Frame_BK = mean(Frames1(:,:,1:end),3); %calculo el promedio de todos los frames en una sola matriz

%Frame_BK = zeros(size(Frames1(:,:,1)));


for i = 1:length(Time) % es segun lo que eligo acotar en la tercera dim% 1:195
    
    % aplicar un filtro de mediana a la diferencia entre la imagen actual y
    % una imagen de fondo para reducir ruido y artefactos
    Frame_tmp = medfilt2(Frames1(:,:,i)-Frame_BK,[3 3],'Symmetric');
    %La resta Frames1(:,:,i) - Frame_BK calcula la diferencia entre la imagen actual y el promedio de la imagen(frames)
    %[3 3] especifica el tamaño del vecindario del filtro de mediana
    %'Symmetric' es una opción que indica que el borde de la imagen debe ser tratado de manera simétrica durante el filtrado


    %Frame_tmp = medfilt2(Frames1(:,:,i),[3 3],'Symmetric');
    %Frame_tmp = Frame_tmp -1*repmat(Frames1_border(:,i),1,size(Frames1,2));
    %Frame_tmp = medfilt2(Frame_tmp,[5 3],'Symmetric');
    
    %Visualizar cada frame en una figura y aplica un colormap fireice para la representación visual
    c.gcf = figure(1); %creo una nueva figura
    imagesc(Xaxis, Zaxis,Frame_tmp')
    clim([-0.3 0.3]);%([-5 5])%
    ylabel('y-axis (mm)');
    xlabel('x-axis (mm)');
    %axis equal
    axis([0 Xaxis(end) 0 Zaxis(end)])
    %title(['Motion frames - Filtered (Time = ',num2str(round((i-1)*Ts*1e3,2),'%10.2f\n'),' ms)'])   
    set(gca,'FontSize', 14);
    colormap(fireice);
    drawnow
    
end

disp('Time filtering ok');

%% Saving Video
%procesar una secuencia de imágenes y guardar el resultado en un archivo de video
%da como resultado un video que muestra una secuencia de imágenes procesadas y filtradas con un fondo y un primer plano fusionados, 
%proporcionando una visualización clara y continua

%configuracion de video
CLim = 0.5;%5%0.05;%limite de color (contraste)
%rango de frames 0 a 200
% se descartan los primeros 10 frames y los últimos 6
Time_ini = 10;
Time_end = 194;
%vector de time que corresponden a los frames 
Time1 = Time(Time_ini:end-6); %(Time_ini:Time_end) 

%Crear y Configurar el Video
aviobj = VideoWriter('Video_2D_Filtered1.avi'); 
%aviobj = VideoWriter(['Video_2D_Filtered1.avi']); 
aviobj.FrameRate = 10; 
open(aviobj); 

    I = uint8(255*mat2gray(Bmode_IntLog, [OCE_system.i_thresh_low OCE_system.i_thresh_high]));%I convierte los datos Bmode_IntLog en una imagen en escala de grises
    bg = ind2rgb(I,gray(255));%bg convierte la imagen en escala de grises en una imagen RGB
    bgImg = double(bg).*repmat(Bmode_Mask,1,1,3);%aplica una máscara Bmode_Mask al fondo
    alphaFactor = 0.5;
    % ajusto la imagen del fondo en función de Mask 
    bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*repmat(Bmode_Mask,1,1,3);
    bgImgAlpha_out = bgImg.*(1-repmat(Bmode_Mask,1,1,3));
    bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;
    cont = 1;
    Frames2 = [];
  
for j = 1:length(Time1)%Time_ini:Time_end %Procesar y Grabar Frames en el Video
    %se calcula como la diferencia entre el frame actual y un fondo de
    %referencia Frame_BK, seguido de un filtrado medfilt2
    Frame_tmp = squeeze(Frames1(:,:,j)-Frame_BK)';
%     Frame_tmp = squeeze(Frame_tmp)...
%                 -1*repmat(Frames1_border_BK(:,j),1,OCE_system.NewDepthSize)';

    Frame_tmp = medfilt2(Frame_tmp,[5 3],'Symmetric');
    Frames2(:,:,cont) = Frame_tmp';
    cont = cont+1;

    %mat2gray: Convertir una matriz en una imagen en escala de grises
    II = uint8(255*mat2gray(Frame_tmp, [-CLim CLim]));%II normaliza y convierte el frame filtrado en una imagen RGB

    im = ind2rgb(II,fireice(255));

    fgImg = double(im);%se aplica una máscara a la imagen del primer plano
    fgImgAlpha = alphaFactor .* fgImg.*(repmat(Bmode_Mask,1,1,3));

    fusedImg = fgImgAlpha + bgImgAlpha;%sumo la imagen de fondo con la del primer plano

    gcf=figure(1);
    imagesc(Xaxis,Zaxis,fusedImg)
    %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
    ylabel('z-axis (mm)');
    xlabel('y-axis (mm)');
    %axis equal
    axis([0 Xaxis(end) 0 Zaxis(end)])
    title(['Motion frames - Filtered (Time = ',num2str(round(Time(j),2),'%10.2f\n'),' ms)'])   
    set(gca,'FontSize',14)
    drawnow
    
  
    %pause(0.2)
    

    F=getframe(gcf); %capturo la imagen actual y la grabo en el video
    writeVideo(aviobj,F);
end
%cierro el video
close(aviobj);
fclose all;
disp('Motion frames and saving video ok');

%% SpaceTime

CLim = 0.3;%5%0.1;%limite de color
%Aquí se está eliminando el promedio de cada fila de la matriz Frames1_border para obtener Frames1_border_BK
Frames1_border_BK = Frames1_border - repmat(mean(Frames1_border(:,1:end),2),1,size(Frames1_border,2));
SpaceTime = medfilt2(Frames1_border_BK,[3 3],'Symmetric');%aplica un filtro mediano de tamaño 3x3 a la matriz Frames1_border_BK para eliminar ruido

%Generación de la figura y la visualización
gcf = figure;
%imagesc(Xaxis,Ti,SpaceTime')%muestra la matriz SpaceTime como una imagen
imagesc(SpaceTime')
%SpaceTime' se utiliza para que los ejes X e Y se correspondan correctamente con Xaxis y Time
colormap(fireice)
clim([-CLim CLim])
ylabel('time (ms)')
xlabel('x-axis (mm)')
title('Space-time map')
set(gca,'FontSize',14)
%axis([0 7 2 5])
%Guardo la imagen
saveas(gcf,'SpaceTimeMap.fig');
saveas(gcf,'SpaceTimeMap.tif');
disp('Space time map and save image ok');
%% SpaceTime NEW
%hacer el filtering directional por derecha e izquierda
CLim = 0.1;%5%0.1;%limite de color 
%Aquí se está eliminando el promedio de cada fila de la matriz Frames1_border para obtener Frames1_border_BK
% Frames1_border_BK = Frames1_border - repmat(mean(Frames1_border(:,1:end),2),1,size(Frames1_border,2));
% SpaceTime = medfilt2(Frames1_border_BK,[3 3],'Symmetric');%aplica un filtro mediano de tamaño 3x3 a la matriz Frames1_border_BK para eliminar ruido
Tres = Time(2);
Xres = Xaxis(2);
%Zres = Zaxis(2);
points = size(SpaceTime,1);
Dir = 'right';
[SpaceTimeNEW_Right] = DirectionalFilter2(SpaceTime',Tres,Xres,points,Dir);
gcf = figure;
imagesc(Xaxis,Time,SpaceTimeNEW_Right)%muestra la matriz SpaceTime como una imagen
%SpaceTime' se utiliza para que los ejes X e Y se correspondan correctamente con Xaxis y Time
colormap(fireice)
clim([-CLim CLim])
ylabel('time (ms)')
xlabel('x-axis (mm)')
title('Space-time RIGHT map')
set(gca,'FontSize',14)
%axis([0 7 2 5])
%Guardo la imagen
saveas(gcf,'SpaceTimeMapRIGHT.fig');
saveas(gcf,'SpaceTimeMapRIGHT.tif');
Dir = 'left';
[SpaceTimeNEW_Left] = DirectionalFilter2(SpaceTime',Tres,Xres,points,Dir);
gcf = figure;
imagesc(Xaxis,Time,SpaceTimeNEW_Left)%muestra la matriz SpaceTime como una imagen
%SpaceTime' se utiliza para que los ejes X e Y se correspondan correctamente con Xaxis y Time
colormap(fireice)
clim([-CLim CLim])
ylabel('time (ms)')
xlabel('x-axis (mm)')
title('Space-time LEFT map')
set(gca,'FontSize',14)
%axis([0 7 2 5])
%Guardo la imagen
saveas(gcf,'SpaceTimeMapLEFT.fig');
saveas(gcf,'SpaceTimeMapLEFT.tif');
SpaceTimeNEW_Right=SpaceTimeNEW_Right';
SpaceTimeNEW_Left=SpaceTimeNEW_Left';
%% Directional Filtering 3D

%Se aplican tres tipos de filtros direccionales a los datos para hacer análisis de datos espaciales y temporales
Tres = Time(2);
Xres = Xaxis(2);
Zres = Zaxis(2);
Dir = 'right';
%Frames2: Es un volumen de datos 3D de tamaño [m, n, o] 
%Tres: Resolución temporal (espaciado entre los fotogramas)
%Xres: Resolución espacial en el eje X (lateral)
%Zres: Resolución espacial en el eje Z (profundidad)
%Dir: Dirección del filtrado ('left', 'right', 'depth')
[Frames2_Filtered_Right] = DirectionalFilter3(Frames2,Tres,Xres,Zres,Dir);
Dir = 'left';
[Frames2_Filtered_Left] = DirectionalFilter3(Frames2,Tres,Xres,Zres,Dir);
Dir = 'depth';
[Frames2_Filtered_Depth] = DirectionalFilter3(Frames2,Tres,Xres,Zres,Dir);



%aviobj = Video  Writer(['Video_2D_Filtered_Right.avi']); 
aviobj = VideoWriter('Video_2D_Filtered_Right.avi'); 

aviobj.FrameRate = 10; %tasa de fotogramas se establece en 10 fps
open(aviobj); 
for j = 1:size(Frames2_Filtered_Right,3)%Loop para cada fotograma
    
    Frame_tmp = squeeze(Frames2_Filtered_Right(:,:,j))';%Se extrae el fotograma y se transponen (squeeze(Frames2_Filtered_Right(:,:,j))')
    %Frame_tmp = medfilt2(Frame_tmp,[3 3],'Symmetric');

    II = uint8(255*mat2gray(Frame_tmp, [-CLim CLim]));
    im = ind2rgb(II,fireice(255));

    fgImg = double(im);
    fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);

    fusedImg = fgImgAlpha + bgImgAlpha;%se suman(interponen) imágenes de fgImgAlpha y fondo bgImgAlpha

    gcf=figure(1);%Se crea una visualización 2D del fotograma actual
    imagesc(Xaxis,Zaxis,fusedImg)
    %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
    ylabel('z-axis (mm)');
    xlabel('y-axis (mm)');
    %axis equal
    axis([0 Xaxis(end) 0 Zaxis(end)])
    title(['Motion frames - Filtered (Time = ',num2str(round(Time(j),2),'%10.2f\n'),' ms)'])   
    set(gca,'FontSize',14)
    drawnow
    
  
    %pause(0.2)
    

    F=getframe(gcf); %Se captura el fotograma y se añade al video
    writeVideo(aviobj,F);
end
close(aviobj);
fclose all;
disp('Video filtered right ok');

aviobj = VideoWriter('Video_2D_Filtered_Left.avi'); 
aviobj.FrameRate = 10; 
open(aviobj);  
for j = 1:size(Frames2_Filtered_Left,3)%Loop para cada fotograma
    
    Frame_tmp = squeeze(Frames2_Filtered_Left(:,:,j))';%Se extrae el fotograma y se transponen (squeeze(Frames2_Filtered_Right(:,:,j))')
    %Frame_tmp = medfilt2(Frame_tmp,[3 3],'Symmetric');

    II = uint8(255*mat2gray(Frame_tmp, [-CLim CLim]));
    im = ind2rgb(II,fireice(255));

    fgImg = double(im);
    fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);

    fusedImg = fgImgAlpha + bgImgAlpha;%se suman(interponen) imágenes de fgImgAlpha y fondo bgImgAlpha

    gcf=figure(1);%Se crea una visualización 2D del fotograma actual
    imagesc(Xaxis,Zaxis,fusedImg)
    %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
    ylabel('z-axis (mm)');
    xlabel('y-axis (mm)');
    %axis equal
    axis([0 Xaxis(end) 0 Zaxis(end)])
    title(['Motion frames - Filtered (Time = ',num2str(round(Time(j),2),'%10.2f\n'),' ms)'])   
    set(gca,'FontSize',14)
    drawnow
    
  
    %pause(0.2)
    

    F=getframe(gcf); %Se captura el fotograma y se añade al video
    writeVideo(aviobj,F);
end
close(aviobj);
fclose all;
disp('Video filtered left ok');

aviobj = VideoWriter('Video_2D_Filtered_Depth.avi'); 
aviobj.FrameRate = 10; 
open(aviobj);  
for j = 1:size(Frames2_Filtered_Depth,3)%Loop para cada fotograma
    
    Frame_tmp = squeeze(Frames2_Filtered_Depth(:,:,j))';%Se extrae el fotograma y se transponen (squeeze(Frames2_Filtered_Right(:,:,j))')
    %Frame_tmp = medfilt2(Frame_tmp,[3 3],'Symmetric');

    II = uint8(255*mat2gray(Frame_tmp, [-CLim CLim]));
    im = ind2rgb(II,fireice(255));

    fgImg = double(im);
    fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);

    fusedImg = fgImgAlpha + bgImgAlpha;%se suman(interponen) imágenes de fgImgAlpha y fondo bgImgAlpha

    gcf=figure(1);%Se crea una visualización 2D del fotograma actual
    imagesc(Xaxis,Zaxis,fusedImg)
    %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
    ylabel('z-axis (mm)');
    xlabel('y-axis (mm)');
    %axis equal
    axis([0 Xaxis(end) 0 Zaxis(end)])
    title(['Motion frames - Filtered (Time = ',num2str(round(Time(j),2),'%10.2f\n'),' ms)'])   
    set(gca,'FontSize',14)
    drawnow
    
  
    %pause(0.2)
    

    F=getframe(gcf); %Se captura el fotograma y se añade al video
    writeVideo(aviobj,F);
end
close(aviobj);
fclose all;
disp('Video filtered depth ok');
%% SpaceTime Depth

% SpaceTime1 = [];
% for i = 1:500
%     pos_depth = round(Border.Idx(i));
%     SpaceTime1(i,:) = squeeze(Frames2_Filtered_Depth(i,pos_depth,:));
% end
% 
% gcf = figure;
% imagesc(Xaxis,Time,SpaceTime1')
% colormap(fireice)
% caxis([-CLim CLim])
% ylabel('time (ms)')
% xlabel('x-axis (mm)')
% title('Space-time map')
% set(gca,'FontSize',14)
% %axis([0 7 2 5])


%% Speed calculation

CLim = 0.1;%5;%0.1;
NumBscanSingle =measurement.ScanInfo.Bframes_in_3Dscan;%Número de imágenes B-scan en un escaneo(measurement.ScanInfo)
Angle = 0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(OCT_system.NumAngles-1);%vector de los ángulos en grados a los que se calcularán las velocidades
%Angle = [0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(OCT_system.NumAngles-1)];

for i = 1:OCT_system.NumAngles%Recorre todos los ángulos especificados en Angle
    %SpeedAnalysis: calcula la velocidad en función del tiempo y el espacio para cada ángulo
    %SpaceTime(NumBscanSingle*(i-1)+1:NumBscanSingle*(i),:)' aca se extrae los datos de SpaceTime para el ángulo actual
    %Xaxis y Time especifican las coordenadas espaciales y temporales para el análisis
    %GroupSpeed almacena los resultados de velocidad para cada ángulo
    [GroupSpeed(i*2-1,1),GroupSpeed(i*2-1,2)] = SpeedAnalysis(SpaceTime(NumBscanSingle*(i-1)+1:NumBscanSingle*(i),:)',Xaxis(1:NumBscanSingle),Time(1:end),['SpeedCalculation_Left_',num2str(Angle(i))],CLim);
    [GroupSpeed(i*2,1),GroupSpeed(i*2,2)] = SpeedAnalysis(SpaceTime(NumBscanSingle*(i-1)+1:NumBscanSingle*(i),:)',Xaxis(1:NumBscanSingle),Time(1:end),['SpeedCalculation_Right_',num2str(Angle(i))],CLim);
end
%vector que contiene todos los ángulos
AnglesAll = (0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(2*OCT_system.NumAngles-1))';
%AnglesAll = [0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(2*OCT_system.NumAngles-1)]';

%GroupSpeed_New = GroupSpeed([1 4 5 8 2 3 6 7],1);
[idx_angles] = IDXSelection(OCT_system.NumAngles);%selecciona los índices de los angles
GroupSpeed_New = GroupSpeed(idx_angles,1);%velocidades

figure
polarplot(AnglesAll/180*pi,GroupSpeed_New)%se hace un gráfico polar para visualizar las velocidades en función del ángulo

save('Speeds_vs_Angles.mat','GroupSpeed','GroupSpeed_New','AnglesAll');
%%
%HACER EN COMBINACION CON LO ANTERIOR
i = 3;
GroupSpeed_NewAll(:,i) = GroupSpeed_New(:,1);
MeanSpeed = mean(GroupSpeed_NewAll(:,:),2);
ErrorSpeed = std(GroupSpeed_NewAll,[],2);

figure
polarplot([AnglesAll/180*pi; 0],[MeanSpeed;MeanSpeed(1)])

figure
polarwitherrorbar([AnglesAll/180*pi; 0]',[MeanSpeed;MeanSpeed(1)]',[ErrorSpeed;ErrorSpeed(1)]')

save('Speeds_vs_Angles_Avg_4.mat','GroupSpeed_NewAll','MeanSpeed','ErrorSpeed','AnglesAll');

%% Speed calculation NEW

CLim = 0.1;%5;%0.1;
NumBscanSingle =measurement.ScanInfo.Bframes_in_3Dscan;%Número de imágenes B-scan en un escaneo(measurement.ScanInfo)
Angle = 0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(OCT_system.NumAngles-1);%vector de los ángulos en grados a los que se calcularán las velocidades
%Angle = [0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(OCT_system.NumAngles-1)];

for i = 1:OCT_system.NumAngles%Recorre todos los ángulos especificados en Angle
    %SpeedAnalysis: calcula la velocidad en función del tiempo y el espacio para cada ángulo
    %SpaceTime(NumBscanSingle*(i-1)+1:NumBscanSingle*(i),:)' aca se extrae los datos de SpaceTime para el ángulo actual
    %Xaxis y Time especifican las coordenadas espaciales y temporales para el análisis
    %GroupSpeed almacena los resultados de velocidad para cada ángulo
    [GroupSpeedN(i*2-1,1),GroupSpeedN(i*2-1,2)] = SpeedAnalysis(SpaceTimeNEW_Left(NumBscanSingle*(i-1)+1:NumBscanSingle*(i),:)',Xaxis(1:NumBscanSingle),Time(1:end),['SpeedCalculation_Left_NEW',num2str(Angle(i))],CLim);
    [GroupSpeedN(i*2,1),GroupSpeedN(i*2,2)] = SpeedAnalysis(SpaceTimeNEW_Right(NumBscanSingle*(i-1)+1:NumBscanSingle*(i),:)',Xaxis(1:NumBscanSingle),Time(1:end),['SpeedCalculation_Right_NEW',num2str(Angle(i))],CLim);
end
%vector que contiene todos los ángulos
AnglesAllN = (0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(2*OCT_system.NumAngles-1))';
%AnglesAll = [0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(2*OCT_system.NumAngles-1)]';

%GroupSpeed_New = GroupSpeed([1 4 5 8 2 3 6 7],1);
[idx_angles] = IDXSelection(OCT_system.NumAngles);%selecciona los índices de los angles
GroupSpeed_NewN = GroupSpeedN(idx_angles,1);%velocidades

figure
polarplot(AnglesAllN/180*pi,GroupSpeed_NewN)%se hace un gráfico polar para visualizar las velocidades en función del ángulo

save('Speeds_vs_Angles_NEW.mat','GroupSpeedN','GroupSpeed_NewN','AnglesAllN');
%%
%HACER EN COMBINACION CON LO ANTERIOR
i = 3;
GroupSpeed_NewAllN(:,i) = GroupSpeed_NewN(:,1);
MeanSpeedN = mean(GroupSpeed_NewAllN(:,:),2);
ErrorSpeedN = std(GroupSpeed_NewAllN,[],2);

figure
polarplot([AnglesAllN/180*pi; 0],[MeanSpeedN;MeanSpeedN(1)])

figure
polarwitherrorbar([AnglesAllN/180*pi; 0]',[MeanSpeedN;MeanSpeedN(1)]',[ErrorSpeedN;ErrorSpeedN(1)]')

save('Speeds_vs_Angles_Avg_4N.mat','GroupSpeed_NewAllN','MeanSpeedN','ErrorSpeedN','AnglesAllN');


%% Speed Lamb dispersion at a 'pos' depth
%realiza un análisis de dispersión de velocidad para diferentes direcciones de propagación en un conjunto de datos espacio-temporales

%ParamsDisp: estructura de parámetros utilizados para la función de análisis de dispersión
DirFlag = 'left';
ParamsDisp.FFT_Nx = (2^13)+1; % Number of samples in FFT along space (must be odd number)
ParamsDisp.FFT_Nt = (2^13)+1; % Number of samples in FFT along time (must be odd number)
ParamsDisp.Cut_InvLambda = 1/(0.1e-3); % Inverse lambda cut value (e.g. 1 / 1mm);
                                 % If not known, leave empty.
ParamsDisp.Cut_Freq = 6000; % Inverse frequency cut value (e.g. 1000 Hz);
                        % If not known, leave empty.
ParamsDisp.Thres_Jump = 40;  % Jump treshold for multi-mode cases. Typically 40.
ParamsDisp.Thres_Mag = 0.5;%0.01;  % Intensity threshold in the k-w space (e.g. 20% is 0.2)

%DisperssionSpeedFull: Función que calcula la velocidad de dispersión, la frecuencia y la magnitud de la FFT para una dirección de propagación 
[Speed_disp{1},freq_disp{1},FFT_time_disp{1}] = DisperssionSpeedFull (SpaceTime,Xaxis,Time,ParamsDisp,DirFlag);
Speed_disp{1} = smooth(Speed_disp{1},0.1,'lowess');

%estructura de parámetros
DirFlag = 'right';
ParamsDisp.FFT_Nx = (2^13)+1; % Number of samples in FFT along space (must be odd number)
ParamsDisp.FFT_Nt = (2^13)+1; % Number of samples in FFT along time (must be odd number)
ParamsDisp.Cut_InvLambda = 1/(0.1e-3); % Inverse lambda cut value (e.g. 1 / 1mm);
                                 % If not known, leave empty.
ParamsDisp.Cut_Freq = 6000; % Inverse frequency cut value (e.g. 1000 Hz);
                        % If not known, leave empty.
ParamsDisp.Thres_Jump = 40;  % Jump treshold for multi-mode cases. Typically 40.
ParamsDisp.Thres_Mag = 0.5;%0.01;  % Intensity threshold in the k-w space (e.g. 20% is 0.2)
%DisperssionSpeedFull: Función que calcula la velocidad de dispersión, la frecuencia y la magnitud de la FFT para una dirección de propagación 
[Speed_disp{2},freq_disp{2},FFT_time_disp{2}] = DisperssionSpeedFull (SpaceTime,Xaxis,Time,ParamsDisp,DirFlag);%DisperssionSpeedFull aca cambio el Clim
Speed_disp{2} = smooth(Speed_disp{2},0.1,'lowess');

%Grafica la velocidad y la magnitud de la FFT
gcf = figure;
yyaxis left
plot(freq_disp{1},Speed_disp{1},'DisplayName','Left prop. - Speed')
ylim([0 10])
ylabel('Speed (m/s)')
yyaxis right
plot(freq_disp{1},FFT_time_disp{1}/max(FFT_time_disp{1}),'DisplayName','Left prop. - Spectrum')
ylabel('Magnitude FFT (Arb.)')
xlabel('Frequency (Hz)')
xlim([0 2500])
%xlim([2000 4000])

hold on

yyaxis left
plot(freq_disp{2},Speed_disp{2},'DisplayName','Right prop. - Speed')
ylim([0 20])
ylabel('Speed (m/s)')
yyaxis right
plot(freq_disp{2},FFT_time_disp{2}/max(FFT_time_disp{2}),'DisplayName','Right prop. - Spectrum')
ylabel('Magnitude FFT (Arb.)')
xlabel('Frequency (Hz)')
xlim([0 6000])
%xlim([2000 4000])

legend(gca,'show','Location','northeast');
set(gca,'FontSize',14)
saveas(gcf,'SpeedDispersion_0.fig');
saveas(gcf,'SpeedDispersion_0.tif');

%% Speed Lamb dispersion at a 'pos' depth NEW
%realiza un análisis de dispersión de velocidad para diferentes direcciones de propagación en un conjunto de datos espacio-temporales

%ParamsDisp: estructura de parámetros utilizados para la función de análisis de dispersión
DirFlag = 'left';
ParamsDisp.FFT_Nx = (2^13)+1; % Number of samples in FFT along space (must be odd number)
ParamsDisp.FFT_Nt = (2^13)+1; % Number of samples in FFT along time (must be odd number)
ParamsDisp.Cut_InvLambda = 1/(0.1e-3); % Inverse lambda cut value (e.g. 1 / 1mm);
                                 % If not known, leave empty.
ParamsDisp.Cut_Freq = 6000; % Inverse frequency cut value (e.g. 1000 Hz);
                        % If not known, leave empty.
ParamsDisp.Thres_Jump = 40;  % Jump treshold for multi-mode cases. Typically 40.
ParamsDisp.Thres_Mag = 0.5;%0.01;  % Intensity threshold in the k-w space (e.g. 20% is 0.2)

%DisperssionSpeedFull: Función que calcula la velocidad de dispersión, la frecuencia y la magnitud de la FFT para una dirección de propagación 
[Speed_disp{1},freq_disp{1},FFT_time_disp{1}] = DisperssionSpeedFull (SpaceTimeNEW_Left,Xaxis,Time,ParamsDisp,DirFlag);
Speed_disp{1} = smooth(Speed_disp{1},0.1,'lowess');

%estructura de parámetros
DirFlag = 'right';
ParamsDisp.FFT_Nx = (2^13)+1; % Number of samples in FFT along space (must be odd number)
ParamsDisp.FFT_Nt = (2^13)+1; % Number of samples in FFT along time (must be odd number)
ParamsDisp.Cut_InvLambda = 1/(0.1e-3); % Inverse lambda cut value (e.g. 1 / 1mm);
                                 % If not known, leave empty.
ParamsDisp.Cut_Freq = 6000; % Inverse frequency cut value (e.g. 1000 Hz);
                        % If not known, leave empty.
ParamsDisp.Thres_Jump = 40;  % Jump treshold for multi-mode cases. Typically 40.
ParamsDisp.Thres_Mag = 0.5;%0.01;  % Intensity threshold in the k-w space (e.g. 20% is 0.2)
%DisperssionSpeedFull: Función que calcula la velocidad de dispersión, la frecuencia y la magnitud de la FFT para una dirección de propagación 
[Speed_disp{2},freq_disp{2},FFT_time_disp{2}] = DisperssionSpeedFull (SpaceTimeNEW_Right,Xaxis,Time,ParamsDisp,DirFlag);
Speed_disp{2} = smooth(Speed_disp{2},0.1,'lowess');

%Grafica la velocidad y la magnitud de la FFT
gcf = figure;
yyaxis left
plot(freq_disp{1},Speed_disp{1},'DisplayName','Left prop. - Speed')
ylim([0 10])
ylabel('Speed (m/s)')
yyaxis right
plot(freq_disp{1},FFT_time_disp{1}/max(FFT_time_disp{1}),'DisplayName','Left prop. - Spectrum')
ylabel('Magnitude FFT (Arb.)')
xlabel('Frequency (Hz)')
xlim([0 2500])
%xlim([2000 4000])

hold on

yyaxis left
plot(freq_disp{2},Speed_disp{2},'DisplayName','Right prop. - Speed')
ylim([0 20])
ylabel('Speed (m/s)')
yyaxis right
plot(freq_disp{2},FFT_time_disp{2}/max(FFT_time_disp{2}),'DisplayName','Right prop. - Spectrum')
ylabel('Magnitude FFT (Arb.)')
xlabel('Frequency (Hz)')
xlim([0 6000])
%xlim([2000 4000])

legend(gca,'show','Location','northeast');
set(gca,'FontSize',14)
saveas(gcf,'SpeedDispersion_0_NEW.fig');
saveas(gcf,'SpeedDispersion_0_NEW.tif');


%% Wave speed 2D - 1000 Hz

%Configuración de Parámetros y Datos
Params.Freq = 3500;%1000
Params.FFT_Nx = 2^11;

Ts = 1/(OCT_system.a_scan_rate*1000);% Calcula el intervalo de muestreo 
freq = linspace(0,1,Params.FFT_Nx)/Ts;
Nf = find(freq>Params.Freq);%idx de frecuencias
Nf = Nf(1);

Params.Threshold = [10 10];
Params.FFT_FreqSample = Nf;
Params.WinSize = [1 0.1]; 

%estimo la velocidad 
[Speed2D, Xaxis_E, Zaxis_E] = SpeedEstimation_PhaseDeriv(Frames2,Xaxis,Zaxis,Params);
Speed2D_Equiv_Filt = medfilt2(abs(Speed2D.Equiv),[3 3],'Symmetric');

figure
imagesc(Xaxis_E,Zaxis_E,abs(Speed2D_Equiv_Filt))
clim([0 10])
colormap(jet)
%interpolo los datos
SpeedEquivInterp = interp2(Xaxis_E,Zaxis_E,Speed2D_Equiv_Filt,Xaxis,Zaxis,'linear',0.001);

% figure
% imagesc(Xaxis,Zaxis,SpeedEquivInterp.*Bmode_Mask)
% caxis([0 5])

gcf = figure;
imagesc(Xaxis,Zaxis,SpeedEquivInterp.*Bmode_Mask)
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
title(['Speed Map - ',num2str(Params.Freq),' Hz'])
%axis equal
axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(end)])
set(gca,'FontSize',14)
colorbar
colormap(jet)
clim([0 10])
saveas(gcf,['Speed_Map_Alone_',num2str(Params.Freq),'Hz.fig']);
saveas(gcf,['Speed_Map_Alone_',num2str(Params.Freq),'Hz.tif']);

% gcf = figure;
% imagesc(Xaxis,Zaxis,SpeedEquivInterp.*Bmode_Mask)
% ylabel('z-axis (mm)');
% xlabel('x-axis (mm)');
% title(['Speed Map - ',num2str(Params.Freq),' Hz'])
% axis equal
% axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(end)])
% set(gca,'FontSize',14)
% colorbar
% colormap(jet)
% caxis([0 10])
% saveas(gcf,['Speed_Map_Alone_',num2str(Params.Freq),'Hz_New.fig']);
% saveas(gcf,['Speed_Map_Alone_',num2str(Params.Freq),'Hz_New.tif']);



I = uint8(255*mat2gray(Bmode_IntLog.*Bmode_Mask, [OCE_system.i_thresh_low OCE_system.i_thresh_high]));
bg = ind2rgb(I,gray(255));
bgImg = double(bg);
alphaFactor = 0.4;
bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*Bmode_Mask;
bgImgAlpha_out = bgImg.*(1-Bmode_Mask);
bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;

II = uint8(255*mat2gray(SpeedEquivInterp.*Bmode_Mask, [0 10]));
im = ind2rgb(II,hot(255));

fgImg = double(im);
fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);
fusedImg = fgImgAlpha + bgImgAlpha;

gcf=figure;
imagesc(Xaxis,Zaxis,fusedImg)
%imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
%axis equal
axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(end)])
title(['Speed Map - ',num2str(Params.Freq),' Hz'])
set(gca,'FontSize',14)
colorbar
colormap(hot)
clim([0 10])
drawnow
saveas(gcf,['Elastogram_2D_Hot_',num2str(Params.Freq),'Hz.fig']);
saveas(gcf,['Elastogram_2D_Hot_',num2str(Params.Freq),'Hz.tif']);


I = uint8(255*mat2gray(Bmode_IntLog.*Bmode_Mask, [OCE_system.i_thresh_low OCE_system.i_thresh_high]));
bg = ind2rgb(I,gray(255));
bgImg = double(bg);
alphaFactor = 0.5;
bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*Bmode_Mask;
bgImgAlpha_out = bgImg.*(1-Bmode_Mask);
bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;

II = uint8(255*mat2gray(SpeedEquivInterp.*Bmode_Mask, [0 10]));
im = ind2rgb(II,jet(255));

fgImg = double(im);
fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);
fusedImg = fgImgAlpha + bgImgAlpha;


gcf=figure;
imagesc(Xaxis,Zaxis,fusedImg)
%imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
%axis equal
axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(end)]) 
title(['Speed Map - ',num2str(Params.Freq),' Hz'])
set(gca,'FontSize',14)
colorbar
colormap(jet)
clim([0 10])
drawnow
saveas(gcf,['Elastogram_2D_Jet1_',num2str(Params.Freq),'Hz.fig']);
saveas(gcf,['Elastogram_2D_Jet1_',num2str(Params.Freq),'Hz.tif']);

% I = uint8(255*mat2gray(Bmode_IntLog, [OCE_system.i_thresh_low OCE_system.i_thresh_high]));
% bg = ind2rgb(I,gray(255));
% bgImg = double(bg);
% alphaFactor = 0.5;
% bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*Bmode_Mask;
% bgImgAlpha_out = bgImg.*(1-Bmode_Mask);
% bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;
% 
% II = uint8(255*mat2gray(SpeedEquivInterp.*Bmode_Mask, [2 4]));
% im = ind2rgb(II,jet(255));
% 
% fgImg = double(im);
% fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);
% fusedImg = fgImgAlpha + bgImgAlpha;
% 
% 
% gcf=figure;
% imagesc(Xaxis,Zaxis,fusedImg)
% %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
% ylabel('z-axis (mm)');
% xlabel('x-axis (mm)');
% axis equal
% axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(end)]) 
% title(['Speed Map - ',num2str(Params.Freq),' Hz'])
% set(gca,'FontSize',14)
% colorbar
% colormap(jet)
% caxis([2 4])
% drawnow
% saveas(gcf,['Elastogram_2D_Jet1_',num2str(Params.Freq),'Hz_New.fig']);
% saveas(gcf,['Elastogram_2D_Jet1_',num2str(Params.Freq),'Hz_New.tif']);

%% Wave speed 2D - 2000 Hz

Params1.Freq = 2001;
Params1.FFT_Nx = 2^11;

Ts = 1/(OCT_system.a_scan_rate*1000);
freq = linspace(0,1,Params1.FFT_Nx)/Ts;
Nf = find(freq>Params1.Freq);
Nf = Nf(1);

Params1.Threshold = [10 10];
Params1.FFT_FreqSample = Nf;
Params1.WinSize = [0.5 0.1]; 

% [Speed2D, Xaxis_E1, Zaxis_E1] = SpeedEstimation_PhaseDeriv(Frames2_Filtered_Right,Xaxis,Zaxis,Params);
% Speed2D_Equiv_Filt_Right = medfilt2(abs(Speed2D.Equiv),[3 3],'Symmetric');
% 
% [Speed2D, Xaxis_E1, Zaxis_E1] = SpeedEstimation_PhaseDeriv(Frames2_Filtered_Left,Xaxis,Zaxis,Params);
% Speed2D_Equiv_Filt_Left = medfilt2(abs(Speed2D.Equiv),[3 3],'Symmetric');

[Speed2D, Xaxis_E1, Zaxis_E1] = SpeedEstimation_PhaseDeriv(Frames2_Filtered_Depth,Xaxis,Zaxis,Params);
Speed2D_Equiv_Filt_Depth = medfilt2(abs(Speed2D.Equiv),[3 3],'Symmetric');


% tmp = abs(fft(Frames2_Filtered_Right,Params.FFT_Nx,3));
% tmp = tmp(:,:,138);
% tmp = medfilt2(tmp,[7 7],'Symmetric');
% Mask_tmp = tmp>0.8;
% Mask_tmp = medfilt2(Mask_tmp,[5 5],'Symmetric');
% Mask_Right = Mask_tmp'.*Bmode_Mask;
% Mask_RightEquivInterp = interp2(Xaxis,Zaxis,Mask_Right,Xaxis_E,Zaxis_E,'linear');
% 
% tmp = abs(fft(Frames2_Filtered_Left,Params.FFT_Nx,3));
% tmp = tmp(:,:,138);
% tmp = medfilt2(tmp,[7 7],'Symmetric');
% Mask_tmp = tmp>0.8;
% Mask_tmp = medfilt2(Mask_tmp,[5 5],'Symmetric');
% Mask_Left = Mask_tmp'.*Bmode_Mask;
% Mask_LeftEquivInterp = interp2(Xaxis,Zaxis,Mask_Left,Xaxis_E,Zaxis_E,'linear');
% 
% figure
% imagesc(Xaxis_E,Zaxis_E,Mask_RightEquivInterp)
% figure
% imagesc(Xaxis_E,Zaxis_E,Mask_LeftEquivInterp)
% 
% 
% Speed2D_Equiv_Filt1 = Mask_RightEquivInterp.*Speed2D_Equiv_Filt_Right +...
%             Mask_LeftEquivInterp.*Speed2D_Equiv_Filt_Left;
% mask2 =  (Mask_RightEquivInterp+Mask_LeftEquivInterp==2);   
% Mean_tmp = mean(cat(3,Speed2D_Equiv_Filt_Right,Speed2D_Equiv_Filt_Left),3);
% 
% Speed2D_Equiv_Filt1(mask2==1) = Mean_tmp(mask2==1);     
% 
% figure
% imagesc(Xaxis_E,Zaxis_E,Speed2D_Equiv_Filt1)
% caxis([0 10])
% colormap(jet)
% 
% figure
% imagesc(Xaxis_E,Zaxis_E,abs(Speed2D_Equiv_Filt_Right))
% caxis([0 10])
% colormap(jet)
% figure
% imagesc(Xaxis_E,Zaxis_E,abs(Speed2D_Equiv_Filt_Left))
% caxis([0 10])
% colormap(jet)
% figure
% imagesc(Xaxis_E,Zaxis_E,abs(Speed2D_Equiv_Filt_Depth))
% caxis([0 10])
% colormap(jet)


Speed2D_Equiv_Filt1 = Speed2D_Equiv_Filt_Depth;
SpeedEquivInterp1 = interp2(Xaxis_E1,Zaxis_E1,Speed2D_Equiv_Filt1,Xaxis,Zaxis,'cubic');

figure
imagesc(Xaxis_E,Zaxis_E,abs(Speed2D_Equiv_Filt1))
clim([0 10])
colormap(jet)


gcf = figure;
imagesc(Xaxis,Zaxis,SpeedEquivInterp1.*Bmode_Mask)
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
title(['Speed Map - ',num2str(Params1.Freq),' Hz'])
axis equal
axis([Xaxis_E1(1) Xaxis_E1(end) 0 Zaxis(end)])
set(gca,'FontSize',14)
colorbar
colormap(jet)
clim([0 10])
saveas(gcf,['Speed_Map_Alone_',num2str(Params1.Freq),'Hz.fig']);
saveas(gcf,['Speed_Map_Alone_',num2str(Params1.Freq),'Hz.tif']);

% gcf = figure;
% imagesc(Xaxis,Zaxis,SpeedEquivInterp1.*Bmode_Mask)
% ylabel('z-axis (mm)');
% xlabel('x-axis (mm)');
% title(['Speed Map - ',num2str(Params1.Freq),' Hz'])
% axis equal
% axis([Xaxis_E1(1) Xaxis_E1(end) 0 Zaxis(end)])
% set(gca,'FontSize',14)
% colorbar
% colormap(jet)
% caxis([2.5 4])
% saveas(gcf,['Speed_Map_Alone_',num2str(Params1.Freq),'Hz_New.fig']);
% saveas(gcf,['Speed_Map_Alone_',num2str(Params1.Freq),'Hz_New.tif']);

% figure
% hold on
% plot(SpeedEquivInterp(:,120))
% plot(SpeedEquivInterp1(:,120))
% plot(Bmode_IntLog(:,120)*0.3-16)


I = uint8(255*mat2gray(Bmode_IntLog.*Bmode_Mask, [OCE_system.i_thresh_low OCE_system.i_thresh_high]));
bg = ind2rgb(I,gray(255));
bgImg = double(bg);
alphaFactor = 0.4;
bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*Bmode_Mask;
bgImgAlpha_out = bgImg.*(1-Bmode_Mask);
bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;

II = uint8(255*mat2gray(SpeedEquivInterp1.*Bmode_Mask, [0 10]));
im = ind2rgb(II,hot(255));

fgImg = double(im);
fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);
fusedImg = fgImgAlpha + bgImgAlpha;

gcf=figure;
imagesc(Xaxis,Zaxis,fusedImg)
%imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
axis equal
axis([Xaxis_E1(1) Xaxis_E1(end) 0 Zaxis(end)])
title(['Speed Map - ',num2str(Params1.Freq),' Hz'])
set(gca,'FontSize',14)
colorbar
colormap(hot)
clim([0 10])
drawnow
saveas(gcf,['Elastogram_2D_Hot_',num2str(Params1.Freq),'Hz.fig']);
saveas(gcf,['Elastogram_2D_Hot_',num2str(Params1.Freq),'Hz.tif']);


I = uint8(255*mat2gray(Bmode_IntLog.*Bmode_Mask, [OCE_system.i_thresh_low OCE_system.i_thresh_high]));
bg = ind2rgb(I,gray(255));
bgImg = double(bg);
alphaFactor = 0.4;
bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*Bmode_Mask;
bgImgAlpha_out = bgImg.*(1-Bmode_Mask);
bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;

II = uint8(255*mat2gray(SpeedEquivInterp1.*Bmode_Mask, [0 10]));
im = ind2rgb(II,jet(255));

fgImg = double(im);
fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);
fusedImg = fgImgAlpha + bgImgAlpha;


gcf=figure;
imagesc(Xaxis,Zaxis,fusedImg)
%imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
axis equal
axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(end)]) 
title(['Speed Map - ',num2str(Params1.Freq),' Hz'])
set(gca,'FontSize',14)
colorbar
colormap(jet)
clim([0 10])
drawnow
saveas(gcf,['Elastogram_2D_Jet_',num2str(Params1.Freq),'Hz.fig']);
saveas(gcf,['Elastogram_2D_Jet_',num2str(Params1.Freq),'Hz.tif']);

% 
% I = uint8(255*mat2gray(Bmode_IntLog, [OCE_system.i_thresh_low OCE_system.i_thresh_high]));
% bg = ind2rgb(I,gray(255));
% bgImg = double(bg);
% alphaFactor = 0.4;
% bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*Bmode_Mask;
% bgImgAlpha_out = bgImg.*(1-Bmode_Mask);
% bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;
% 
% II = uint8(255*mat2gray(SpeedEquivInterp1.*Bmode_Mask, [2.5 4]));
% im = ind2rgb(II,jet(255));
% 
% fgImg = double(im);
% fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);
% fusedImg = fgImgAlpha + bgImgAlpha;
% 
% 
% gcf=figure;:
% imagesc(Xaxis,Zaxis,fusedImg)
% %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,,j)))
% ylabel('z-axis (mm)');
% xlabel('x-axis (mm)');
% axis equal
% axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(end)]) 
% title(['Speed Map - ',num2str(Params1.Freq),' Hz'])
% set(gca,'FontSize',14)
% colorbar
% colormap(jet)
% caxis([2.5 4])
% drawnow
% saveas(gcf,['Elastogram_2D_Jet_',num2str(Params1.Freq),'Hz_New.fig']);
% saveas(gcf,['Elastogram_2D_Jet_',num2str(Params1.Freq),'Hz_New.tif']);

%% Saving data


save(['Data_Processed_',Data_name,'.mat'],...
      'OCE_system','OCT_system','Frames2','Frames1','Xaxis','Zaxis',...
      'Border','Border1','Frames1_border','Bmode_IntLog','Bmode_Mask',...
      'freq','FFT','SpaceTime','Time','Time1',...
      'GroupSpeed','ParamsDisp','loaded_phases_Border_Disp',...
      'Speed_disp','freq_disp','FFT_time_disp',...
      'Params','Xaxis_E','Zaxis_E','Speed2D','Speed2D_Equiv_Filt','SpeedEquivInterp',... 
       '-v7.3');

              

cd(oldFolder);


save(['Data_Processed_ACUS_1MHz_2000Hz_5push_3D_Y_5v_1.mat'],...
      'OCE_system','OCT_system','Frames2','Frames1','Xaxis','Zaxis',...
      'Border','Frames1_border','Bmode_IntLog','Bmode_Mask',...
      'freq','FFT','SpaceTime','Time','Time1',...
      'GroupSpeed','ParamsDisp','Frames2_Filtered_Depth',...
      'Speed_disp','freq_disp','FFT_time_disp',...
      'Params','Xaxis_E','Zaxis_E','Speed2D','Speed2D_Equiv_Filt','SpeedEquivInterp',...
       '-v7.3');
   
   
   
