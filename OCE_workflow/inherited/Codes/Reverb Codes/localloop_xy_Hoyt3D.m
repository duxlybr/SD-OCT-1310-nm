function [vec_xy]=localloop_xy_Hoyt3D(s_2D,Res_xy,k,N,n,M,ini)

%ini=15;
 
Res_x = Res_xy(1);
Res_y = Res_xy(2);

j=-round(N/2)+1:round(N/2)-1;
jj=-round(M/2)+1:round(M/2)-1;
i=round(N/2):n-round(N/2);
 
s_idx=1:10:floor(length(i)/2)*2;
ii=i(s_idx);
%ii=i;
 
correc=xcorr2(ones(M-1,N-1));
 
%xdata = [-Res_x*(N-1-1):Res_x:Res_x*(N-1-1)]';
vec_xy_X = zeros(1,length(ii));
vec_xy_Y = vec_xy_X;

parfor l=1:length(ii)
      
    [Im]=xcorr2(s_2D(k+jj,ii(l)+j),s_2D(k+jj,ii(l)+j)); 
    m0=(size(Im,1)+1)/2;
    n0=(size(Im,2)+1)/2;
    imP1=(Im)./correc;
    
%     figure
%     imagesc(real(imP1))
%     figure
%     imagesc(real(s_2D(k+jj,ii(l)+j)))
    
    %%%%% Along Y axis %%%%%
    B=imP1(m0+1:end,n0);
    nn=ini;
    
    if real(B(nn)) > real(B(1))
        nn = nn+5;
    end
    
    if real(B(nn)) > real(B(1))
        nn = nn+8;
    end    
    
%     figure
%     hold on
%     plot(real(B))
    
    vec_xy_Y(1,l) = (1/(Res_y*nn))*atan2(imag(B(nn)),real(B(nn)));
    
    %%%%% Along X axis %%%%%
    B=imP1(m0,n0+1:end);
    nn=ini;
    
    if real(B(nn)) > real(B(1))
        nn = nn+5;
    end
    
    if real(B(nn)) > real(B(1))
        nn = nn+8;
    end    
    
    vec_xy_X(1,l) = (1/(Res_x*nn))*atan2(imag(B(nn)),real(B(nn)));

end
   
   vec_xy.X = vec_xy_X;
   vec_xy.Y = vec_xy_Y;

end