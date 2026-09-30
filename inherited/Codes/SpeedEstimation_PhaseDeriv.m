function [Speed, Xaxis_E, Zaxis_E] = SpeedEstimation_PhaseDeriv(Frames2,Xaxis,Zaxis,Params)
%se calcula la velocidad de ondas en un conjunto de imágenes utilizando derivadas de fase

%resolucion
Res_X = Xaxis(2);
Res_Z = Zaxis(2);
% WinSize = [2 0.2]; 
WinSize = Params.WinSize;
WinSize_n = (WinSize./[Res_X Res_Z]);
WinSize_n(1) = round2even(WinSize_n(1)); %Along X
WinSize_n(2) = round2even(WinSize_n(2)); %Along Z

Xaxis_win = Xaxis(1:WinSize_n(1));
Zaxis_win = Zaxis(1:WinSize_n(2));

[M,N,~] = size(Frames2); %dimensiones del conjunto de imágenes
%[M,N,o] = size(Frames2); %dimensiones del conjunto de imágenes
GRIdd_X = (WinSize_n(1)/2):round(WinSize_n(1)/4):(M-WinSize_n(1)/2);
GRIdd_Z = (WinSize_n(2)/2):round(WinSize_n(2)/4):(N-WinSize_n(2)/2);
%GRIdd_X = [(WinSize_n(1)/2):round(WinSize_n(1)/4):(M-WinSize_n(1)/2)];
%GRIdd_Z = [(WinSize_n(2)/2):round(WinSize_n(2)/4):(N-WinSize_n(2)/2)];

GRIdd_X_size = length(GRIdd_X);
GRIdd_Z_size = length(GRIdd_Z);

c_tmp = zeros(GRIdd_Z_size,GRIdd_X_size);
%matrices para almacenar las velocidades calculadas y la velocidad equivalente
Speed.X = c_tmp;
Speed.Z = c_tmp;
Speed.Equiv = c_tmp;

for jj = 1:GRIdd_Z_size
    
    Z_i = GRIdd_Z(jj) - (WinSize_n(2)/2)+1;
    Z_f = GRIdd_Z(jj) + (WinSize_n(2)/2);
    
    for ii = 1:GRIdd_X_size

        X_i = GRIdd_X(ii) - (WinSize_n(1)/2)+1;
        X_f = GRIdd_X(ii) + (WinSize_n(1)/2);

        ROI_win = Frames2(X_i:X_f, Z_i:Z_f, :);

%         Params.Threshold = [15 15];
%         Params.FFT_Nx = 2^10;
%         Params.FFT_FreqSample = 35;
%         Params.Freq = 1000;

        [Speed_PhD, ~] = PhaseDerivativeSpeed (ROI_win,Xaxis_win,Zaxis_win,Params);        
%[Speed_PhD, K] = PhaseDerivativeSpeed (ROI_win,Xaxis_win,Zaxis_win,Params);
        Speed_vec_X(1,ii) = Speed_PhD.X;
        Speed_vec_Z(1,ii) = Speed_PhD.Z;
        Speed_vec_Equiv(1,ii) = Speed_PhD.Equiv;
 
    end
    
    Speed.X(jj,:) = Speed_vec_X;
    Speed.Z(jj,:) = Speed_vec_Z;
    Speed.Equiv(jj,:) = Speed_vec_Equiv;
    %jj                                        %modifique
end

Xaxis_E = Xaxis(round(GRIdd_X));
Zaxis_E = Zaxis(round(GRIdd_Z));

end