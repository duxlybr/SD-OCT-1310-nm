"""Eight independent physical scalar-SH Helmholtz acquisitions of two circles.

Each acquisition solves div(mu grad U)+rho*omega^2 U=-F for ONE finite line
source. There is no simultaneous multi-source field or cross-phase sum.
mu(x,y)=E(x,y)/(2*(1+nu)); harmonic face averages conserve shear flux. The
global complex-mass sponge is outside the ROI. This is a scalar antiplane
idealization, not complete 3-D OCE/Lamb/Rayleigh or an experimental truth.

The incoming nominal angle theta points from the external source to the ROI:
source center=-R*[cos(theta),sin(theta)]. Re[U exp(-i omega t)] is exported;
the MATLAB +i omega t convention recovers conj(U), whose physical direction
is theta. Source-aperture diffraction/refraction can alter local directions.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import time
for name in ("OMP_NUM_THREADS","OPENBLAS_NUM_THREADS","MKL_NUM_THREADS"):
    os.environ[name]="1"
import numpy as np
import scipy
from scipy import sparse
from scipy.sparse.linalg import splu
from scipy.ndimage import minimum_filter
from scipy.io import savemat

HERE=Path(__file__).resolve().parent
RHO=1000.; NU=.495; FREQUENCY=1800.; BACKGROUND_E=12000.; INCLUSION_E=24000.
DOMAIN_HALF=15e-3; ABSORBER_START=13.8e-3
SOURCE_RADIUS=12e-3; SOURCE_SIGMA_NORMAL=.15e-3; SOURCE_HALF_APERTURE=7e-3
SOURCE_CUTOFF=1e-3; SOURCE_NORMAL_SUPPORT=SOURCE_SIGMA_NORMAL*np.sqrt(2*np.log(1/SOURCE_CUTOFF))
WINDOW=.001; ROI_HALF=.006; EXPORT_HALF=.007
HEAD_CENTER=np.array([-1e-3,0.]); TAIL_CENTER=np.array([2.3e-3,0.])
HEAD_RADIUS=2.2e-3; TAIL_RADIUS=1.2e-3
BACKGROUND_C=np.sqrt(BACKGROUND_E/(2*(1+NU)*RHO))
BACKGROUND_LAMBDA=BACKGROUND_C/FREQUENCY
T=np.arange(160)/(40*FREQUENCY)


def harmonic(a,b):
    return 2*a*b/(a+b)


def build_operator(dx):
    count=int(round(2*DOMAIN_HALF/dx))+1
    x=(np.arange(count)-(count-1)/2)*dx
    X,Y=np.meshgrid(x,x)
    head=np.hypot(X-HEAD_CENTER[0],Y-HEAD_CENTER[1])<=HEAD_RADIUS
    tail=np.hypot(X-TAIL_CENTER[0],Y-TAIL_CENTER[1])<=TAIL_RADIUS
    E=np.full(X.shape,BACKGROUND_E); E[head|tail]=INCLUSION_E
    mu=E/(2*(1+NU)); central=mu[1:-1,1:-1]
    east=harmonic(central,mu[1:-1,2:])/dx**2
    west=harmonic(central,mu[1:-1,:-2])/dx**2
    north=harmonic(central,mu[2:,1:-1])/dx**2
    south=harmonic(central,mu[:-2,1:-1])/dx**2
    ramp=np.clip((np.maximum(abs(X),abs(Y))-ABSORBER_START)/(DOMAIN_HALF-ABSORBER_START),0,1)
    loss=4*ramp**3
    omega=2*np.pi*FREQUENCY
    diagonal=-east-west-north-south+RHO*omega**2*(1+1j*loss[1:-1,1:-1])
    index=np.arange(central.size).reshape(central.shape)
    rows=[index.ravel()]; cols=[index.ravel()]; values=[diagonal.ravel()]
    for start,end,coefficient in [(index[:,:-1],index[:,1:],east[:,:-1]),
                                  (index[:,1:],index[:,:-1],west[:,1:]),
                                  (index[:-1,:],index[1:,:],north[:-1,:]),
                                  (index[1:,:],index[:-1,:],south[1:,:])]:
        rows.append(start.ravel()); cols.append(end.ravel()); values.append(coefficient.ravel())
    operator=sparse.coo_matrix((np.concatenate(values),(np.concatenate(rows),np.concatenate(cols))),
                              shape=(central.size,central.size)).tocsc()
    print(f'Factoring {count} x {count} grid; {central.size} unknowns, dx={dx*1e3:.6f} mm',flush=True)
    began=time.perf_counter(); factor=splu(operator)
    print(f'Factorization completed in {time.perf_counter()-began:.2f} s',flush=True)
    return x,X,Y,E,head,tail,loss,operator,factor


def source_for_angle(X,Y,angle,index):
    theta=np.deg2rad(angle); normal=np.array([np.cos(theta),np.sin(theta)])
    tangent=np.array([-normal[1],normal[0]])
    center=-SOURCE_RADIUS*normal
    q=(X-center[0])*normal[0]+(Y-center[1])*normal[1]
    transverse=(X-center[0])*tangent[0]+(Y-center[1])*tangent[1]
    envelope=np.exp(-.5*(q/SOURCE_SIGMA_NORMAL)**2-(transverse/SOURCE_HALF_APERTURE)**12)
    envelope[envelope<SOURCE_CUTOFF]=0
    phase=np.random.default_rng(20261005+index).uniform(0,2*np.pi)
    source=envelope*np.exp(1j*phase)
    return source,normal,center,phase


def make_data(U,x,valid,angle,index,phase,center,noise_seed):
    motion=np.real(U[:,:,None]*np.exp(-2j*np.pi*FREQUENCY*T))
    sigma=np.sqrt(np.mean(motion[valid]**2))*10**(-25/20)
    motion+=np.random.default_rng(noise_seed+index).normal(0,sigma,motion.shape)
    metadata={'source':'independent_variable_mu_scalar_SH_Helmholtz_single_line',
              'frequency_hz':FREQUENCY,'displacement_unit':'m','phase_coherent':True,
              'phase_coherent_within_acquisition':True,'phase_coherent_between_acquisitions':False,
              'individual_acquisition':True,'simultaneous_source_count':1,
              'acquisition_index':index+1,'incoming_nominal_angle_deg':float(angle),
              'source_center_m':center,'source_phase_rad':phase,
              'source_kind':'finite_line_Gaussian_normal_superGaussian_transverse',
              'noise_snr_db':25,'noise_seed':noise_seed+index,'density_kg_m3':RHO,
              'poisson_ratio':NU,'forward_time_convention':'real(U exp(-i omega t))',
              'model':'scalar_antiplane_shear_not_full_3D_OCE',
              'description':'Ocho adquisiciones individuales: no sumar fasores entre adquisiciones.'}
    return {'motion':motion.astype(np.float32),'x_m':x,'row_m':x,'t_s':T,
            'valid_mask':valid,'plane_type':'enface','metadata':metadata}


def cell(items):
    result=np.empty((1,len(items)),dtype=object)
    for i,item in enumerate(items):result[0,i]=item
    return result


def export_grid(dx,angles,stem,save_alternate_noise):
    began=time.perf_counter()
    x,X,Y,E,head,tail,loss,operator,factor=build_operator(dx)
    selected=np.flatnonzero(abs(x)<=EXPORT_HALF+1e-12)
    xc=x[selected]; ix=np.ix_(selected,selected)
    Xc=X[ix]; Yc=Y[ix]; Ec=E[ix]; hc=head[ix]; tc=tail[ix]
    roi=(abs(Xc)<=ROI_HALF+1e-12)&(abs(Yc)<=ROI_HALF+1e-12)
    head_core=roi&(np.hypot(Xc-HEAD_CENTER[0],Yc)<=HEAD_RADIUS-np.sqrt(2)*WINDOW/2)
    tail_core=roi&(np.hypot(Xc-TAIL_CENTER[0],Yc)<=TAIL_RADIUS-np.sqrt(2)*WINDOW/2)
    bg=roi&(np.hypot(Xc-HEAD_CENTER[0],Yc)>=HEAD_RADIUS+np.sqrt(2)*WINDOW/2)& \
        (np.hypot(Xc-TAIL_CENTER[0],Yc)>=TAIL_RADIUS+np.sqrt(2)*WINDOW/2)
    inter=roi&~head_core&~tail_core&~bg
    hh=WINDOW/(2*dx); half_samples=max(1,int(np.floor(hh+16*np.spacing(hh))))
    kernel_size=2*half_samples+1
    assert abs(2*half_samples*dx-WINDOW)<1e-12,'Physical fit window must not shrink under discretization'
    cases=[]; alternate=[]; data8=[]; phasors=[]; diagnostics=[]; full_fields=[]
    for index,angle in enumerate(angles):
        source,normal,center,phase=source_for_angle(X,Y,angle,index)
        rhs=-source[1:-1,1:-1].ravel()
        solved=factor.solve(rhs)
        residual=float(np.linalg.norm(operator@solved-rhs)/np.linalg.norm(rhs))
        assert residual<1e-9,'Sparse PDE residual exceeds tolerance'
        U=np.zeros_like(source);U[1:-1,1:-1]=solved.reshape(X.shape[0]-2,X.shape[1]-2)
        # Conservative distance to the entire infinite support band includes
        # the finite aperture's actual force support, hence cannot overstate
        # clearance by using distance to the source center or to its ends.
        q=SOURCE_RADIUS+Xc*normal[0]+Yc*normal[1]
        distance=q-SOURCE_NORMAL_SUPPORT
        valid=(distance>=2*BACKGROUND_LAMBDA)&(np.maximum(abs(Xc),abs(Yc))<ABSORBER_START)
        complete=minimum_filter(valid.astype(np.uint8),size=kernel_size,mode='constant',cval=0).astype(bool)
        continuous_gap=distance-(abs(normal[0])+abs(normal[1]))*WINDOW/2
        absorber_gap=ABSORBER_START-(np.maximum(abs(Xc),abs(Yc))+WINDOW/2)
        far=roi&complete&(continuous_gap>=2*BACKGROUND_LAMBDA)&(absorber_gap>0)
        assert np.array_equal(far,roi),'All predeclared map windows must meet far-field requirements'
        scale=10e-9/np.sqrt(np.mean(np.abs(U[ix][valid])**2))
        U*=scale; source*=scale; Uc=U[ix]
        data=make_data(Uc,xc,valid,angle,index,phase,center,20262005)
        label=f'fish_individual_{int(angle):03d}deg'
        case={'label':label,'data':data,'f_hz':FREQUENCY,'frequency_hz':FREQUENCY,
              'density_kg_m3':RHO,'poisson_ratio':NU,'model':'bulk_shear','reverb_model':'scalar2d',
              'direction_deg':float(angle),'angle_deg':float(angle),'window_m':WINDOW,
              'truth_speed':np.sqrt(Ec/(2*(1+NU)*RHO)),'truth_young':Ec,'truth_young_pa':Ec,
              'inclusion_mask':hc|tc,'head_mask':hc,'tail_mask':tc,
              'head_core_mask':head_core,'tail_core_mask':tail_core,'background_mask':bg,
              'interface_mask':inter,'roi_mask':roi,'farfield_mask':far,'complete_window_mask':complete,
              'source_center_m':center,'source_direction_unit_vector':normal,
              'source_distance_from_support_m':distance,'continuous_window_source_gap_m':continuous_gap,
              'continuous_window_absorber_gap_m':absorber_gap,'background_wavelength_m':BACKGROUND_LAMBDA,
              'forward_phasor':Uc,'relative_sparse_residual':residual}
        cases.append(case);data8.append(data);phasors.append(Uc);full_fields.append(U)
        if save_alternate_noise:
            alternative=dict(case);alternative['label']=label+'_noise2'
            alternative['data']=make_data(Uc,xc,valid,angle,index,phase,center,20272005)
            alternate.append(alternative)
        source_norm=np.sum(abs(source)**2)
        diagnostics.append({'label':label,'angle_deg':float(angle),'source_center_m':center.tolist(),
                            'source_phase_rad':float(phase),'simultaneous_source_count':1,
                            'relative_sparse_residual':residual,'force_scale_n_m3':float(scale),
                            'source_l2_fraction_in_absorbing_rim':float(np.sum(abs(source[loss>0])**2)/source_norm),
                            'minimum_complete_roi_source_gap_wavelengths':float(continuous_gap[far].min()/BACKGROUND_LAMBDA),
                            'minimum_complete_roi_absorber_gap_mm':float(absorber_gap[far].min()*1e3),
                            'roi_pixels':int(roi.sum()),'head_core_pixels':int(head_core.sum()),
                            'tail_core_pixels':int(tail_core.sum()),'background_pixels':int(bg.sum())})
        print(f'{label}: residual {residual:.3g}; min window gap {diagnostics[-1]["minimum_complete_roi_source_gap_wavelengths"]:.5f} lambda',flush=True)
    geometry={'head_center_m':HEAD_CENTER,'head_radius_m':HEAD_RADIUS,'tail_center_m':TAIL_CENTER,
              'tail_radius_m':TAIL_RADIUS,'background_young_pa':BACKGROUND_E,
              'head_young_pa':INCLUSION_E,'tail_young_pa':INCLUSION_E,
              'center_distance_m':float(np.linalg.norm(HEAD_CENTER-TAIL_CENTER)),
              'axial_circle_overlap_m':float(HEAD_RADIUS+TAIL_RADIUS-np.linalg.norm(HEAD_CENTER-TAIL_CENTER)),
              'inclusion_policy':'union_of_two_circles_same_material_no_internal_material_interface'}
    common={'geometry':geometry,'x_m':xc,'row_m':xc,'t_s':T,'angles_deg':np.asarray(angles),
            'truth_speed':np.sqrt(Ec/(2*(1+NU)*RHO)),'truth_young':Ec,
            'inclusion_mask':hc|tc,'head_mask':hc,'tail_mask':tc,'head_core_mask':head_core,
            'tail_core_mask':tail_core,'background_mask':bg,'interface_mask':inter,'roi_mask':roi,
            'density_kg_m3':RHO,'poisson_ratio':NU,'f_hz':FREQUENCY,'window_m':WINDOW,
            'grid_dx_m':dx,'source_normal_support_m':SOURCE_NORMAL_SUPPORT,
            'independent_acquisitions':True,'phase_coherent_between_acquisitions':False}
    print('Saving '+stem+'.mat',flush=True)
    savemat(HERE/(stem+'.mat'),{**common,'cases':cell(cases),'data8':cell(data8),
                              'phasors8':cell(phasors)},do_compression=True,long_field_names=True)
    if alternate:
        savemat(HERE/(stem+'_noise2.mat'),{**common,'cases':cell(alternate),
                'data8':cell([c['data'] for c in alternate]),'phasors8':cell(phasors)},
                do_compression=True,long_field_names=True)
    np.savez_compressed(HERE/(stem+'_full_forward_phasors.npz'),x_m=x,E_pa=E,
                        absorbing_loss=loss,phasors=np.asarray(full_fields),angles_deg=np.asarray(angles))
    metadata={'stem':stem,'grid_count':len(x),'dx_m':dx,'background_points_per_wavelength':BACKGROUND_LAMBDA/dx,
              'domain_half_m':DOMAIN_HALF,'absorber_start_m':ABSORBER_START,'frequency_hz':FREQUENCY,
              'source_radius_m':SOURCE_RADIUS,'source_sigma_normal_m':SOURCE_SIGMA_NORMAL,
              'source_half_aperture_m':SOURCE_HALF_APERTURE,'source_relative_amplitude_cutoff':SOURCE_CUTOFF,
              'source_normal_support_m':SOURCE_NORMAL_SUPPORT,'window_m':WINDOW,'window_samples':kernel_size,
              'noise_snr_db':25,'primary_noise_base_seed':20262005,'secondary_noise_base_seed':20272005,
              'samples_per_acquisition':len(T),'phase_coherent_between_acquisitions':False,
              'single_source_per_acquisition':True,'simultaneous_field_sum_performed':False,
              'forward':'div(mu grad U)+rho omega^2 U=-F; harmonic face averages; complex mass sponge',
              'ground_truth':'material coefficient E; scalar-shear c=sqrt(E/[2rho(1+nu)]) conditional local reference',
              'field_is_lossless_in_roi':True,'full_elastodynamic_or_OCT_forward':False,
              'geometry':{key:value.tolist() if isinstance(value,np.ndarray) else value for key,value in geometry.items()},
              'cases':diagnostics,'elapsed_seconds':time.perf_counter()-began,
              'python':platform.python_version(),'numpy':np.__version__,'scipy':scipy.__version__,
              'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    (HERE/(stem+'_diagnostics.json')).write_text(json.dumps(metadata,indent=2),encoding='utf-8')
    print(f'{stem} completed in {metadata["elapsed_seconds"]:.1f} s',flush=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--grid-check',action='store_true',help='One angle at dx 1/16 mm, separate files')
    args=parser.parse_args()
    if args.grid_check:
        export_grid(1e-3/16,[0],'fish_grid_check_000deg',False)
    else:
        export_grid(1e-3/14,list(range(0,360,45)),'fish_individual_fields',True)


if __name__=='__main__':main()
