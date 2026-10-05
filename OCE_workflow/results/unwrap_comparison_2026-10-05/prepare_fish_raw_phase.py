"""Raw optical observation of eight separate scalar-SH fish excitations."""
from pathlib import Path
import numpy as np
from scipy.io import savemat
HERE=Path(__file__).resolve().parent
a=np.load(HERE.parent/'bscan_fish_validation_2026-10-05/fish_forward/fish_individual_fields_full_forward_phasors.npz')
x=a['x_m'];indices=np.flatnonzero(abs(x)<=6e-3)[::2];x=x[indices]
E=a['E_pa'][np.ix_(indices,indices)];f=1800.;t=np.arange(160)/(40*f)
beta=4*np.pi*1.4/1310e-9;fields=[]
for j,P in enumerate(a['phasors']):
    P=P[np.ix_(indices,indices)];rng=np.random.default_rng(20261100+j)
    carrier=rng.uniform(-np.pi,np.pi,P.shape)
    u=.8e-6*np.real((P/np.max(abs(P)))[...,None]*np.exp(2j*np.pi*f*t))
    raw=np.angle(np.exp(1j*(carrier[...,None]+beta*u+.03*rng.normal(size=u.shape))))
    fields.append(dict(raw_phase_rad=raw.astype(np.float32),x_m=x,row_m=x,t_s=t,
        valid_mask=np.ones(P.shape,bool),plane_type='enface',metadata=dict(
        independent_excitation=True,simultaneous_sum=False,angle_deg=float(a['angles_deg'][j]),
        raw_phase_model='independent static optical carrier + 4pi*n*u/lambda + 0.03rad noise',
        forward='scalar SH div(mu grad U), not full-vector FDTD nor OCT speckle solver')))
savemat(HERE/'fish_raw_phase.mat',dict(data8=np.array(fields,dtype=object),truth_young_pa=E,
    x_m=x,angles_deg=a['angles_deg'],frequency_hz=f),do_compression=True,long_field_names=True)
print('FISH_RAW_PHASE_SAVED',len(fields),fields[0]['raw_phase_rad'].shape)
