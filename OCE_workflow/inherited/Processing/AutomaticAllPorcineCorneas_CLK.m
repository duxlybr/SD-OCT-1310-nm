close all
clear all
clc

%% Case Depth

% % GeneralPath = 'C:\Users\proyecto\Documents\Bocanegra Cristian\PROCESAR DATA OCE\Datanew\26022025-1\Data';
% GeneralPath = 'E:\26022025-1_Porcine\Data';
% 
% Cases = {'Depth'};
% IOPs = [5, 10, 15, 20, 25, 30,];
% Freqs = [1000, 1500, 2000, 2500, 3000, 3500, 4000];
% % Freqs = [2000];
% Excit = [1, 3];
% 
% for i = 1:length(Cases)
% 
%     %%% Cases
%     pathname_1 = [GeneralPath,'\',Cases{i},'\'];
%     oldfolfer = cd(pathname_1);
%     files1 = dir('*.bin');
%     cd(oldfolfer)
% 
%     PhaseSpeed_NewAll = zeros(length(Freqs),length(IOPs),2);
% 
%     for j = 1:length(files1)
% 
%         file = files1(j).name;
% 
%         % Search frequency
%         kk = strfind(file,'Hz');
%         FreqVal = str2num(file(kk-4:kk-1));
% 
%         % Search IOP
%         kk = strfind(file,'mmHg');
%         IOPVal = str2num(file(kk-2:kk-1));
%         if isempty(IOPVal)
%             IOPVal = str2num(file(kk-1));
%         end
% 
%         % Search Excitation
%         kk = strfind(file,'cycles');
%         ExcitType = str2num(file(kk-1));
% 
%         ParamsAuto.FreqVal = FreqVal;
%         ParamsAuto.ExcitType = ExcitType;
%         ParamsAuto.IOPval = IOPVal;
% 
% 
%         [PhaseSpeedEval,...
%         freq_disp,...
%         Speed_disp] = Automatic_OCE_Analysis_CorneasDepth_mod(file,pathname_1,ParamsAuto);
% 
%         idxFreqVal = find(FreqVal==Freqs);
%         idxIOPs = find(IOPVal==IOPs);
%         idxExcit = find(ExcitType==Excit);
%         PhaseSpeed_NewAll(idxFreqVal,idxIOPs,idxExcit) = PhaseSpeedEval;
%         freq_disp_NewAll{idxFreqVal,idxIOPs,idxExcit} = freq_disp{1};
%         Speed_disp_NewAll{idxFreqVal,idxIOPs,idxExcit} = Speed_disp{1};
%     end
% 
%     cd(oldfolfer)
% 
%     i
% end
% 
% 
% % figure
% % plot(squeeze(PhaseSpeed_NewAll(3,:,2)))
% 

%% Case lateral

%GeneralPath = 'C:\Users\proyecto\Documents\Bocanegra Cristian\PROCESAR DATA OCE\Datanew\26022025-1\Data';
GeneralPath = 'G:\09042025-1_CXL_Porcine\Data';
Cases = {'Lateral'};
% IOPs = [5, 10, 15, 20, 25, 30,];
% Freqs = [1000, 1500, 2000, 2500, 3000, 3500, 4000];
IOPs = [15];
Freqs = [2000];
% Excit = [1, 3];
Excit = [3];

Acq = [0:1:21];
Num = [1, 2, 3, 4, 5, 6];

for i = 1:length(Cases)

    %%% Cases
    pathname_1 = [GeneralPath,'\',Cases{i},'\'];
    oldfolfer = cd(pathname_1);
    files1 = dir('*.bin');
    cd(oldfolfer)
    
    % PhaseSpeed_NewAll = zeros(length(Freqs),length(IOPs),2);
    PhaseSpeed_NewAll = zeros(length(Acq),length(Num),2);

    for j = 1:length(files1)

        file = files1(j).name;
         
        % Search frequency
        kk = strfind(file,'Hz');
        FreqVal = str2num(file(kk-4:kk-1));

        % Search IOP
        kk = strfind(file,'mmHg');
        IOPVal = str2num(file(kk-2:kk-1));
        if isempty(IOPVal)
            IOPVal = str2num(file(kk-1));
        end

        % Search Excitation
        kk = strfind(file,'cycles');
        ExcitType = str2num(file(kk-1));
        
        % Search acquisition
        kk = strfind(file,'Acq');
        Acq = str2num(file(kk+3:kk+4));
        if isempty(Acq)
            Acq = str2num(file(kk+3));
        end

        % Search Number acquisition
        kk = strfind(file,'Num');
        Num = str2num(file(kk+3));

        % ParamsAuto.FreqVal = FreqVal;
        if Num == 1 | Num == 2 | Num == 3
            ParamsAuto.FreqVal = FreqVal;
        else
            ParamsAuto.FreqVal = FreqVal/2;
        end
        ParamsAuto.ExcitType = ExcitType;
        ParamsAuto.IOPval = IOPVal;
        ParamsAuto.Acq = Acq;
        ParamsAuto.Num = Num;
        
        %ver que archivo .bin voy a leer
        % FreqVal
        % ExcitType
        % IOPVal
        Acq
        Num

        [PhaseSpeed_New,...
        Thickness_New,...
        MeanSpeed,...
        ErrorSpeed,...
        MeanTh,...
        ErrorTh] = Automatic_OCE_Analysis_CorneasLateral_CLK(file,pathname_1,ParamsAuto);


        % idxFreqVal = find(FreqVal==Freqs);
        % idxIOPs = find(IOPVal==IOPs);
        % idxExcit = find(ExcitType==Excit);
        % PhaseSpeedLateral_NewAll(idxFreqVal,idxIOPs,idxExcit,:) = PhaseSpeed_New;
        % ThicknessLateral_NewAll(idxFreqVal,idxIOPs,idxExcit,:) = Thickness_New;

        PhaseSpeedLateral_NewAll(Acq+1,Num,:) = PhaseSpeed_New;
        ThicknessLateral_NewAll(Acq+1,Num,:) = Thickness_New;

        
    end

    cd(oldfolfer)

    i
end

%% Analysis
% 
% time = linspace(0,60,21);
% 
% %%% Speed  %%%%
% SpeedMeanAllCases = squeeze(mean(PhaseSpeedLateral_NewAll,3));
% SpeedErrorAllCases = squeeze(std(PhaseSpeedLateral_NewAll,[],3))/sqrt(3);
% 
% figure
% plot(time,SpeedMeanAllCases)
% 
% SpeedMeanMerTime = mean(SpeedMeanAllCases,1);
% SpeedErrorMerTime = mean(SpeedMeanAllCases,1)/sqrt(16);
% 
% figure
% errorbar(time,SpeedMeanMerTime,SpeedErrorMerTime)
% 
% DiffSpeedMeanAllCases = diff(SpeedMeanAllCases,1,2);
% 
% %%% Speed  %%%%
% ThMeanAllCases = squeeze(mean(ThicknessLateral_NewAll,3));
% ThErrorAllCases = squeeze(std(ThicknessLateral_NewAll,[],3))/sqrt(3);
% 
% figure
% plot(time,ThMeanAllCases)
% 
% ThMeanMerTime = mean(ThMeanAllCases,1);
% ThErrorMerTime = mean(ThMeanAllCases,1)/sqrt(16);
% 
% figure
% errorbar(time,ThMeanMerTime,ThErrorMerTime)
% 
% DiffSpeedMeanAllCases = diff(ThMeanAllCases,1,2);
%% Save data

save('Phase_Thickness_all.mat','PhaseSpeedLateral_NewAll',...
                                 'ThicknessLateral_NewAll');

%% analysis for 2kHz

SpeedAveAll = squeeze(mean(PhaseSpeedLateral_NewAll(:,1:3,:),2));
SpeedErrorAll = squeeze(std(PhaseSpeedLateral_NewAll(:,1:3,:),[],2))/sqrt(3);

ThAveAll = squeeze(mean(ThicknessLateral_NewAll(:,1:3,:),2));
ThErrorAll = squeeze(std(ThicknessLateral_NewAll(:,1:3,:),[],2));

figure
errorbar(SpeedAveAll,SpeedErrorAll)

figure
Rlimit = 8;
for i = 1:21
    hold on
    polarwitherrorbarMod(theta(1:16)',SpeedAveAll(i,:),SpeedErrorAll(i,:),Rlimit);
    hold off
end

%% Speed

Time = [0,2.5:5:27.5,30,32.5:5:57.5,60,62.5,65:5:90];

DiffSpeedAveAll = diff(SpeedAveAll,1);

figure
plot(DiffSpeedAveAll)
% figure
% plot(DiffThAveAll)

MeanDiffSpeed = mean(DiffSpeedAveAll,2);
ErrorDiffSpeed = std(DiffSpeedAveAll,[],2)/sqrt(16);
ErrorDiffSpeed = [ErrorDiffSpeed(1); ErrorDiffSpeed];
SpeedAveAllNew = cumsum([mean(SpeedAveAll(1,:)); MeanDiffSpeed]);

figure
errorbar(Time, SpeedAveAllNew,ErrorDiffSpeed)
grid on
xlabel('Time (s)')
ylabel('Lamb wave speed @ 2kHz (m/s)')
title('Dresden Protocol (30 min of RB soaking, 30 min UV-A irradiation 3 mW/cm2)')

%% Thickness

DiffThAveAll = diff(ThAveAll*1000,1);

% figure
% plot(DiffSpeedAveAll)
figure
plot(DiffThAveAll)

ThDiffSpeed = mean(DiffThAveAll,2);
ErrorDiffTh = std(DiffThAveAll,[],2)/sqrt(16);
ErrorDiffTh = [ErrorDiffTh(1); ErrorDiffTh];
ThAveAllNew = cumsum([mean(ThAveAll(1,:)*1000); ThDiffSpeed]);

figure
errorbar(Time, ThAveAllNew,ErrorDiffTh)
grid on
xlabel('Time (s)')
ylabel('Corneal thickness (um)')
title('Dresden Protocol (30 min of RB soaking, 30 min UV-A irradiation 3 mW/cm2)')

%% analysis for 1kHz
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
SpeedAveAll = squeeze(mean(PhaseSpeedLateral_NewAll(:,4:6,:),2));
SpeedErrorAll = squeeze(std(PhaseSpeedLateral_NewAll(:,4:6,:),[],2))/sqrt(3);

ThAveAll = squeeze(mean(ThicknessLateral_NewAll(:,4:6,:),2));
ThErrorAll = squeeze(std(ThicknessLateral_NewAll(:,4:6,:),[],2));

figure
errorbar(SpeedAveAll,SpeedErrorAll)

figure
Rlimit = 8;
for i = 1:21
    hold on
    polarwitherrorbarMod(theta(1:16)',SpeedAveAll(i,:),SpeedErrorAll(i,:),Rlimit);
    hold off
end

%% Speed

Time = [0,2.5:5:27.5,30,32.5:5:57.5,60,62.5,65:5:90];

DiffSpeedAveAll = diff(SpeedAveAll,1);

figure
plot(DiffSpeedAveAll)
% figure
% plot(DiffThAveAll)

MeanDiffSpeed = mean(DiffSpeedAveAll,2);
ErrorDiffSpeed = std(DiffSpeedAveAll,[],2)/sqrt(16);
ErrorDiffSpeed = [ErrorDiffSpeed(1); ErrorDiffSpeed];
SpeedAveAllNew = cumsum([mean(SpeedAveAll(1,:)); MeanDiffSpeed]);

figure
errorbar(Time, SpeedAveAllNew,ErrorDiffSpeed)
grid on
xlabel('Time (s)')
ylabel('Lamb wave speed @ 1kHz (m/s)')
title('Dresden Protocol (30 min of RB soaking, 30 min UV-A irradiation 3 mW/cm2)')

%% Thickness

DiffThAveAll = diff(ThAveAll*1000,1);

% figure
% plot(DiffSpeedAveAll)
figure
plot(DiffThAveAll)

ThDiffSpeed = mean(DiffThAveAll,2);
ErrorDiffTh = std(DiffThAveAll,[],2)/sqrt(16);
ErrorDiffTh = [ErrorDiffTh(1); ErrorDiffTh];
ThAveAllNew = cumsum([mean(ThAveAll(1,:)*1000); ThDiffSpeed]);

figure
errorbar(Time, ThAveAllNew,ErrorDiffTh)
grid on
xlabel('Time (s)')
ylabel('Corneal thickness (um)')
title('Dresden Protocol (30 min of RB soaking, 30 min UV-A irradiation 3 mW/cm2)')

%%
% 
% IOP = 3
% CXL = 2
% 
% LSW_SpeedsAvg_All(:,IOP,CXL) = MeanSpeedLSWFilt;
% LSW_SpeedsStd_All(:,IOP,CXL) = ErrorSpeedLSWFilt;
% 
% LambW_SpeedsAvg_All(:,IOP,CXL) = MeanSpeed;
% LambW_SpeedsStd_All(:,IOP,CXL) = ErrorSpeed;
% 
% Thickness_Avg_All(:,IOP,CXL) = MeanThickness;
% Thickness_Std_All(:,IOP,CXL) = ErrorThickness;
% 
% 
% %%
% 
% figure
% hold on
% plot(Zaxis,squeeze(LSW_SpeedsAvg_All(:,:,1)))
% plot(Zaxis,squeeze(LSW_SpeedsAvg_All(:,:,2)))
% 
% 
% figure
% hold on
% errorbar(squeeze(LambW_SpeedsAvg_All(:,:,1))',squeeze(LambW_SpeedsStd_All(:,:,1))')
% errorbar(squeeze(LambW_SpeedsAvg_All(:,:,2))',squeeze(LambW_SpeedsStd_All(:,:,2))')
% 
% figure
% hold on
% errorbar(squeeze(Thickness_Avg_All(:,:,1))',squeeze(Thickness_Std_All(:,:,1))')
% errorbar(squeeze(Thickness_Avg_All(:,:,2))',squeeze(Thickness_Std_All(:,:,2))')
% 
% 
% 
% 
% 
% 
% 
% 

