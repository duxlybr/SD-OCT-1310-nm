close all
clear all
clc

Ts = 1/(OCT_system.a_scan_rate*1000);
Line = squeeze(MotionSurface1(60,60,:));
FFT = fft(Line,2^12);
freq = linspace(0,1,2^12)/Ts;

figure
plot(Line)
figure
plot(freq,abs(FFT)) 

fig = figure;
plot(freq,abs(FFT))
grid on
ylabel('Magnitude (Arb.)');
xlabel('Frequency (Hz)');
title('FFT of the signal');
axis([0 2*3500 0 max(abs(FFT))*1.1])
h = imrect(gca,[1e3-200,-200,400,(max(abs(FFT))*1.1)+400]);
position = wait(h); 
b = fir1(50,[position(1)*2*Ts (position(1)+position(3))*2*Ts]);

figure
hold on
plot(Line)
plot(filter(b,1,Line))

Frames1 = MotionSurface1;

for j=1:size(MotionSurface1,1) 
    for i=1:size(MotionSurface1,2)
        signal=squeeze(MotionSurface1(j,i,:));
        if isnan(sum(signal))
            Frames1(j,i,:) = zeros(1,size(MotionSurface1,3));
        else
            Frames1(j,i,:)=filter(b,1,signal);
        end
    end
    j
end

aviobj = VideoWriter(['SiliconPhantom_ACUS_1MHz_Filt.avi']); 
aviobj.FrameRate = 20; 
open(aviobj); 

for i = 1:size(Frames1,3)
    
    Frames2(:,:,i) = medfilt2(Frames1(:,:,i),[3 1],'Symmetric');
    
    gcf = figure(1);
    imagesc(Xaxis, Yaxis,Frames2(:,:,i))
    caxis([-2 2])
    ylabel('y-axis (mm)');
    xlabel('x-axis (mm)');
    axis equal
    axis([0 Xaxis(end) 0 Yaxis(end)])
    title(['Motion frames - Filtered (Time = ',num2str(round((i-1)*Ts*1e3,2),'%10.2f\n'),' ms)'])   
    set(gca,'FontSize', 14);
    colormap(fireice);
    drawnow
    
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
    
end

close(aviobj);
fclose all;

%% Space time Map

time = [0:Ts:Ts*(size(Frames1,3)-1)]*1e3;
SpaceTimeMap_Y = squeeze(Frames2(50,:,:))';
SpaceTimeMap_X = squeeze(Frames2(:,50,:))';

tim1_idx = 185;
tim2_idx = 202;
tim3_idx = 219;

SpaceTimeProfile_Y_1 =  SpaceTimeMap_Y(tim1_idx,:);
SpaceTimeProfile_Y_2 =  SpaceTimeMap_Y(tim2_idx,:);
SpaceTimeProfile_Y_3 =  SpaceTimeMap_Y(tim3_idx,:);


SpaceTimeProfile_X_1 =  SpaceTimeMap_X(tim1_idx,:);
SpaceTimeProfile_X_2 =  SpaceTimeMap_X(tim2_idx,:);
SpaceTimeProfile_X_3 =  SpaceTimeMap_X(tim3_idx,:);


figure
imagesc(Xaxis,time,SpaceTimeMap_Y)
caxis([-1 1])
colormap(fireice);
ylabel('time (ms)');
xlabel('y-axis (mm)');

figure
imagesc(Xaxis,time,SpaceTimeMap_X)
caxis([-1 1])
colormap(fireice);
ylabel('time (ms)');
xlabel('x-axis (mm)');

figure
imagesc(SpaceTimeMap_Y)
caxis([-0.5 0.5])
colormap(fireice);
ylabel('time (ms)');
xlabel('y-axis (mm)');

figure
imagesc(SpaceTimeMap_X)
caxis([-0.5 0.5])
colormap(fireice);
ylabel('time (ms)');
xlabel('x-axis (mm)');

Num = 1;
[fitresult, gof] = GaussianFit(Xaxis, SpaceTimeProfile_X_1);
GaussParams(Num,:) = [fitresult.a1, fitresult.b1, fitresult.c1];
Gauss_fit_X_1 = GaussParams(Num,1)*exp(-((Xaxis-GaussParams(Num,2))/GaussParams(Num,3)).^2);

Num = 2;
[fitresult, gof] = GaussianFit(Xaxis, SpaceTimeProfile_X_2);
GaussParams(Num,:) = [fitresult.a1, fitresult.b1, fitresult.c1];
Gauss_fit_X_2 = GaussParams(Num,1)*exp(-((Xaxis-GaussParams(Num,2))/GaussParams(Num,3)).^2);

Num = 3;
[fitresult, gof] = GaussianFit(Xaxis, SpaceTimeProfile_X_3);
GaussParams(Num,:) = [fitresult.a1, fitresult.b1, fitresult.c1];
Gauss_fit_X_3 = GaussParams(Num,1)*exp(-((Xaxis-GaussParams(Num,2))/GaussParams(Num,3)).^2);

Num = 4;
[fitresult, gof] = GaussianFit(Xaxis, SpaceTimeProfile_Y_1);
GaussParams(Num,:) = [fitresult.a1, fitresult.b1, fitresult.c1];
Gauss_fit_Y_1 = GaussParams(Num,1)*exp(-((Xaxis-GaussParams(Num,2))/GaussParams(Num,3)).^2);

Num = 5;
[fitresult, gof] = GaussianFit(Xaxis, SpaceTimeProfile_Y_2);
GaussParams(Num,:) = [fitresult.a1, fitresult.b1, fitresult.c1];
Gauss_fit_Y_2 = GaussParams(Num,1)*exp(-((Xaxis-GaussParams(Num,2))/GaussParams(Num,3)).^2);

Num = 6;
[fitresult, gof] = GaussianFit(Xaxis, SpaceTimeProfile_Y_3);
GaussParams(Num,:) = [fitresult.a1, fitresult.b1, fitresult.c1];
Gauss_fit_Y_3 = GaussParams(Num,1)*exp(-((Xaxis-GaussParams(Num,2))/GaussParams(Num,3)).^2);

figure
hold on
plot(Xaxis,SpaceTimeProfile_X_1)
plot(Xaxis,Gauss_fit_X_1)
plot(Xaxis,SpaceTimeProfile_X_2)
plot(Xaxis,Gauss_fit_X_2)
plot(Xaxis,SpaceTimeProfile_X_3)
plot(Xaxis,Gauss_fit_X_3)
plot(Xaxis,SpaceTimeProfile_Y_1)
plot(Xaxis,Gauss_fit_Y_1)
plot(Xaxis,SpaceTimeProfile_Y_2)
plot(Xaxis,Gauss_fit_Y_2)
plot(Xaxis,SpaceTimeProfile_Y_3)
plot(Xaxis,Gauss_fit_Y_3)
ylabel('Particle velocity (Arb.)');
xlabel('x-axis (mm)');


figure
hold on
plot(GaussParams(1:3,3),GaussParams(4:6,3));
plot([0 1 2],[0 1 2]);
ylabel('\sigma (mm) along Y-axis');
xlabel('\sigma (mm) along x-axis');





