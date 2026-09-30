function [DeltaPhi] = Loupas2D_Fast(ALine_Spec,M)
% Aline_Spec = squeeze(Cplx_Matrix(ii,:,:))
% M = Options.LoupasAxialWin
% DeltaPhi =  raw_phases_Diff 
%tiene como objetivo calcular el cambio de fase en una imagen 2D (matriz de datos complejos) usando el método de Loupas

    F1=ALine_Spec;
    %IQ y IQ1 son segmentos consecutivos en la dimensión de las columnas
    IQ = F1(1:end,1:end-1);
    I = real(IQ); Q = imag(IQ);
    IQ1 = F1(1:end,2:end);
    I1 = real(IQ1); Q1 = imag(IQ1);
    
    %se calcula los componentes del numerador y denominador para la diferencia de fase a lo largo de la dimensión de las columnas de IQ e IQ1
    Num1 = (Q.*I1)-(I.*Q1);
    Den1 = (I.*I1)+(Q.*Q1);
    
    %se calcula el numerador y denominador para la diferencia de fase combinada, que incluye diferencias entre los pares consecutivos de IQ e IQ1
    Num2 = ((Q(1:end-1,:).*I(2:end,:))-(I(1:end-1,:).*Q(2:end,:))) +...
           ((Q1(1:end-1,:).*I1(2:end,:))-(I1(1:end-1,:).*Q1(2:end,:)));
    Den2 = ((I(1:end-1,:).*I(2:end,:))+(Q(1:end-1,:).*Q(2:end,:))) +...
           ((I1(1:end-1,:).*I1(2:end,:))+(Q1(1:end-1,:).*Q1(2:end,:)));    

    Win1 = ones(M,1);
    ConvNum1 = conv2(Win1,[1],Num1,'valid');
    ConvDen1 = conv2(Win1,[1],Den1,'valid');
    
    Win2 = ones(M-1,1);
    ConvNum2 = conv2(Win2,[1],Num2,'valid');
    ConvDen2 = conv2(Win2,[1],Den2,'valid');
    
    DeltaPhi = (atan2(ConvNum1,ConvDen1)./(1+(atan2(ConvNum2,ConvDen2)/(2*pi))));

     %figure
     %imagesc(DeltaPhi)

end