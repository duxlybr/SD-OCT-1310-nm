function [InvLambda]=Kasai6(s_2D,win,Res_x)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Local frequency estimator of a wave base on the approach proposed by
% Hoyt, et al. 
% Inputs:  Video - Estructure Video{i}, i=1,..,n, where n is the amount of 
%                  frames in th video. Each frame contains an array of rows
%                  where each row corresponds to a signal.
%          win   - Size of the windows kernel.
%          Res_L - Resolution of the x-axis of the signal in Video.
% Outputs: K-shear - Spatial frequency (k) of video for each x. If the video
%                    has more than one frame, the estimated k will be the
%                    average of all frames.
%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Examples:
%__________________________________________________________
%  Estimation of local frequency of a signal of 300 Hz
%  f=200;
%  Ts=1/(100*f);
%  x=0:Ts:0.01;
%  Sa=(cos(2*pi*f*x+pi/5)+0);
%  s_2D = hilbert(Sa);
%  
%  win=[30 1];
%  Res_x=Ts;
%  Res_y=Ts;
%   
% [InvLambda]=Kasai(s_2D,win,Res_x,Res_y);
% 
%  figure
%  plot(InvLambda{1}/(2*pi))  
% 
% [r1,lags] = xcorr(s_2D,s_2D);
% r1=(real(r1))/(max(real(r1)));
% [fitresult, gof] = J1_Fitting(lags(120:280), r1(120:280));
% k=fitresult.b/(Ts)/(2*pi);
%______________________________________________________________________

[m,n]=size(s_2D);
N=win(2); 
M=win(1); 
    
i=round(M/2):m-round(M/2);
s_idx=1:1:floor(length(i)/2)*2;
ii=i(s_idx);
%ii=i;

Kasai_xy_Mean = zeros(length(ii),length(ii));
Kasai_xy_Min = zeros(length(ii),length(ii));
Kasai_xy_AngleMin = zeros(length(ii),length(ii));
Kasai_xy_Max = zeros(length(ii),length(ii));
Kasai_xy_AngleMax = zeros(length(ii),length(ii));
%Quality = zeros(length(ii),length(ii));
 
for k=1:length(ii)

    [vec_xy]=localloop_xy_v6(s_2D,Res_x,ii(k),N,n,M);
    Kasai_xy_Mean(k,:)=vec_xy.Ave;
    Kasai_xy_Min(k,:)=vec_xy.Min;
    Kasai_xy_AngleMin(k,:)=vec_xy.AngleMin;
    Kasai_xy_Max(k,:)=vec_xy.Max;
    Kasai_xy_AngleMax(k,:)=vec_xy.AngleMax;
    
    %Qual_xy(k,:)=qual_xy;
    [k length(ii)]
end 
    
        
InvLambda.Ave=Kasai_xy_Mean;
InvLambda.Min=Kasai_xy_Min;
InvLambda.AngleMin=Kasai_xy_AngleMin;
InvLambda.Max=Kasai_xy_Max;
InvLambda.AngleMax=Kasai_xy_AngleMax;
%Quality=Qual_xy;



end