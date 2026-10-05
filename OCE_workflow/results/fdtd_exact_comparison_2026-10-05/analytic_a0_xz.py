"""Independent homogeneous free-plate A0 axial eigenfield.

Coordinates: z=0 top, z=h bottom; x propagation is positive.
Convention: real(U * exp(-1j*omega*t)); MATLAB +i phasor is conj(U).
Only an infinite, homogeneous, isotropic, lossless, unstressed plate with
traction-free faces is exact here. A localized FDTD force can also excite
other modes and near fields. This is not an exact heterogeneous solution.

Derivation uses Navier potentials and the antisymmetric Rayleigh-Lamb
secular equation (Lamb 1917, doi:10.1098/rspa.1917.0008). The dimensional
potentials and stress definitions are independently checked below; no
octsim theory/eigenshape function is imported.
"""
from __future__ import annotations

import csv
import importlib.util
import json
from pathlib import Path

import numpy as np


def _reference_speed(E, nu, rho, h, f):
    # Scalar secular root already independently implemented in our exporter.
    module_path = Path(__file__).resolve().parents[2] / 'workflows' / 'export_simulator_wave_cases.py'
    spec = importlib.util.spec_from_file_location('independent_oce_wave_reference', module_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.independent_lamb_a0(E, nu, rho, h, f)


def _hyperbolic_ratio(v, halfwidth, odd=False):
    """sinh(v)/cosh(a) or cosh(v)/cosh(a), without growing exp(a)."""
    positive = np.exp(v - halfwidth)
    negative = np.exp(-v - halfwidth)
    return (positive - negative if odd else positive + negative) / (1 + np.exp(-2 * halfwidth))


def _material(E, nu, rho, h, f, c):
    if not (E > 0 and rho > 0 and h > 0 and f > 0 and -1 < nu < 0.5):
        raise ValueError('Require E,rho,h,f>0 and -1<nu<0.5.')
    mu = E / (2 * (1 + nu))
    lam = E * nu / ((1 + nu) * (1 - 2 * nu))
    cs = np.sqrt(mu / rho)
    cl = np.sqrt((lam + 2 * mu) / rho)
    if c is None:
        c = _reference_speed(E, nu, rho, h, f)
    if not (np.isfinite(c) and 0 < c < cs):
        raise ValueError('This helper is restricted to the sub-shear A0 branch.')
    omega = 2 * np.pi * f
    k = omega / c
    p = np.sqrt(k*k - (omega/cl)**2)
    q = np.sqrt(k*k - (omega/cs)**2)
    return mu, lam, cs, cl, omega, k, p, q, float(c)


def _depth_fields(z, h, k, p, q):
    """Return ux,uz and their first/second z derivatives from potentials.

    phi=A*sinh(p*zeta)/cosh(p*a), psi=B*cosh(q*zeta)/cosh(q*a)
    u=(i*k*phi-psi', phi'+i*k*psi), a=h/2, zeta=z-a.
    sigma_xz(a)=0 gives B=2*i*k*p*A/(k²+q²).
    sigma_zz(a)=0 gives D²*tanh(p*a)-4*k²*p*q*tanh(q*a)=0.
    """
    zeta = np.asarray(z, dtype=float) - h/2
    D = k*k + q*q
    # At either face uz=A*p*(1-2*k²/D); normalize axial surface to +1.
    A = 1 / (p * (1 - 2*k*k/D))
    B = 2j*k*p*A/D
    phi = [A*p**n*_hyperbolic_ratio(p*zeta, p*h/2, odd=(n % 2 == 0)) for n in range(4)]
    psi = [B*q**n*_hyperbolic_ratio(q*zeta, q*h/2, odd=(n % 2 == 1)) for n in range(4)]
    ux = [1j*k*phi[n] - psi[n+1] for n in range(3)]
    uz = [phi[n+1] + 1j*k*psi[n] for n in range(3)]
    return ux, uz


def verify(E_pa, nu, rho, thickness_m, f_hz, c=None):
    """Verify Navier, both traction-free faces, A0 parity and secular root.

    Residuals are relative to dimensional inertial/stress scales. Analytic
    derivatives are evaluated independently of the scalar determinant.
    Also reports a finite-difference Navier check on the actual axial and
    in-plane shape samples, to expose potential derivative/sign errors.
    """
    h = thickness_m
    mu, lam, cs, cl, omega, k, p, q, c = _material(E_pa, nu, rho, h, f_hz, c)
    z = np.linspace(0, h, 257)
    ux, uz = _depth_fields(z, h, k, p, q)
    div = 1j*k*ux[0] + uz[1]
    divz = 1j*k*ux[1] + uz[2]
    rx = (lam+mu)*1j*k*div + mu*(ux[2]-k*k*ux[0]) + rho*omega**2*ux[0]
    rz = (lam+mu)*divz + mu*(uz[2]-k*k*uz[0]) + rho*omega**2*uz[0]
    umax = float(max(np.max(abs(ux[0])), np.max(abs(uz[0]))))
    sxz = mu*(ux[1] + 1j*k*uz[0])
    szz = lam*1j*k*ux[0] + (lam+2*mu)*uz[1]
    D = k*k+q*q
    left = D**2*np.tanh(p*h/2)
    right = 4*k*k*p*q*np.tanh(q*h/2)
    # Direct fourth-order finite differences; no supplied analytic derivative.
    dz = z[1]-z[0]
    def d1(v):
        return (v[:-4]-8*v[1:-3]+8*v[3:-1]-v[4:])/(12*dz)
    def d2(v):
        return (-v[:-4]+16*v[1:-3]-30*v[2:-2]+16*v[3:-1]-v[4:])/(12*dz**2)
    uxc, uzc = ux[0][2:-2], uz[0][2:-2]
    fdx = -(lam+2*mu)*k*k*uxc + mu*d2(ux[0]) + (lam+mu)*1j*k*d1(uz[0]) + rho*omega**2*uxc
    fdz = (lam+2*mu)*d2(uz[0]) - mu*k*k*uzc + (lam+mu)*1j*k*d1(ux[0]) + rho*omega**2*uzc
    result = {
        'phase_speed_m_s': c, 'shear_speed_m_s': float(cs), 'longitudinal_speed_m_s': float(cl),
        'wavenumber_rad_m': float(k), 'kh_full_thickness': float(k*h),
        'dispersion_relative_residual': float(abs(left-right)/max(abs(left),abs(right))),
        'navier_analytic_relative_residual': float(max(np.max(abs(rx)),np.max(abs(rz)))/(rho*omega**2*umax)),
        'navier_fd4_relative_residual': float(max(np.max(abs(fdx)),np.max(abs(fdz)))/(rho*omega**2*umax)),
        'traction_relative_residual': float(max(np.max(abs(sxz[[0,-1]])),np.max(abs(szz[[0,-1]])))/(mu*k*umax)),
        'traction_xz_top_relative': float(abs(sxz[0])/(mu*k*umax)),
        'traction_xz_bottom_relative': float(abs(sxz[-1])/(mu*k*umax)),
        'traction_zz_top_relative': float(abs(szz[0])/(mu*k*umax)),
        'traction_zz_bottom_relative': float(abs(szz[-1])/(mu*k*umax)),
        'axial_even_parity_relative': float(np.max(abs(uz[0]-uz[0][::-1]))/umax),
        'inplane_odd_parity_relative': float(np.max(abs(ux[0]+ux[0][::-1]))/umax),
        'surface_axial_normalization_error': float(abs(uz[0][0]-1)),
        'z_origin': 'top_free_face', 'time_convention': 'real(U*exp(-i*omega*t))',
        'propagation': '+x', 'model': 'homogeneous_isotropic_unloaded_free_plate_A0',
        'exact_scope': 'single continuum eigenmode; not localized forcing or heterogeneous inclusion',
        'reference_doi': '10.1098/rspa.1917.0008',
    }
    result['passed'] = bool(result['dispersion_relative_residual'] < 1e-9 and result['navier_analytic_relative_residual'] < 1e-9
                            and result['traction_relative_residual'] < 1e-8 and result['navier_fd4_relative_residual'] < 1e-4
                            and result['surface_axial_normalization_error'] < 1e-10)
    return result


def phasor(x_m, z_m, E_pa, nu, rho, thickness_m, f_hz, c=None):
    """Return (axial_complex_field[nz,nx], checks), surface axial value 1.

    Outside [0,h] field values are NaN. Supplying a speed does not bypass
    traction/secular verification: a non-A0 speed raises ValueError.
    """
    checks = verify(E_pa, nu, rho, thickness_m, f_hz, c)
    if not checks['passed']:
        raise ValueError(f'A0 continuum verification failed: {checks}')
    _, _, _, _, _, k, p, q, _ = _material(E_pa, nu, rho, thickness_m, f_hz, checks['phase_speed_m_s'])
    x = np.asarray(x_m, dtype=float).reshape(-1)
    z = np.asarray(z_m, dtype=float).reshape(-1)
    # Avoid evaluating exponential outside the physical plate.
    valid = np.isfinite(z) & (z >= 0) & (z <= thickness_m)
    shape = np.full(z.size, np.nan+1j*np.nan, dtype=complex)
    _, uz = _depth_fields(z[valid], thickness_m, k, p, q)
    shape[valid] = uz[0]
    return shape[:,None]*np.exp(1j*k*x[None,:]), checks


def main():
    root = Path(__file__).resolve().parent
    records=[]
    for E in (6000.,12000.,24000.):
        for nu in (.45,.495):
            for h in (.0006,.0012):
                check=verify(E,nu,1000.,h,1000.)
                records.append({'E_pa':E,'nu':nu,'rho':1000.,'h_m':h,'f_hz':1000.,**check})
                if not check['passed']:
                    raise AssertionError(check)
    with (root/'analytic_a0_checks.csv').open('w',newline='',encoding='utf-8') as fp:
        writer=csv.DictWriter(fp,fieldnames=list(records[0]));writer.writeheader();writer.writerows(records)
    (root/'analytic_a0_checks.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
    print(json.dumps({'cases':len(records),'all_passed':all(r['passed'] for r in records),
                      'max_navier_analytic':max(r['navier_analytic_relative_residual'] for r in records),
                      'max_navier_fd4':max(r['navier_fd4_relative_residual'] for r in records),
                      'max_traction':max(r['traction_relative_residual'] for r in records)},indent=2))


if __name__=='__main__':
    main()
