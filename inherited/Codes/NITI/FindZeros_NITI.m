function [K_sol] = FindZeros_NITI(k_max,w,G,mu,rho_s,cf,rho_f,d,cp)

k_tmp = linspace(0,k_max,2000);
ConNum = zeros(length(k_tmp),1);
lambda = rho_s*cp^2 - 2*mu;
  
for i = 1:length(k_tmp)
    %[tmp ConNum(i)] = mRLFE(k_tmp(i),w,c1,mu,rho_s,cf,rho_f,d);
    [ConNum(i), ~] = compute_niti_kappa(w/(2*pi), k_tmp(i)/(2*pi), d, G, mu, lambda, rho_s, rho_f, cf);
end

% figure
% plot(ConNum(10:60))

[pks, locs] = findpeaks(ConNum,'NPeaks',5); 

K_sol = zeros(1,5);
if ~isempty(locs)
    K_sol(1:length(locs)) = k_tmp(locs);
end


end