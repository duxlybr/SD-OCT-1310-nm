function [] = SliceCutter (StructuralVolume3D,OCE_system,N)

[nX,nY,nZ] = size(StructuralVolume3D);
Bmode_X = squeeze(StructuralVolume3D(:,round(nY/2),:))';
Bmode_Y = squeeze(StructuralVolume3D(round(nX/2),:,:))';


figure
subplot(1,3,1);
imagesc(Bmode_X);
caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high*1])
colormap(gray)  
title(['X profile. Choose N = ',num2str(N),' positions to analyse motion']);

subplot(1,3,2);
imagesc(Bmode_Y);
caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high*1])
colormap(gray)  
title(['Y profile']);

for ii = 1:N

    [x,y,button] = ginput(1);
    X_pos = round(x);
    Y_pos = round(y);
    
    subplot(1,3,1);
    hold on 
    scatter(X_pos,Y_pos,'filled','blue');
    hold off
    title(['Motion plot (rad) numer N = ',num2str(ii)]);
    
    EnFace_Slice = StructuralVolume3D(:,:,Y_pos)';
    
    subplot(1,3,3);
    imagesc(EnFace_Slice);
    caxis([OCE_system.i_thresh_low OCE_system.i_thresh_high*1])
    colormap(gray)  
    title(['En-face profile']);
    
end


end




