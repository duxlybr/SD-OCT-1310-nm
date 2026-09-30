close all
clear all
clc

%% Selecting folder

GeneralPath = 'C:\Users\proyecto\Documents\Tesis\CristianBocanegra\ClinicalData\20220830_ACUS';
Cases = {'S039'};

ParamsElasto.Freq = 3500;                 %frecuencia de onda mecanica
ParamsElasto.FFT_Nx = 2^11;
ParamsElasto.Threshold = [20 20];
ParamsElasto.WinSize = [1.5 0.2]; 
ParamsElasto.DeltaSpace = 25;



for i = 1:length(Cases)
    
    %%% Left side
    pathname_1 = [GeneralPath,'\Data\',Cases{i},'\LeftEye\']; % selecciono la ubicacion de la data
    oldfolfer = cd(pathname_1);
    files1 = dir('*.bin');
    cd(oldfolfer)
    
    cont1 = 1;
    SpeedMap_All = [];
    PhaseSpeed_NewAll = [];
    Thickness_NewAll = [];
    
    for j = 1:length(files1)
        file = files1(j).name;
        if length(file) == 43
            [SpeedMap,X,Y,...
            PhaseSpeed_New,...
            Thickness_New,...
            AnglesAll] = Automatic_OCE_Analysis_New(file,pathname_1,ParamsElasto); %Automatic_OCE_Analysis_New funcion
        
            SpeedMap_All(:,:,cont1) = SpeedMap;
            PhaseSpeed_NewAll(:,cont1) = PhaseSpeed_New(:,1);
            Thickness_NewAll(:,cont1) = Thickness_New(:,1);
            cont1 = cont1 + 1;
        end
    end
    
    pathname_1 = [GeneralPath,'\Results\',Cases{i},'\LeftEye\'];
    oldfolfer = cd(pathname_1);

                MeanSpeed = median(SpeedMap_All,3,'omitnan');   %Median value of array 
                ErrorSpeed = std(SpeedMap_All,[],3,'omitnan');  %std desviacion standard

                gcf=figure;
                imagesc(X(1,:),Y(:,1),MeanSpeed)
                %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
                ylabel('y-axis (mm)');
                xlabel('x-axis (mm)');
                axis equal
                axis([-5 5,...
                      -5 5]);
                colormap(jet)
                colorbar
                clim([0 20]) 
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
                axis([-5 5,...
                      -5 5]);
                colormap(jet)
                colorbar
                clim([0 20]) 
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
                
                Thres_ErrorSpeed = 1.2;
                [MeanSpeed,ErrorSpeed] = SmartMerging (PhaseSpeed_NewAll,Thres_ErrorSpeed);
                Thres_ErrorThickness = 20;
                [MeanThickness,ErrorThickness] = SmartMerging (Thickness_NewAll*1e3,Thres_ErrorThickness);
                                     
                                     
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

                                                    
    cd(oldfolfer)


    
    %%% Right side
    pathname_2 = [GeneralPath,'\Data\',Cases{i},'\RightEye\'];
    oldfolfer_2 = cd(pathname_2);
    files2 = dir('*.bin');
    cd(oldfolfer_2)
    
    cont2 = 1;
    SpeedMap_All = [];
    PhaseSpeed_NewAll = [];
    Thickness_NewAll = [];
    
    for k = 1:length(files2)
        file = files2(k).name;
        if length(file) == 43
            [SpeedMap,X,Y,...
            PhaseSpeed_New,...
            Thickness_New,...
            AnglesAll] = Automatic_OCE_Analysis_New(file,pathname_2,ParamsElasto);
        
            SpeedMap_All(:,:,cont2) = SpeedMap;
            PhaseSpeed_NewAll(:,cont2) = PhaseSpeed_New(:,1);
            Thickness_NewAll(:,cont2) = Thickness_New(:,1);
            cont2 = cont2 + 1;
        end
    end
    
    pathname_2 = [GeneralPath,'\Results\',Cases{i},'\RightEye\'];
    oldfolfer = cd(pathname_2);

                MeanSpeed = median(SpeedMap_All,3,'omitnan');
                ErrorSpeed = std(SpeedMap_All,[],3,'omitnan');

                gcf=figure;
                imagesc(X(1,:),Y(:,1),MeanSpeed)
                %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
                ylabel('y-axis (mm)');
                xlabel('x-axis (mm)');
                axis equal
                axis([-5 5,...
                      -5 5]);
                colormap(jet)
                colorbar
                clim([0 20]) 
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
                axis([-5 5,...
                      -5 5]);
                colormap(jet)
                colorbar
                clim([0 20]) 
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
 
                Thres_ErrorSpeed = 0.7;
                [MeanSpeed,ErrorSpeed] = SmartMerging (PhaseSpeed_NewAll,Thres_ErrorSpeed);
                Thres_ErrorThickness = 20;
                [MeanThickness,ErrorThickness] = SmartMerging (Thickness_NewAll*1e3,Thres_ErrorThickness);
                                     
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

                                                    
    cd(oldfolfer)
    

    i
end


%%

SpeedMap_All(:,:,[6])=[];
PhaseSpeed_NewAll(:,[7,8])=[];
Thickness_NewAll(:,[7,8])=[];
