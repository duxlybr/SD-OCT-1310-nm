function [STM_Filtered] = DirectionalFilter2(SpaceTimeCurved,Tres,Xres,Nx,Dir)


[m,n] = size(SpaceTimeCurved);
Fs1 = 1/Tres; Fs2 = 1/Xres;
[k1,k2] = meshgrid(linspace(-0.5,0.5,Nx));
k1 = k1*(2*pi*Fs1);
k2 = k2*(2*pi*Fs2);
FFT = fftshift(fft2(SpaceTimeCurved,Nx,Nx));
% 
% figure
% imagesc(k1(1,:),k2(:,1),abs(FFT))
% axis equal
% axis([-3000 3000 -30000 30000])

H = zeros(Nx,Nx);
if strcmp(Dir,'left')  
    H(k1>=0 & k2>=0) = 1;
    H(k1<0 & k2<0) = 1;
elseif strcmp(Dir,'right')  
    H(k1>=0 & k2<0) = 1;
    H(k1<0 & k2>=0) = 1;
end
% H(k1>32000 | k1<-32000) = 0;
% H(k2>32000 | k2<-32000) = 0;
sigma = 2;
H_Gauss = imgaussfilt(H,sigma);

% figure
% imagesc(k1(1,:),k2(:,1),H_Gauss)
% axis equal
% axis([-8000 8000 -4000 4000])

STM_Filtered = real(ifft2(ifftshift(FFT.*H_Gauss)));
STM_Filtered = STM_Filtered(1:m,1:n);

end