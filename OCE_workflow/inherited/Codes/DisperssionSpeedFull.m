function [Speed_disp,freq_disp,FFT_time_disp] = DisperssionSpeedFull (SpaceTime,Xaxis,Time,ParamsDisp,DirFlag)
%Esta función se encarga de calcular la velocidad de dispersión a partir de los datos segun la direccion
figure;
himage= imagesc(SpaceTime');%Muestra los datos
colormap(fireice)
 %clim([-0.3 0.3])
clim([-0.05 0.05])
colorbar
h = imrect(gca,[100,100,100,100]);%Permite seleccionar un rectángulo en la imagen para definir la región de interés
PosTime = wait(h);
PosTime = round(PosTime);
title('Select time region to be calculated');
ST = SpaceTime';%se transpone los datos para que las dimensiones estén alineadas correctamente
ST = ST(PosTime(2):PosTime(2)+PosTime(4),PosTime(1):PosTime(1)+PosTime(3));%submatriz de SpaceTime definida por el rectángulo seleccionado
Xaxis_ST = Xaxis(PosTime(1):PosTime(1)+PosTime(3))-Xaxis(PosTime(1));
Time_ST = Time(PosTime(2):PosTime(2)+PosTime(4))-Time(PosTime(2));

ParamsDisp.ResT = Time_ST(2)*1e-3; % Resolution along time in seconds
ParamsDisp.ResX = Xaxis_ST(2)*1e-3; % Resolution along space in meters
% ParamsDisp.FFT_Nx = (2^13)+1; % Number of samples in FFT along space (must be odd number)
% ParamsDisp.FFT_Nt = (2^13)+1; % Number of samples in FFT along time (must be odd number)
% ParamsDisp.Cut_InvLambda = 1/(1e-3); % Inverse lambda cut value (e.g. 1 / 1mm);
%                                  % If not known, leave empty.
% ParamsDisp.Cut_Freq = 3000; % Inverse frequency cut value (e.g. 1000 Hz);
%                         % If not known, leave empty.
% ParamsDisp.Thres_Jump = 40;  % Jump treshold for multi-mode cases. Typically 40.
% ParamsDisp.Thres_Mag = 0.1;  % Intensity threshold in the k-w space (e.g. 20% is 0.2)

if strcmp(DirFlag,'left') 
    [Speed_disp,freq_disp,FFT_time_disp] = DispersionK (flip(ST,2),ParamsDisp);
elseif strcmp(DirFlag,'right') 
    [Speed_disp,freq_disp,FFT_time_disp] = DispersionK (ST,ParamsDisp);
end

FFT_time_disp = mean(FFT_time_disp,1)';

end