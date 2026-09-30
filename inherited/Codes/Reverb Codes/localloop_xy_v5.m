function [vec_xy]=localloop_xy_v5(s_2D,Res_x,k,N,n,M)


 j=-round(N/2)+1:round(N/2)-1;
 jj=-round(M/2)+1:round(M/2)-1;
 i=round(N/2):n-round(N/2);
 
 s_idx=1:1:floor(length(i)/2)*2;
 ii=i(s_idx);
 
 correc=xcorr2(ones(M-1,N-1));
 xdata = [-Res_x*(N-1-1):Res_x:Res_x*(N-1-1)]';
 
 vec_xy_ave = zeros(1,length(ii));
 zci = @(v) find(v(:).*circshift(v(:), [-1 0]) <= 0);  

parfor l=1:length(ii)
      
        [Im]=xcorr2(s_2D(k+jj,ii(l)+j),s_2D(k+jj,ii(l)+j)); 
%         [c] = contourc(real(Im)/real(Im(n0,n0)),[0.7 0.7]);
%         [coeff]  = pca(c');
        
%         figure
%         quiver(35,35,coeff(1,1),coeff(2,1),30);
%         hold on
%         quiver(35,35,coeff(1,2),coeff(2,2),30);
%         hold on
%         scatter(c(1,:),c(2,:))

        n0=(size(Im,1)+1)/2;
        imP = ImToPolar(real(Im), 0, 1, n0, 360);
        imP1=[imP(end:-1:1,181:end);imP(2:end,1:180)];
        imP1=imP1./repmat(correc(:,n0),1,180);                
        %imP1_ave=min(imP1,[],2);
        imP1_ave=mean(imP1,2);
        
        
        %% Getting Avergae and Half Profiles
        
        imP1_ave_half = imP1_ave(n0+1:end);
        xdata_half = xdata(n0+1:end);
        
        %% Getting Zero crossing
        zx = zci(imP1_ave_half);   

        pt1x = [xdata_half(zx(1)) xdata_half(zx(1)+1)];
        pt1y = [0 0];
        pt2x = pt1x;
        pt2y = [imP1_ave_half(zx(1)) imP1_ave_half(zx(1)+1)];
        [Zero_xi,Zero_yi] = polyxpoly(pt1x,pt1y,pt2x,pt2y);    

        %% Finding k based on calibration

        vec_xy_ave(1,l) = 2.744/Zero_xi;


   end
   
vec_xy = vec_xy_ave;


end