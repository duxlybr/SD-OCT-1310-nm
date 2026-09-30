%%%%%%%%%%%%%%%
close all
%%%%%%%%%%%%%%%

NumBscanSingle = OCT_system.NumBscanSingle;

for i = 1:OCT_system.NumAngles
    
    SpaceTime_tmp = SpaceTime(NumBscanSingle*(i-1)+1:NumBscanSingle*(i),:);
    
    figure
    imagesc(SpaceTime_tmp')
    colormap(fireice)
    caxis([-CLim CLim/2])
    
    Propagation(i*2-1,:,:) = SpaceTime_tmp(NumBscanSingle/2:-1:1,:);
    Propagation(i*2,:,:) = SpaceTime_tmp(NumBscanSingle/2+1:NumBscanSingle,:);


end

AnglesAll = [0:180/OCT_system.NumAngles:180/OCT_system.NumAngles*(2*OCT_system.NumAngles-1)]';
[idx_angles] = IDXSelection(OCT_system.NumAngles);

Propagation_New = Propagation(idx_angles,:,:);

theta = repmat(AnglesAll/180*pi,1,NumBscanSingle/2);
rho = repmat(linspace(0,5e-3,NumBscanSingle/2),length(AnglesAll),1);
[x,y] = pol2cart(theta,rho);

[X, Y] = meshgrid(linspace(-5e-3,5e-3,NumBscanSingle));

figure
scatter(x,y)

%%%%%%%%%%%%%%%%%%%%%%
CLim = 0.1;
%%%%%%%%%%%%%%%%%%%%%%
aviobj = VideoWriter(['Video_2D_Filtered_Enface.avi']); 
aviobj.FrameRate = 10; 
open(aviobj); 

for i = 1:900
    
    rhoMotion = Propagation_New(:,:,i);
    
    F = scatteredInterpolant(x(:),y(:),rhoMotion(:),'natural','none');
    Frame_tmp_r = F(X,Y);
    VideoEnFace(:,:,i) = Frame_tmp_r;
    
%     figure(1)
%     imagesc(X(1,:),Y(:,1),Frame_tmp_r)
%     colormap(fireice)
%     caxis([-CLim CLim])
%     axis equal
%     drawnow
    
    gcf=figure(1);
    imagesc((X(1,:))*1e3,(Y(:,1))*1e3,Frame_tmp_r)
    %imagesc(Xaxis1*1e3,Yaxis1*1e3,squeeze(SpaceTime(:,:,j)))
    ylabel('y-axis (mm)');
    xlabel('x-axis (mm)');
    axis equal
    axis([-5 5 -5 5])
    colormap(fireice)
    caxis([-CLim CLim/2])
    title(['Motion frames - Filtered (Time = ',num2str(round(Time(i),2),'%10.2f\n'),' ms)'])   
    set(gca,'FontSize',14)
    drawnow
    
  
    %pause(0.2)
    

    F=getframe(gcf); 
    writeVideo(aviobj,F);

end

close(aviobj);
fclose all;


FFT = fft(VideoEnFace,2^12,3);

figure
imagesc(X(1,:),Y(:,1),real(FFT(:,:,73)))
colormap(fireice)
caxis([-3 3])
axis equal
ylim reverse

%%%%%%%%%%%%%%%%%%
%cd(oldFolder)
%%%%%%%%%%%%%%%%%%
