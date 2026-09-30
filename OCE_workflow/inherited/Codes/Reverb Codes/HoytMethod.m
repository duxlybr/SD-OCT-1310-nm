function [InvLambda]=HoytMethod(s_2D,win,Res_xy,ini)
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
M=win(1); % Along y
N=win(2); % Along x

i=round(M/2):m-round(M/2);  % Along y
s_idx=1:10:floor(length(i)/2)*2;   
ii=i(s_idx);
%ii=i;

i_2=round(N/2):n-round(N/2); % Along x
s_idx2=1:1:floor(length(i_2)/2)*2; % Along x
ii2=i_2(s_idx2);                    % Along x

Kasai_xy_Min = zeros(length(ii),length(ii2));
%Quality = zeros(length(ii),length(ii));
 
for k=1:length(ii)

    [vec_xy]=localloop_xy_Hoyt(s_2D,Res_xy,ii(k),N,n,M,ini);
    Kasai_xy_Min(k,:)=vec_xy.Min;

    [k length(ii)]
end 
    
        
InvLambda=Kasai_xy_Min;


end