function [MeanSpeed,ErrorSpeed] = SmartCleaning (MeanSpeed,ErrorSpeed,Thres_ErrorSpeed)
PhaseSpeed_NewAll = MeanSpeed;
ErrorSpeed_NewAll  = ErrorSpeed;


MeanSpeed = median(PhaseSpeed_NewAll(:));
ErrorSpeed = abs(MeanSpeed - PhaseSpeed_NewAll);

idx_ErrorSpeed = find(ErrorSpeed>Thres_ErrorSpeed);
PhaseSpeed_NewAll(idx_ErrorSpeed)=nan;
ErrorSpeed_NewAll(idx_ErrorSpeed)=nan;

MeanSpeed = PhaseSpeed_NewAll;
ErrorSpeed = ErrorSpeed_NewAll;

end