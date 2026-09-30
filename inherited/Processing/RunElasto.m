close all
clear all
clc

%%



ParamsElasto.Freq = 3500;
ParamsElasto.FFT_Nx = 2^11;
ParamsElasto.Threshold = [20 20];
ParamsElasto.WinSize = [1.5 0.2]; 
ParamsElasto.DeltaSpace = 25;

Ts = 1/(OCT_system.a_scan_rate*1000);
ParamsElasto.Ts = Ts;
ParamsElasto.ZcutRange = [min(medfilt2(Border.Idx_Up,[1 11]))-40 max(Border.Idx_Down)+40];

Thres = 94;
Bmode_Mask = Bmode_IntLog>Thres;
[DistBorder,Border,TopBorder,BottomBorder] = FindBothConrealBorders(Xaxis,Zaxis,Bmode,OCE_system,OCT_system);

Elastogram(ParamsElasto,OCT_system,OCE_system,Frames2,Bmode_Mask,Bmode_IntLog,Border,Xaxis,Zaxis);


%%

Path = 'E:\ACUS_Clinical\20211118_ACUS\Results\Patient\OCE038\';
Cases = {'LeftEye','RightEye'};

ParamsElasto.Freq = 3500;
ParamsElasto.FFT_Nx = 2^11;
ParamsElasto.Threshold = [20 20];
ParamsElasto.WinSize = [1.5 0.2]; 
ParamsElasto.DeltaSpace = 25;

for i = 1:length(Cases)
    
    %%% Right side
    pathname_1 = [Path,Cases{i}];
    oldfolfer = cd(pathname_1);
    files1 = dir;
    
    SpeedMap_All = [];
    cont = 1;
    
    for j = 1:length(files1)
        FolderName = files1(j).name;
        if length(FolderName) >= 39
           oldfolfer1 = cd(files1(j).name);

           load('ProcessedData.mat')
           
           Ts = 1/(OCT_system.a_scan_rate*1000);
           ParamsElasto.Ts = Ts;
           AveBorderTop = reshape(Border.Idx_Up,OCT_system.NumBscanSingle,[]);
           AveBorderBottom = reshape(Border.Idx_Down,OCT_system.NumBscanSingle,[]);
           
           %ParamsElasto.ZcutRange = [min(medfilt2(Border.Idx_Up,[1 11]))-40 max(Border.Idx_Down)+40];
           %ParamsElasto.ZcutRange=[80 419] 
           ParamsElasto.ZcutRange= [min(round(median(AveBorderTop,2)))-40 max(round(median(AveBorderBottom,2)))+40];

           Thres = 94;
           Bmode_Mask = Bmode_IntLog>Thres;
           %[DistBorder,Border,TopBorder,BottomBorder] = FindBothConrealBorders(Xaxis,Zaxis,Bmode,OCE_system,OCT_system);

           [SpeedMap,X,Y] = Elastogram(ParamsElasto,OCT_system,OCE_system,Frames2,Bmode_Mask,Bmode_IntLog,Border,Xaxis,Zaxis);
           SpeedMap_All(:,:,cont) = SpeedMap;

           cont = cont+1;
           cd(oldfolfer1)
           close all
        end
    end
                
                MeanSpeed = median(SpeedMap_All,3);
                ErrorSpeed = std(SpeedMap_All,[],3);

                gcf=figure;
                imagesc(X(1,:),Y(:,1),MeanSpeed)
                %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
                ylabel('y-axis (mm)');
                xlabel('x-axis (mm)');
                axis equal
                axis([-OCT_system.x_scan_width/2 OCT_system.x_scan_width/2,...
                      -OCT_system.x_scan_width/2 OCT_system.x_scan_width/2]);
                colormap(jet)
                colorbar
                caxis([0 20]) 
                set(gca,'FontSize',14)
                drawnow
                saveas(gcf,['Elastogram_EnFace_Mean_',num2str(3500),'Hz.fig']);
                saveas(gcf,['Elastogram_EnFace_Mean_',num2str(3500),'Hz.tif']);


                gcf=figure;
                imagesc(X(1,:),Y(:,1),ErrorSpeed)
                %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
                ylabel('y-axis (mm)');
                xlabel('x-axis (mm)');
                axis equal
                axis([-OCT_system.x_scan_width/2 OCT_system.x_scan_width/2,...
                      -OCT_system.x_scan_width/2 OCT_system.x_scan_width/2]);
                colormap(jet)
                colorbar
                caxis([0 20]) 
                set(gca,'FontSize',14)
                drawnow
                saveas(gcf,['Elastogram_EnFace_Error_',num2str(3500),'Hz.fig']);
                saveas(gcf,['Elastogram_EnFace_Error_',num2str(3500),'Hz.tif']);


                save('MeanSpeedMaps.mat','MeanSpeed','ErrorSpeed','X','Y',...
                                         'SpeedMap_All');
                                     
                                     
                MeanSpeed = median(PhaseSpeed_NewAll(:,:),2);
                ErrorSpeed = std(PhaseSpeed_NewAll,[],2);
                MeanThickness = median(Thickness_NewAll(:,:)*1e3,2);
                ErrorThickness = std(Thickness_NewAll*1e3,[],2);



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
title(['Thickness (um)'])
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
                                                 
                                                 
                cd(oldfolfer)
                
                
end

%%
SpeedMap_All(:,:,[4])=[];


                MeanSpeed = median(SpeedMap_All,3);
                ErrorSpeed = std(SpeedMap_All,[],3);

                gcf=figure;
                imagesc(X(1,:),Y(:,1),MeanSpeed)
                %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
                ylabel('y-axis (mm)');
                xlabel('x-axis (mm)');
                axis equal
                axis([-OCT_system.x_scan_width/2 OCT_system.x_scan_width/2,...
                      -OCT_system.x_scan_width/2 OCT_system.x_scan_width/2]);
                colormap(jet)
                colorbar
                caxis([0 20]) 
                set(gca,'FontSize',14)
                drawnow
                saveas(gcf,['Elastogram_EnFace_Mean_',num2str(3500),'Hz.fig']);
                saveas(gcf,['Elastogram_EnFace_Mean_',num2str(3500),'Hz.tif']);


                gcf=figure;
                imagesc(X(1,:),Y(:,1),ErrorSpeed)
                %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
                ylabel('y-axis (mm)');
                xlabel('x-axis (mm)');
                axis equal
                axis([-OCT_system.x_scan_width/2 OCT_system.x_scan_width/2,...
                      -OCT_system.x_scan_width/2 OCT_system.x_scan_width/2]);
                colormap(jet)
                colorbar
                caxis([0 20]) 
                set(gca,'FontSize',14)
                drawnow
                saveas(gcf,['Elastogram_EnFace_Error_',num2str(3500),'Hz.fig']);
                saveas(gcf,['Elastogram_EnFace_Error_',num2str(3500),'Hz.tif']);


                save('MeanSpeedMaps.mat','MeanSpeed','ErrorSpeed','X','Y',...
                                         'SpeedMap_All');





