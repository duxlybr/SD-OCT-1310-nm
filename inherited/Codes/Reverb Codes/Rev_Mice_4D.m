close all
clear all
clc

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Experiment 1 - tone burst  {200} Hz
% Piezoelectric 200 hz (T3=2.5ms)
% T1=75ms  T2=150ms T4=75ms
% Ttrig=225ms, packets=3000, A-lines=300
% Tm-mode=0.05ms (Total time = 67.5s)
% Field of View (FOV) = 29mm
% Heterogenious Inclusion Phantom 10% and 11% of gel concentration (Milk 5%).
% Mechanical Meaurements: Young Modulus = ?
% Day of the experiment: 06/26/2015
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Reading data

path = 'Reverb_Mice_Hole_4D';

oldFolder = cd(path);
Dir=dir('*.csv');
n=size(Dir,1); % n := Lateral dimension
n1=sqrt(n);
n2=sqrt(n);

A = importdata(Dir(1).name);
[m,o]=size(A); % m := Axial dimension
               % o := Time dimension

filename=Dir(1).name;
k1 = strfind(filename,'Frame');
filename=filename(1:k1+4);
clear Dir

cd(oldFolder)

%% Axis definition

Xmax=7e-3; % Lateral FOV
Ymax=7e-3; % Lateral FOV
dx=2.5e-6;  % Depth sampling resolution

Xaxis=linspace(0,1,n1)*Xmax; % lateral axis
Yaxis=linspace(0,1,n2)*Ymax; % lateral axis

fft_n=2^12;
depth=fft_n/4;
Zaxis=[0:dx:dx*(depth-1)];  % depth axis

%% Displacement estimation using Doppler Phase.
%  LOUPAS Method

addpath(path);
% Loupas parameters
M=20;

for j=1:n1
for i=1:n2
    D{j,i}=zeros(depth-M+1,o-1);
end
end

%B_mode=zeros(depth,250);

parfor j=1:n1
for i=1:n2

file1=[filename,num2str(j),'_spect_A',num2str(i),'.csv'];
% file1=['Cornea400Hz_spect_A',num2str(i),'.csv'];
% file1=['Sclera1000Hz_spect_A',num2str(i),'.csv'];
% file1=['Sclera400Hz_spect_A',num2str(i),'.csv'];
A = importdata(file1);

F1=(fft(A(1:end,1:end-1),2^12));
F2=(fft(A(1:end,2:end),2^12));

F11=F1(1:depth,:);
F22=F2(1:depth,:);

B_mode{j}(:,i)=mean(abs(F11),2);
%B_mode(:,i)=abs(F11(:,50));
%D{i}=atan2(imag(conj(F11).*F22),real(conj(F11).*F22));
D{j,i}=Loupas_2D(F11,F22,dx,M);


end
j
end

I=B_mode{100};
I1=((I-min(I(:)))./(1e6)*255)+1;
B_mode_log=log10(I1)/log10(256);

figure
imagesc(Xaxis*1e3,Zaxis*1e3,B_mode_log)
colormap('gray')

Yaxis1=linspace(0,1,n2)*Ymax; % lateral axis
Bmask=zeros(n1,n2);

for j=1:n1
    
    I=B_mode{j};
    I1=((I-min(I(:)))./(1e6)*255)+1;
    B_mode_log=log10(I1)/log10(256);
    B_mode_log=medfilt2(B_mode_log,[5 3],'symmetric');
    
%     figure
%     imagesc(B_mode_log)
%     colormap('gray')

    for i=1:n2
        Profile=smooth(B_mode_log(20:end,i),0.005,'lowess');
        %plot(Profile)
        [pks, locs] = findpeaks(Profile,'NPeaks',4,'MinPeakHeight',0.17);     
        
        
        if isempty(locs)
            locs1=NaN;
        else
            locs1=locs(1);
        end
        
        Bmask(j,i)=locs1(1)+20-1;
    end
    j
end


Bmask1=medfilt2(Bmask,[5 5],'symmetric');
%Bmask1=medfilt2(Bmask1,[3 31],'symmetric');

pos=121
I=B_mode{pos};
I1=((I-min(I(:)))./(1e6)*255)+1;
B_mode_log=log10(I1)/log10(256);

figure
imagesc(B_mode_log)
colormap('gray')
hold on
plot(Bmask1(pos,:))


Zaxis1=[0:dx:dx*((depth-M+1)-1)]; 

figure
surface(Xaxis*1e3,Yaxis*1e3,Bmask1.*mask1);
shading flat

figure
imagesc(Xaxis*1e3,Yaxis*1e3,Bmask1);

Frames=zeros(n1,n2,o-1);

for j=1:n1    
    parfor i=1:n2
        if isnan(Bmask1(j,i))
            Frames(j,i,:)=repmat(NaN,1,o-1);
        else      
            Frames(j,i,:)=(D{j,i}(Bmask1(j,i)-M/2+30,:));
        end
    end
    j
end


%% Filtering in the time domain

Tf=0.05e-3; 
N_Alines=o-1;
time=[0:Tf:Tf*(N_Alines-1)];

FFT=fft((squeeze(Frames(100,100,:))),2^9);
freq=linspace(0,1,2^9)/0.05e-3;

figure
plot(freq,abs(FFT))
grid on
xlabel('Frequency (Hz)');
ylabel('Amplitude');
title('FFT of the signal');

b = fir1(80,[2450*2*Tf 2550*2*Tf]);
Amp_map=filter(b,1,squeeze(Frames(100,100,:)));
delay=mean(grpdelay(b,N_Alines,1/Tf));

figure
plot(time*1e3,squeeze(Frames(100,100,:)))
hold on
plot([time(1:end)-time(1+delay)]*1e3,Amp_map(1:end))
grid on
xlabel('Time (ms)');
ylabel('Displacement (Arb.)');


for j=1:n1  
    for i=1:n2
        signal=squeeze(Frames(j,i,:));
%         signal=unwrap(signal);
%         met=mean(signal);
%         
%         if met>pi
%             signal=signal-2*pi;
%         elseif met<-pi
%             signal=signal+2*pi;
%         end
%             
%         %Frames1(j,i,:)=signal;
        Frames1(j,i,:)=(filter(b,1,signal));
    end
    j
end

%% Filtering in space

FFT=fft((squeeze(Frames(:,170,40))),2^9);
freq=linspace(0,1,2^9)/Xaxis(2);

figure
plot(freq,abs(FFT))
grid on
xlabel('Frequency (Hz)');
ylabel('Amplitude');
title('FFT of the signal');


Frame_temp=Frames1(:,:,40);
figure
imagesc(Frame_temp)

FFT2 = abs((fftshift(fft2(ifftshift(Frame_temp)))));

figure
imagesc(log10(FFT2))


[k1,k2] = freqspace(size(Frame_temp),'meshgrid');
Hd = ones(size(Frame_temp)); 
r = sqrt(k1.^2 + k2.^2);
cs_max=1.7;
cs_min=0.7;
Fs=1/Xaxis(2);
f=2500;
kl = (2*pi/cs_max)*f*2/(2*pi*Fs); kh = (2*pi/cs_min)*f*2/(2*pi*Fs);
Hd((r<kl)|(r>kh)) = 0;

% figure
% mesh(Hd)

sigma=30;
win = fspecial('gaussian',size(Frame_temp),sigma);
win = win ./ max(win(:));

% figure
% mesh(win)

h = fwind2(Hd, win);

mask2 = abs((fftshift(fft2(ifftshift(h)))));
figure
imagesc(mask2)

Y = filter2(h,Frame_temp,'same');
figure;
imagesc(Y)

for j=1:N_Alines

    frame_temp=Frames1(:,:,j);
    frame_temp(isnan(frame_temp(:)))=0;
    Frames1(:,:,j)=filter2(h,frame_temp,'same');
    
   j
end


% 
% for j=1:n1  
%     for i=1:n2
%         env=abs(hilbert(Frames1(j,i,:)));
%         Fra=squeeze(Frames1(j,i,:))./squeeze(env);
%         Frames2(j,i,:)=medfilt2(Fra,[7 7],'symmetric');
%     end
%     j
% end


figure
plot(time*1e3,squeeze(env))
hold on
plot(time*1e3,squeeze(Frames1(j,i,:)))
plot(time*1e3,squeeze(Frames1(j,i,:))./squeeze(env))
grid on
xlabel('Time (ms)');
ylabel('Displacement (Arb.)');


figure
plot(time*1e3,squeeze(Frames1(50,1:200,:)))


%%% Make a video of the wave in x during the time
aviobj = VideoWriter('Mice_Reverb_4D_Filtered_norm.avi'); 
aviobj.FrameRate = 10; 
open(aviobj); 
for j=41:N_Alines

    gcf=figure(1);
    %imagesc(Xaxis*1e3,Xaxis*1e3,medfilt2(Frames1(:,:,j),[9 9]))
    imagesc(Xaxis*1e3,Xaxis*1e3,Frames1(:,:,j))
    
    ylabel('y axis (mm)');
    xlabel('x axis (mm)');
    %set(gcf, 'Position', [50 50 900 300])
    colormap(redblue)
    
    
    caxis([-pi/16 pi/16])
    %caxis([-1 1])
    axis equal
    axis([0 7 0 7])
    drawnow
    %pause
    j
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
end

close(aviobj);
fclose all;


 
%% Surface extraction


Surface=zeros(n1,n2);
Bmode_Surf=zeros(n1,n2);
%Bmode_Surf1=zeros(n1,n2);

for j=1:n1   
    
    I=B_mode{j};
    I1=((I-min(I(:)))./(1e6)*255)+1;
    B_mode_log=log10(I1)/log10(256);
    B_mode_log=medfilt2(B_mode_log,[5 3],'symmetric');
    
    for i=1:n2   
        locs=Bmask1(j,i);
        
        if isnan(locs)
            Bmode_Surf(j,i)=NaN;
            Surface(j,i)=NaN;
        else
            Bmode_Surf(j,i)=B_mode_log(locs+15,i);
            Surface(j,i)=(locs)*dx;
        end
        
        
%         [pks, locs] = findpeaks(Profile,'SortStr','descend');
%         Bmode_Surf(j,i)=B_mode_log(locs(1)+50-1,i);
%         Bmode_Surf1(j,i)=pks(1);
%         Surface(j,i)=(locs(1)+50-1)*dx;
    end
    j
end

Surface1=medfilt2(Surface,[21 21],'symmetric');

figure
surface(Xaxis*1e3,Yaxis*1e3,-Surface1*1e3)
colormap('gray') 
shading flat


figure
imagesc(Xaxis*1e3,Yaxis*1e3,Bmode_Surf)
colormap('gray')


figure
surface(Xaxis*1e3,Yaxis*1e3,Surface1*1e3,Bmode_Surf,'FaceLighting','phong')
colormap('gray')
view(150,50)
shading flat
set(gca,'zdir','reverse')
ylabel('y axis (mm)');
xlabel('x axis (mm)');
zlabel('z axis (mm)');
axis equal
%camlight headlight

%% MAsk generation


h_im = imagesc(Bmask1);
colormap(redblue)
h = impoly;
position = wait(h); 
mask1=createMask(h,h_im);
mask1=double(mask1);

figure
imagesc(mask1)


%% Motion with surface

%%% Make a video of the wave in x during the time
aviobj = VideoWriter('Mice_Reverb_3DSurface.avi'); 
aviobj.FrameRate = 10; 
open(aviobj); 


for j=21:N_Alines
    gcf=figure(1);
    
    wave=Frames1(:,:,j).*mask1;
    %wave=medfilt2(cat(1,Frames1(1:115,:,j),flip(Frames1(15:99,:,j),1)),[9 9]);
    iii=surface(Xaxis*1e3,Yaxis*1e3,(Surface1*1e3)+wave*1.0,wave,'FaceLighting','phong');
    set(iii,'Visible','on');
    caxis([-pi/16 pi/16])
    %caxis([-1 1])
    shading flat
    grid on

    colormap(jet)
    set(gca,'zdir','reverse')
    ylabel('y axis (mm)');
    xlabel('x axis (mm)');
    zlabel('z axis (mm)');
    
    
    view(150,50)
    axis equal
    %view(-90,0)
    axis([0 7 0 7 -1 2])
    if j==21
    camlight headlight
    end
    drawnow
    

    %pause
    
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);

    if j~=N_Alines
        set(iii,'Visible','off');
    end
    
    j
end

close(aviobj);
fclose all;

%% Volume motion

[XII,YII,ZII]=meshgrid(Xaxis,Yaxis,Zaxis(1:end));

for j=1:n1
    I=B_mode{j};
    I1=((I-min(I(:)))./(1e6)*255)+1;
    B_mode_log=log10(I1)/log10(256);
    C(:,j,:)=transpose(B_mode_log);
end

C=permute(C,[2 1 3]);

aviobj = VideoWriter('Bmode_Dynamic.avi'); 
aviobj.FrameRate = 10; 
open(aviobj); 

for i=1:n1
    
    gcf=figure;
    hsurfaces = slice(XII*1e3,YII*1e3,ZII*1e3,C,Xaxis(i)*1e3,Yaxis(n1-i+1)*1e3,1.8);
    set(hsurfaces,'FaceColor','interp','EdgeColor','none')
    set(gca,'zdir','reverse')
    %set(hsurfaces,'Clipping','on');
    %axis equal
    axis([0 7 0 7 0 2.5])
    view(-133,58)
    caxis([0  1]) 
    ylabel('y axis (mm)');
    xlabel('x axis (mm)');
    zlabel('z axis (mm)');
    colormap(gray)
    drawnow

   pause(0.5)

%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
    close all
    
    %set(hsurfaces,'Visible','off');
end

close(aviobj);
fclose all;



%% Space time map (as is)

for j=1:N_Alines
    Frames3(:,:,j)=medfilt2(Frames1(:,:,j),[7 7]);
    j
end

figure
imagesc(Xaxis*1e3,time*1e3,squeeze(Frames3(120,:,:))',[-pi/32 pi/32])
colorbar
colormap(redblue)
xlabel('Lateral axis (mm)')
ylabel('Time (ms)')

and_max=atan((Xaxis(end)/2)/(1.172*1e-3 ))*180/pi;

ang=linspace(-and_max,and_max,200);

for i=1:200
    
hsp = surf(time,Yaxis,zeros(length(Yaxis),length(time))-Xaxis(end)/2);
rotate(hsp,[0,1,0],-90,[0 Xaxis(end)/2 0])

rotate(hsp,[0,0,1],ang(i),[Xaxis(end)/2 Yaxis(end)+1.172*1e-3 1])
axis([0 0.015 0 0.015 0 0.0075])
view(0,90)

xd = hsp.XData;
yd = hsp.YData;
zd = hsp.ZData;

[temp]=slice(Xaxis,Yaxis,time,Frames3,xd,yd,zd,'cubic');

x_prof=temp.XData(:,1)';
y_prof=temp.YData(:,1)';
radio_prof{i}=sqrt((x_prof-Xaxis(end)/2).^2+(y_prof).^2);

%time_prof=temp.ZData(1,:);
stm_prof{i}=temp.CData';

idx=find(isnan(stm_prof{i}(1,:)));
stm_prof{i}(:,idx)=[];
radio_prof{i}(:,idx)=[];

end

figure
imagesc(radio_prof{175}*1e3,time*1e3,stm_prof{175})
colorbar
colormap(redblue)
caxis([-pi/32 pi/32])
xlabel('Lateral axis (mm)')
ylabel('Time (ms)')

figure
plot(time*1e3,stm_prof{100}(:,50))
hold on
plot(time*1e3,stm_prof{100}(:,100))
plot(time*1e3,stm_prof{100}(:,140))

cont=1;
[nn1]=length(radio_prof{100});

N=8;
for i=1:nn1-N
    dt = normxcorr2(resample(stm_prof{100}(:,i),4,1),resample(stm_prof{100}(:,i+N),4,1));
    [val,idx]=max(dt);
    delay(cont)=abs(idx-4*149)*0.05/4;
    DX(cont)=abs(radio_prof{100}(i)-radio_prof{100}(i+N))*1000;
    cont=cont+1;
end

figure
plot(smooth(DX./delay,0.1,'lowess'))
figure
plot(smooth(DX,0.1,'lowess'))
figure
plot(smooth(delay,0.1,'lowess'))

clear DX
clear cs
clear delay

freq=1000;
[Cs_xy,Cs_x,Cs_y]=Hoyt2D_Estimator(Frames2(:,:,40:N_Alines),40,Xaxis(2),freq);
[Cs_xy,Cs_x,Cs_y]=Kasai_new(Frames2(:,:,50:N_Alines),20,Xaxis(2),freq);

figure
imagesc(Cs_y)
colorbar
colormap(jet)
caxis([0 3])

%%

%% Volume motion

[XII,YII,ZII]=meshgrid(Xaxis,Yaxis,Zaxis(1:end));

for j=1:n1
    I=B_mode{j};
    I1=((I-min(I(:)))./(1e6)*255)+1;
    B_mode_log=log10(I1)/log10(256);
    C(:,j,:)=transpose(B_mode_log);
    j
end

C=permute(C,[2 1 3]);

aviobj = VideoWriter('Bmode_Dynamic.avi'); 
aviobj.FrameRate = 10; 
open(aviobj); 
gcf=figure;
for i=1:n1
    
    %h=figure(1);
    hsurfaces = slice(XII*1e3,YII*1e3,ZII*1e3,C,Xaxis(i)*1e3,Yaxis(n1-i+1)*1e3,1);
    set(hsurfaces,'FaceColor','interp','EdgeColor','none')
    set(gca,'zdir','reverse')
    %axis equal
    view(-133,56)
    ylabel('y axis (mm)');
    xlabel('x axis (mm)');
    zlabel('z axis (mm)');
    colormap(gray)
    drawnow
    
    F=getframe(gcf); 
    writeVideo(aviobj,F);

end

close(aviobj);
fclose all;

aviobj = VideoWriter('EnFace_PorcineEye.avi'); 
aviobj.FrameRate = 30; 
open(aviobj); 

for i=80:1024
    
    gcf=figure(1);
    hsurfaces = imagesc(Xaxis*1e3,Yaxis*1e3,imadjust(squeeze(C(:,:,i))));
    axis equal
    axis([0 10 0 10])
    caxis([0  1]) 
    title(['En-face profile at depth ',num2str(round(Zaxis(i)*1e5)/100),' mm'])
    ylabel('y axis (mm)');
    xlabel('x axis (mm)');
    colormap(gray)
    drawnow
i
    F=getframe(gcf); 
    writeVideo(aviobj,F);
    
end

close(aviobj);
fclose all;


%% Video in Profile X

Frames_x=zeros(depth-M+1,n2,o-1);

    j=100;
    for i=1:n2
        Frames_x(:,i,:)=D{j,i}(:,:);
    end

for j=1:depth-M+1  
    for i=1:n2
        signal=squeeze(Frames_x(j,i,:));
        Frames_x1(j,i,:)=filter(b,1,signal);
    end
    j
end
    
 %%% Make a video of the wave in x during the time
aviobj = VideoWriter('HumanCornea_Video_ProfileX_2.avi'); 
aviobj.FrameRate = 8; 
open(aviobj); 
for j=1:N_Alines

    gcf=figure(1);
    %imagesc(Xaxis*1e3,Yaxis*1e3,medfilt2(Frames1(:,:,j),[7 7]))
    imagesc(Xaxis*1e3,Zaxis*1e3,Frames_x1(:,:,j))
    
    ylabel('y axis (mm)');
    xlabel('x axis (mm)');
    %set(gcf, 'Position', [50 50 900 300])
    colormap(redblue)
    caxis([-pi/4 pi/4])
    axis equal
    axis([0 7 0 2.5])
    drawnow
    %pause(0.1)
    
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
end

close(aviobj);
fclose all;
   
    

%% Video in Profile Y

Frames_y=zeros(depth-M+1,n1,o-1);

    i=170;
    for j=1:n2
        Frames_y(:,j,:)=D{j,i}(:,:);
    end

for j=1:depth-M+1  
    for i=1:n1
        signal=squeeze(Frames_y(j,i,:));
        Frames_y1(j,i,:)=filter(b,1,signal);
    end
    j
end
    
 %%% Make a video of the wave in x during the time
aviobj = VideoWriter('HumanCornea_Video_ProfileY.avi'); 
aviobj.FrameRate = 8; 
open(aviobj); 
for j=1:N_Alines

    gcf=figure(1);
    %imagesc(Xaxis*1e3,Yaxis*1e3,medfilt2(Frames1(:,:,j),[7 7]))
    imagesc(Xaxis*1e3,Zaxis*1e3,Frames_y1(:,:,j))
    
    ylabel('y axis (mm)');
    xlabel('x axis (mm)');
    %set(gcf, 'Position', [50 50 900 300])
    colormap(redblue)
    caxis([-pi/16 pi/16])
    axis equal
    axis([0 7 0 2.5])
    drawnow
    %pause(0.1)
    
%     F=getframe(gcf); 
%     writeVideo(aviobj,F);
end

close(aviobj);
fclose all;



