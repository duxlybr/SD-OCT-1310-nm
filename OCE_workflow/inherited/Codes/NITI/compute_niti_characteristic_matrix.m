function M = compute_niti_characteristic_matrix(omega, k, alpha_sqr, beta_sqr, gamma_sqr, delta_sqr, rho, rho_f)
% COMPUTE_NITI_CHARACTERISTIC_MATRIX - Compute the boundary condition matrix M for NITI
%
% M = compute_niti_characteristic_matrix(omega, k, alpha_sqr, beta_sqr, gamma_sqr, delta_sqr, rho, rho_f)
%
% The dispersion relation for a NITI plate of thickness h bounded above by air and below by water can be solved 
% as a superposition of partial bulk waves. The partial wave solutions are assumed for the displacements and substituted
% into the governing elastic wave equations and boundary conditions. This leads to a 5x5 homogeneous system of equations
% for the partial wave amplitude constants, Mc = 0. The determinant of M must be zero to yield a non-trival solution
% (i.e. M must be singular).
%
% This function returns the 5x5 matrix M for a given dimensionless angular-frequency/wavenumber.
%
% The helper function compute_niti_kappa returns the condition number (kappa) and determinant (detM) of the
% matrix M for a set of dimensional inputs, making it a much simpler interface for obtaining dispersion curves.
%
% Important
% ---------
% This function solves M using the dimensionless form of the governing equations and boundary conditions. The following
% scales are used:
%
% x* = x/h
% u* = u/h
% t* = t * sqrt(mu/rho)/h
% f* = fh/sqrt(mu/rho)
% k* = kh
%
% When the governing equations are non-dimensionalized, the following dimensionless parameters are obtained:
% 
% alpha_sqr = G/mu,                 (anisotropy factor)
% beta_sqr  = (lambda + 2*mu)/mu,   (squared ratio of p-wave to fast s-wave speed)
% gamma_sqr = (lambda + G)/mu,      (coefficient of shear terms in elastic wave equations)
% delta_sqr = rho*c_f^2 / mu,       (squared ratio of fluid acoustic wave speed to fast s-wave speed in plate)
%
% Parameters
% ----------
% omega : [double] dimensionless angular frequency, omega = 2*pi*f*h/sqrt(mu/rho)
% k : [double] dimensionless angular wavenumber, k = 2*pi*k[1/m]*h
% alpha_sqr : [double] dimensionless parameter, G/mu
% beta_sqr : [double] dimensionless parameter, (lambda + 2*mu)/mu
% gamma_sqr : [double] dimensionless parameter, (lambda + G)/mu
% delta_sqr : [double] dimensionless parameter, 
% rho : [double] density of the plate in kg/m^3
% rho_f : [double] density of the fluid in kg/m^3
%
% Returns
% -------
% M : [double] 5x5 matrix
%
% Notes
% -----
% See Supplementary Note 4, Equation S4.25
%
% Author: John J. Pitre, Jr.
%
% Pitre, JJ, MA Kirby, DS Li, TT Shen, RK Wang, M O'Donnell, and I Pelivanov.
%    Nearly-incompressible transverse isotropy (NITI) of cornea elasticity: 
%    model and experiments with acoustic micro-tapping OCE. Scientific Reports 
%    (2020).
%
% ---


    % Compute subexpressions for q terms and phi
    qa_sqr = k^2 - omega^2/alpha_sqr;
    qb_sqr = k^2 - omega^2/beta_sqr;
    qf = sqrt(k^2 - omega^2/delta_sqr);
    phi = (gamma_sqr^2)*(k^2)/(alpha_sqr*beta_sqr) - (alpha_sqr/beta_sqr)*qa_sqr - (beta_sqr/alpha_sqr)*qb_sqr;

    % Compute the terms Lj
    sqrt_term = sqrt(phi^2 - 4*qa_sqr*qb_sqr);
    L1 = -(1/sqrt(2))*sqrt(phi - sqrt_term);
    L2 =  (1/sqrt(2))*sqrt(phi - sqrt_term);
    L3 = -(1/sqrt(2))*sqrt(phi + sqrt_term);
    L4 =  (1/sqrt(2))*sqrt(phi + sqrt_term);

    % Compute the coefficients Aj
    A1 = -(-sqrt(2)*(gamma_sqr)*k/alpha_sqr)*sqrt(phi - sqrt_term)/(phi + 2*(beta_sqr/alpha_sqr)*qb_sqr - sqrt_term);
    A2 =  (-sqrt(2)*(gamma_sqr)*k/alpha_sqr)*sqrt(phi - sqrt_term)/(phi + 2*(beta_sqr/alpha_sqr)*qb_sqr - sqrt_term);
    A3 = -(-sqrt(2)*(gamma_sqr)*k/alpha_sqr)*sqrt(phi + sqrt_term)/(phi + 2*(beta_sqr/alpha_sqr)*qb_sqr + sqrt_term);
    A4 =  (-sqrt(2)*(gamma_sqr)*k/alpha_sqr)*sqrt(phi + sqrt_term)/(phi + 2*(beta_sqr/alpha_sqr)*qb_sqr + sqrt_term);

    % Define the boundary conditions and construct the characteristic matrix
    BC1 = [L1*A1 + k, L2*A2 + k, L3*A3 + k, L4*A4 + k, 0];
    BC2 = [(L1*A1 + k)*exp(1i*L1), (L2*A2 + k)*exp(1i*L2), (L3*A3 + k)*exp(1i*L3), (L4*A4 + k)*exp(1i*L4), 0];
    BC3 = [(k*(gamma_sqr - alpha_sqr)*A1 + (beta_sqr)*L1)*exp(1i*L1), ...
           (k*(gamma_sqr - alpha_sqr)*A2 + (beta_sqr)*L2)*exp(1i*L2), ...
           (k*(gamma_sqr - alpha_sqr)*A3 + (beta_sqr)*L3)*exp(1i*L3), ...
           (k*(gamma_sqr - alpha_sqr)*A4 + (beta_sqr)*L4)*exp(1i*L4), 0];
    BC4 = [(k*(gamma_sqr - alpha_sqr)*A1 + (beta_sqr)*L1), ...
           (k*(gamma_sqr - alpha_sqr)*A2 + (beta_sqr)*L2), ...
           (k*(gamma_sqr - alpha_sqr)*A3 + (beta_sqr)*L3), ...
           (k*(gamma_sqr - alpha_sqr)*A4 + (beta_sqr)*L4), omega*rho_f/rho];
    BC5 = [omega, omega, omega, omega, -1i*qf];
    M = [BC1; BC2; BC3; BC4; BC5];