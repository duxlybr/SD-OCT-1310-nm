function [Speed, K] = PhaseDerivativeSpeed (ROI,Xaxis,Zaxis,Params)
%la función estima las velocidades en las direcciones X y Z mediante el análisis de la fase de la transformada rápida de Fourier
Threshold = Params.Threshold;
FFT_Nx = Params.FFT_Nx;
FFT_FreqSample = Params.FFT_FreqSample;%frecuencia en la FFT utilizada para el análisis
Freq = Params.Freq;

% Threshold = [15 15]; % 15% along X, and Z.
% FFT_Nx = 2^10;
% FFT_FreqSample = 35;
% Freq = 1000; %in Hz

[Z,X] = meshgrid(Zaxis,Xaxis); %Zaxis and Xaxis are in mm.
FFT_matrix = fft(ROI,FFT_Nx,3);

Phase = angle(FFT_matrix(:,:,FFT_FreqSample));%obtengo la fase de la fft
UnwrapPhase = unwrap(Phase,[],1);
UnwrapPhase = unwrap(UnwrapPhase,[],2);

xfit = reshape(X,[],1);
yfit = reshape(Z,[],1);
zfit = reshape(UnwrapPhase,[],1);

[fitresult, ~] = Poly2DFitting(xfit, yfit, zfit);
%[fitresult, gof] = Poly2DFitting(xfit, yfit, zfit);

ConfidentRange = confint(fitresult);
ConFi_x = ConfidentRange(2,2)-ConfidentRange(1,2);
ConFi_z = ConfidentRange(2,3)-ConfidentRange(1,3);
ConFi_x_PerVar = ConFi_x/fitresult.p10*100;
ConFi_z_PerVar = ConFi_z/fitresult.p01*100;

%pendientes obtenidas del ajuste polinómico
K_x = fitresult.p10*1e3;
K_z = fitresult.p01*1e3;

if (ConFi_x_PerVar > Threshold(1)) || isinf(K_x)%(ConFi_x_PerVar > Threshold(1)) | isinf(K_x)
    K_x = 0;
elseif (ConFi_z_PerVar > Threshold(2)) || isinf(K_z)%(ConFi_z_PerVar > Threshold(2)) | isinf(K_z)
    K_z = 0;
end

K_equival = sqrt(K_x.^2 + K_z.^2);%magnitud equivalente

K.X = K_x;
K.Z = K_z;
K.Equiv = K_equival;

%Velocidades
Speed.X = 2*pi*Freq./K_x;
Speed.Z = 2*pi*Freq./K_z;
Speed.Equiv = 2*pi*Freq./K_equival;


end