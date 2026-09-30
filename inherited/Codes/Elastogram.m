function [Frame_tmp_r,X,Y] = Elastogram(ParamsElasto,OCT_system,OCE_system,Frames2,Bmode_Mask,Bmode_IntLog,Border,Xaxis,Zaxis)

%% Parameters
Params = ParamsElasto;
Ts = Params.Ts;

freq = linspace(0,1,Params.FFT_Nx)/Ts;
Nf = find(freq>Params.Freq);
Nf = Nf(1);

Params.FFT_FreqSample = Nf;
DephtCut = Params.ZcutRange;


%% Wave speed 2D - multi-meridian

[Speed2D, Xaxis_E, Zaxis_E] = SpeedEstimation_PhaseDeriv(Frames2(1:end,DephtCut(1):DephtCut(2),:),Xaxis(1:end),Zaxis(1:diff(DephtCut)+1),Params);
Speed2D_Equiv = abs(Speed2D.Equiv);
Speed2D_Equiv(Speed2D_Equiv>20) = NaN;
Speed2D_Equiv(Speed2D_Equiv<0) = NaN;
Speed2D_Equiv_Filt = nanmedfilt2(Speed2D_Equiv,[3 3]);

%Speed2D_Equiv_Filt = medfilt2(Speed2D_Equiv,[3 3],'Symmetric');

figure
imagesc(Xaxis_E,Zaxis_E,abs(Speed2D_Equiv_Filt))
caxis([0 20])
colormap(jet)

SpeedEquivInterp = interp2(Xaxis_E,Zaxis_E,Speed2D_Equiv_Filt,Xaxis,Zaxis(1:diff(DephtCut)+1),'linear',0.0005);

% figure
% imagesc(Xaxis,Zaxis,SpeedEquivInterp.*Bmode_Mask)
% caxis([0 5])

gcf = figure;
imagesc(Xaxis,Zaxis(1:diff(DephtCut)+1),SpeedEquivInterp.*Bmode_Mask(DephtCut(1):DephtCut(2),:))
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
title(['Speed Map - ',num2str(Params.Freq),' Hz'])
%axis equal
axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(diff(DephtCut)+1)])
set(gca,'FontSize',14)
colorbar
colormap(jet)
caxis([0 20])
saveas(gcf,['Speed_Map_Alone_',num2str(Params.Freq),'Hz.fig']);
saveas(gcf,['Speed_Map_Alone_',num2str(Params.Freq),'Hz.tif']);


I = uint8(255*mat2gray(Bmode_IntLog(DephtCut(1):DephtCut(2),:).*...
                       Bmode_Mask(DephtCut(1):DephtCut(2),:), ...
                       [OCE_system.i_thresh_low OCE_system.i_thresh_high]));
bg = ind2rgb(I,gray(255));
bgImg = double(bg);
alphaFactor = 0.4;
bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*Bmode_Mask(DephtCut(1):DephtCut(2),:);
bgImgAlpha_out = bgImg.*(1-Bmode_Mask(DephtCut(1):DephtCut(2),:));
bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;

II = uint8(255*mat2gray(SpeedEquivInterp.*Bmode_Mask(DephtCut(1):DephtCut(2),:), [0 20]));
im = ind2rgb(II,hot(255));

fgImg = double(im);
fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask(DephtCut(1):DephtCut(2),:));
fusedImg = fgImgAlpha + bgImgAlpha;

gcf=figure;
imagesc(Xaxis,Zaxis(1:diff(DephtCut)+1),fusedImg)
%imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
%axis equal
axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(diff(DephtCut)+1)])
title(['Speed Map - ',num2str(Params.Freq),' Hz'])
set(gca,'FontSize',14)
colorbar
colormap(hot)
caxis([0 20])
drawnow
saveas(gcf,['Elastogram_2D_Hot_',num2str(Params.Freq),'Hz.fig']);
saveas(gcf,['Elastogram_2D_Hot_',num2str(Params.Freq),'Hz.tif']);


I = uint8(255*mat2gray(Bmode_IntLog(DephtCut(1):DephtCut(2),:).*Bmode_Mask(DephtCut(1):DephtCut(2),:), [OCE_system.i_thresh_low OCE_system.i_thresh_high]));
bg = ind2rgb(I,gray(255));
bgImg = double(bg);
alphaFactor = 0.4;
bgImgAlpha_in = (1 - alphaFactor) .* bgImg.*Bmode_Mask(DephtCut(1):DephtCut(2),:);
bgImgAlpha_out = bgImg.*(1-Bmode_Mask(DephtCut(1):DephtCut(2),:));
bgImgAlpha = bgImgAlpha_in + bgImgAlpha_out;

II = uint8(255*mat2gray(SpeedEquivInterp.*Bmode_Mask(DephtCut(1):DephtCut(2),:), [0 20]));
im = ind2rgb(II,jet(255));

fgImg = double(im);
fgImgAlpha = alphaFactor .* fgImg.*(Bmode_Mask(DephtCut(1):DephtCut(2),:));
fusedImg = fgImgAlpha + bgImgAlpha;


gcf=figure;
imagesc(Xaxis,Zaxis(1:diff(DephtCut)+1),fusedImg)
%imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
%axis equal
axis([Xaxis_E(1) Xaxis_E(end) 0 Zaxis(diff(DephtCut)+1)]) 
title(['Speed Map - ',num2str(Params.Freq),' Hz'])
set(gca,'FontSize',14)
colorbar
colormap(jet)
caxis([0 20])
drawnow
saveas(gcf,['Elastogram_2D_Jet1_',num2str(Params.Freq),'Hz.fig']);
saveas(gcf,['Elastogram_2D_Jet1_',num2str(Params.Freq),'Hz.tif']);

%% En-face wave speed map

NumBscanSingle = OCT_system.NumBscanSingle;
DeltaSpace = Params.DeltaSpace;
Center_idx = NumBscanSingle/2;

for i = 1:OCT_system.NumAngles
    
    Speed_tmp = SpeedEquivInterp(:,NumBscanSingle*(i-1)+1:NumBscanSingle*(i))';
    
    for j = 1: NumBscanSingle 
        pointer_ini = Border.Idx_Up(NumBscanSingle*(i-1)+j)-DephtCut(1)+1;
        if pointer_ini<1 | pointer_ini > diff(DephtCut)+1-DeltaSpace-10
            pointer_ini = round(diff(DephtCut)/2);
        end
        Speed_Line(j) = median(Speed_tmp(j,pointer_ini:pointer_ini+DeltaSpace),2);
    end
    
%     figure
%     imagesc(Speed_tmp')
%     colormap(jet)
%     caxis([0 20])
    
    SpeedMer(i*2-1,:) = Speed_Line(NumBscanSingle/2:-1:1);
    SpeedMer(i*2,:) = Speed_Line(NumBscanSingle/2+1:NumBscanSingle);
    
    SpeedMerAve(i*2-1,1) = mean(Speed_Line(1,Center_idx-DeltaSpace-4:Center_idx-4));
    SpeedMerAve(i*2,1) = mean(Speed_Line(1,Center_idx+4:Center_idx+4+DeltaSpace));


end

AnglesAll = [0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(2*OCT_system.NumAngles-1)]';
[idx_angles] = IDXSelection(OCT_system.NumAngles);

SpeedMer_New = SpeedMer(idx_angles,:,:);
SpeedMerAve_New = SpeedMerAve(idx_angles,:,:);

theta = repmat(AnglesAll/180*pi,1,NumBscanSingle/2);
rho = repmat(linspace(0,OCT_system.x_scan_width/2,NumBscanSingle/2),length(AnglesAll),1);
[x,y] = pol2cart(theta,rho);

[X, Y] = meshgrid(linspace(-OCT_system.x_scan_width/2,OCT_system.x_scan_width/2,NumBscanSingle));

% figure
% scatter(x,y)
    
rhoSpeed = SpeedMer_New(:,:);

F = scatteredInterpolant(x(:),y(:),rhoSpeed(:),'natural','none');
Frame_tmp_r = F(X,Y);
Frame_tmp_r = medfilt2(Frame_tmp_r,[5 5],'Symmetric');

gcf=figure;
imagesc(X(1,:),Y(:,1),Frame_tmp_r)
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
saveas(gcf,['Elastogram_EnFace_Jet1_',num2str(Params.Freq),'Hz.fig']);
saveas(gcf,['Elastogram_EnFace_Jet1_',num2str(Params.Freq),'Hz.tif']);

uiopen('FigModelPolarPlot.fig',1)
gcf = figure(1);
subplot(1,2,1)
polarplot([AnglesAll/180*pi; 0],[SpeedMerAve_New; SpeedMerAve_New(1)],'-bs','linewidth',1,'MarkerSize',8)
title(['Phase speed (m/s) @ ',num2str(Params.Freq),'Hz.'])
set(gca,'FontSize',14);
subplot(1,2,2)
boxplot(SpeedMerAve_New,'Whisker',1);
[Mean,Error,Range] = grpstats (SpeedMerAve_New,[],{'mean','std','range'});
title(['Mean ',num2str(round(Mean,2)),' m/s, STD ',num2str(round(Error,3)),' m/s.'])
grid on
saveas(gcf,'PolarPhaseSpeedAvg.fig');
saveas(gcf,'PolarPhaseSpeedAvg.tif');

%% Saving variables

save('Elastograms.mat','Speed2D','Xaxis_E','Zaxis_E','Speed2D_Equiv_Filt',...
                      'SpeedEquivInterp','SpeedMer_New','SpeedMerAve_New',...
                      'theta','rho','X','Y','rhoSpeed','Frame_tmp_r');

                  
end
