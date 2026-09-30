function [vec_xy]=localloop_xy_v6(s_2D,Res_x,k,N,n,M)

%ini=15;
   
 j=-round(N/2)+1:round(N/2)-1;
 jj=-round(M/2)+1:round(M/2)-1;
 i=round(N/2):n-round(N/2);
 
 s_idx=1:1:floor(length(i)/2)*2;
 ii=i(s_idx);
%ii=i;
 
 correc=xcorr2(ones(M-1,N-1));
%  n_vecx=1:size(correc,2);
%  n_vecy=1:size(correc,1);
%  
%  z_vecx=zeros(1,size(correc,2));
%  z_vecy=zeros(1,size(correc,1));
 
 xdata = [-Res_x*(N-1-1):Res_x:Res_x*(N-1-1)]';
 vec_xy_ave = zeros(1,length(ii));
 vec_xy_min = vec_xy_ave;
 vec_xy_minAngle = vec_xy_ave;
 vec_xy_max = vec_xy_ave;
 vec_xy_maxAngle = vec_xy_ave;
 %Qual_xy = zeros(1,length(ii));
 
%     parfor l=1:length(ii)
%         vec_x(1,l)=real(s_2D(k,ii(l)));
%         vec_y(1,l)=imag(s_2D(k,ii(l)));
%     end
 
parfor l=1:length(ii)
      
       
%     xdata = [0:Res_x:Res_x*99];   
%     figure
%     imagesc(xdata(k+jj),xdata(ii(l)+j),real(s_2D(k+jj,ii(l)+j)))   
  
%     figure
%     imagesc(xdata,xdata,real(s_2D))
  
    [Im]=xcorr2(s_2D(k+jj,ii(l)+j),s_2D(k+jj,ii(l)+j)); 
    
%     figure
%     imagesc(xdata,xdata,real(Im)./correc)
%     axis equal
    
    n0=(size(Im,1)+1)/2;
    imP = ImToPolar(real(Im), 0, 1, n0, 360);
    imP1=[imP(end:-1:1,181:end);imP(2:end,1:180)];
    imP1=imP1./repmat(correc(:,n0),1,180);
    %imP1_ave=min(imP1,[],2);
    imP1_ave=mean(imP1,2);
    [pks, locs] = findpeaks(-imP1_ave(n0+1:end),'NPeaks',1);
    
    if isempty(locs)
        locs = length(imP1_ave(n0+1:end))-1;
    end
    
    step_x = round(locs/3)+n0;
    [ val, MaxAngle] = max(imP1(step_x,:));
    [ val, MinAngle] = min(imP1(step_x,:));
        
    imP1_min=imP1(:,MinAngle);
    imP1_max=imP1(:,MaxAngle);

%     figure
%     plot(xdata,imP1)
%     hold on
%     plot(xdata,imP1_ave)
%     plot(xdata,imP1_min)
%     plot(xdata,imP1_max)
    
    %%%%%%%%%%%%% Fitting in Average %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    B=imP1_ave(n0+1:end);
    xdata1 = xdata(n0+1:end);
    [pks, locs] = findpeaks(-B,'NPeaks',1);
    
    if isempty(locs)
        Zero_xi=NaN;
    else
        Zero_xi = xdata1(locs);
    end
    vec_xy_ave(1,l) = 4.2329/Zero_xi;
   
    %%%%%%%%%%%%% Fitting in Min %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    B=imP1_min(n0+1:end);
    xdata1 = xdata(n0+1:end);
    [pks, locs] = findpeaks(-B,'NPeaks',1);
    
    if isempty(locs)
        Zero_xi=NaN;
    else
        Zero_xi = xdata1(locs);
    end
    vec_xy_min(1,l) = 4.2329/Zero_xi;
            
    %%%%%%%%%%%%% Fitting in Max %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    B=imP1_max(n0+1:end);
    xdata1 = xdata(n0+1:end);
    [pks, locs] = findpeaks(-B,'NPeaks',1);
    
    if isempty(locs)
        Zero_xi=NaN;
    else
        Zero_xi = xdata1(locs);
    end
    vec_xy_max(1,l) = 4.2329/Zero_xi;

    vec_xy_minAngle(1,l) = MinAngle;
    vec_xy_maxAngle(1,l) = MaxAngle;
    %Qual_xy(1,l) = gof.adjrsquare;

end
   
   vec_xy.Ave = vec_xy_ave;
   vec_xy.Min = vec_xy_min;
   vec_xy.AngleMin = vec_xy_minAngle;
   vec_xy.Max = vec_xy_max;
   vec_xy.AngleMax = vec_xy_maxAngle;
   

end