function [vec_xy]=localloop_xy_Hoyt(s_2D,Res_xy,k,N,n,M,ini)

%ini=15;
 Res_y = Res_xy(2);  
 j=-round(N/2)+1:round(N/2)-1; % Along x
 jj=-round(M/2)+1:round(M/2)-1; % Along y
 i=round(N/2):n-round(N/2); % Along x
 
 s_idx=1:1:floor(length(i)/2)*2; % Along x
 ii=i(s_idx);                    % Along x
%ii=i;
 
 correc=xcorr2(ones(M-1,N-1));
 ydata = [-Res_y*(M-1-1):Res_y:Res_y*(M-1-1)]';

 
parfor l=1:length(ii)
      
       
%     xdata = [0:Res_x:Res_x*99];   
%     figure
%     imagesc(ydata(k+jj),ydata(ii(l)+j),real(s_2D(k+jj,ii(l)+j)))   
  
%     figure
%     imagesc(real(s_2D))
  
    [Im]=xcorr2(s_2D(k+jj,ii(l)+j),s_2D(k+jj,ii(l)+j)); 
    
%     figure
%     imagesc(real(Im)./correc)
%     axis equal
    
    m0=(size(Im,1)+1)/2;
    n0=(size(Im,2)+1)/2;
    imP1=(Im)./correc;

    %%%%%%%%%%%%% Fitting in Min %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    B=imP1(m0+1:end,n0);
    nn=ini;
    
%     figure
%     plot(B)
%     figure
%     plot(real(s_2D(k+jj,ii(l))))
    
    if real(B(nn)) > real(B(1))
        nn = nn+5;
    end
    
    if real(B(nn)) > real(B(1))
        nn = nn+8;
    end    
    
    %vec_xy_min(1,l)=sqrt( (1/(Res_y*nn)^2*(1-(real(B(nn))/real(B(1))))) );
    vec_xy_min(1,l) = (1/(Res_y*nn))*atan2(imag(B(nn)),real(B(nn)));

end
   
   vec_xy.Min = vec_xy_min;

   
end