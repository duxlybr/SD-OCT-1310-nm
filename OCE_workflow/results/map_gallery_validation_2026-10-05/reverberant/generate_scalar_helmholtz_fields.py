"""Actual 2-D variable-medium scalar shear Helmholtz forward simulations.

The physical scalar approximation is anti-plane SH displacement U(x,y):
    div(mu grad U) + rho*omega**2 U = -F, mu=E/[2*(1+nu)].
Finite-volume harmonic face averages enforce traction continuity across
interfaces. An imaginary mass term only in the outer rim absorbs outgoing
waves; the external numerical boundary is Dirichlet. The interior material
is lossless. Multiple peripheral sources generate genuine interference and
interface reflection/transmission. The field is solved, never painted from
a local truth speed map. This is not a 3-D OCT/elastodynamic simulation.
"""
from pathlib import Path
import json
import numpy as np
from scipy import sparse
from scipy.sparse.linalg import spsolve
from scipy.io import savemat

SOURCE_RADIUS_M=10e-3
SOURCE_SIGMA_M=.16e-3
ABSORBER_START_M=10.3e-3
WINDOW_HALF_WIDTH_M=1.2e-3


def harmonic(a, b):
    return 2*a*b/(a+b)


def forward(E, x, y, f, rho, nu, seed):
    X, Y = np.meshgrid(x, y)
    dx=float(x[1]-x[0]); dy=float(y[1]-y[0])
    mu=E/(2*(1+nu)); central=mu[1:-1,1:-1]
    east=harmonic(central,mu[1:-1,2:])/dx**2
    west=harmonic(central,mu[1:-1,:-2])/dx**2
    north=harmonic(central,mu[2:,1:-1])/dy**2
    south=harmonic(central,mu[:-2,1:-1])/dy**2
    rim=np.clip((np.maximum(np.abs(X),np.abs(Y))-ABSORBER_START_M)/
                (x[-1]-ABSORBER_START_M),0,1)
    absorbing=4.0*rim**3
    omega=2*np.pi*f
    diagonal=-east-west-north-south+rho*omega**2*(1+1j*absorbing[1:-1,1:-1])
    index=np.arange(central.size).reshape(central.shape)
    rows=[index.ravel()]; cols=[index.ravel()]; values=[diagonal.ravel()]
    for start,end,coefficient in [(index[:,:-1],index[:,1:],east[:,:-1]),
                                  (index[:,1:],index[:,:-1],west[:,1:]),
                                  (index[:-1,:],index[1:,:],north[:-1,:]),
                                  (index[1:,:],index[:-1,:],south[1:,:])]:
        rows.append(start.ravel()); cols.append(end.ravel()); values.append(coefficient.ravel())
    operator=sparse.coo_matrix((np.concatenate(values),
                               (np.concatenate(rows),np.concatenate(cols))),
                              shape=(central.size,central.size)).tocsc()
    rng=np.random.default_rng(seed)
    angles=np.arange(24)*2*np.pi/24
    phases=rng.uniform(0,2*np.pi,angles.size)
    centers=SOURCE_RADIUS_M*np.column_stack((np.cos(angles),np.sin(angles)))
    source=np.zeros_like(X,dtype=complex)
    for (cx,cy), phase in zip(centers,phases):
        source += np.exp(-((X-cx)**2+(Y-cy)**2)/(2*SOURCE_SIGMA_M**2))*np.exp(1j*phase)
    rhs=-source[1:-1,1:-1].ravel()
    solution=spsolve(operator,rhs)
    residual=float(np.linalg.norm(operator@solution-rhs)/np.linalg.norm(rhs))
    U=np.zeros_like(source); U[1:-1,1:-1]=solution.reshape(central.shape)
    return U,centers,absorbing,residual


def main():
    destination=Path(__file__).resolve().parent
    dx=0.1e-3; n=241
    x=(np.arange(n)-(n-1)/2)*dx; y=x.copy()
    X,Y=np.meshgrid(x,y); radius=np.hypot(X,Y)
    density=1000.; nu=.495; f=1800.; inclusion_radius=2.2e-3
    background_wavelength=np.sqrt(12000/(2*(1+nu)*density))/f
    rng=np.random.default_rng(20261005)
    cases=[]; diagnostics=[]
    for label,inclusion_E in [('homogeneous',12000.),('stiff_inclusion',24000.),('soft_inclusion',6000.)]:
        E=np.full((n,n),12000.); E[radius<=inclusion_radius]=inclusion_E
        U,sources,absorbing,residual=forward(E,x,y,f,density,nu,20261005)
        support=np.maximum(abs(X),abs(Y))<ABSORBER_START_M
        distance=np.min(np.sqrt((X[:,:,None]-sources[:,0])**2+
                                (Y[:,:,None]-sources[:,1])**2),axis=2)
        # Pre-fit mask: remain at least two background wavelengths beyond
        # the 3-sigma Gaussian source support and outside the absorbing rim.
        support &= distance >= 2*background_wavelength+3*SOURCE_SIGMA_M
        U=U/max(np.sqrt(np.mean(np.abs(U[support])**2)),np.finfo(float).tiny)*10e-9
        t=np.arange(240)/(40*f)
        motion=np.real(U[:,:,None]*np.exp(-2j*np.pi*f*t))
        noise=np.sqrt(np.mean(motion[support]**2))*10**(-25/20)
        motion += rng.normal(0,noise,motion.shape)
        truth_speed=np.sqrt(E/(2*(1+nu)*density))
        # Scoring is safely outside sources and absorption. Separate core
        # masks exclude the full square fit aperture around the interface.
        farfield=(radius<=4.8e-3)&(np.maximum(abs(X),abs(Y))<=4.5e-3)
        # Exact Euclidean distance from each source center to each axis-aligned
        # fit square; subtract the source's 3-sigma radius. This checks the
        # full aperture, not only the map-center distance.
        window_dx=np.maximum(abs(X[:,:,None]-sources[:,0])-WINDOW_HALF_WIDTH_M,0)
        window_dy=np.maximum(abs(Y[:,:,None]-sources[:,1])-WINDOW_HALF_WIDTH_M,0)
        aperture_source_gap=np.min(np.hypot(window_dx,window_dy),axis=2)-3*SOURCE_SIGMA_M
        aperture_absorber_gap=ABSORBER_START_M-(np.maximum(abs(X),abs(Y))+WINDOW_HALF_WIDTH_M)
        assert np.all(aperture_source_gap[farfield]>=2*background_wavelength)
        assert np.all(aperture_absorber_gap[farfield]>0)
        core=farfield&(radius<=inclusion_radius-np.sqrt(2)*WINDOW_HALF_WIDTH_M)
        background=farfield&(radius>=inclusion_radius+np.sqrt(2)*WINDOW_HALF_WIDTH_M)
        interface=farfield&~core&~background
        cases.append({'label':label,'f_hz':f,'truth_speed':truth_speed,'truth_young':E,
                      'density_kg_m3':density,'poisson_ratio':nu,'inclusion_radius_m':inclusion_radius,
                      'core_mask':core,'background_mask':background,'interface_mask':interface,
                      'farfield_mask':farfield,'source_centers_m':sources,'absorbing_rim':absorbing,
                      'data':{'motion':motion.astype(np.float32),'x_m':x,'row_m':y,'t_s':t,
                              'valid_mask':support,'plane_type':'enface',
                              'metadata':{'source':'independent_divergence_form_scalar_SH_Helmholtz',
                                          'frequency_hz':f,'phase_coherent':True,'displacement_unit':'m',
                                          'description':'Simulación escalar 2D de corte anti-plano, no simulación OCT 3D. El módulo es condicional al modelo escalar de corte.'}},
                      'forward_phasor':U})
        diagnostics.append({'case':label,'E_background_pa':12000.,'E_inclusion_pa':inclusion_E,
                            'relative_sparse_residual':residual,'grid_points':n,'dx_m':dx,'f_hz':f,
                            'source_count':sources.shape[0],'source_seed':20261005,'input_snr_db':25,
                            'source_radius_m':SOURCE_RADIUS_M,'source_sigma_m':SOURCE_SIGMA_M,
                            'absorber_start_m':ABSORBER_START_M,'window_m':2*WINDOW_HALF_WIDTH_M,
                            'background_wavelength_m':background_wavelength,
                            'minimum_farfield_aperture_source_gap_m':float(aperture_source_gap[farfield].min()),
                            'minimum_farfield_aperture_source_gap_wavelengths':float(aperture_source_gap[farfield].min()/background_wavelength),
                            'minimum_farfield_aperture_absorber_gap_m':float(aperture_absorber_gap[farfield].min()),
                            'interior_is_lossless':True,'full_elastodynamics':False,
                            'equation':'div(mu grad U)+rho omega^2 U=-F; harmonic mu-face averages',
                            'absorption':'imaginary mass term only in outer rim, Dirichlet exterior boundary'})
        print(label,'sparse residual',residual,'core pixels',int(core.sum()),'background pixels',int(background.sum()))
    cell=np.empty((1,len(cases)),dtype=object)
    for i,case in enumerate(cases): cell[0,i]=case
    savemat(destination/'scalar_helmholtz_fields.mat',{'cases':cell},do_compression=True,long_field_names=True)
    (destination/'forward_diagnostics.json').write_text(json.dumps(diagnostics,indent=2),encoding='utf-8')


if __name__=='__main__': main()
