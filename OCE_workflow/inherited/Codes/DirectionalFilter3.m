function [STM_Filtered] = DirectionalFilter3(Frames2,Tres,Xres,Zres,Dir)
%Frames2: Es un volumen de datos 3D de tamaño [m, n, o] 
%Tres: Resolución temporal (espaciado entre los fotogramas)
%Xres: Resolución espacial en el eje X (lateral)
%Zres: Resolución espacial en el eje Z (profundidad)
%Dir: Dirección del filtrado ('left', 'right', 'depth')

[m,n,o] = size(Frames2);
Fs1 = 1/Xres; Fs2 = 1/Zres; Fs3 = 1/Tres;% frecuencias de muestreo Fs1, Fs2, y Fs3
Nm = 2^nextpow2(m)+1; Nn = 2^nextpow2(n)+1; No = 2^nextpow2(o)+1;

[k1,k2,k3] = meshgrid(linspace(-0.5,0.5,Nn),linspace(-0.5,0.5,Nm),linspace(-0.5,0.5,No)); %%k1: dim2, k2: dim1, k3: dim3.
k1 = k1*(2*pi*Fs2); % Along depth
k2 = k2*(2*pi*Fs1); % Along lateral
k3 = k3*(2*pi*Fs3);  % Along time

%La función fftn calcula la Transformada Rápida de Fourier en 3D del volumen Frames2, y fftshift ajusta el centro de la frecuencia a la posición de origen
FFT = fftshift(fftn(Frames2,[Nm Nn No]));
% 
% figure
% imagesc(k1(1,:),k2(:,1),abs(FFT))
% axis equal
% axis([-3000 3000 -30000 30000])

H = zeros(Nm,Nn,No);
if strcmp(Dir,'left')  %los componentes de frecuencia donde k3 y k2 están en la misma dirección
    H(k3>=0 & k2>=0) = 1;
    H(k3<0 & k2<0) = 1;
elseif strcmp(Dir,'right')  % los componentes de frecuencia en direcciones opuestas de k3 y k2
    H(k3>=0 & k2<0) = 1;
    H(k3<0 & k2>=0) = 1;
elseif strcmp(Dir,'depth')  %los componentes de frecuencia según k1 y k3 para resaltar cambios en la profundidad(time)
    H(k3>=0 & k1<0) = 1;
    H(k3<0 & k1>=0) = 1;    
end
% H(k1>32000 | k1<-32000) = 0;
% H(k2>32000 | k2<-32000) = 0;
% sigma = 2;
% H_Gauss = imgaussfilt(H,sigma);
H_Gauss = H;%mask de frecuencias

% figure
% imagesc(k1(1,:),k2(:,1),H_Gauss)
% axis equal
% axis([-8000 8000 -4000 4000])

%se multiplica la FFT del volumen por la máscara de frecuencia H_Gauss, se aplica la transformada inversa de Fourier y se ajusta el volumen resultante al tamaño original
STM_Filtered = real(ifftn(ifftshift(FFT.*H_Gauss)));
STM_Filtered = STM_Filtered(1:m,1:n,1:o);

end