function [MeanSpeed,ErrorSpeed] = SmartMerging (PhaseSpeed_NewAll,Thres_ErrorSpeed)

MeanSpeed = median(PhaseSpeed_NewAll(:,:),2);
ErrorSpeed = abs(repmat(MeanSpeed,1,size(PhaseSpeed_NewAll,2)) - PhaseSpeed_NewAll);

idx_ErrorSpeed = find(ErrorSpeed>Thres_ErrorSpeed);
PhaseSpeed_NewAll(idx_ErrorSpeed)=nan;
MeanSpeed = median(PhaseSpeed_NewAll(:,:),2,'omitnan');
ErrorSpeed = std(PhaseSpeed_NewAll(:,:),[],2,'omitnan');

end