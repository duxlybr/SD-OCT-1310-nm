function [Speed1D] = PhaseDeriv_1D (UnwrapPhaseSmooth2,Xaxis,WinSize,Freq)

Res_X = Xaxis(2);
WinSize_n = (WinSize./[Res_X]);
WinSize_n(1) = round2even(WinSize_n(1)); %Along X

Xaxis_win = Xaxis(1:WinSize_n(1));

[M,o] = size(UnwrapPhaseSmooth2);
GRIdd_X = [WinSize_n(1)/2:WinSize_n(1)/2:M-WinSize_n(1)/2];

GRIdd_X_size = length(GRIdd_X);
c_tmp = zeros(1,GRIdd_X_size);

for ii = 1:GRIdd_X_size

        X_i = GRIdd_X(ii) - (WinSize_n(1)/2)+1;
        X_f = GRIdd_X(ii) + (WinSize_n(1)/2);

        Yfit = UnwrapPhaseSmooth2(X_i:X_f);
        Xfit = Xaxis(X_i:X_f);
        
        [fitresult, gof] = LinealFit(Xfit, Yfit);


        c_tmp(ii) = 2*pi*Freq./(fitresult.p1*1e3);
 
end

Xaxis_E = Xaxis(GRIdd_X);
Speed1D = abs(interp1(Xaxis_E,c_tmp,Xaxis,'nearest'));

end