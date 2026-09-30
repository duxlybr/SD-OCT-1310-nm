function [PhaseSpeedEval,freq_disp,Speed_disp] = Automatic_OCE_Analysis_CorneasDepth_mod(file,pathname_1,ParamsAuto)

%% Selecting folder

% start_path = 'Data';
% [file,pathname_1,indx] = uigetfile('.bin','Choose OCE file (just one)');

%% Read Params

FreqVal = ParamsAuto.FreqVal;
ExcitType = ParamsAuto.ExcitType;
IOPval = ParamsAuto.IOPval;
Acq = ParamsAuto.Acq;
Num = ParamsAuto.Num;
load ParamsforDepth450.mat %load('Params.mat')

%% Reading raw data

OCE_AcqType = 1; % MulMer = 1, Spiral = 2
measurement = oct2_readRawData(file,pathname_1,OCE_AcqType);

%% Input OCT parameters

OCT_system.NumAngles = measurement.ScanInfo.No_3Dscans;
OCT_system.center_wavelength = 1.300; % µm
OCT_system.a_scan_rate = 200; % kHz
OCT_system.axial_pixel_res = 7.46; %µm
OCT_system.x_scan_width = measurement.ScanInfo.Ver_scan_length_mm; % mm
OCT_system.IDXrefrac = 1.486; % refactive index of the sample

OCE_system = [];

%% Measure size of data

OCE_system.NumLateralPos = measurement.ScanInfo.Bframes_in_3Dscan*OCT_system.NumAngles;
OCE_system.NumMrept = measurement.ScanInfo.Alines_in_Bframe;
OCT_system.spec_len = measurement.ScanInfo.samples_in_Aline;
OCE_system.DepthSize =  measurement.ScanInfo.samples_in_Aline /2;
OCT_system.NumBscanSingle = measurement.ScanInfo.Bframes_in_3Dscan;

%% Sizing data along z, adjusting contrast, fixing jump   

% [OCE_system] = Resize_Adjust_Fix_Parameters (measurement,OCT_system,OCE_system);

OCE_system.Jump_Lat_pos =  OCE_system1.Jump_Lat_pos;
OCE_system.NewDepthSize = OCE_system1.NewDepthSize;
OCE_system.Cut_Depth_ini = OCE_system1.Cut_Depth_ini;
OCE_system.Cut_Depth_end = OCE_system1.Cut_Depth_end;
OCE_system.i_thresh_low = OCE_system1.i_thresh_low;
OCE_system.i_thresh_high = OCE_system1.i_thresh_high;

%% Sizing data along time

% N = 5;
% [OCE_system] = SizeTime (measurement,OCT_system,OCE_system,N);      

OCE_system.Cut_Time_ini = OCE_system1.Cut_Time_ini;
OCE_system.Cut_Time_end = OCE_system1.Cut_Time_end;
OCE_system.NewTimeSize = OCE_system1.NewTimeSize;

%% Create Folder

pathname = [pathname_1 file];
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

%% Reading

% [OCE_system_tmp] = Resize_Adjust_Fix_Parameters (pathname,OCT_system,OCE_system);
% OCE_system.Jump_Lat_pos = OCE_system_tmp.Jump_Lat_pos;

[Cplx_Matrix] = ReadCplx_Volume_BS (measurement,OCT_system,OCE_system);



%% Bmode

Xaxis = linspace(0,OCT_system.x_scan_width*OCT_system.NumAngles,OCE_system.NumLateralPos);
Zaxis = [0:1:OCE_system.NewDepthSize-1]'*OCT_system.axial_pixel_res*1e-3;
Zaxis = Zaxis/OCT_system.IDXrefrac;

Bmode = mean(abs(Cplx_Matrix(:,:,:)),3)';
Bmode_IntLog = real(20*log10(Bmode));

[DistBorder,Border,TopBorder,BottomBorder] = FindBothConrealBordersDepth(Xaxis,Zaxis,Bmode,OCE_system,OCT_system);

figure
imagesc(Bmode_IntLog)
hold on
plot(TopBorder/OCT_system.axial_pixel_res*OCT_system.IDXrefrac)
clim([OCE_system.i_thresh_low OCE_system.i_thresh_high])
colormap(gray)
hold on
plot(Border.Idx_Up);

%% Mask

Jump = 450;
% Bmode = mean(abs(Cplx_Matrix(:,:,:)),3)';
% Bmode_IntLog = real(20*log10(Bmode));
% Bmode_Filt = medfilt2(Bmode_IntLog,[5 5],'symmetric');
% Thres = 55;
% Bmode_Mask = Bmode_Filt>Thres;


Thres = 94;
Bmode_Mask = Bmode_IntLog>Thres;

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
imagesc(Bmode_Mask)

gcf = figure;
imagesc(Xaxis,Zaxis,Bmode_IntLog.*Bmode_Mask)
clim([OCE_system.i_thresh_low OCE_system.i_thresh_high])
colormap(gray)
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
title('B-mode image');
%axis equal
%axis([Xaxis(1) Xaxis(end) Zaxis(1) Zaxis(end)])
axis([0  Xaxis(end) 0 Zaxis(end)])
set(gca,'FontSize', 14);
saveas(gcf,'Bmode.fig');
saveas(gcf,'Bmode.tif');


%% Motion analysis

Options.LineOrFrame = 2; % Line = 1, Frame = 2
Options.MotionType = 2; % Displacement = 1, particle volicity = 2;
Options.LoupasAxialWin = []; % 10 pixels along depth, if empty, no Loupas;
Options.SmoothingWinPer = [0.05]; % if empty, no smoothing 
[loaded_phases] = MotionAnalysis(Cplx_Matrix,Border.Idx_Up,Options);

% Options.MotionType = 2; 
% Options.Delta = 5;
% Options.LoupasAxialWin = []; 
% Options.SmoothingWinPer = [0.05];
% [loaded_phases_Border] = MotionAnalysisBorder(Cplx_Matrix,round(Border.Idx),Options);

Options.MotionType = 2;
Options.Delta = 10;
Options.LoupasAxialWin = [20]; 
Options.SmoothingWinPer = [0.05];
[loaded_phases_Border] = MotionAnalysisBorder_mod1(Cplx_Matrix,Border.Idx_Up,Options);


%% Time filtering

Ts = 1/(OCT_system.a_scan_rate*1000);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
Line = squeeze(loaded_phases_Border(50,:));
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
FFT = fft(Line,2^12);
freq = linspace(0,1,2^12)/Ts;

Time = [0:Ts:(OCE_system.NewTimeSize-2)*Ts]*1e3;

fig = figure;
plot(freq,abs(FFT))
grid on
ylabel('Magnitude (Arb.)');
xlabel('Frequency (Hz)');
title('FFT of the signal');
axis([0 8000 0 max(abs(FFT))*1.1])
% h = imrect(gca,[1e3-200,-200,400,(max(abs(FFT))*1.1)+400]);
% position = wait(h); 
%position = [0.5604   -0.2000    5.4691    0.4070]*1e3;
if ExcitType == 1
    position = [0.3   -0.2000    4    0.4070]*1e3;
else
    position = [FreqVal/1000-0.3   -0.2000    0.6    0.4070]*1e3;
end
h = imrect(gca,[position(1),-200,position(3),(max(abs(FFT))*1.1)+400]);

% MOD FILTRO FIR 1   fir1(100...
b = fir1(100,[position(1)*2*Ts (position(1)+position(3))*2*Ts]);

delay = mean(grpdelay(b));
saveas(fig,'Spectrum.fig');
saveas(fig,'Spectrum.tif');


gcf = figure;
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



Frames1 = loaded_phases;
Frames1_border = loaded_phases_Border;
for j=1:size(loaded_phases_Border,1) 

    signal=squeeze(loaded_phases(j,:,:));
    signal_border=squeeze(loaded_phases_Border(j,:));
    if isnan(sum(signal_border(:)))
        Frames1(j,:,:) = zeros(size(signal));
        
        Frames1_border(j,:) = zeros(1,size(signal_border,2));
    else
       Frames1(j,:,:)=filter(b,1,signal')';
       Frames1_border(j,:) = filter(b,1,signal_border);
        %Frames1_border(j,:) = signal_border;
    end

    j
end


%Frames1_Filt = medfilt3(Frames1,[7 3 5],'Symmetric');
Frame_BK = mean(Frames1(:,:,1:end),3);
%Frame_BK = zeros(size(Frames1(:,:,1)));





%% Saving Video
close all
uiopen('FigModelVideoDepth.fig',1)

CLim = 0.08;
Time_ini = 1;
Time_end = length(Time);%930;

Time1 = Time(Time_ini:Time_end);

aviobj = VideoWriter(['Video_2D_FilteredDepth.avi']); 
aviobj.FrameRate = 10; 
open(aviobj); 

    I = uint8(255*mat2gray(Bmode_IntLog, [OCE_system.i_thresh_low OCE_system.i_thresh_high]));
    bg = ind2rgb(I,gray(255));
    bgImg = double(bg).*repmat(Bmode_Mask,1,1,3);
    alphaFactor = 0.5;
    bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*repmat(Bmode_Mask,1,1,3);
    bgImgAlpha_out = bgImg.*(1-repmat(Bmode_Mask,1,1,3));
    bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;
    cont = 1;
    Frames2 = [];
  
for j = Time_ini:Time_end
    
    Frame_tmp = squeeze(Frames1(:,:,j)-Frame_BK)';
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % HACER ESTO PARA COMPENSAR EL MOV DENTRO DEL TEJIDO
        Frame_tmp = squeeze(Frames1(:,:,j))'...
                +0.33*repmat(Frames1_border(:,j),1,OCE_system.NewDepthSize)';
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Frame_tmp = medfilt2(Frame_tmp,[5 3],'Symmetric');
    Frames2(:,:,cont) = Frame_tmp';
    cont = cont+1;

    
    II = uint8(255*mat2gray(Frame_tmp, [-CLim CLim]));
    im = ind2rgb(II,fireice(255));

    fgImg = double(im);
    fgImgAlpha = alphaFactor .* fgImg.*(repmat(Bmode_Mask,1,1,3));

    fusedImg = fgImgAlpha + bgImgAlpha;

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
    

    F=getframe(gcf); 
    writeVideo(aviobj,F);
end

close(aviobj);
fclose all;
%% convertir a mp4
% Leer el video AVI
vidReader = VideoReader('Video_2D_FilteredDepth.avi');

% Obtener las dimensiones originales
origWidth = vidReader.Width;
origHeight = vidReader.Height;

% Asegurar que sean múltiplos de 2
newWidth = origWidth + mod(origWidth,2);
newHeight = origHeight + mod(origHeight,2);

% Crear el nuevo archivo MP4
vidWriter = VideoWriter('Video_2D_FilteredDepth.mp4', 'MPEG-4');
vidWriter.FrameRate = vidReader.FrameRate;
open(vidWriter);

% Leer y escribir cada frame con el tamaño corregido
while hasFrame(vidReader)
    frame = readFrame(vidReader);
    frameResized = imresize(frame, [newHeight newWidth]); % Redimensionar
    writeVideo(vidWriter, frameResized);
end

% Cerrar el archivo de video
close(vidWriter);

%% SpaceTime

CLim = 0.15;%5;%0.1;
Frames1_border_BK = Frames1_border - repmat(mean(Frames1_border(:,1:10),2),1,size(Frames1_border,2));
%SpaceTime = medfilt2(Frames1_border_BK,[3 3],'Symmetric');
SpaceTime = medfilt2(Frames1_border_BK,[3 3],'Symmetric');
gcf = figure;
imagesc(Xaxis,Time,SpaceTime')
colormap(fireice)
clim([-CLim CLim])
ylabel('time (ms)')
xlabel('x-axis (mm)')
title('Space-time map')
set(gca,'FontSize',14)
%axis([0 7 2 5])
saveas(gcf,'SpaceTimeMap.fig');
saveas(gcf,'SpaceTimeMap.tif');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% DEFINIR UN CENTRAL NEW
gcf = figure;
temp = sum(SpaceTime .^ 2, 2);%sum(SpaceTime.*SpaceTime,2); ORIGINAL
plot(temp(1:101))

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
temp1 = smooth(temp,2,'lowess');
plot(temp1(30:71))
% % 🔹 OPCIÓN 1
% hold on
% temp1 = smooth(temp, 2, 'lowess'); 
% plot(temp1(1:101), 'r') % Señal suavizada en rojo
% 
% % 🔹 OPCIÓN 2
% temp1_movmean = movmean(temp, 8); 
% plot(temp1_movmean(1:101), 'g') % Señal suavizada en verde
% 
% % 🔹 OPCIÓN 3
% temp1_gauss = imgaussfilt(temp, 2);
% plot(temp1_gauss(1:101), 'm') % Señal suavizada en magenta
% 
% legend('Original', 'Lowess', 'Media móvil', 'Gaussiano')
% hold off;
% saveas(gcf,'CenterNew_FIG.fig');
% saveas(gcf,'CenterNew_FIG.tif');
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

[psor,lsor] = findpeaks(temp1(30:70),'SortStr','descend');
CentralNew = 30 + lsor(1) -1;

% si lsor(1) esta vacio hacer esto
if ~isempty(lsor)
    CentralNew = 30 + lsor(1) - 1;
else
    CentralNew = 50; % valor por defecto si no hay picos detectados
end
%Ajustar CentralNew dentro del rango permitido
if CentralNew > 50+4
    CentralNew = 50;
elseif CentralNew < 50-4
    CentralNew = 50;
end

CentralNew
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
FreqVal
ExcitType
IOPval

saveas(gcf,'FindPeak.fig');
saveas(gcf,'FindPeak.tif');
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
disp('SpaceTime OK')
%% SpaceTime Depth

SpaceTimeDepth = squeeze(Frames2(CentralNew,:,:));
%SpaceTimeDepth = squeeze(Frames2(50,:,:));

CLim = 0.15;%5;%0.1;
gcf = figure;
imagesc(SpaceTimeDepth')
colormap(fireice)
clim([-CLim CLim])
saveas(gcf,'SpaceTimeMap_Depth_no considerar.fig');
saveas(gcf,'SpaceTimeMap_Depth_no considerar.tif');

CLim = 0.15;%5;%0.1;
gcf = figure;
imagesc(Time,Zaxis,SpaceTimeDepth')
colormap(fireice)
clim([-CLim CLim])
ylabel('time (ms)')
xlabel('z-axis (mm)')
title('Space-time Depth map')
set(gca,'FontSize',14)
saveas(gcf,'SpaceTimeMap_Depth.fig');
saveas(gcf,'SpaceTimeMap_Depth.tif');


disp('SpaceTime Depth OK')
%% Directional Filtering Depth

Tres = Time(2);
Xres = Xaxis(2);
Zres = Zaxis(2);
Dir = 'depth';
[Frames2_Filtered_Depth] = DirectionalFilter3(Frames2(1:100,:,:),Tres,Xres,Zres,Dir);

% figure
% for i = 1:size(Frames2_Filtered_Depth,3)
%     imagesc(Frames2_Filtered_Depth(:,:,i)')
%     colormap(fireice)
%     clim([-CLim CLim])
%     drawnow
% end

SpaceTimeDepthFiltered = squeeze(Frames2_Filtered_Depth(50,:,:));

CLim = 0.08;%5;%0.1;
gcf = figure;
imagesc(Time,Zaxis,SpaceTimeDepthFiltered')
colormap(fireice)
clim([-CLim CLim])
ylabel('time (ms)')
xlabel('z-axis (mm)')
title('Space-time Depth Filtered map')
set(gca,'FontSize',14)
saveas(gcf,'SpaceTimeMap_DepthFilt.fig');
saveas(gcf,'SpaceTimeMap_DepthFilt.tif');

%% Phase speed along depth

DirFlag = 'right';
ParamsDisp.FFT_Nx = (2^15)+1; % Number of samples in FFT along space (must be odd number)
ParamsDisp.FFT_Nt = (2^15)+1; % Number of samples in FFT along time (must be odd number)
ParamsDisp.Cut_InvLambda = 1/(0.01e-3); % Inverse lambda cut value (e.g. 1 / 1mm);
                                 % If not known, leave empty.
ParamsDisp.Cut_Freq = 6000; % Inverse frequency cut value (e.g. 1000 Hz);
                        % If not known, leave empty.
ParamsDisp.Thres_Jump = 40;  % Jump treshold for multi-mode cases. Typically 40.
ParamsDisp.Thres_Mag = 0.01;%0.01;  % Intensity threshold in the k-w space (e.g. 20% is 0.2)
%DisperssionSpeedFull: Función que calcula la velocidad de dispersión, la frecuencia y la magnitud de la FFT para una dirección de propagación 

%%%%%%%%%%%%%%%%%%%%%%%%%
CentralFreq=FreqVal;
%%%%%%%%%%%%%%%%%%%%%%%%%
ParamsDisp.PosTime = [200,30,100,400];
%ParamsDisp.PosTime = [200,50,100,125];
%%%%%%%%%%%%%%%%%%%%%%%%%
% % % ACA TOMO MI KERNEL SEGUN LA FREC Y EXCIT
% if FreqVal == 2000
%         if ExcitType == 1
%             ParamsDisp.PosTime = [200,40,100,350];
%         else
%             ParamsDisp.PosTime = [200,40,100,400];
%         end
%     elseif FreqVal == 2500
%         if ExcitType == 1
%             ParamsDisp.PosTime = [200,40,100,300];
%         else
%             ParamsDisp.PosTime = [200,40,100,350];
%         end
%     elseif FreqVal == 3000
%         if ExcitType == 1
%             ParamsDisp.PosTime = [200,40,100,300];
%         else
%             ParamsDisp.PosTime = [200,40,100,350];
%         end
%     elseif FreqVal == 3500
%         if ExcitType == 1
%             ParamsDisp.PosTime = [200,40,100,300];
%         else
%             ParamsDisp.PosTime = [200,40,100,300];
%         end
%     else %if FreqVal == 4000
%         if ExcitType == 1
%             ParamsDisp.PosTime = [200,40,100,250];
%         else
%             ParamsDisp.PosTime = [200,40,100,300];
%         end
% end   
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

ParamsDisp.fo = CentralFreq;
[Speed_disp{1},freq_disp{1},FFT_time_disp{1},PhaseSpeedEval] = DisperssionSpeedFullWin (SpaceTimeDepth,Zaxis,Time,ParamsDisp,DirFlag);%DisperssionSpeedFull aca cambio el Clim
Speed_disp{1} = smooth(Speed_disp{1},0.1,'lowess');



%Grafica la velocidad y la magnitud de la FFT
gcf = figure;
yyaxis left
plot(freq_disp{1},Speed_disp{1},'DisplayName','Left prop. - Speed')
ylim([0 20])
ylabel('Speed (m/s)')
yyaxis right
plot(freq_disp{1},FFT_time_disp{1}/max(FFT_time_disp{1}),'DisplayName','Left prop. - Spectrum')
ylabel('Magnitude FFT (Arb.)')
xlabel('Frequency (Hz)')
xlim([0 ParamsDisp.Cut_Freq])
grid on
title(['Phase Speed @',num2str(CentralFreq),'Hz = ',num2str(round(PhaseSpeedEval,2)),' m/s']);
set(gca,'FontSize',14)
saveas(gcf,'PhaseSpeed_Depth.fig');
saveas(gcf,'PhaseSpeed_Depth.tif');

%% Save data

% save('ProcessedDataDepth'+FreqVal+'Hz'+IOPval+'mmHg'+ExcitType+'cycles.mat','Speed_disp','freq_disp','FFT_time_disp',...
%                             'SpaceTimeDepth',...
%                             'Xaxis','Zaxis','Time',...
%                             'Frames1_border_BK','Frames2','Frames1','loaded_phases_Border',...
%                             'SpaceTimeDepthFiltered','SpaceTime',...
%                             'PhaseSpeedEval','Bmode','Bmode_IntLog','Border','TopBorder','BottomBorder',...
%                              'OCE_system','OCT_system','CentralFreq');
% 
%filename = sprintf('ProcessedDataDepth%gHz%gmmHg%sCycles.mat', FreqVal, IOPval, ExcitType);
% filename = strcat('ProcessedDataDepth', num2str(FreqVal), 'Hz', num2str(IOPval), 'mmHg', num2str(ExcitType), 'Cycles.mat');
filename = strcat('ProcessedDataDepth', num2str(FreqVal), 'Hz', num2str(IOPval), 'mmHg', num2str(ExcitType), 'Cycles', num2str(Acq), 'Acq', num2str(Num), 'Num.mat');
save(filename, 'Speed_disp', 'freq_disp', 'FFT_time_disp', ...
              'SpaceTimeDepth', ...
              'Xaxis', 'Zaxis', 'Time', ...
              'Frames1_border_BK', 'Frames2', 'Frames1', 'loaded_phases_Border', ...
              'SpaceTimeDepthFiltered', 'SpaceTime', ...
              'PhaseSpeedEval', 'Bmode', 'Bmode_IntLog', 'Border', 'TopBorder', 'BottomBorder', ...
              'OCE_system', 'OCT_system', 'CentralFreq','CentralNew');

%%
cd(oldFolder)
close all
end
