"""Pair actual FDTD and exact homogeneous mode on IDENTICAL physical XZ axes.
Noise seeds are independent but SNR and estimator settings are shared.
An inclusion gets a homogeneous analytic baseline, never a fictitious exact
heterogeneous solution. Numerical maps/manifest remain outside image gallery.
"""
from pathlib import Path
import sys,json,hashlib
import numpy as np
from scipy.io import loadmat,savemat
HERE=Path(__file__).resolve().parent;WF=HERE.parents[1]
sys.path.insert(0,str(HERE))

def observed(P,c,seed):
 t=np.arange(160)/(40*c['frequency_hz']);mask=np.asarray(c['valid_mask'],bool)
 gain=10e-9/np.sqrt(np.mean(np.abs(P[mask])**2)/2)
 wave=np.real(P[...,None]*gain*np.exp(2j*np.pi*c['frequency_hz']*t))
 noise=10e-9*10**(-30/20)*np.random.default_rng(seed).normal(size=wave.shape)
 return dict(motion=(wave+noise).astype(np.float32),x_m=c['x_m'],row_m=c['row_m'],t_s=t,valid_mask=mask,plane_type='bmode',metadata=dict(frequency_hz=c['frequency_hz'],snr_db=30,displacement_unit='m',noise_seed=seed,amplitude_scale_global=gain))

def pair(c,seed):
 x=np.asarray(c['x_m']);z=np.asarray(c['row_m']);X,Z=np.meshgrid(x,z);f=float(c['frequency_hz']);nu=float(c['poisson_ratio']);rho=float(c['density_kg_m3']);E= float(np.min(c['truth_young_pa']));speed=float(c['reference_speed_m_s']);k=2*np.pi*f/speed
 if c['model']=='rayleigh':
  cs=np.sqrt(E/(2*(1+nu)*rho));cp=np.sqrt(E*(1-nu)/((1+nu)*(1-2*nu)*rho));p=np.sqrt(1-(speed/cp)**2);q=np.sqrt(1-(speed/cs)**2)
  exact=(-np.exp(-p*k*Z)+2/(1+q*q)*np.exp(-q*k*Z))*np.exp(-1j*k*X)
  analytic_checks=dict(model='homogeneous traction-free Rayleigh halfspace eigenfunction',secular_speed=speed)
 else:
  from analytic_a0_xz import phasor
  exact,analytic_checks=phasor(x,z,E,nu,rho,float(c['thickness_m']),f,speed)
  exact=np.conj(exact)
 fdtd=np.asarray(c['fdtd_phasor_m']);a=observed(exact,c,seed);b=observed(fdtd,c,seed+1)
 c['exact_data']=a;c['fdtd_data']=b;c['exact_phasor_normalized']=exact/np.max(abs(exact));c['analytic_checks']=analytic_checks
 c['reference_scope']='homogeneous analytic baseline, not exact heterogeneous wavefield' if c['has_inclusion'] else 'exact homogeneous continuous modal reference vs numerical excited finite domain'
 c['homogeneous_reference_young_pa']=np.full(fdtd.shape,E)
 return c

def main():
 paired=[]
 # Original 12kPa Rayleigh is another independently retained mesh/source case.
 old=loadmat(WF/'results/bscan_fish_validation_2026-10-05/bscan_simulation/bscan_forward_cases.mat',simplify_cells=True)['cases'][-1]
 c=dict(label='rayleigh_12kPa_original_mesh010mm',model='rayleigh',frequency_hz=float(old['frequency_hz']),density_kg_m3=float(old['density_kg_m3']),poisson_ratio=float(old['poisson_ratio']),thickness_m=0.,reference_speed_m_s=float(old['truth_speed_m_s'][0,0]),wavelength_m=float(old['wavelength_bg_m']),x_m=old['data']['x_m'],row_m=old['data']['row_m'],fdtd_phasor_m=np.asarray(old['data']['motion'])[:,:,0].astype(complex),valid_mask=old['data']['valid_mask'],source_distance_m=old['source_distance_m'],truth_young_pa=old['truth_young_pa'],grid_cell_m=.1e-3,record_info=old['record_info'],has_inclusion=False)
 # Recover its measured phasor from the complete noisy time trace by LS;
 # this case is transparently identified, and not passed as noiseless FDTD.
 t=np.asarray(old['data']['t_s']);D=np.column_stack([np.cos(2*np.pi*c['frequency_hz']*t),np.sin(2*np.pi*c['frequency_hz']*t),np.ones_like(t)])
 fits=np.linalg.lstsq(D,np.asarray(old['data']['motion']).reshape(-1,len(t)).T,rcond=None)[0]
 c['fdtd_phasor_m']=(fits[0]-1j*fits[1]).reshape(c['truth_young_pa'].shape)
 c['fdtd_phasor_origin']='LS reconstructed from previously exported FDTD+30dB trace; its small residual noise remains'
 original_pair=pair(c,20261021)
 original_pair['fdtd_data']=old['data']
 original_pair['fdtd_phasor_origin']='original CPU FDTD trace, original 30dB noise retained without resynthesis'
 paired.append(original_pair)
 files={file.name:file for file in (HERE/'gpu').glob('*_forward.mat')}
 files.update({file.name:file for file in (HERE/'gpu_extended').glob('*_forward.mat')})
 for j,file in enumerate([files[name] for name in sorted(files)]):
  c=loadmat(file,simplify_cells=True)['case'];seed=20261030+int(hashlib.sha256(c['label'].encode()).hexdigest()[:8],16)
  paired.append(pair(c,seed))
 savemat(HERE/'paired_xz_cases.mat',dict(cases=np.array(paired,dtype=object)),do_compression=True,long_field_names=True)
 manifest=[dict(label=c['label'],model=c['model'],shape=c['fdtd_data']['motion'].shape,grid_cell_m=c['grid_cell_m'],reference_scope=c['reference_scope'],analytic_checks=c['analytic_checks'],record_info=c['record_info']) for c in paired]
 (HERE/'paired_case_manifest.json').write_text(json.dumps(manifest,indent=2,default=lambda x:x.tolist() if isinstance(x,np.ndarray) else str(x)),encoding='utf-8')
 print('PAIRED_XZ_PREPARATION_FINISHED',len(paired))
if __name__=='__main__':main()
