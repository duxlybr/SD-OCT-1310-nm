close all
clear all
clc

Xaxis = linspace(0,OCT_system.x_scan_width,size(loaded_phases,1));
Zaxis = [0:1:size(loaded_phases,2)-1]'*OCT_system.axial_pixel_res*1e-3;

Ts = 1/(OCT_system.a_scan_rate*1000);
Line = squeeze(loaded_phases(125,200,:));
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

Frames1 = loaded_phases;

for j=1:size(loaded_phases,1) 

    signal=squeeze(loaded_phases(j,:,:));
    if isnan(sum(signal(:)))
        Frames1(j,:,:) = zeros(size(signal));
    else
        Frames1(j,:,:)=filter(b,1,signal')';
    end

    j
end

for i = 1:size(Frames1,3)
    
    %Frames2(:,:,i) = medfilt2(Frames1(:,:,i),[3 1],'Symmetric');
    
    gcf = figure(1);
    imagesc(Xaxis, Zaxis,Frames1(:,:,i)')
    caxis([-0.02 0.02])
    ylabel('y-axis (mm)');
    xlabel('x-axis (mm)');
    %axis equal
    axis([0 Xaxis(end) 0 Zaxis(end)])
    title(['Motion frames - Filtered (Time = ',num2str(round((i-1)*Ts*1e3,2),'%10.2f\n'),' ms)'])   
    set(gca,'FontSize', 14);
    colormap(fireice);
    drawnow
    
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
    
end











