function [] = VolumeGenerationElastogram (B_mode1,Elasto,Bmask3,Zaxis,Xaxis,mask,Bmode_Enface)

Zaxis2=Zaxis(1:size(B_mode1{1},1));
params1.bmode_int_limit=[0 255];
params1.bmode_axes{1}=Xaxis';
params1.bmode_axes{2}=Zaxis2';
params1.vshear_int_limit=[3 4.3];
params1.vshear_axes{1}=Xaxis(1:end);
params1.vshear_axes{2}=Zaxis2; %(M/2:end-M/2);
params1.transparency=0.3;

h_im = imagesc(Bmode_Enface);
h = imellipse;
position = wait(h); 
mask2=(createMask(h,h_im));

h_im = imagesc(Bmode_Enface);
h = imrect;
position = wait(h); 
mask2=mask2.*(1-(createMask(h,h_im)));

for j = 1:100

    Min=18;
    Max=28;
    I=abs(B_mode1{j})+eps;
    I1=log10(I)*10;
    B_mode_log=255*((I1-Min)./(Max-Min));

    B_mode_log1=zeros(size(I,1)+max(Bmask3(j,:)),size(I,2));
    
    for i=1:100
        B_mode_log1(Bmask3(j,i):Bmask3(j,i)+size(I,1)-1,i)=B_mode_log(:,i);
    end
    
    B_mode_log1 = B_mode_log1.*repmat(mask2(j,:),size(B_mode_log1,1),1);

    Elasto1=zeros(size(I,1)+max(Bmask3(j,:)),size(I,2));
    mask1=Elasto1;
    for i=1:100
        Elasto1(Bmask3(j,i):Bmask3(j,i)+size(I,1)-1,i)=Elasto(:,i);
        mask1(Bmask3(j,i):Bmask3(j,i)+size(I,1)-1,i)=mask(:,i);
    end
    
    mask1 = mask1.*repmat(mask2(j,:),size(mask1,1),1);


    [xx,yy]=meshgrid([1:size(Elasto1,2)],[1:size(Elasto1,1)]);
    [xx1,yy1]=meshgrid(linspace(1,size(Elasto1,2),500),[1:size(Elasto1,1)]);
    Elasto2 = interp2(xx,yy,Elasto1,xx1,yy1);
    Elasto2 = imgaussfilt(Elasto2,3);

%     figure
%     imagesc(Elasto1)
%     caxis([[3 4.3]])
% 
%     figure
%     imagesc(Elasto2)
%     caxis([[3 4.3]])

    params1.mask=interp2(xx,yy,mask1(:,1:end),xx1,yy1);
    B_mode_log2=interp2(xx,yy,B_mode_log1,xx1,yy1);
    
    
    Show_Elastogram1(B_mode_log2,Elasto2(:,1:end),params1,j)
    
   j
end





















