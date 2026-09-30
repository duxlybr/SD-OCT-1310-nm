function [vec_x,vec_y]=localloop_xy_v2(s_2D,Res_x,Res_y,k,N,n,M,ini)

%ini=15;
   
 j=-round(N/2)+1:round(N/2)-1;
 jj=-round(M/2)+1:round(M/2)-1;
 i=round(N/2):n-round(N/2);
 
%  s_idx=1:2:floor(length(i)/2)*2;
%  ii=i(s_idx);
ii=i;
 
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
  
    [Im]=xcorr2(s_2D(k+jj,ii(l)+j),s_2D(k+jj,ii(l)+j));
    %[Im]=xcorr(s_2D(k+jj,ii(l)),s_2D(k+jj,ii(l)),'unbiased');
  
    %%%%%%%%%%%%% x axis %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    n0=(size(Im,1)+1)/2;
    n1=(size(Im,2)+1)/2;
    B=Im(n0,:);
    B=B./correc(n0,:);
    B=B/max(abs(B(n1)));
    
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
    
    
    vec_x(1,l)=sqrt( (1/(Res_x*nn)^2*(1-(real(B(n1))/real(B(n0))))) );
    %vec_x(1,l)=1/(Res_x*nn)/2*atan2(imag(B(n1)),real(B(n1)));
     
    %%%%%%%%%%%%% y axis %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
     
    n0=(size(Im,2)+1)/2;
    n1=(size(Im,1)+1)/2;
    B=Im(:,n0);
    B=B./correc(:,n0);
    B=B/max(abs(B(n1)));
     
%     figure
%     plot(real(B)) 
%     
%     
%     
%     [xout,yout]=intersections(n_vecy(n1:end),real(B(n1:end)),n_vecy(n1:end),z_vecy(n1:end),1);
%     
%     if isempty(xout)
%         vec_y(1,l)=0;
%     else
%         vec_y(1,l)= (2.081/(xout(1)-n0))/(Res_y/(sqrt(pi)));
%     end 

    

    nn=ini;
    n0=(length(B)+1)/2;
    n1=n0+nn;
    
    if real(B(n1)) > real(B(n0))
        n1=n0+nn+3;
    end
    
    if real(B(n1)) > real(B(n0))
        n1=n0+nn+6;
    end   
    
    vec_y(1,l)=sqrt( (1/(Res_y*nn)^2*(1-(real(B(n1))/real(B(n0))))) );
    %vec_y(1,l)=1/(Res_y*nn)/2*atan2(imag(B(n1)),real(B(n1)));
    
    


   end
   
   
%    figure
%    hold on
%    plot(2*pi*500./(vec_x))
%    plot(2*pi*500./(vec_y))
   
  
  
   %vec1=smooth(vec(1,round(N/2):n-round(N/2)),z,'lowess');
 
end
