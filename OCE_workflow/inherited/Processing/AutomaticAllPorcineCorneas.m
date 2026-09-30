close all
clear all
clc

%% Case Depth

GeneralPath = 'C:\Users\proyecto\Documents\Bocanegra Cristian\PROCESAR DATA OCE\Datanew\26022025-1\Data';
Cases = {'Depth'};
IOPs = [5, 10, 15, 20, 25, 30,];
Freqs = [1000, 1500, 2000, 2500, 3000, 3500, 4000];
Excit = [1, 3];

for i = 1:length(Cases)

    %%% Cases
    pathname_1 = [GeneralPath,'\',Cases{i},'\'];
    oldfolfer = cd(pathname_1);
    files1 = dir('*.bin');
    cd(oldfolfer)
    
    PhaseSpeed_NewAll = zeros(length(Freqs),length(IOPs),2);

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

        ParamsAuto.FreqVal = FreqVal;
        ParamsAuto.ExcitType = ExcitType;

        [PhaseSpeedEval,...
        freq_disp,...
        Speed_disp] = Automatic_OCE_Analysis_CorneasDepth(file,pathname_1,ParamsAuto);

        idxFreqVal = find(FreqVal==Freqs);
        idxIOPs = find(IOPVal==IOPs);
        idxExcit = find(ExcitType==Excit);
        PhaseSpeed_NewAll(idxFreqVal,idxIOPs,idxExcit) = PhaseSpeedEval;
        freq_disp_NewAll{idxFreqVal,idxIOPs,idxExcit} = freq_disp{1};
        Speed_disp_NewAll{idxFreqVal,idxIOPs,idxExcit} = Speed_disp{1};
    end

    cd(oldfolfer)

    i
end


figure
plot(squeeze(PhaseSpeed_NewAll(3,:,2)))


%% Case lateral

GeneralPath = 'C:\Users\proyecto\Documents\Bocanegra Cristian\PROCESAR DATA OCE\Datanew\26022025-1\Data';
Cases = {'Lateral'};
IOPs = [5, 10, 15, 20, 25, 30,];
Freqs = [1000, 1500, 2000, 2500, 3000, 3500, 4000];
Excit = [1, 3];

for i = 1:length(Cases)

    %%% Cases
    pathname_1 = [GeneralPath,'\',Cases{i},'\'];
    oldfolfer = cd(pathname_1);
    files1 = dir('*.bin');
    cd(oldfolfer)
    
    PhaseSpeed_NewAll = zeros(length(Freqs),length(IOPs),2);

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

        ParamsAuto.FreqVal = FreqVal;
        ParamsAuto.ExcitType = ExcitType;

        [PhaseSpeed_New,...
        Thickness_New,...
        MeanSpeed,...
        ErrorSpeed,...
        MeanTh,...
        ErrorTh] = Automatic_OCE_Analysis_CorneasLateral(file,pathname_1,ParamsAuto);


        idxFreqVal = find(FreqVal==Freqs);
        idxIOPs = find(IOPVal==IOPs);
        idxExcit = find(ExcitType==Excit);
        PhaseSpeedLateral_NewAll(idxFreqVal,idxIOPs,idxExcit,:) = PhaseSpeed_New;
        ThicknessLateral_NewAll(idxFreqVal,idxIOPs,idxExcit,:) = Thickness_New;
    end

    cd(oldfolfer)

    i
end
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
