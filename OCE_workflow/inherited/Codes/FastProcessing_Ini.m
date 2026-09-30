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

