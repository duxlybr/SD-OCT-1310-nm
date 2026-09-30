function [Speed,Error] = SpeedAnalysis(Spacetime,Xaxis,Time1,FigureName,CLim)
%se realiza un análisis de velocidad en un mapa espacio-temporal

%Spacetime: es una matriz que representa el mapa espacio-temporal
%Xaxis: vector de coordenadas del eje x (espacial)
%Time1: vector de tiempos correspondientes al eje y
%FigureName: nombre de archivo para guardar las figuras generadas
%CLim: límite de color

figure;
himage= imagesc(Xaxis,Time1,Spacetime);
colormap(fireice)
clim([-CLim CLim])
colorbar
ylabel('time (ms)');
xlabel('x-axis (mm)');
title('Space-Time Map');
set(gca,'FontSize', 14);
% h = imrect(gca,[100,100,...
%                 100,300]);
h = impoly(gca);
wait(h); %PosTime = wait(h);
title('Select time region to be calculated');
BW = createMask(h,himage);

Line_t = sum(BW,2);
idx_t1 = find(Line_t==0);
Jump = find(diff(idx_t1)>2);
t_ini = idx_t1(Jump(1));
t_end = idx_t1(Jump(1)+1);

Spacetime_Mask = Spacetime.*BW;
count = 1;

for i = 1: size(Spacetime_Mask,2)
    [val,idx] = min(Spacetime_Mask(:,i));
    if val~=0 && (isnan(val)==0) & (isempty(idx)==0) %val~=0 & (isnan(val)==0) & (isempty(idx)==0)
        Xdata(count) = Xaxis(i);
        Tdata(count) = Time1(idx);
        count = count +1;
    end
end

[fitresult, ~] = LinealFit(Xdata, Tdata);
%[fitresult, gof] = LinealFit(Xdata, Tdata);
ci = confint(fitresult);
        
Speed =  abs(1/fitresult.p1); %velocidad 
Error =  abs((1/ci(1,1))-(1/ci(2,1)));%error en la velocidad

gcf = figure;
imagesc(Xaxis,Time1,Spacetime);
colormap(fireice)
hold on
plot(Xdata,(fitresult.p1*Xdata+fitresult.p2),'LineWidth',2,'Color','green');
clim([-CLim CLim])
axis([ Xaxis(1) Xaxis(end) Time1(t_ini) Time1(t_end) ])
colorbar
ylabel('time (ms)');
xlabel('x-axis (mm)');
title(['Speed = ',num2str(round(Speed,2)),' +- ',num2str(round(Error,2)),' m/s']);
set(gca,'FontSize', 14);
saveas(gcf,[FigureName,'.fig']);
saveas(gcf,[FigureName,'.tif']);

end