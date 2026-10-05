"""Independent actual 3D FDTD XZ cases, saved per case for bounded/resumable runs.
No prescribed heterogeneous phase; matched analytic fields are generated separately.
"""
from pathlib import Path
import os,sys,json,time,argparse
for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS'):os.environ[key]='1'
import numpy as np
from scipy.io import savemat
HERE=Path(__file__).resolve().parent; WF=HERE.parents[1]
SIM=WF.parent/'.claude/worktrees/oct-simulator-gui-python-9d18ef/simulator'
sys.path[:0]=[str(SIM),str(WF/'workflows'),str(WF/'results/map_gallery_validation_2026-10-05/fdtd')]
from octsim.materials import Material
from octsim.geometry import Geometry,Layer,Inclusion
from octsim.excitation import ExcitationConfig
from octsim.fdtd import FDTDSolver,FDTDSettings,surface_k_index,MODEL_VERSION
from export_simulator_wave_cases import independent_rayleigh_ratio,independent_lamb_a0
from generate_fdtd_gallery import SnapshotBackend

BACKEND='cpu'
PPW=20.
MAX_PERIODS=36
CONFIGS=[
 dict(label='lamb_A0_12kPa_h060mm_500Hz',E=12.,nu=.495,rho=1000.,f=500.,plate=True,h=.6),
 dict(label='rayleigh_12kPa_point_source_1000Hz',E=12.,nu=.495,rho=1000.,f=1000.,plate=False,source_shape='punto'),
 dict(label='rayleigh_6kPa_1000Hz',E=6.,nu=.495,rho=1000.,f=1000.,plate=False),
 dict(label='rayleigh_24kPa_1000Hz',E=24.,nu=.495,rho=1000.,f=1000.,plate=False),
 dict(label='rayleigh_12kPa_nu045_1500Hz',E=12.,nu=.45,rho=1000.,f=1500.,plate=False),
 dict(label='rayleigh_12kPa_stiff_inclusion',E=12.,nu=.495,rho=1000.,f=1000.,plate=False,inclusion=True),
 dict(label='lamb_A0_12kPa_h060mm_1000Hz',E=12.,nu=.495,rho=1000.,f=1000.,plate=True,h=.6),
 dict(label='lamb_A0_12kPa_h120mm_1000Hz',E=12.,nu=.495,rho=1000.,f=1000.,plate=True,h=1.2),
]

def run(c):
 file=HERE/(c['label']+'_forward.mat')
 if file.exists():print(c['label'],'REUSE',flush=True);return
 mat=Material(name=c['label'],E_kPa=c['E'],eta_Pa_s=0,nu=c['nu'],rho=c['rho'])
 speed=independent_lamb_a0(mat.E,mat.nu,mat.rho,c['h']*1e-3,c['f']) if c['plate'] else independent_rayleigh_ratio(mat.nu)*mat.cs
 lam=speed/c['f'];cell=lam/PPW
 if c['plate']:cell=min(cell,c['h']*1e-3/12)
 height=c['h'] if c['plate'] else 1.8*lam*1e3
 inclusions=[]
 if c.get('inclusion',False):
  im=Material(name='stiff24',E_kPa=24,eta_Pa_s=0,nu=c['nu'],rho=c['rho'])
  inclusions=[Inclusion(im,shape='esfera',center_mm=(1.25*lam*1e3,0,.55*lam*1e3),size_mm=(.55*lam*1e3,0,0))]
 geom=Geometry(size_x_mm=9*lam*1e3,size_y_mm=3*lam*1e3,size_z_mm=height,layers=[Layer(mat,0)],inclusions=inclusions,lateral='absorbente',bottom='libre' if c['plate'] else 'absorbente')
 ex=ExcitationConfig(mode='arf_sin_contacto',regime='armonico',pressure_MPa=.007,shape=c.get('source_shape','linea'),size_a_mm=.3*lam*1e3,size_b_mm=8*lam*1e3,center_x_mm=-3*lam*1e3,harmonic_hz=c['f'],n_sources=1,ring_radius_mm=0,random_phase=False,ramp_periods=2)
 settings=FDTDSettings(cell_mm=cell*1e3,backend=BACKEND,pml_cells=12,record_stride=1,record_margin_mm=0,record_depth_mm=height,harmonics=1,harmonic_window_periods=2,harmonic_min_periods=12,harmonic_max_periods=MAX_PERIODS,harmonic_tol=.005)
 def progress(fr,message):
  if 'periodos' in message:print(c['label'],message,flush=True)
 start=time.perf_counter();solver=FDTDSolver(geom,ex,settings,(-.5*lam*1e3,2.8*lam*1e3,-.05*lam*1e3,.05*lam*1e3),progress=progress)
 solver.backend=SnapshotBackend(solver.backend);print(c['label'],solver.describe(),flush=True)
 rec=solver.run_harmonic();jc=solver._slice_index();sk=surface_k_index(solver.grid.ids)[solver.grid.nx//2,jc];top=rec.slice_z_m[sk]
 keepx=(rec.slice_x_m>=-.5*lam)&(rec.slice_x_m<=2.8*lam)
 depth=rec.slice_z_m-top;depth_max=(height*1e-3-cell*.8) if c['plate'] else .8*lam
 keepz=(depth>=-1e-12)&(depth<=depth_max+1e-12)
 x=rec.slice_x_m[keepx];z=depth[keepz];P=rec.slice_U[1][keepx,:][:,keepz].T.copy();ids=rec.slice_ids[keepx,:][:,keepz].T
 assert np.all(np.isfinite(P)) and np.any(abs(P)>0)
 X,Z=np.meshgrid(x,z);half=ex.size_a_mm*1e-3*np.sqrt(np.log(1000)/(4*np.log(2)));dist=X-ex.center_x_mm*1e-3-half
 mask=(dist>=2*lam)&(ids!=0);E=geom.material_id_map(X*1e3,np.zeros_like(X), (Z+top)*1e3)
 E=np.where(E==2,24000.,mat.E) if c.get('inclusion',False) else np.full(P.shape,mat.E)
 case=dict(label=c['label'],model='lamb_a0_free' if c['plate'] else 'rayleigh',frequency_hz=c['f'],density_kg_m3=c['rho'],poisson_ratio=c['nu'],thickness_m=height*1e-3 if c['plate'] else 0.,reference_speed_m_s=speed,wavelength_m=lam,x_m=x,row_m=z,fdtd_phasor_m=P,valid_mask=mask,source_distance_m=dist,truth_young_pa=E,grid_cell_m=cell,record_info=rec.info,has_inclusion=bool(c.get('inclusion',False)),actual_axial_solid_nodes=int(np.count_nonzero(solver.grid.ids[solver.grid.nx//2,jc,:])),source_surface_z_m=top,source_support_halfwidth_m=half)
 savemat(file,dict(case=case),do_compression=True,long_field_names=True)
 manifest=dict(config=c,geometry=geom.to_dict(),excitation=ex.to_dict(),settings=settings.to_dict(),record_info=rec.info,seconds=time.perf_counter()-start,model_version=MODEL_VERSION,cpu_snapshot_copy_workaround=True,reference_scope='exact homogeneous modal reference; heterogeneous constitutive map is not an exact wave-phase field')
 (HERE/(c['label']+'_manifest.json')).write_text(json.dumps(manifest,indent=2,default=lambda v:v.tolist() if isinstance(v,np.ndarray) else str(v)),encoding='utf-8')
 solver.release();print(c['label'],'SAVED',manifest['seconds'],flush=True)

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('--family',choices=['rayleigh','lamb','all'],default='all');ap.add_argument('--backend',choices=['cpu','gpu'],default='cpu');ap.add_argument('--output-subdir',default='');ap.add_argument('--case',default='');ap.add_argument('--ppw',type=float,default=20.);ap.add_argument('--max-periods',type=int,default=36);a=ap.parse_args()
 BACKEND=a.backend;PPW=a.ppw;MAX_PERIODS=a.max_periods
 if a.output_subdir:
  HERE=HERE/a.output_subdir;HERE.mkdir(exist_ok=True)
 for c in CONFIGS:
  if (not a.case or c['label']==a.case) and (a.family=='all' or (a.family=='lamb')==c['plate']):run(c)
 print('FDTD_VARIETY_FINISHED',a.family,flush=True)
