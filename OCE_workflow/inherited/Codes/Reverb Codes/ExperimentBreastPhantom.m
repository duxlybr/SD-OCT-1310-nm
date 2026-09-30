close all
clear all
clc

%% Acquisition

% res_x=fer.dinf.dx;
% res_y=fer.dinf.dz;
% dt=1/9600;

res_x=Xaxis(2);
res_y=Xaxis(2);

Volume=Frames2{2};
%Volume=u_new;
[m,n,o]=size(Volume);

x_vec=0:res_x:res_x*(n-1);
y_vec=0:res_y:res_y*(m-1);

%% Video visualization
figure(2)
for i=1:o
    imagesc(Volume(:,:,i))
    caxis([-1 1]*1e-1)
    colorbar
    drawnow
end

%% Analyse FFT of an arbitrary position

i=100;
k=100;
FFT=squeeze(fft(((Volume(i,k,:))),2^11));

figure
plot(abs(FFT))

%% Filtering using FFT in the 3D block

freq_sample=256;
clear j
for i=1:m
    for k=1:n
        FFT=fft(((Volume(i,k,:))),2^11);
        %Frames(i,k)=abs(FFT(freq_sample))*exp(j*angle(FFT(freq_sample)));
        Frames(i,k)=exp(j*angle(FFT(freq_sample)));
        i
    end
end



figure
imagesc(x_vec*1e2,y_vec*1e2,abs(Frames))
xlabel('Lateral position (cm)');
ylabel('Depth (cm)');
%caxis([0 2]*1e-5)
caxis([0 3])
axis equal
axis([x_vec(1)*1e2 x_vec(end)*1e2 y_vec(1)*1e2 y_vec(end)*1e2])

figure
imagesc(x_vec*1e2,y_vec*1e2,angle(Frames))
xlabel('Lateral position (cm)');
ylabel('Depth (cm)');
axis equal
axis([x_vec(1)*1e2 x_vec(end)*1e2 y_vec(1)*1e2 y_vec(end)*1e2])


figure
imagesc(x_vec*1e2,y_vec*1e2,real(Frames))
xlabel('Lateral position (cm)');
ylabel('Depth (cm)');
%caxis([-8 8]*1e-5)
caxis([-3 3])
axis equal
axis([x_vec(1)*1e2 x_vec(end)*1e2 y_vec(1)*1e2 y_vec(end)*1e2])

figure
imagesc(x_vec*1e2,y_vec*1e2,imag(Frames))
xlabel('Lateral position (cm)');
ylabel('Depth (cm)');
%caxis([-8 8]*1e-6)
caxis([-3 3])
axis equal
axis([x_vec(1)*1e2 x_vec(end)*1e2 y_vec(1)*1e2 y_vec(end)*1e2])

figure
imagesc(x_vec*1e2,y_vec*1e2,Bmode(72:384,:))
xlabel('Lateral position (cm)');
ylabel('Depth (cm)');
caxis([-60 0])
colormap(gray)
axis equal
axis([x_vec(1)*1e2 x_vec(end)*1e2 y_vec(1)*1e2 y_vec(end)*1e2])
   

%% Saving images of Kasai Real 400 Hz, different tau and win 3D


name=[2500];
ini=[5 10 15 20]; %tau samples

k=1;
for i=1:4
  
    cont=1;
    
    for win=[30 50 70 90] % window size
 
    freq=name(k);
    [InvLambda]=Kasai3(Frames,[win win],res_x,res_y,ini(i));
    
    C1{i,cont}=2*pi*freq./InvLambda{1};
    C2{i,cont}=2*pi*freq./InvLambda{2};
    C3{i,cont}=2*pi*freq./InvLambda{3};
    C4{i,cont}=2*pi*freq./InvLambda{4};
    

    figure
    imagesc(x_vec(win/2:end-win/2)*1e2,y_vec(win/2:end-win/2)*1e2,real(C1{i,cont}))
    colormap(jet)
    caxis([0 4])
    colorbar
    axis equal
    %set(gca,'YDir','normal')
    axis([x_vec(win/2)*1e2 x_vec(end-win/2)*1e2 y_vec(win/2)*1e2 y_vec(end-win/2)*1e2])
    xlabel('Lateral position (cm)');
    ylabel('Depth (cm)');
    saveas(gcf,['Reverb_Mice_Kasai_Real_freq_',num2str(name(k)),'Hz_win_',num2str(win),'_Tau_',num2str(ini(i)),'_x','.tiff'])
    
%     Mean1(i,cont)=mean(C1(:));
%     Std1(i,cont)=std(C1(:));
    
    figure
    imagesc(x_vec(win/2:end-win/2)*1e2,y_vec(win/2:end-win/2)*1e2,real(C2{i,cont}))
    colormap(jet)
    caxis([0 4])
    colorbar
    axis equal
    %set(gca,'YDir','normal')
    axis([x_vec(win/2)*1e2 x_vec(end-win/2)*1e2 y_vec(win/2)*1e2 y_vec(end-win/2)*1e2])
    xlabel('Lateral position (cm)');
    ylabel('Depth (cm)');
    saveas(gcf,['Experiment_Equal3_Kasai_Real_freq_',num2str(name(k)),'Hz_win_',num2str(win),'_Tau_',num2str(ini(i)),'_y','.tiff'])
    
%     Mean2(i,cont)=mean(C2(:));
%     Std2(i,cont)=std(C2(:));
    
    figure
    imagesc(x_vec(win/2:end-win/2)*1e2,y_vec(win/2:end-win/2)*1e2,real(C3{i,cont}))
    colormap(jet)
    caxis([0 4])
    colorbar
    axis equal
    %set(gca,'YDir','normal')
    axis([x_vec(win/2)*1e2 x_vec(end-win/2)*1e2 y_vec(win/2)*1e2 y_vec(end-win/2)*1e2])
    xlabel('Lateral position (cm)');
    ylabel('Depth (cm)');
    saveas(gcf,['Experiment_Equal3_Kasai_Real_freq_',num2str(name(k)),'Hz_win_',num2str(win),'_Tau_',num2str(ini(i)),'_ave','.tiff'])
    
%     Mean3(i,cont)=mean(C3(:));
%     Std3(i,cont)=std(C3(:));

    figure
    imagesc(x_vec(win/2:end-win/2)*1e2,y_vec(win/2:end-win/2)*1e2,real(C4{i,cont}))
    colormap(jet)
    caxis([0 4])
    colorbar
    axis equal
    %set(gca,'YDir','normal')
    axis([x_vec(win/2)*1e2 x_vec(end-win/2)*1e2 y_vec(win/2)*1e2 y_vec(end-win/2)*1e2])
    xlabel('Lateral position (cm)');
    ylabel('Depth (cm)');
    saveas(gcf,['Experiment_Equal3_Kasai_Real_freq_',num2str(name(k)),'Hz_win_',num2str(win),'_Tau_',num2str(ini(i)),'_sqrt','.tiff'])
    
%     Mean3(i,cont)=mean(C3(:));
%     Std3(i,cont)=std(C3(:));
    
    cont=cont+1;
    
    end
    close all
    i
end


%% Saving images of Zero Crossin Approach  400 Hz, different  win


name=[400];
ini=[10];

k=1;
i=1
    
for win=[30 50 70 90]
 
    freq=name(k);
    [InvLambda]=Kasai2(Frames,[win win],res_x,res_y,ini(i));
    
    C1{cont}=2*pi*freq./InvLambda{1};
    C2{cont}=2*pi*freq./InvLambda{2};
    C3{cont}=2*pi*freq./InvLambda{3};
    C4{cont}=2*pi*freq./InvLambda{4};
    
    figure
    imagesc(x_vec(win/2:end-win/2)*1e2,y_vec(win/2:end-win/2)*1e2,real(C1{i,cont}))
    colormap(jet)
    caxis([0 4])
    colorbar
    axis equal
    %set(gca,'YDir','normal')
    axis([x_vec(win/2)*1e2 x_vec(end-win/2)*1e2 y_vec(win/2)*1e2 y_vec(end-win/2)*1e2])
    xlabel('Lateral position (cm)');
    ylabel('Depth (cm)');
    saveas(gcf,['ExperimentSum_Zero_Crossing_freq_',num2str(name(k)),'Hz_win_',num2str(win),'_x','.tiff'])
    
%     Mean1(i,cont)=mean(C1(:));
%     Std1(i,cont)=std(C1(:));
    
    figure
    imagesc(x_vec(win/2:end-win/2)*1e2,y_vec(win/2:end-win/2)*1e2,real(C2{i,cont}))
    colormap(jet)
    caxis([0 4])
    colorbar
    axis equal
    %set(gca,'YDir','normal')
    axis([x_vec(win/2)*1e2 x_vec(end-win/2)*1e2 y_vec(win/2)*1e2 y_vec(end-win/2)*1e2])
    xlabel('Lateral position (cm)');
    ylabel('Depth (cm)');
    saveas(gcf,['ExperimentSum_Zero_Crossing_freq_',num2str(name(k)),'Hz_win_',num2str(win),'_y','.tiff'])
    
%     Mean2(i,cont)=mean(C2(:));
%     Std2(i,cont)=std(C2(:));
    
    figure
    imagesc(x_vec(win/2:end-win/2)*1e2,y_vec(win/2:end-win/2)*1e2,real(C3{i,cont}))
    colormap(jet)
    caxis([0 4])
    colorbar
    axis equal
    %set(gca,'YDir','normal')
    axis([x_vec(win/2)*1e2 x_vec(end-win/2)*1e2 y_vec(win/2)*1e2 y_vec(end-win/2)*1e2])
    xlabel('Lateral position (cm)');
    ylabel('Depth (cm)');
    saveas(gcf,['ExperimentSum_Zero_Crossing_freq_',num2str(name(k)),'Hz_win_',num2str(win),'_ave','.tiff'])
    
%     Mean3(i,cont)=mean(C3(:));
%     Std3(i,cont)=std(C3(:));

    figure
    imagesc(x_vec(win/2:end-win/2)*1e2,y_vec(win/2:end-win/2)*1e2,real(C4{i,cont}))
    colormap(jet)
    caxis([0 4])
    colorbar
    axis equal
    %set(gca,'YDir','normal')
    axis([x_vec(win/2)*1e2 x_vec(end-win/2)*1e2 y_vec(win/2)*1e2 y_vec(end-win/2)*1e2])
    xlabel('Lateral position (cm)');
    ylabel('Depth (cm)');
    saveas(gcf,['ExperimentSum_Zero_Crossing_freq_',num2str(name(k)),'Hz_win_',num2str(win),'_sqrt','.tiff'])
    
%     Mean3(i,cont)=mean(C3(:));
%     Std3(i,cont)=std(C3(:));
    
    cont=cont+1;
    
end

