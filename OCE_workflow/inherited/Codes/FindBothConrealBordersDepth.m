function [DistBorder,Border,TopBorder,BottomBorder] = FindBothConrealBorders(Xaxis,Zaxis,Bmode,OCE_system,OCT_system)


NumBscanSingle = OCT_system.NumBscanSingle;

%% Find top border

OCE_system.PeakThresMult = 10;
OCE_system.PeakThresWinSize = 50; 
[Border] = FindSurface(Bmode,OCE_system,OCT_system);

Border.Idx(end)= nan;
Border.Idx = Border.Idx - 4;
idx1 = find(Border.Idx>OCE_system.NewDepthSize-1-0);
Border.Idx (idx1) = OCE_system.NewDepthSize-1-1;

Bmode_IntLog = real(20*log10(Bmode));

% figure
% imagesc(Bmode_IntLog)
% caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
% colormap(gray)
% hold on
% plot(Border.Idx);

DiffBorder = abs(diff(Border.Idx));
%%%%%%%%%%%%%%%%%%%%%%%%%%%
idx2 = find(DiffBorder>25);
%%%%%%%%%%%%%%%%%%%%%%%%%%%
CloseDist = abs(diff(idx2));
idx_dist = find(CloseDist<=3);
idx2_New = [];
for i = idx_dist
    tmp = idx2(i)+1:idx2(i+1)-1;
    idx2_New = cat(2,idx2_New,tmp);
end
%DiffBorder = medfilt2(DiffBorder,[1 3],'Symmetric');
%idx = find(DiffBorder>25);
%idx = union(idx,idx+1);
idx = union(idx2_New,idx2);
Border.Idx(idx) = NaN;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% tamaño de datos(imagen en profundidad)
Border.Idx(Border.Idx<30) = NaN;
Border.Idx(Border.Idx>900) = NaN;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

Border_tmp = Border.Idx;
for i = 1:OCT_system.NumAngles
    Border_tmp(1,NumBscanSingle*(i-1)+1:NumBscanSingle*(i)) = ...
    smooth(Border.Idx(1,NumBscanSingle*(i-1)+1:NumBscanSingle*(i)),0.08,'lowess');
end
    
Border.Idx_Up = round(Border_tmp);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
Border.Idx_Up(Border.Idx_Up<30) = 30;
Border.Idx_Up(Border.Idx_Up>900) = 900;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% figure
% imagesc(Bmode_IntLog)
% caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
% colormap(gray)
% hold on
% plot(Border.Idx );
% plot(Border.Idx_Up );

%% Find bottom border

Bk_section = Bmode(50:100,10:30);
Bk = mean(Bk_section(:));
Bmode1 = Bmode;
for i =1:size(Bmode,2)
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Bmode1(Border.Idx_Up(i)+320:end,i) = Bk;
    %aca modificar para el tema de borde inferior para porcine
end

% Bmode_IntLog1 = real(20*log10(Bmode1));
% 
% figure
% imagesc(Bmode_IntLog1)
% caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
% colormap(gray)
% hold on
% plot(Border.Idx);

OCE_system.PeakThresMult = 10;%1.5;
OCE_system.PeakThresWinSize =30; 
[Border1_1] = FindSurface(flip(Bmode1,1),OCE_system,OCT_system);
OCE_system.PeakThresMult = 13;% 8  4;
OCE_system.PeakThresWinSize = 50; 
[Border1_2] = FindSurface(flip(Bmode1,1),OCE_system,OCT_system);

for i = 1:OCT_system.NumAngles
    Border1.Idx(NumBscanSingle*(i-1)+1+40:NumBscanSingle*(i)-40) = Border1_2.Idx(NumBscanSingle*(i-1)+1+40:NumBscanSingle*(i)-40);
    Border1.Idx([NumBscanSingle*(i-1)+1:NumBscanSingle*(i-1)+1+39,NumBscanSingle*(i)-39:NumBscanSingle*(i)]) = Border1_1.Idx([NumBscanSingle*(i-1)+1:NumBscanSingle*(i-1)+1+39,NumBscanSingle*(i)-39:NumBscanSingle*(i)]);
end

Border1.Idx(idx) = NaN;
Border1.Idx = medfilt2(Border1.Idx,[1 5],'Symmetric');

Border_tmp = Border1.Idx;
for i = 1:OCT_system.NumAngles
    Border_tmp(1,NumBscanSingle*(i-1)+1:NumBscanSingle*(i)) = ...
    smooth(Border1.Idx(1,NumBscanSingle*(i-1)+1:NumBscanSingle*(i)),0.08,'lowess');
end
    
Border.Idx_Down = round(Border_tmp-4);   
Border.Idx_Down = size(Bmode,1) - Border.Idx_Down+1;

for i = 1:OCT_system.NumAngles
    Border.Idx_Down([NumBscanSingle*(i-1)+1:NumBscanSingle*(i-1)+1+20,NumBscanSingle*(i)-20:NumBscanSingle*(i)]) = NaN;
end

% Bmode_IntLog1 = real(20*log10(flip(Bmode1,1)));
% 
% figure
% imagesc(Bmode_IntLog)
% caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
% colormap(gray)
% hold on
% plot(Border.Idx_Up);
% plot(Border.Idx_Down);


%%

TopBorder(:,1) = Xaxis;
TopBorder(:,2) = Border.Idx_Up'*OCT_system.axial_pixel_res/OCT_system.IDXrefrac*1e-3;

BottomBorder(:,1) = Xaxis;
BottomBorder(:,2) = Border.Idx_Down'*OCT_system.axial_pixel_res/OCT_system.IDXrefrac*1e-3;

gcf = figure;
imagesc(Xaxis,Zaxis,Bmode_IntLog)
hold on
plot(TopBorder(:,1),TopBorder(:,2));
plot(BottomBorder(:,1),BottomBorder(:,2));
caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high])
colormap(gray)
ylabel('z-axis (mm)');
xlabel('x-axis (mm)');
title('B-mode image');
%axis equal
%axis([Xaxis(1) Xaxis(end) Zaxis(1) Zaxis(end)])
axis([0  Xaxis(end) 0 Zaxis(end)])
set(gca,'FontSize', 14);
saveas(gcf,'BmodeBorder.fig');
saveas(gcf,'BmodeBorder.tif');
%% Thickness

[IdxBorder,DistBorder] = knnsearch(BottomBorder,TopBorder,'K',1);
%DistBorder = medfilt2(DistBorder,[3 1],'Symmetric');
DistBorder = smooth(DistBorder,0.005,'lowess');

% figure
% plot(DistBorder)

end