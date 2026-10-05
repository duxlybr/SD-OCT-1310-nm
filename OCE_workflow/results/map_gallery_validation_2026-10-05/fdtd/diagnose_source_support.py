"""Read-only numerical diagnosis of the existing simulator's source/support."""
from pathlib import Path
import json, os, sys
for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ[name]="1"
import numpy as np
HERE=Path(__file__).resolve().parent
WORKFLOW=HERE.parents[2]
sys.path.insert(0,str(WORKFLOW.parent/".claude/worktrees/oct-simulator-gui-python-9d18ef/simulator"))
from octsim.geometry import Geometry, Layer
from octsim.materials import Material
from octsim.excitation import ExcitationConfig, harmonic_group_signals, source_phases
from octsim.fdtd import FDTDSettings,FDTDSolver

def main():
    material=Material(name="diagnostic_12kPa",E_kPa=12,eta_Pa_s=0,nu=.495,rho=1000)
    geometry=Geometry(size_x_mm=14,size_y_mm=7,size_z_mm=.6,layers=[Layer(material,0)],
                      lateral="absorbente",bottom="libre")
    excitation=ExcitationConfig(mode="arf_sin_contacto",regime="armonico",pressure_MPa=.007,
                               shape="linea",center_x_mm=-5.5,size_a_mm=.6,size_b_mm=12,
                               harmonic_hz=1000,n_sources=1,ramp_periods=2)
    settings=FDTDSettings(cell_mm=.1,backend="cpu",pml_cells=12,record_stride=1,
                          record_margin_mm=0,record_depth_mm=.25,harmonics=1)
    solver=FDTDSolver(geometry,excitation,settings,(-2,5,-2.5,2.5))
    solver._allocate(solver.dt_max*.99,np.pi*1000)
    idx=np.asarray(solver.src_idx); bz=solver.m["bz"].reshape(-1)[idx]
    _,_,k=np.unravel_index(idx,solver.grid.shape)
    sig=harmonic_group_signals(excitation,np.array([.0005,.002,.00225]),source_phases(excitation))
    result={"source_count":int(idx.size),"source_force_minmax": [float(solver.src_w.min()),float(solver.src_w.max())],
            "source_bz_minmax":[float(bz.min()),float(bz.max())],"source_bz_nonzero":int(np.count_nonzero(bz)),
            "source_k_unique":np.unique(k).tolist(),"source_signals":sig.tolist(),
            "grid_material_ids":np.unique(solver.grid.ids).tolist(),"table_rho":solver.tables["rho"].tolist(),
            "record_region":str(solver.region),"region_surface_k_minmax":[int(solver._region_surface_k().min()),int(solver._region_surface_k().max())]}
    accumulator=np.array([1+2j,3+4j],np.complex64)
    host_snapshot=solver.backend.asnumpy(accumulator)
    independent_snapshot=solver.backend.asnumpy(accumulator).copy()
    result["cpu_host_snapshot_shares_accumulator_memory"]=bool(np.shares_memory(host_snapshot,accumulator))
    accumulator.fill(0)
    result["host_snapshot_norm_after_accumulator_clear"]=float(np.linalg.norm(host_snapshot))
    result["copied_snapshot_norm_after_accumulator_clear"]=float(np.linalg.norm(independent_snapshot))
    result["diagnosis"]="CPU harmonic export aliases accumulator; clearing accumulator erases returned spectrum and previous convergence snapshot. Source injection and recorded ROI are nonzero."
    source_mask=np.zeros(solver.grid.shape,bool); source_mask.reshape(-1)[idx]=True
    result["source_rho_ids_neighbours"]=[np.unique(solver.grid.ids[source_mask]).tolist(),np.unique(solver.grid.ids[np.roll(source_mask,1,axis=2)]).tolist()]
    flat=solver.f["vz"].reshape(-1)
    result["source_flatten_shares_memory"]=bool(np.shares_memory(flat,solver.f["vz"]))
    solver._step(np.ones(1,np.float32))
    result["first_step_max_abs_vz"]=float(np.max(abs(solver.f["vz"])))
    result["first_step_max_abs_stress"]=float(np.max(abs(solver.f["szz"])))
    for step in range(99):solver._step(np.ones(1,np.float32))
    result["step100_max_abs_vz"]=float(np.max(abs(solver.f["vz"])))
    result["step100_max_record_abs_vz"]=float(np.max(abs(solver.region.view(solver.f["vz"]))))
    (HERE/"source_support_diagnosis.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    print(json.dumps(result,indent=2),flush=True)
    solver.release()

if __name__=="__main__":main()
