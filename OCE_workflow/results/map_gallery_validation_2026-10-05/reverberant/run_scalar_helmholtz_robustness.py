"""Three sequential observational checks outside the nominal map gallery.

Sources/materials/estimator windows stay fixed physically. Two new source
phase seeds probe field realization dependence; one finer grid probes mesh
stability. Each complete PDE forward solve and MATLAB inference is saved in
separate files, so neither nominal fixture nor map PNGs are overwritten.
"""
from pathlib import Path
import csv
import json
import subprocess
import shutil
import numpy as np
from scipy.io import savemat
import generate_scalar_helmholtz_fields as forward_module


def trial_case(name, dx, source_seed):
    half_domain=12e-3
    n=int(round(2*half_domain/dx))+1
    x=(np.arange(n)-(n-1)/2)*dx; y=x.copy()
    X,Y=np.meshgrid(x,y); radius=np.hypot(X,Y)
    density=1000.; nu=.495; f=1800.; inclusion_radius=2.2e-3
    E=np.full((n,n),12000.); E[radius<=inclusion_radius]=24000.
    U,sources,absorbing,residual=forward_module.forward(E,x,y,f,density,nu,source_seed)
    wavelength=np.sqrt(12000/(2*(1+nu)*density))/f
    distance=np.min(np.hypot(X[:,:,None]-sources[:,0],Y[:,:,None]-sources[:,1]),axis=2)
    support=(np.maximum(abs(X),abs(Y))<forward_module.ABSORBER_START_M)
    support &= distance>=2*wavelength+3*forward_module.SOURCE_SIGMA_M
    U=U/np.sqrt(np.mean(np.abs(U[support])**2))*10e-9
    t=np.arange(240)/(40*f)
    motion=np.real(U[:,:,None]*np.exp(-2j*np.pi*f*t))
    noise=np.sqrt(np.mean(motion[support]**2))*10**(-25/20)
    # Keep measurement-noise seed fixed across source-phase trials. The
    # nominal generator consumes its first draw for the homogeneous case;
    # replay that draw so dx=.1 mm trials match nominal stiff-case noise.
    rng=np.random.default_rng(20261005)
    discarded=rng.standard_normal((241,241,240)); del discarded
    motion+=rng.normal(0,noise,motion.shape)
    farfield=(radius<=4.8e-3)&(np.maximum(abs(X),abs(Y))<=4.5e-3)
    half_window=forward_module.WINDOW_HALF_WIDTH_M
    core=farfield&(radius<=inclusion_radius-np.sqrt(2)*half_window)
    background=farfield&(radius>=inclusion_radius+np.sqrt(2)*half_window)
    interface=farfield&~core&~background
    window_dx=np.maximum(abs(X[:,:,None]-sources[:,0])-half_window,0)
    window_dy=np.maximum(abs(Y[:,:,None]-sources[:,1])-half_window,0)
    source_gap=np.min(np.hypot(window_dx,window_dy),axis=2)-3*forward_module.SOURCE_SIGMA_M
    absorber_gap=forward_module.ABSORBER_START_M-(np.maximum(abs(X),abs(Y))+half_window)
    assert np.all(source_gap[farfield]>=2*wavelength)
    assert np.all(absorber_gap[farfield]>0)
    case={'label':name,'f_hz':f,'truth_speed':np.sqrt(E/(2*(1+nu)*density)),
          'truth_young':E,'density_kg_m3':density,'poisson_ratio':nu,
          'inclusion_radius_m':inclusion_radius,'core_mask':core,
          'background_mask':background,'interface_mask':interface,
          'farfield_mask':farfield,'source_centers_m':sources,
          'absorbing_rim':absorbing,'forward_phasor':U,
          'data':{'motion':motion.astype(np.float32),'x_m':x,'row_m':y,'t_s':t,
                  'valid_mask':support,'plane_type':'enface',
                  'metadata':{'source':'independent_divergence_form_scalar_SH_Helmholtz',
                              'frequency_hz':f,'phase_coherent':True,'displacement_unit':'m',
                              'description':'Ensayo observacional escalar 2D: inclusión rígida, sin cambiar mapas nominales.'}}}
    diagnostics={'case':name,'dx_m':dx,'grid_points':n,'source_seed':source_seed,
                 'measurement_noise_seed':20261005,'noise_preamble_shape':[241,241,240],
                 'input_snr_db':25,'f_hz':f,'E_background_pa':12000.,'E_inclusion_pa':24000.,
                 'relative_sparse_residual':residual,
                 'minimum_aperture_source_gap_wavelengths':float(source_gap[farfield].min()/wavelength),
                 'minimum_aperture_absorber_gap_m':float(absorber_gap[farfield].min())}
    return case,diagnostics


def main():
    root=Path(__file__).resolve().parent
    matlab=shutil.which('matlab.exe')
    if not matlab: raise RuntimeError('MATLAB executable not found')
    trials=[('source_seed_20261006',.1e-3,20261006),
            ('source_seed_20261007',.1e-3,20261007),
            ('grid_refinement_dx_0p075mm',.075e-3,20261005)]
    diagnostics=[]; records=[]
    for label,dx,seed in trials:
        print(f'Generating stiff inclusion trial {label}',flush=True)
        case,diag=trial_case(label,dx,seed)
        suffix='_robustness_'+label
        cell=np.empty((1,1),dtype=object); cell[0,0]=case
        artifact=root/('scalar_helmholtz'+suffix+'_fields.mat')
        savemat(artifact,{'cases':cell},do_compression=True,long_field_names=True)
        del case,cell
        print(f'Running MATLAB for {label}',flush=True)
        escaped=str(root).replace('\\','/').replace("'","''")
        command=f"addpath('{escaped}'); estimate_scalar_helmholtz_maps('{escaped}','{suffix}');"
        subprocess.run([matlab,'-singleCompThread','-batch',command,
                        '-logfile',str(root/('matlab_'+label+'.log'))],check=True)
        diagnostics.append(diag)
        with (root/('scalar_helmholtz'+suffix+'_metrics.csv')).open(encoding='utf-8-sig',newline='') as stream:
            records.extend(csv.DictReader(stream))
    with (root/'scalar_helmholtz_robustness_metrics.csv').open('w',encoding='utf-8',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(records[0])); writer.writeheader(); writer.writerows(records)
    (root/'scalar_helmholtz_robustness_diagnostics.json').write_text(json.dumps(diagnostics,indent=2),encoding='utf-8')
    print('Completed three observational checks without changing nominal maps.',flush=True)


if __name__=='__main__': main()
