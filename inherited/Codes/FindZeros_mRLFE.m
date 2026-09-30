function [K_sol] = FindZeros_mRLFE(k_max,w,c1,mu,rho_s,cf,rho_f,d)

k_tmp = linspace(0,k_max,2000);
ConNum = zeros(length(k_tmp),1);
  
for i = 1:length(k_tmp)
    [tmp ConNum(i)] = mRLFE(k_tmp(i),w,c1,mu,rho_s,cf,rho_f,d);
end

% figure
% plot(ConNum)

[pks, locs] = findpeaks(ConNum,'NPeaks',5); 

K_sol = zeros(1,5);
if ~isempty(locs)
    K_sol(1:length(locs)) = k_tmp(locs);
end


end