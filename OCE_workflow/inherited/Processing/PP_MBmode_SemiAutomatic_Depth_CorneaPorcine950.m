close all
clear all
clc

%% Selecting folder

start_path = 'Data';
[file,pathname_1,indx] = uigetfile('.bin','Choose OCE file (just one)');

%% Read Params

load('Params950.mat')
%% Reading raw data

OCE_AcqType = 1; % MulMer = 1, Spiral = 2
measurement = oct2_readRawData(file,pathname_1,OCE_AcqType);

%% Input OCT parameters

OCT_system.NumAngles = measurement.ScanInfo.No_3Dscans;
OCT_system.center_wavelength = 1.300; % µm
OCT_system.a_scan_rate = 200; % kHz
OCT_system.axial_pixel_res = 7.46;%8.4; %µm
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
%% 
%Cplx_Matrix(1:50,:,:)=Cplx_Matrix([100:-1:51],:,:);

%% Bmode

% Xaxis = linspace(0,OCT_system.x_scan_width*OCT_system.NumAngles,OCE_system.NumLateralPos);
% %Xaxis = Xaxis*4.77/5.83;
% Zaxis = [0:1:OCE_system.NewDepthSize-1]'*OCT_system.axial_pixel_res*1e-3;
% Zaxis = Zaxis/OCT_system.IDXrefrac;
% 
% Bmode = mean(abs(Cplx_Matrix(:,:,:)),3)';
% 
% OCE_system.PeakThresMult = 5;
% OCE_system.PeakThresWinSize = 50; 
% [Border] = FindSurface(Bmode,OCE_system,OCT_system);
% 
% Border.Idx(end)= nan;
% Border.Idx = Border.Idx - 4;
% % idx1 = find(Border.Idx < 60);
% % Border.Idx (idx1) = 60;
% idx1 = find(Border.Idx>OCE_system.NewDepthSize-1-0);
% Border.Idx (idx1) = OCE_system.NewDepthSize-1-1;
% 
% Border.Idx = medfilt2(Border.Idx,[1 3],'Symmetric');
% Border.Idx = smooth(Border.Idx,0.005,'lowess');
% 
% 
% %Bmode = mean(abs(Cplx_Matrix(:,:,:)),3)';
% Bmode_IntLog = real(20*log10(Bmode));
% %Bmode_IntLog = Bmode_IntLog-repmat(mean(Bmode_IntLog(200:210,:),1),size(Bmode_IntLog,1),1);
% 
% figure
% imagesc(Bmode_IntLog)
% caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
% colormap(gray)
% hold on
% plot(Border.Idx);
% 
% 
% % Border.Idx = Border.Idx - 4;
% % idx1 = find(Border.Idx < 73);
% % Border.Idx (idx1) = 73;
% idx1 = find(Border.Idx>OCE_system.NewDepthSize-1-21);
% Border.Idx (idx1) = OCE_system.NewDepthSize-1-21;
% 
% %Border.Idx([1:15,185:200])=100;
% 
% % tmp = Border.Idx;
% % idx = (tmp>=size(Bmode_IntLog,1)-50)
% % tmp(tmp>=size(Bmode_IntLog,1)-50) = size(Bmode_IntLog,1)-100;
% % Border.Idx = tmp;

%% Bmode

Xaxis = linspace(0,OCT_system.x_scan_width*OCT_system.NumAngles,OCE_system.NumLateralPos);
Zaxis = (0:1:OCE_system.NewDepthSize-1)'*OCT_system.axial_pixel_res*1e-3;
Zaxis = Zaxis/OCT_system.IDXrefrac;

Bmode = mean(abs(Cplx_Matrix(:,:,:)),3)';
Bmode_IntLog = real(20*log10(Bmode));

[DistBorder,Border,TopBorder,BottomBorder] = FindBothConrealBorders(Xaxis,Zaxis,Bmode,OCE_system,OCT_system);%se cambia segun si es con o sin epitelio


figure
imagesc(Bmode_IntLog)
hold on
plot(TopBorder/OCT_system.axial_pixel_res*OCT_system.IDXrefrac)
clim([OCE_system.i_thresh_low OCE_system.i_thresh_high])
colormap(gray)
hold on
plot(Border.Idx_Up);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%Border.Idx_Up(Border.Idx_Up>600)=600;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Mask

Jump = 450;
% Bmode = mean(abs(Cplx_Matrix(:,:,:)),3)';
% Bmode_IntLog = real(20*log10(Bmode));
% Bmode_Filt = medfilt2(Bmode_IntLog,[5 5],'symmetric');
% Thres = 55;
% Bmode_Mask = Bmode_Filt>Thres;

%%%%%%%%%%%%
Thres =90;
%%%%%%%%%%%%
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
Options.SmoothingWinPer = 0.05; % if empty, no smoothing 
[loaded_phases] = MotionAnalysis(Cplx_Matrix,Border.Idx_Up,Options);

% Options.MotionType = 2; 
% Options.Delta = 5;
% Options.LoupasAxialWin = []; 
% Options.SmoothingWinPer = [0.05];
% [loaded_phases_Border] = MotionAnalysisBorder(Cplx_Matrix,round(Border.Idx),Options);

Options.MotionType = 2;
Options.Delta = 10;%10;
Options.LoupasAxialWin = 20; 
Options.SmoothingWinPer = 0.05;
[loaded_phases_Border] = MotionAnalysisBorder_mod1(Cplx_Matrix,Border.Idx_Up,Options);


%% Time filtering

Ts = 1/(OCT_system.a_scan_rate*1000);
Line = squeeze(loaded_phases_Border(50,:));
FFT = fft(Line,2^12);
freq = linspace(0,1,2^12)/Ts;

Time = (0:Ts:(OCE_system.NewTimeSize-2)*Ts)*1e3;

fig = figure;
plot(freq,abs(FFT))
grid on
ylabel('Magnitude (Arb.)');
xlabel('Frequency (Hz)');
title('FFT of the signal');
axis([0 8000 0 max(abs(FFT))*1.1])
h = imrect(gca,[1e3-200,-200,400,(max(abs(FFT))*1.1)+400]);
position = wait(h); 
%position = [0.5604   -0.2000    5.4691    0.4070]*1e3;
%position = [3.2   -0.2000    0.6    0.4070]*1e3;
h = imrect(gca,[position(1),-200,position(3),(max(abs(FFT))*1.1)+400]);
b = fir1(50,[position(1)*2*Ts (position(1)+position(3))*2*Ts]);
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

    j;
end


%Frames1_Filt = medfilt3(Frames1,[7 3 5],'Symmetric');
Frame_BK = mean(Frames1(:,:,800:end),3);
%Frame_BK = zeros(size(Frames1(:,:,1)));





%% Saving Video
close all
uiopen('FigModelVideo.fig',1)

CLim = 0.1;%5;%0.1;
Time_ini = 1;
Time_end = length(Time);%930;

%Time1 = Time(Time_ini:Time_end);
Time1 = Time(Time_ini:end-6);
aviobj = VideoWriter('Video_2D_Filtered.avi'); 
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
    %Frames3 = [];
  
for j = Time_ini:Time_end
    
    Frame_tmp = squeeze(Frames1(:,:,j)-Frame_BK)';
    % Frame_tmp = squeeze(Frames1(:,:,j))'...
    %             +0.33*repmat(Frames1_border(:,j),1,OCE_system.NewDepthSize)';

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

%%

% close all
% uiopen('FigModelVideo.fig',1)
% 
% aviobj = VideoWriter(['Video_2D_Filtered_Right.avi']); 
% aviobj.FrameRate = 10; 
% open(aviobj); 
% for j = 1:size(Frames2_Filtered_Right,3)
%     
%     Frame_tmp = squeeze(Frames2_Filtered_Right(:,:,j))';
%     %Frame_tmp = medfilt2(Frame_tmp,[3 3],'Symmetric');
% 
%     II = uint8(255*mat2gray(Frame_tmp, [-CLim CLim]));
%     im = ind2rgb(II,fireice(255));
% 
%     fgImg = double(im);
%     fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);
% 
%     fusedImg = fgImgAlpha + bgImgAlpha;
% 
%     gcf=figure(1);
%     imagesc(Xaxis,Zaxis,fusedImg)
%     %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
%     ylabel('z-axis (mm)');
%     xlabel('y-axis (mm)');
%     %axis equal
%     axis([0 Xaxis(end) 0 Zaxis(end)])
%     title(['Motion frames - Filtered (Time = ',num2str(round(Time(j),2),'%10.2f\n'),' ms)'])   
%     set(gca,'FontSize',14)
%     drawnow
%     
%   
%     %pause(0.2)
%     
% 
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
% end
% close(aviobj);
% fclose all;
% 
% close all
% uiopen('FigModelVideo.fig',1)
% 
% aviobj = VideoWriter(['Video_2D_Filtered_Left.avi']); 
% aviobj.FrameRate = 10; 
% open(aviobj);  
% for j = 1:size(Frames2_Filtered_Left,3)
%     
%     Frame_tmp = squeeze(Frames2_Filtered_Left(:,:,j))';
%     %Frame_tmp = medfilt2(Frame_tmp,[3 3],'Symmetric');
% 
%     II = uint8(255*mat2gray(Frame_tmp, [-CLim CLim]));
%     im = ind2rgb(II,fireice(255));
% 
%     fgImg = double(im);
%     fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);
% 
%     fusedImg = fgImgAlpha + bgImgAlpha;
% 
%     gcf=figure(1);
%     imagesc(Xaxis,Zaxis,fusedImg)
%     %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
%     ylabel('z-axis (mm)');
%     xlabel('y-axis (mm)');
%     %axis equal
%     axis([0 Xaxis(end) 0 Zaxis(end)])
%     title(['Motion frames - Filtered (Time = ',num2str(round(Time(j),2),'%10.2f\n'),' ms)'])   
%     set(gca,'FontSize',14)
%     drawnow
%     
%   
%     %pause(0.2)
%     
% 
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
% end
% close(aviobj);
% fclose all;
% 
% close all
% uiopen('FigModelVideo.fig',1)
% 
% aviobj = VideoWriter(['Video_2D_Filtered_Depth.avi']); 
% aviobj.FrameRate = 10; 
% open(aviobj);  
% for j = 1:size(Frames2_Filtered_Depth,3)
%     
%     Frame_tmp = squeeze(Frames2_Filtered_Depth(:,:,j))';
%     %Frame_tmp = medfilt2(Frame_tmp,[3 3],'Symmetric');
% 
%     II = uint8(255*mat2gray(Frame_tmp, [-CLim CLim]));
%     im = ind2rgb(II,fireice(255));
% 
%     fgImg = double(im);
%     fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask);
% 
%     fusedImg = fgImgAlpha + bgImgAlpha;
% 
%     gcf=figure(1);
%     imagesc(Xaxis,Zaxis,fusedImg)
%     %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
%     ylabel('z-axis (mm)');
%     xlabel('y-axis (mm)');
%     %axis equal
%     axis([0 Xaxis(end) 0 Zaxis(end)])
%     title(['Motion frames - Filtered (Time = ',num2str(round(Time(j),2),'%10.2f\n'),' ms)'])   
%     set(gca,'FontSize',14)
%     drawnow
%     
%   
%     %pause(0.2)
%     
% 
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
% end
% close(aviobj);
% fclose all;

%% SpaceTime

CLim = 0.1;%5;%0.1;
Frames1_border_BK = Frames1_border - repmat(mean(Frames1_border(:,1:10),2),1,size(Frames1_border,2));
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

%% SpaceTime Depth

SpaceTimeDepth = squeeze(Frames2(45,:,:));

CLim = 0.1;%5;%0.1;
gcf = figure;
imagesc(Time,Zaxis,SpaceTimeDepth')
colormap(fireice)
clim([-CLim CLim])
ylabel('time (ms)')
xlabel('z-axis (mm)')
title('Space-time map')
set(gca,'FontSize',14)
saveas(gcf,'SpaceTimeMap_Depth.fig');
saveas(gcf,'SpaceTimeMap_Depth.tif');

%% Directional Filtering Depth

Tres = Time(2);
Xres = Xaxis(2);
Zres = Zaxis(2);
Dir = 'depth';
[Frames2_Filtered_Depth] = DirectionalFilter3(Frames2(1:100,:,:),Tres,Xres,Zres,Dir);

figure
for i = 1:size(Frames2_Filtered_Depth,3)
    imagesc(Frames2_Filtered_Depth(:,:,i)')
    colormap(fireice)
    clim([-CLim CLim])
    drawnow
end

SpaceTimeDepthFiltered = squeeze(Frames2_Filtered_Depth(45,:,:));

CLim = 0.1;%5;%0.1;
gcf = figure;
imagesc(Time,Zaxis,SpaceTimeDepthFiltered')
colormap(fireice)
clim([-CLim CLim])
ylabel('time (ms)')
xlabel('z-axis (mm)')
title('Space-time map')
set(gca,'FontSize',14)
saveas(gcf,'SpaceTimeMap_DepthFilt.fig');
saveas(gcf,'SpaceTimeMap_DepthFilt.tif');

%% Group Speed calculation along depth

[Speed,Error] = SpeedAnalysis(SpaceTimeDepth',Zaxis,Time,'GroupSpeed_Depth',CLim);

%% Phase speed along depth

Ts = 1/(OCT_system.a_scan_rate*1000);
Line = squeeze(SpaceTimeDepth(300,:));
FFT = fft(Line,2^12);
freq = linspace(0,1,2^12)/Ts;
Time = (0:Ts:(OCE_system.NewTimeSize-2)*Ts)*1e3;

figure
plot(Time,Line)

figure;
plot(freq,abs(FFT))
grid on
ylabel('Magnitude (Arb.)');
xlabel('Frequency (Hz)');
title('FFT of the signal');
axis([0 8000 0 max(abs(FFT))*1.1])



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
[Speed_disp{1},freq_disp{1},FFT_time_disp{1}] = DisperssionSpeedFull (SpaceTimeDepth,Zaxis,Time,ParamsDisp,DirFlag);%DisperssionSpeedFull aca cambio el Clim
Speed_disp{1} = smooth(Speed_disp{1},0.1,'lowess');

CentralFreq=3000;
idx = knnsearch(freq_disp{1}',CentralFreq,'K',1);
PhaseSpeedEval = Speed_disp{1}(idx);

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
xlim([0 4000])
grid on
title(['Phase Speed @',num2str(CentralFreq),'Hz = ',num2str(round(PhaseSpeedEval,2)),' m/s']);
set(gca,'FontSize',14)
saveas(gcf,'PhaseSpeed_Depth.fig');
saveas(gcf,'PhaseSpeed_Depth.tif');


%% Directional Filtering 3D

% Tres = Time(2);
% Xres = Xaxis(2);
% Zres = Zaxis(2);
% Dir = 'right';
% [Frames2_Filtered_Right] = DirectionalFilter3(Frames2,Tres,Xres,Zres,Dir);
% Dir = 'left';
% [Frames2_Filtered_Left] = DirectionalFilter3(Frames2,Tres,Xres,Zres,Dir);

%% SpaceTime Depth

% SpaceTime_Right = [];
% for i = 1:size(Frames2_Filtered_Right,1)
%     pos_depth = round(Border.Idx(i));
%     SpaceTime_Right(i,:) = squeeze(Frames2_Filtered_Right(i,pos_depth,:));
% end
% 
% gcf = figure;
% imagesc(Xaxis,Time,SpaceTime_Right')
% colormap(fireice)
% caxis([-CLim CLim]*1.5)
% ylabel('time (ms)')
% xlabel('x-axis (mm)')
% title('Space-time map')
% set(gca,'FontSize',14)
% saveas(gcf,'SpaceTimeMap_Left.fig');
% saveas(gcf,'SpaceTimeMap_Left.tif');
% 
% SpaceTime_Left = [];
% for i = 1:size(Frames2_Filtered_Right,1)
%     pos_depth = round(Border.Idx(i));
%     SpaceTime_Left(i,:) = squeeze(Frames2_Filtered_Left(i,pos_depth,:));
% end
% 
% gcf = figure;
% imagesc(Xaxis,Time,SpaceTime_Left')
% colormap(fireice)
% caxis([-CLim CLim]*1.5)
% ylabel('time (ms)')
% xlabel('x-axis (mm)')
% title('Space-time map')
% set(gca,'FontSize',14)
% saveas(gcf,'SpaceTimeMap_Right.fig');
% saveas(gcf,'SpaceTimeMap_Right.tif');


%% Phase speed cauclation

CLim = 0.3;%5;%0.1;
NumBscanSingle = OCT_system.NumBscanSingle;
Angle = 0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(OCT_system.NumAngles-1);

ParamsDisp.FFT_Nx = (2^13)+1; % Number of samples in FFT along space (must be odd number)
ParamsDisp.FFT_Nt = (2^13)+1; % Number of samples in FFT along time (must be odd number)
ParamsDisp.Cut_InvLambda = 1/(0.3e-3); % Inverse lambda cut value (e.g. 1 / 1mm);
                                 % If not known, leave empty.
ParamsDisp.Cut_Freq = 6000; % Inverse frequency cut value (e.g. 1000 Hz);
                        % If not known, leave empty.
ParamsDisp.Thres_Jump = 40;  % Jump treshold for multi-mode cases. Typically 40.
ParamsDisp.Thres_Mag = 0.01;  % Intensity threshold in the k-w space (e.g. 20% is 0.2)

% PosTimeLeft = [18 10 32 183];
% PosTimeRight = [52 10 32 183];
% PosTimeLeft = [27 10 21 183];
% PosTimeRight = [52 10 21 183];

DeltaSpace = 25;
% PosTimeLeft = [50-DeltaSpace-6 40 DeltaSpace 140];
% PosTimeRight = [56 40 DeltaSpace 140];

%%%%%%%%%%%%%%%%%%%%%%
ParamsDisp.fo = 1000;%frecuencia de exitacion
%%%%%%%%%%%%%%%%%%%%%%

%[DistBorder,Border,TopBorder,BottomBorder] = FindBothConrealBorders(Xaxis,Zaxis,Bmode,OCE_system,OCT_system);

for i = 1:OCT_system.NumAngles
    
    SpaceTime_tmp = SpaceTime(NumBscanSingle*(i-1)+1:NumBscanSingle*(i),:);
    
    figure
    imagesc(SpaceTime_tmp')
    colormap(fireice)
    clim([-CLim CLim])
    
    ST_Mask = smooth(mean(abs(SpaceTime_tmp),2),0.07,'lowess');
    [~, Center_idx] = max(ST_Mask(20:80));
    Center_idx = Center_idx+20-1
    if Center_idx<40 || Center_idx>60
        Center_idx = 50
    end
    Center_idx = 50
    %%%%%%%%%%%%%%%%%%%%
    PosTimeLeft = [Center_idx-DeltaSpace-4 13 DeltaSpace 500];
    PosTimeRight = [Center_idx+4 13 DeltaSpace 500];
    %%%%%%%%%%%%%%%%%%%%
    ThicknessSection = DistBorder(NumBscanSingle*(i-1)+1:NumBscanSingle*(i));
    Thickness(i*2-1,1) = mean(ThicknessSection(PosTimeLeft(1):PosTimeLeft(1)+PosTimeLeft(3)));
    Thickness(i*2,1) = mean(ThicknessSection(PosTimeRight(1):PosTimeRight(1)+PosTimeRight(3)));
% end
% for i = 1:OCT_system.NumAngles
    % %estoy agregando filtro direccional por derecha e izquierda
    % Tres = Time(2);
    % Xres = Xaxis(2);
    % %Zres = Zaxis(2);
    % points = size(SpaceTime,1);
    % Dir = 'right';
    % [SpaceTimeNEW_Right] = DirectionalFilter2(SpaceTime_tmp',Tres,Xres,points,Dir);
    % gcf = figure;
    % imagesc(Xaxis,Time,SpaceTimeNEW_Right)%muestra la matriz SpaceTime como una imagen
    % %SpaceTime' se utiliza para que los ejes X e Y se correspondan correctamente con Xaxis y Time
    % colormap(fireice)
    % clim([-CLim CLim])
    % ylabel('time (ms)')
    % xlabel('x-axis (mm)')
    % title('Space-time RIGHT map')
    % set(gca,'FontSize',14)
    % %axis([0 7 2 5])
    % %Guardo la imagen
    % saveas(gcf,'SpaceTimeMapRIGHT.fig');
    % saveas(gcf,'SpaceTimeMapRIGHT.tif');
    % Dir = 'left';
    % [SpaceTimeNEW_Left] = DirectionalFilter2(SpaceTime_tmp',Tres,Xres,points,Dir);
    % gcf = figure;
    % imagesc(Xaxis,Time,SpaceTimeNEW_Left)%muestra la matriz SpaceTime como una imagen
    % %SpaceTime' se utiliza para que los ejes X e Y se correspondan correctamente con Xaxis y Time
    % colormap(fireice)
    % clim([-CLim CLim])
    % ylabel('time (ms)')
    % xlabel('x-axis (mm)')
    % title('Space-time LEFT map')
    % set(gca,'FontSize',14)
    % %axis([0 7 2 5])
    % %Guardo la imagen
    % saveas(gcf,'SpaceTimeMapLEFT.fig');
    % saveas(gcf,'SpaceTimeMapLEFT.tif');
    % SpaceTimeNEW_Right=SpaceTimeNEW_Right';
    % SpaceTimeNEW_Left=SpaceTimeNEW_Left';
    % DirFlag = 'left';
    % ParamsDisp.PosTime = PosTimeLeft;
    % [Speed_disp{i*2-1},freq_disp{i*2-1},FFT_time_disp{i*2-1},PhaseSpeed(i*2-1,1)] = DisperssionSpeedFullWin (SpaceTimeNEW_Left,Xaxis(1:NumBscanSingle),Time,ParamsDisp,DirFlag);
    % 
    % DirFlag = 'right';
    % ParamsDisp.PosTime = PosTimeRight;
    % [Speed_disp{i*2},freq_disp{i*2},FFT_time_disp{i*2},PhaseSpeed(i*2,1)] = DisperssionSpeedFullWin (SpaceTimeNEW_Right,Xaxis(1:NumBscanSingle),Time,ParamsDisp,DirFlag);
    DirFlag = 'left';
    ParamsDisp.PosTime = PosTimeLeft;
    [Speed_disp{i*2-1},freq_disp{i*2-1},FFT_time_disp{i*2-1},PhaseSpeed(i*2-1,1)] = DisperssionSpeedFullWin (SpaceTime_tmp,Xaxis(1:NumBscanSingle),Time,ParamsDisp,DirFlag);

    DirFlag = 'right';
    ParamsDisp.PosTime = PosTimeRight;
    [Speed_disp{i*2},freq_disp{i*2},FFT_time_disp{i*2},PhaseSpeed(i*2,1)] = DisperssionSpeedFullWin (SpaceTime_tmp,Xaxis(1:NumBscanSingle),Time,ParamsDisp,DirFlag);

    
    gcf = figure;
    yyaxis left
    plot(freq_disp{i*2-1},Speed_disp{i*2-1},'DisplayName','Left prop. - Speed')
    ylim([0 15])
    ylabel('Speed (m/s)')
    yyaxis right
    plot(freq_disp{i*2-1},FFT_time_disp{i*2-1}/max(FFT_time_disp{i*2-1}),'DisplayName','Left prop. - Spectrum')
    ylabel('Magnitude FFT (Arb.)')
    xlabel('Frequency (Hz)')
    xlim([0 6000])
    %xlim([2000 4000])

    hold on

    yyaxis left
    plot(freq_disp{i*2},Speed_disp{i*2},'DisplayName','Right prop. - Speed')
    ylim([0 20])
    ylabel('Speed (m/s)')
    yyaxis right
    plot(freq_disp{i*2},FFT_time_disp{i*2}/max(FFT_time_disp{i*2}),'DisplayName','Right prop. - Spectrum')
    ylabel('Magnitude FFT (Arb.)')
    xlabel('Frequency (Hz)')
    xlim([0 6000])
    %xlim([2000 4000])

    legend(gca,'show','Location','northeast');
    set(gca,'FontSize',14)
    grid on
    title(gca,['Th. Left: ',num2str(round(Thickness(i*2-1,1)*1e3,1)),...
          ' um. Th.  Right: ',num2str(round(Thickness(i*2,1)*1e3,1)),' um.']);
    saveas(gcf,['SpeedDispersion_',num2str(round(Angle(i),1)),'Hz.fig']);
    saveas(gcf,['SpeedDispersion_',num2str(round(Angle(i),1)),'Hz.tif']);
end

%%%%%%%%%%%%%%%%%%
CentralFreq = ParamsDisp.fo; % Hz
%%%%%%%%%%%%%%%%%%

for i = 1:OCT_system.NumAngles
    
    idx = knnsearch(freq_disp{i*2-1}',CentralFreq,'K',1);
    PhaseSpeed(i*2-1,1) = Speed_disp{i*2-1}(idx);
    
    idx = knnsearch(freq_disp{i*2}',CentralFreq,'K',1);
    PhaseSpeed(i*2,1) = Speed_disp{i*2}(idx);
    
end
%PhaseSpeed(4,1)=PhaseSpeed(1,1);
%PhaseSpeed(15,1)=PhaseSpeed(1,1);
% PhaseSpeed(5,1)=PhaseSpeed(1,1);
% PhaseSpeed(7,1)=PhaseSpeed(10,1);

AnglesAll = (0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(2*OCT_system.NumAngles-1))';
%GroupSpeed_New = GroupSpeed([1 4 5 8 2 3 6 7],1);
[idx_angles] = IDXSelection(OCT_system.NumAngles);
PhaseSpeed_New = PhaseSpeed(idx_angles,1);
Thickness_New = Thickness(idx_angles,1);

close all
uiopen('FigModelPolarPlot.fig',1)
gcf = figure(1);
subplot(1,2,1)
polarplot([AnglesAll/180*pi; 0],[Thickness_New; Thickness_New(1)]*1e3,'-bs','linewidth',1,'MarkerSize',8)
title('Thickness (um)')
set(gca,'FontSize',14);
subplot(1,2,2)
boxplot(Thickness_New*1e3,'Whisker',1);
[MeanTh,ErrorTh,RangeTh] = grpstats (Thickness_New*1e3,[],{'mean','std','range'});
title(['Mean ',num2str(round(MeanTh,2)),' um, STD ',num2str(round(ErrorTh,3)),' um.'])
grid on
saveas(gcf,'PolarThickness.fig');
saveas(gcf,'PolarThickness.tif');



uiopen('FigModelPolarPlot.fig',1)
gcf = figure(2);
subplot(1,2,1)
polarplot([AnglesAll/180*pi; 0],[PhaseSpeed_New; PhaseSpeed_New(1)],'-bs','linewidth',1,'MarkerSize',8)
title(['Phase speed (m/s) @ ',num2str(CentralFreq),'Hz.'])
set(gca,'FontSize',14);
subplot(1,2,2)
boxplot(PhaseSpeed_New,'Whisker',1);
[Mean,Error,Range] = grpstats (PhaseSpeed_New,[],{'mean','std','range'});
title(['Mean ',num2str(round(Mean,2)),' m/s, STD ',num2str(round(Error,3)),' m/s.'])
grid on
saveas(gcf,'PolarPhaseSpeed.fig');
saveas(gcf,'PolarPhaseSpeed.tif');


%%

save('PhaseSpeed.mat','Speed_disp','freq_disp','FFT_time_disp',...
                      'PhaseSpeed','PhaseSpeed_New','AnglesAll',...
                      'Mean','Error','Range',...
                      'Thickness_New','MeanTh','ErrorTh','RangeTh','Thickness');

% save('ProcessedData.mat','Speed_disp','freq_disp','FFT_time_disp',...
%                             'PhaseSpeed','PhaseSpeed_New','AnglesAll',...
%                             'Xaxis','Zaxis','Time',...
%                             'SpaceTime','Frames2','Frames1','loaded_phases_Border',...
%                             'Thickness_New','Bmode','Bmode_IntLog','Border','TopBorder','BottomBorder',...
%                              'OCE_system','OCT_system','CentralFreq');
%cd(oldFolder)


%%
close all
clear all
clc

load('PhaseSpeed.mat')

i = 1;
PhaseSpeed_NewAll(:,i) = PhaseSpeed_New(:,1);
Thickness_NewAll(:,i) = Thickness_New(:,1);

MeanSpeed = median(PhaseSpeed_NewAll(:,:),2);
ErrorSpeed = std(PhaseSpeed_NewAll,[],2);
MeanThickness = median(Thickness_NewAll(:,:)*1e3,2);
ErrorThickness = std(Thickness_NewAll*1e3,[],2);

% figure
% polarplot([AnglesAll/180*pi; 0],[MeanSpeed;MeanSpeed(1)])

% figure
% polarwitherrorbar([AnglesAll/180*pi; 0]',[MeanSpeed;MeanSpeed(1)]',[ErrorSpeed;ErrorSpeed(1)]')
% title(['Mean phase speed (n = 3) @ ',num2str(CentralFreq),'Hz.'])
% xlabel('Max. error: ')
% set(gca,'FontSize',12)
% saveas(gcf,'MeanPolarPhaseSpeed.fig');
% saveas(gcf,'MeanPolarPhaseSpeed.tif');

Limit = 15;
CentralFreq = 3500; % Hz
close all
uiopen('FigModelPolarPlot.fig',1)
gcf = figure(1);
subplot(1,2,1)
polarwitherrorbar([AnglesAll/180*pi; 0]',[MeanSpeed; MeanSpeed(1)]',[ErrorSpeed;ErrorSpeed(1)]',Limit)
title(['Phase speed (m/s) @ ',num2str(CentralFreq),'Hz.'])
set(gca,'FontSize',14);
subplot(1,2,2)
boxplot(MeanSpeed,'Whisker',1);
[Mean,Error,Range] = grpstats (MeanSpeed,[],{'mean','std','range'});
title(['Mean ',num2str(round(Mean,2)),' m/s, STD ',num2str(round(Error,3)),' m/s.'])
grid on
saveas(gcf,'PolarPhaseSpeed_3push_1.fig');
saveas(gcf,'PolarPhaseSpeed_3push_1.tif');


Limit = 600;
uiopen('FigModelPolarPlot.fig',1)
gcf = figure(2);
subplot(1,2,1)
polarwitherrorbar([AnglesAll/180*pi; 0]',[MeanThickness; MeanThickness(1)]',[ErrorThickness;ErrorThickness(1)]',Limit)
title('Thickness (um)')
set(gca,'FontSize',14);
subplot(1,2,2)
boxplot(MeanThickness,'Whisker',1);
[MeanTh,ErrorTh,RangeTh] = grpstats (MeanThickness,[],{'mean','std','range'});
title(['Mean ',num2str(round(MeanTh,2)),' um, STD ',num2str(round(ErrorTh,3)),' um.'])
grid on
saveas(gcf,'PolarThickness_3push_1.fig');
saveas(gcf,'PolarThickness_3push_1.tif');

save('MeanPhaseSpeedPolar_3Push.mat','PhaseSpeed_NewAll','MeanSpeed',...
                                     'ErrorSpeed','AnglesAll','Mean','Error','Range',...
                                     'Thickness_NewAll','MeanThickness','ErrorThickness',...
                                     'MeanTh','ErrorTh','RangeTh');

figure
hold on
scatter(MeanThickness,MeanSpeed)
scatter(MeanTh,Mean,'filled')

%%
% clear all
% 
% [x,y] = pol2cart(AnglesAll/180*pi,MeanSpeed);
% 
% Limit = 15;
% CentralFreq = 3500; % Hz
% close all
% uiopen('FigModelPolarPlot.fig',1)
% gcf = figure(1);
% subplot(1,2,1)
% polarwitherrorbar([AnglesAll/180*pi; 0]',[MeanSpeed; MeanSpeed(1)]',[ErrorSpeed;ErrorSpeed(1)]',Limit)
% hold on
% ellipse_t = fit_ellipse( x,y,gcf );
% Asym = ellipse_t.long_axis/ellipse_t.short_axis;
% AsymAngle = ellipse_t.phi*180/pi+90;
% hold off
% title(['b/a = ',num2str(round(1/Asym,3)),'. Angle = ',num2str(round(AsymAngle,2)),'°.'])
% set(gca,'FontSize',14);
% subplot(1,2,2)
% boxplot(MeanSpeed,'Whisker',1);
% [Mean,Error,Range] = grpstats (MeanSpeed,[],{'mean','std','range'});
% title(['Mean ',num2str(round(Mean,2)),' m/s, STD ',num2str(round(Error,3)),' m/s.'])
% grid on
% saveas(gcf,'PolarPhaseSpeed_3push_2.fig');
% saveas(gcf,'PolarPhaseSpeed_3push_2.tif');


%%

% AstigAll = [4.4 3.5 2.4 1.4 1.4 0.7 0.6 0.4 ];
% AsymAll = [0.854 0.87 0.961 0.954 0.944 0.974 0.967 0.988];
% Eccentricity = sqrt(1-AsymAll.^2);
% 
% 
% figure
% plot(AstigAll,AsymAll)
% figure
% plot(AstigAll,Eccentricity)

%%

% MeanSpeed =[];
% ErrorSpeed =[];
% MeanTh =[];
% ErrorTh =[];
% Eye = 1:2;
% figure
% for i =1:16
%     hold on
%     MeanSpeed(i,:) = mean(SpeedAll_Mean(:,Eye,i),1);
%     ErrorSpeed(i,:) = std(SpeedAll_Mean(:,Eye,i),[],1);
%     MeanTh(i,:) = mean(ThicknessAll_Mean(:,Eye,i),1);
%     ErrorTh(i,:) = std(ThicknessAll_Mean(:,Eye,i),[],1);
%     errorbar(MeanTh(i,:),MeanSpeed(i,:),...
%              ErrorSpeed(i,:)/2,ErrorSpeed(i,:)/2,...
%              ErrorTh(i,:)/2,ErrorTh(i,:)/2,'o')
%     axis([400 700 9 15])
% end
% 
% MeanSpeedVect = MeanSpeed(:);
% MeanThVect = MeanTh(:);
% scatter(MeanThVect,MeanSpeedVect)
% 
% 
% figure
% boxchart(squeeze(SpeedAll_Mean(:,1,:))')
% 
% figure
% for i =1:16
%     hold on
%     MeanSpeed(i,:) = reshape(SpeedAll_Mean(:,:,i),1,[]);
%     ErrorSpeed(i,:) = reshape(SpeedAll_Error(:,:,i),1,[]);
%     MeanTh(i,:) = reshape(ThicknessAll_Mean(:,:,i),1,[]);
%     ErrorTh(i,:) = reshape(ThicknessAll_Error(:,:,i),1,[]);
%     errorbar(MeanTh(i,:),MeanSpeed(i,:),...
%              ErrorSpeed(i,:)/2,ErrorSpeed(i,:)/2,...
%              ErrorTh(i,:)/2,ErrorTh(i,:)/2,'o')
%     axis([400 700 9 15])
%     pause
% end
% 
% MeanSpeedVect = MeanSpeed(:);
% MeanThVect = MeanTh(:);
% scatter(MeanThVect,MeanSpeedVect)


%% Isotropic Lamb wave


% mu_0 = 800e3;
% Poisson = 0.49997;
% rho_s = 1046;
% rho_f = 1000;
% cf = 1500;
% %c1 = sqrt(2*mu_0*(1-Poisson)/(1-2*Poisson)/rho_s);
% c1 = 1540;
% 
% w = 2*pi*[10:50:6000];
% 
% k_solve = [];
% d = (0.6)/2*1e-3;
% nu = 0;
% mu = mu_0 + 1i*w*nu;
% c2 = sqrt(mu/rho_s);
% 
% for i = 1:length(w)
%     k_max = (w(i)/c2(i))*5;
%     [K_sol] = FindZeros_mRLFE(k_max,w(i),c1,mu(i),rho_s,cf,rho_f,d);
%     k_solve(i,:) = real(K_sol);
%     i
% end
% 
% % figure
% % hold on
% % plot(w/2/pi,w./k_solve(:,1)')
% % plot(w/2/pi,w./k_solve(:,2)')
% % plot(w/2/pi,w./k_solve(:,3)')
% % plot(w/2/pi,w./k_solve(:,4)')
% % plot(w/2/pi,w./k_solve(:,5)')
% % axis([0 8000 0 40])
% 
% idx_select=4
% c_L2 = [];
% c_tmp = [w' w']./k_solve(:,idx_select:idx_select+1);
% idx_cl = (c_tmp < sqrt(G/rho_s)*0.95);
% idx_cl = (idx_cl(:,1)*idx_select) + (idx_cl(:,2)*(idx_select+1));
% idx_0 = find(idx_cl == 0);
% idx_cl(idx_0)=idx_select;
% for i = 1:length(w)
%     c_L(i,1) = w(i)./k_solve(i,idx_cl(i));
% end
% c_L(idx_0) = [];
% w1 = w'; w1(idx_0)=[];
% 
% figure
% hold on
% plot(w1/2/pi,c_L)
% axis([0 8000 0 20])

%% Isotropic Lamb (Speed vs. Thickness)

% mu_0 = 800e3;
% Poisson = 0.49997;
% rho_s = 1046;
% rho_f = 1000;
% cf = 1500;
% %c1 = sqrt(2*mu_0*(1-Poisson)/(1-2*Poisson)/rho_s);
% c1 = 1540;
% 
% w = 2*pi*[3500];
% 
% k_solve = [];
% d = (0.5:0.008:0.6)/2*1e-3;
% nu = 10;
% mu = mu_0 + 1i*w*nu;
% c2 = sqrt(mu/rho_s);
% 
% for i = 1:length(d)
%     k_max = (w/c2)*5;
%     [K_sol] = FindZeros_mRLFE(k_max,w,c1,mu,rho_s,cf,rho_f,d(i));
%     k_solve(i,:) = real(K_sol);
%     i
% end
% 
% % figure
% % hold on
% % plot(d,w./k_solve(:,1)')
% % plot(d,w./k_solve(:,2)')
% % plot(d,w./k_solve(:,3)')
% % plot(d,w./k_solve(:,4)')
% % plot(d,w./k_solve(:,5)')
% % axis([0 8000 0 40])
% 
% idx_select=4
% c_L = [];
% c_tmp = [w' w']./k_solve(:,idx_select:idx_select+1);
% idx_cl = (c_tmp < sqrt(G/rho_s)*0.95);
% idx_cl = (idx_cl(:,1)*idx_select) + (idx_cl(:,2)*(idx_select+1));
% idx_0 = find(idx_cl == 0);
% idx_cl(idx_0)=idx_select;
% for i = 1:length(d)
%     c_L(i,1) = w./k_solve(i,idx_cl(i));
% end
% c_L(idx_0) = [];
% d1 = d'; d1(idx_0)=[];
% 
% figure
% hold on
% plot(d1*2*1e3,c_L)
% axis([0.45 0.65 10 13])
% grid on

%% Theoretical curve NITI 

% G = 300e3;
% mu_0 = 1000e3;
% Poisson = 0.49999;
% rho_s = 1046;
% rho_f = 1000;
% cf = 1500;
% %c1 = sqrt(2*mu_0*(1-Poisson)/(1-2*Poisson)/rho_s);
% cl = 1540;
% 
% w = 2*pi*[10:50:6000];
% 
% % Nu = 0.0;
% % G_visco = G+1j*w*Nu;
% 
% k_solve = [];
% d = (0.55)*1e-3;
% c2 = sqrt(G/rho_s);
% k_solve = [];
% for i = 1:length(w)
%     k_max = (w(i)/c2)*7;
%     [K_sol] = FindZeros_NITI(k_max,w(i),G,mu_0,rho_s,cf,rho_f,d,cl);
%     k_solve(i,:) = K_sol;
%     i
% end
% 
% figure
% hold on
% plot(w/2/pi,w./k_solve(:,1)')
% plot(w/2/pi,w./k_solve(:,2)')
% plot(w/2/pi,w./k_solve(:,3)')
% plot(w/2/pi,w./k_solve(:,4)')
% plot(w/2/pi,w./k_solve(:,5)')
% axis([0 8000 0 20])
% 
% idx_select=3
% c_L2 = [];
% c_tmp = [w' w']./k_solve(:,idx_select:idx_select+1);
% idx_cl = (c_tmp < sqrt(G/rho_s)*0.95);
% idx_cl = (idx_cl(:,1)*idx_select) + (idx_cl(:,2)*(idx_select+1));
% idx_0 = find(idx_cl == 0);
% idx_cl(idx_0)=idx_select;
% for i = 1:length(w)
%     c_L2(i,1) = w(i)./k_solve(i,idx_cl(i));
% end
% c_L2(idx_0) = [];
% w2= w'; w2(idx_0)=[];
% 
% figure
% hold on
% plot(w2/2/pi,c_L2)
% axis([0 8000 0 20])
% 
% for i = 1:length(cursor_info1)
%     XY(i,:) = cursor_info1(i).Position;
% end
% 
% sum(sqrt(diff(XY(:,1)).^2 + diff(XY(:,2)).^2))

%% Theoretical curve NITI (Speed vs. Thickness)


% G = 700e3;
% mu_0 = 1500e3;
% Poisson = 0.49999;
% rho_s = 1046;
% rho_f = 1000;
% cf = 1500;
% %c1 = sqrt(2*mu_0*(1-Poisson)/(1-2*Poisson)/rho_s);
% cl = 1540;
% 
% w = 2*pi*[3500];
% % Nu = 1;
% % G_visco = G+1j*w*Nu;
% 
% k_solve = [];
% d = [0.5:0.01:0.6]*1e-3;
% c2 = sqrt(G/rho_s);
% k_solve = [];
% for i = 1:length(d)
%     k_max = (w/c2)*7;
%     [K_sol] = FindZeros_NITI(k_max,w,G,mu_0,rho_s,cf,rho_f,d(i),cl);
%     k_solve(i,:) = K_sol;
%     i
% end
% 
% % figure
% % hold on
% % plot(d*1e3,w./k_solve(:,1)')
% % plot(d*1e3,w./k_solve(:,2)')
% % plot(d*1e3,w./k_solve(:,3)')
% % plot(d*1e3,w./k_solve(:,4)')
% % plot(d*1e3,w./k_solve(:,5)')
% % axis([0.4 0.7 0 20])
% 
% idx_select=4
% c_L2 = [];
% c_tmp = [w' w']./k_solve(:,idx_select:idx_select+1);
% idx_cl = (c_tmp < sqrt(G/rho_s)*0.95);
% idx_cl = (idx_cl(:,1)*idx_select) + (idx_cl(:,2)*(idx_select+1));
% idx_0 = find(idx_cl == 0);
% idx_cl(idx_0)=idx_select;
% for i = 1:length(d)
%     c_L2(i,1) = w./k_solve(i,idx_cl(i));
% end
% c_L2(idx_0) = [];
% d2= d'; d2(idx_0)=[];
% 
% figure
% hold on
% plot(d2*1e3,c_L2)
% axis([0.4 0.7  10 13])
% grid on
%%

