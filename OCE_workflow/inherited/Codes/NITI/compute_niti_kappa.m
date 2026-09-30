function [kappa, detM] = compute_niti_kappa(f, k, h, G, mu, lambda, rho, rho_f, c_l)
% COMPUTE_NITI_KAPPA - Compute condition number and determinant of M for NITI
%
% [kappa, detM] = compute_niti_kappa(f, k, h, G, mu, lambda, rho, rho_f, c_l)
%
% This function serves as a mid-level interface for computing dispersion curves. The input
% parameters are dimensional and the frequency and wavenumber can be supplied as arrays or
% as scalars. The dispersion relation is satisfied when the coefficient matrix M is singular, 
% i.e. when det|M| = 0 or kappa = cond(M) -> infinity. 
%
% This function does not return the dispersion curves themselves, and some kind of mode-tracing
% routine (typically peak finding or more advanced schemes with function minimization) is needed
% after. Note that this problem is numerically poorly conditioned, and so care must be taken in 
% obtaining the dispersion curves. In particular, the chosen sampling in f and k and the magnitude
% of f and k play a large role in determining the behavior. Be careful when tracing modes from this!
%
% See the function compute_niti_amode for A0 mode tracing.
%
% NITI stiffness tensor:
%
% C =  [C11, C12, C12, 0, 0,  0]
%      [C12, C11, C12, 0, 0,  0]
%      [C12, C12, C11, 0, 0,  0]
%      [0  ,   0,   0, G, 0,  0]
%      [0  ,   0,   0, 0, G,  0]
%      [0  ,   0,   0, 0, 0, mu]
%
% C11 = lambda + 2*mu
% C12 = lambda
%
% Parameters
% ----------
% f     : [double] dimensional frequency in Hz, can be an array
% k     : [double] dimensional wavenumber in 1/m, can be an array
% h     : [double] thickness of the plate in m
% G     : [double] plate shear modulus in Pa
% mu    : [double] plate shear modulus in Pa
% rho   : [double] plate density
% rho_f : [double] fluid density
% c_l   : [double] fluid acoustic wave speed
%
% Returns
% -------
% kappa : [double, nk x nf] array giving the condition number of the 5x5 
%         characteristic matrix for guided wave propagation in a NITI medium
% detM  : [double, nk x nf] array giving the determinant of the 5x5
%         characteristic matrix for guided wave propagation in a NITI medium
%
% Author: John J. Pitre, Jr.
%
% Pitre, JJ, MA Kirby, DS Li, TT Shen, RK Wang, M O'Donnell, and I Pelivanov.
%    Nearly-incompressible transverse isotropy (NITI) of cornea elasticity: 
%    model and experiments with acoustic micro-tapping OCE. Scientific Reports 
%    (2020).
%
% ---

    % Dimensionless parameters
    fi = f*h/sqrt(mu/rho);
    kj = k*h;
    alpha_sqr = G/mu;
    beta_sqr = (lambda+2*mu)/mu;
    gamma_sqr = (lambda + G)/mu;
    delta_sqr = rho*c_l^2/mu;

    % Main call to obtain condition number and det(M). Large values of kappa mean that M is
    % nearly singular at a given (f, k). Alternatively, abs(det(M)) approaches zero.
    kappa = ones(length(kj), length(fi));
    detM = ones(length(kj), length(fi));
    for i = 1:length(fi)
        for j = 1:length(kj)
            w = 2*pi*fi(i);
            k = 2*pi*kj(j);
            if w == 0 && k == 0
                detM(j,i) = 0;
                kappa(j,i) = Inf;
            else
                % Supplementary Note 4, Equation S4.25
                Mij = compute_niti_characteristic_matrix(w, k, alpha_sqr, beta_sqr, gamma_sqr, delta_sqr, rho, rho_f);
                if ~any(isnan(Mij(:))) && ~any(isinf(Mij(:)))
                    kappa(j,i) = cond(Mij);
                end
                detM(j,i) = det(Mij);
            end
        end
    end

