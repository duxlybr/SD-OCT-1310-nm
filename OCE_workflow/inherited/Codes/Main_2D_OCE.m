close all
clear all
clc

%% Input OCT parameters

OCT_system.center_wavelength = 0.840; % µm
OCT_system.a_scan_rate = 25; % kHz
OCT_system.axial_pixel_res = 3; %µm
% OCT data type (PhS-SSOCT: uint16; SD-OCT: uint8 or int16)
OCT_system.data_type = 'uint8';
OCT_system.x_scan_width = 6.3; % mm
OCT_system.IDXrefrac = 1.376; % refactive index of the sample

OCE_system = [];

%% Input Processing parameters

start_path = 'data';
pathname = uigetdir(start_path,'Select directory with the DAT files');

%% load spectrum for k-space resampling by linear interpolation

[OCT_system,OCE_system] = K_Linearization (pathname,OCT_system);

%% Measure size of data

[OCE_system] = SizeData (pathname,OCT_system,OCE_system);
OCE_system.NumLateralPos = 250;

%% Sizing data along z, adjusting contrast, fixing jump   

[OCE_system] = Resize_Adjust_Fix_Parameters (pathname,OCT_system,OCE_system);

%% Sizing data along time

N = 10;
[OCE_system] = SizeTime (pathname,OCT_system,OCE_system,N);      


%% Reading complex data and store in Cplx_Matrix

[Cplx_Matrix, Cplx_Matrix_BgSubs] = ReadCplx_Volume (pathname,OCT_system,OCE_system);

%% Bmode

Bmode = mean(abs(Cplx_Matrix_BgSubs),3)';

OCE_system.PeakThresMult = 15;
OCE_system.PeakThresWinSize = 40; 
[Border] = FindSurface(Bmode,OCE_system,OCT_system);

Bmode_IntLog = 20*log10(Bmode);
figure
imagesc(Bmode_IntLog)
caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
colormap(gray)
hold on
plot(Border.Idx);

%% Motion analysis

Options.LineOrFrame = 2; % Line = 1, Frame = 2
Options.MotionType = 2; % Displacement = 1, particle volicity = 2;
Options.LoupasAxialWin = []; % 10 pixels along depth, if empty, no Loupas;
Options.SmoothingWinPer = [0.05]; % if empty, no smoothing 

[loaded_phases] = MotionAnalysis(Cplx_Matrix,Border.Idx+30,Options);


colormap(fireice)
for ii = 1:size(loaded_phases,3)

gcf = figure(1);
subplot(2,1,1);
imagesc(loaded_phases(:,:,ii)')
caxis([-0.02 0.02])
%colormap(fireice)

drawnow

subplot(2,1,2);
hold on 
scatter(ii,squeeze(loaded_phases(150,200,ii)))
axis([1 OCE_system.NewTimeSize -0.02 0.02])
hold off 
drawnow

% F=getframe(gcf); 
% writeVideo(aviobj,F);
    
end


for ii = 1:size(loaded_phases,2)

gcf = figure(1);
plot(loaded_phases(:,ii))
axis([1 size(loaded_phases,1) -2 2])
hold off 
drawnow

% F=getframe(gcf); 
% writeVideo(aviobj,F);
    
end

save('Data_Processed_1200kHz.mat','loaded_phases','Bmode','Cplx_Matrix',...
                          'Border','OCE_system','OCT_system');

%% 3D analysis


start_path = 'after_cxl';
pathname = uigetdir(start_path,'Select directory with the DAT files');

foldernames = dir(fullfile(pathname));
foldernames(1)=[];
foldernames(1)=[];

folderNum = size(foldernames,1);

OCE_system.PeakThresMult = 15;
OCE_system.PeakThresWinSize = 20; 

Options.LineOrFrame = 1; % Line = 1, Frame = 2
Options.MotionType = 2; % Displacement = 1, particle volicity = 2;
Options.LoupasAxialWin = []; % 10 pixels along depth, if empty, no Loupas;
Options.SmoothingWinPer = [0.05]; % if empty, no smoothing 

SurfaceIntensity = zeros(OCE_system.NumLateralPos,OCE_system.NumLateralPos);
SurfaceIdx = SurfaceIntensity;
SurfaceDepth = SurfaceIntensity;
MotionSurface = zeros(OCE_system.NumLateralPos,...
                      OCE_system.NumLateralPos,...
                      OCE_system.NewTimeSize-1);


for ii = 1:folderNum
    
    pathname_file = [pathname,'\', foldernames(ii).name];
    [Cplx_Matrix, Cplx_Matrix_BgSubs] = ReadCplx_Volume (pathname_file,OCT_system,OCE_system);
    
    Bmode = mean(abs(Cplx_Matrix_BgSubs),3)';
    [Border] = FindSurface(Bmode,OCE_system,OCT_system);
    SurfaceIntensity(ii,:) = Border.Inten;
    SurfaceIdx(ii,:) = Border.Idx;
    SurfaceDepth(ii,:) = Border.DepthPos;
    
    [loaded_phases] = MotionAnalysis(Cplx_Matrix,Border.Idx+10,Options);
    MotionSurface(ii,:,:) = loaded_phases;
    
    ii
end

figure(1)
colormap(fireice)
  

for ii = 1:size(MotionSurface1,3)

    gcf = figure(1);
    imagesc(MotionSurface1(:,:,ii)')
    axis equal
    axis([1 98 1 98])
    caxis([-2 2])
%     colormap(fireice)

    drawnow

    F=getframe(gcf); 
    writeVideo(aviobj,F);
    
end

%% Visualization

SurfaceDepth1 = SurfaceDepth;
SurfaceDepth1(isnan(SurfaceDepth1)) = 100;

SurfaceIntensity1 = SurfaceIntensity;
SurfaceIntensity1(isnan(SurfaceIntensity1)) = 50;

Xaxis = linspace(0,OCT_system.x_scan_width,size(MotionSurface,1));
Yaxis = Xaxis;

gcf = figure;
surf(Xaxis,Yaxis,medfilt2(SurfaceDepth1*1e-3,[7 7],'symmetric'),...
                 medfilt2(SurfaceIntensity1*1e-3,[1 1],'symmetric'))
shading flat
set(gca,'zdir','reverse')
colormap(hot)
%caxis([0 130])
axis equal
axis([0 OCT_system.x_scan_width 0 OCT_system.x_scan_width -1 2])
ylabel('y-axis (mm)');
xlabel('x-axis (mm)');
zlabel('z-axis (mm)');
set(gca,'FontSize',14)
view(-122,46)
saveas(gcf,'3D_Surface.fig');
saveas(gcf,'3D_Surface.tif');


figure
plot(squeeze(MotionSurface(70,70,:)))


%%% Make a video of the wave in x during the time
aviobj = VideoWriter('SiliconPhantom_ACUS_1MHz_Surface.avi'); 
aviobj.FrameRate = 10; 
open(aviobj); 

for j=100:size(MotionSurface,3)
    gcf=figure(1);
    
    wave=medfilt2(MotionSurface1(:,:,j),[3 1]);
    iii=surface(Xaxis,Yaxis,medfilt2(SurfaceDepth1*1e-3,[3 1],'symmetric')+wave*0.5,wave,'FaceLighting','phong');
    set(iii,'Visible','on');
    caxis([-1 1])
    %caxis([-1 1])
    shading flat
    grid on

    colormap(jet)
    set(gca,'zdir','reverse')
    ylabel('y axis (mm)');
    xlabel('x axis (mm)');
    zlabel('z axis (mm)');
    
    
    %view(-126,33)
    view(-122,46)
    axis equal
    %view(-90,0)
    axis([0 OCT_system.x_scan_width 0 OCT_system.x_scan_width -2 2])
    if j==1
    camlight headlight
    end
    drawnow
    

    %pause
%     
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
     
    if j~=size(MotionSurface,3)
        set(iii,'Visible','off');
    end
    
    j
end

close(aviobj);
fclose all;

MotionSurface1 = MotionSurface;
MotionSurface1(isnan(MotionSurface1)) = 0;


%%% Make a video of the wave in x during the time
aviobj = VideoWriter('WaveProp_Cornea_after_cxl_AirPuff.avi'); 
aviobj.FrameRate = 10; 
open(aviobj); 

for j=1:size(MotionSurface1,3)
    
    Frame_tmp = medfilt2(MotionSurface1(:,:,j),[1 1]);

    gcf=figure(2);
    imagesc(Xaxis,Yaxis,Frame_tmp)
    %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
    ylabel('y-axis (mm)');
    xlabel('x-axis (mm)');
    axis equal
    axis([0 OCT_system.x_scan_width 0 OCT_system.x_scan_width])
    caxis([-3 3])
    set(gca,'FontSize',14);
    colormap(fireice)
    drawnow
    
    %pause
%    
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
end

close(aviobj);
fclose all;

save('Data_Processed.mat','MotionSurface1','Xaxis','Yaxis','SurfaceIntensity1',...
                          'SurfaceIdx','SurfaceDepth','OCE_system','OCT_system');



%%

Bmode = mean(abs(Cplx_Matrix_BgSubs),3)';
Bmode_IntLog = 20*log10(Bmode);
figure
imagesc(Bmode_IntLog)
caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
colormap(gray)


figure
plot(Bmode_IntLog(:,40))
figure
plot(Bmode(:,40))

M = 10;
loaded_phases = zeros(OCE_system.NumLateralPos,OCE_system.NewDepthSize-M+1,OCE_system.NewTimeSize);
raw_phases_Diff_Smth = [];
raw_phases_Smth = [];

for ii = 1:OCE_system.NumLateralPos
    
    
%     raw_phases = -1*angle(squeeze(Cplx_Matrix(ii,:,:)));
%     raw_phases_Diff = diff(unwrap(raw_phases,[],2),1,2);
    
    raw_phases_Diff = Loupas2D_Fast(squeeze(Cplx_Matrix(ii,:,:)),M);
    %raw_phases = unwrap(raw_phases,[],2);
    
%     parfor jj = 1: OCE_system.NewDepthSize
%         raw_phases_Smth(jj,:) = smooth(raw_phases(jj,:),0.01,'lowess')';
%     end
    
    
    parfor jj = 1: OCE_system.NewDepthSize-M+1
        raw_phases_Diff_Smth(jj,:) = smooth(raw_phases_Diff(jj,:),0.05,'lowess')';
    end
    
%     figure
%     plot(raw_phases_Diff(90,:))
%     hold on
%     plot(raw_phases_Diff_Smth(90,:))
    
    loaded_phases(ii,:,1:end-1) = raw_phases_Diff_Smth;
    %loaded_phases(ii,:,1:end) = raw_phases_Smth;
    ii
end


aviobj = VideoWriter(['Video_Loupas_PartVelo.avi']); 
aviobj.FrameRate = 20; 
open(aviobj); 

figure(1)
colormap(fireice)
for ii = 1:OCE_system.NewTimeSize

gcf = figure(1);
subplot(2,1,1);
imagesc(loaded_phases(:,:,ii)')
caxis([-0.5 0.5])
%colormap(fireice)

drawnow

subplot(2,1,2);
hold on 
scatter(ii,squeeze(loaded_phases(50,284,ii)))
axis([1 OCE_system.NewTimeSize -1 1])
hold off 
drawnow

% F=getframe(gcf); 
% writeVideo(aviobj,F);
    
end

close(aviobj);
fclose all;


%%

[Cplx_Matrix] = ReadCplx_Volume (pathname,OCT_system,OCE_system);

Bmode = mean(abs(Cplx_Matrix),3)';
Bmode_IntLog = 20*log10(Bmode);
Bmode_IntLog_Norm = Bmode_IntLog/max(Bmode_IntLog(:));
figure
imagesc(Bmode_IntLog_Norm)
caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
colormap(gray)

M = 10;
loaded_phases = zeros(OCE_system.NumLateralPos,OCE_system.NewDepthSize,OCE_system.NewTimeSize);
raw_phases_Diff_Smth = [];
raw_phases_Smth = [];

for ii = 1:OCE_system.NumLateralPos
    
    
    raw_phases = -1*angle(squeeze(Cplx_Matrix(ii,:,:)));
    raw_phases_Diff = diff(unwrap(raw_phases,[],2),1,2);
    
    %raw_phases = unwrap(raw_phases,[],2);
    
%     parfor jj = 1: OCE_system.NewDepthSize
%         raw_phases_Smth(jj,:) = smooth(raw_phases(jj,:),0.01,'lowess')';
%     end
    
    
    parfor jj = 1: OCE_system.NewDepthSize
        raw_phases_Diff_Smth(jj,:) = smooth(raw_phases_Diff(jj,:),0.05,'lowess')';
    end
    
%     figure
%     plot(raw_phases_Diff(90,:))
%     hold on
%     plot(raw_phases_Diff_Smth(90,:))
    
    loaded_phases(ii,:,1:end-1) = raw_phases_Diff_Smth;
    %loaded_phases(ii,:,1:end) = raw_phases_Smth;
    ii
end


aviobj = VideoWriter(['Video_Deriv_PartVelo.avi']); 
aviobj.FrameRate = 20; 
open(aviobj); 

figure(1)
colormap(fireice)
for ii = 1:OCE_system.NewTimeSize

gcf = figure(1);
subplot(2,1,1);
imagesc(loaded_phases(:,:,ii)')
caxis([-0.5 0.5])
%colormap(fireice)

drawnow

subplot(2,1,2);
hold on 
scatter(ii,squeeze(loaded_phases(50,284,ii)))
axis([1 OCE_system.NewTimeSize -1 1])
hold off 
drawnow

F=getframe(gcf); 
writeVideo(aviobj,F);
    
end

close(aviobj);
fclose all;




