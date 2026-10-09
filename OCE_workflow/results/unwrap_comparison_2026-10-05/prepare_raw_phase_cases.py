"""Impose an explicit wrapped optical measurement on existing forward fields.
No filtering, increments, Loupas or unwrap is applied before saving raw phase.
This is a controlled phase observation model, not a full OCT speckle solver.
"""
from pathlib import Path
import hashlib, json
import numpy as np
from scipy.io import loadmat, savemat

HERE=Path(__file__).resolve().parent
paired=loadmat(HERE.parent/'fdtd_exact_comparison_2026-10-05/paired_xz_cases.mat',simplify_cells=True)['cases']
beta=4*np.pi*1.4/1310e-9

def observation(P,c,source,noise=.03,speckle=False,amplitude=.8e-6,shuffle=False):
    t=np.arange(160)/(40*float(c['frequency_hz']))
    shape=P.shape; seed=int(hashlib.sha256((c['label']+source).encode()).hexdigest()[:8],16)
    rng=np.random.default_rng(seed)
    carrier=(rng.uniform(-np.pi,np.pi,shape) if speckle else
             0.7*np.linspace(-1,1,shape[0])[:,None]+.25*np.linspace(-1,1,shape[1])[None,:])
    # Uniform source normalization preserves the forward phase and attenuation.
    u=amplitude*np.real((P/np.max(abs(P)))[...,None]*np.exp(2j*np.pi*c['frequency_hz']*t))
    truth=carrier[...,None]+beta*u
    measured=truth+noise*rng.normal(size=truth.shape)
    if shuffle:
        measured=measured[:,:,rng.permutation(len(t))]
    raw=np.angle(np.exp(1j*measured)).astype(np.float32)
    mask=np.asarray(c['valid_mask'],bool)
    return dict(raw_phase_rad=raw,x_m=c['x_m'],row_m=c['row_m'],t_s=t,
                valid_mask=mask,plane_type='bmode',phase_truth_rad=truth.astype(np.float32),
                metadata=dict(measurement_model='wrapped optical phase: static carrier + 4pi*n*u/lambda + Gaussian phase noise',
                wavelength_m=1310e-9,refractive_index=1.4,phase_noise_sigma_rad=noise,
                peak_displacement_m=amplitude,static_carrier='random independent per pixel' if speckle else 'smooth',
                random_seed=seed,temporal_shuffle=shuffle,
                maximum_true_temporal_step_rad=float(np.max(abs(np.diff(truth,axis=2))))))

def make(c,**kw):
    keep=['label','model','frequency_hz','density_kg_m3','poisson_ratio','thickness_m',
          'reference_speed_m_s','wavelength_m','x_m','row_m','valid_mask','source_distance_m',
          'truth_young_pa','grid_cell_m','has_inclusion','reference_scope','record_info']
    out={key:c[key] for key in keep};out['pd_geometry']='lateral'
    out['exact_raw']=observation(c['exact_phasor_normalized'],c,'exact',**kw)
    out['fdtd_raw']=observation(c['fdtd_phasor_m'],c,'fdtd',**kw)
    return out

cases=[make(c) for c in paired]
parent=next(c for c in paired if c['label']=='lamb_A0_12kPa_h060mm_1000Hz')
for suffix,kw in [('random_static_carrier',dict(speckle=True)),
                  ('phase_noise020rad',dict(noise=.20)),
                  ('temporal_alias',dict(amplitude=2.5e-6)),
                  ('temporal_shuffle_null',dict(shuffle=True))]:
    c=dict(parent);c['label']=parent['label']+'_'+suffix;cases.append(make(c,**kw))
# A genuinely oblique bulk XZ wave checks both components of phase derivative2D.
x=np.linspace(0,8e-3,81);z=np.linspace(0,4e-3,41);X,Z=np.meshgrid(x,z)
f=1000.;speed=2.;k=2*np.pi*f/speed;P=np.exp(-1j*k*(np.cos(np.pi/6)*X+np.sin(np.pi/6)*Z))
c=dict(label='bulk_shear_oblique_30deg',model='bulk_shear',frequency_hz=f,density_kg_m3=1000.,
       poisson_ratio=.495,thickness_m=0.,reference_speed_m_s=speed,wavelength_m=speed/f,
       x_m=x,row_m=z,valid_mask=np.ones(P.shape,bool),source_distance_m=np.full(P.shape,.1),
       truth_young_pa=np.full(P.shape,2*(1+.495)*1000*speed**2),grid_cell_m=1e-4,has_inclusion=False,
       reference_scope='analytic oblique bulk wave; second column is an independent phase-noise realization, not FDTD',
       record_info={},exact_phasor_normalized=P,fdtd_phasor_m=P)
bulk=make(c);bulk['pd_geometry']='in_plane';cases.append(bulk)
savemat(HERE/'raw_phase_cases.mat',dict(cases=np.array(cases,dtype=object)),do_compression=True,long_field_names=True)
manifest=[dict(label=c['label'],model=c['model'],pd_geometry=c['pd_geometry'],reference_scope=c['reference_scope'],
               shape=c['exact_raw']['raw_phase_rad'].shape,exact=c['exact_raw']['metadata'],fdtd=c['fdtd_raw']['metadata']) for c in cases]
(HERE/'raw_phase_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('RAW_PHASE_CASES_SAVED',len(cases))
