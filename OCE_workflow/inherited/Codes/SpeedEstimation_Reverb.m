function [Speed, K, Xaxis_E, Zaxis_E] = SpeedEstimation_Reverb(Frames2,Xaxis,Zaxis,Params)

Res_X = Xaxis(2);
Res_Z = Zaxis(2);
% WinSize = [2 0.2]; 
WinSize = Params.WinSize;
WinSize_n = (WinSize./[Res_X Res_Z]);
WinSize_n(1) = round2even(WinSize_n(1)); %Along X
WinSize_n(2) = round2even(WinSize_n(2)); %Along Z

Xaxis_win = Xaxis(1:WinSize_n(1));
Zaxis_win = Zaxis(1:WinSize_n(2));

[M,N,o] = size(Frames2);
GRIdd_X = [(WinSize_n(1)/2):round(WinSize_n(1)/4):(M-WinSize_n(1)/2)];
GRIdd_Z = [(WinSize_n(2)/2):round(WinSize_n(2)/4):(N-WinSize_n(2)/2)];

GRIdd_X_size = length(GRIdd_X);
GRIdd_Z_size = length(GRIdd_Z);

c_tmp = zeros(GRIdd_Z_size,GRIdd_X_size);
Speed.Ave = c_tmp;
K.Ave = c_tmp;


for jj = 1:GRIdd_Z_size
    
    Z_i = GRIdd_Z(jj) - (WinSize_n(2)/2)+1;
    Z_f = GRIdd_Z(jj) + (WinSize_n(2)/2);
    
    for ii = 1:GRIdd_X_size

        X_i = GRIdd_X(ii) - (WinSize_n(1)/2)+1;
        X_f = GRIdd_X(ii) + (WinSize_n(1)/2);

        ROI_win = Frames2(X_i:X_f, Z_i:Z_f, :);
        
        
%         figure(1)
%         for i = 1:217
%             imagesc(ROI_win(:,:,i)')
%             caxis([-2 2])
%             colormap(jet)
%             drawnow
%         end
        
%      Im_Ones = xcorr2(ones(10,10));   
%      [Im]=xcorr2(ROI_win(:,:,100)); 
%      Im = Im./Im_Ones;
%      
%      figure
%      imagesc(real(Im))
%      
%      Im1_Ones = fftshift(ifft2(fft2(ones(19,19)).*conj(fft2(ones(19,19)))));
%      Im1 = fftshift(ifft2(fft2(ROI_win(:,:,100),19,19).*conj(fft2(ROI_win(:,:,100),19,19))));
%      
%      figure
%      imagesc(real(Im1))
     
         %Im2_Ones= fftshift(ifftn(fftn(ones(19, 19, 217*2-1)).*conj(fftn(ones(19, 19, 217*2-1)))));
         Im2 = fftshift(ifftn(fftn(ROI_win(:,:,:),[WinSize_n(1)*2-1 WinSize_n(1)*2-1 o*2-1])...
                    .*conj(fftn(ROI_win(:,:,:),[WinSize_n(1)*2-1 WinSize_n(1)*2-1 o*2-1]))));
         Im2 = real(Im2(:,:,o));
     
%      figure
%      imagesc((Im2(:,:)))
%      figure
%      imagesc(angle(Im2(:,:)))
%      
%      figure
%      hold on
%      plot(real(Im2_Ones(10,:,217)))
     
    
        n0=(size(Im2,1)+1)/2;
        imP = ImToPolar(real(Im2), 0, 1, n0, 360);
        imP1=[imP(end:-1:1,181:end);imP(2:end,1:180)];
        imP1_ave=min(imP1,[],2);
        %imP1_ave=mean(imP1,2);
        
%        figure
%        hold on
%        plot(imP1_ave/max(imP1_ave)*222.8)
    
        %%%%%%%%%%%%% Fitting in Average %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        ini = 6;
        B=imP1_ave(n0:end);
        nn=ini;

        if real(B(nn)) > real(B(1))
            nn = nn+1;
        end

        if real(B(nn)) > real(B(1))
            nn = nn+2;
        end    

        WaveNumber(1,ii)=sqrt( (1/((Res_X*1e-3)*nn)^2*(1-(real(B(nn))/real(B(1))))) );
    
    end
    
    K.Ave(jj,:) = WaveNumber/1.41;
    Speed.Ave(jj,:) = 2*pi*Params.Freq ./ (WaveNumber/1.41);

    jj
end

Xaxis_E = Xaxis(round(GRIdd_X));
Zaxis_E = Zaxis(round(GRIdd_Z));

end