function [vec_xy]=localloop_xy_v3(s_2D,Res_x,k,N,n,M,ini)

%ini=15;
   
 j=-round(N/2)+1:round(N/2)-1;
 jj=-round(M/2)+1:round(M/2)-1;
 i=round(N/2):n-round(N/2);
 
 s_idx=1:2:floor(length(i)/2)*2;
 ii=i(s_idx);
%ii=i;
 
 correc=xcorr2(ones(M-1,N-1));
 n_vecx=1:size(correc,2);
 n_vecy=1:size(correc,1);
 
 z_vecx=zeros(1,size(correc,2));
 z_vecy=zeros(1,size(correc,1));
  
%     parfor l=1:length(ii)
%         vec_x(1,l)=real(s_2D(k,ii(l)));
%         vec_y(1,l)=imag(s_2D(k,ii(l)));
%     end
 

parfor l=1:length(ii)
       
%     figure
%     imagesc(real(s_2D(k+jj,ii(l)+j)))   
  
    [Im]=xcorr2(s_2D(k+jj,ii(l)+j),s_2D(k+jj,ii(l)+j)); 
    
%     figure
%     imagesc(real(Im)./correc)
    
    n0=(size(Im,1)+1)/2;
    imP = ImToPolar(real(Im), 0, 1, n0, 360);
    imP1=[imP(end:-1:1,181:end);imP(2:end,1:180)];
    imP1=imP1./repmat(correc(:,n0),1,180);
    %imP1=min(imP1,[],2);
    imP1_ave=mean(imP1,2);
    
%     figure
%     plot(imP1)
%     hold on
%     plot(imP1_ave)
    
    %%%%%%%%%%%%% selected axis %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    B=imP1_ave;
    B=B/max(abs(B(n0)))*2/3;
    
%     figure
%     plot(real(B))
%     
% 
%     [xout,yout]=intersections(n_vecx(n1:end),real(B(n1:end)),n_vecx(n1:end),z_vecx(n1:end),1);
%     
%     if isempty(xout)
%         vec_x(1,l)=0;
%     else
%         vec_x(1,l)= (3.141/(xout(1)-n0))/(Res_x/(sqrt(pi)));
%     end 
    
    nn=ini;
    n0=(length(B)+1)/2; 
    n1=n0+nn; 
    
    if real(B(n1)) > real(B(n0))
        n1=n0+nn+5;
    end
    
    if real(B(n1)) > real(B(n0))
        n1=n0+nn+8;
    end   
    
    
    vec_xy(1,l)=sqrt( (1/(Res_x*nn)^2*(1-(real(B(n1))/real(B(n0))))) );

end
   
   
%    figure
%    hold on
%    plot(2*pi*500./(vec_x))
%    plot(2*pi*500./(vec_y))
   
  
  
   %vec1=smooth(vec(1,round(N/2):n-round(N/2)),z,'lowess');
 
end
