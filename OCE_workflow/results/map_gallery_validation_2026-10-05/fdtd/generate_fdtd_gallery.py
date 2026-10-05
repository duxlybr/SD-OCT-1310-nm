"""Actual unchanged elastodynamic FDTD: homogeneous/inclusion plate and block.

Sources and absorbing boundaries are outside the imaging ROI. Harmonic fields
are measured after solver stationarity checks. This script never paints a
heterogeneous phase field from a prescribed material-speed map.
"""
from pathlib import Path
import json
import os
import sys
import time
for name in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ[name] = "1"
import numpy as np
from scipy.io import savemat, loadmat

HERE=Path(__file__).resolve().parent
WORKFLOW=HERE.parents[2]
SIMULATOR=WORKFLOW.parent/".claude/worktrees/oct-simulator-gui-python-9d18ef/simulator"
sys.path[:0]=[str(SIMULATOR),str(WORKFLOW/"workflows")]
from export_simulator_wave_cases import independent_lamb_a0, independent_rayleigh_ratio
from octsim.excitation import ExcitationConfig, source_centers_mm
from octsim.geometry import Geometry, Layer, Inclusion
from octsim.materials import Material
from octsim.fdtd import FDTDSettings, FDTDSolver, MODEL_VERSION


class SnapshotBackend:
    """Instance-local adapter preserves host snapshots before accumulators clear."""
    def __init__(self,backend):self.wrapped=backend
    def __getattr__(self,name):return getattr(self.wrapped,name)
    def asnumpy(self,value):return np.array(self.wrapped.asnumpy(value),copy=True)


def serialise(value):
    if isinstance(value,np.generic):return value.item()
    if isinstance(value,np.ndarray):return value.tolist()
    return str(value)


def main():
    cases=[];manifest=[]
    if (HERE/"fdtd_gallery_cases.mat").exists():
        saved=loadmat(HERE/"fdtd_gallery_cases.mat",simplify_cells=True)["cases"]
        cases=[saved] if isinstance(saved,dict) else list(saved)
        manifest=json.loads((HERE/"fdtd_gallery_manifest.json").read_text(encoding="utf-8"))
        for existing in cases:
            existing["source_fwhm_m"]=float(existing["source_width_m"])
            existing["source_support_halfwidth_m"]=float(existing["source_width_m"])*np.sqrt(np.log(1000)/(4*np.log(2)))
        print("Resuming completed cases:", [case["label"] for case in cases],flush=True)
    background=Material(name="background_12kPa",E_kPa=12,eta_Pa_s=0,nu=.495,rho=1000)
    frequency=1000.;source_x=-5.5; radius=1.5; centre_x=1.5
    # The last (soft Rayleigh) case is a subsequent check of the family-wise
    # method choice; estimator settings remain fixed before its generation.
    for plate,inclusion_kpa in [(True,None),(True,24),(False,None),(False,24),(False,6)]:
        with_inclusion=inclusion_kpa is not None
        label=("lamb_a0" if plate else "rayleigh")+(f"_inclusion_{inclusion_kpa}kPa" if with_inclusion else "_homogeneous_12kPa")
        if any(case["label"]==label for case in cases):continue
        inclusion_material=Material(name=f"inclusion_{inclusion_kpa or 24}kPa",
                                    E_kPa=inclusion_kpa or 24,eta_Pa_s=0,nu=.495,rho=1000)
        height=.6 if plate else 4.
        cell=.10 if plate else .18
        inclusions=[]
        if with_inclusion:
            inclusions=[Inclusion(inclusion_material,shape="cilindro",axis="z",
                                 center_mm=(centre_x,0,height/2),size_mm=(radius,radius,height))]
        geometry=Geometry(size_x_mm=14,size_y_mm=7,size_z_mm=height,
                          layers=[Layer(background,0)],inclusions=inclusions,
                          lateral="absorbente",bottom="libre" if plate else "absorbente")
        excitation=ExcitationConfig(mode="arf_sin_contacto",regime="armonico",pressure_MPa=.007,
                                    shape="linea",center_x_mm=source_x,size_a_mm=.6,size_b_mm=12,
                                    harmonic_hz=frequency,n_sources=1,ring_radius_mm=0,
                                    random_phase=False,ramp_periods=2)
        settings=FDTDSettings(cell_mm=cell,backend="cpu",pml_cells=round(1.2/cell),
                              record_stride=1,record_margin_mm=0,record_depth_mm=.25,
                              harmonics=1,harmonic_window_periods=2,harmonic_min_periods=12,
                              harmonic_max_periods=24,harmonic_tol=.005)
        last=[-1.];started=time.perf_counter()
        def progress(fraction,message):
            if "periodos" in message or fraction-last[0]>.15:
                print(label,message,flush=True);last[0]=fraction
        solver=FDTDSolver(geometry,excitation,settings,(-2,5,-2.5,2.5),progress=progress)
        # CPU Backend.asnumpy returns an alias. run_harmonic clears its
        # accumulation arrays after taking snapshots, so aliasing otherwise
        # destroys exported fields and makes the convergence test tautological.
        # Copy ONLY this instance's host snapshots; no equations or simulator
        # source files are changed by the observational export workaround.
        solver.backend=SnapshotBackend(solver.backend)
        print(label,solver.describe(),flush=True)
        record=solver.run_harmonic()
        # Surface sample is selected independently at each recorded position.
        phasor=np.array([record.U[1][ix,iy,record.surface_k[ix,iy]]
                         for iy in range(record.y_m.size) for ix in range(record.x_m.size)])
        phasor=phasor.reshape(record.y_m.size,record.x_m.size)
        if not np.all(np.isfinite(phasor)) or not np.any(np.abs(phasor)>0):
            raise RuntimeError("Invalid null/nonfinite forward field; cannot generate a propagation map")
        t=np.arange(80)*50e-6
        motion=np.real(phasor[:,:,None]*np.exp(2j*np.pi*frequency*t))
        rng=np.random.default_rng(20261005+len(cases))
        sigma=np.sqrt(np.mean(motion**2))*10**(-40/20)
        motion=motion+sigma*rng.normal(size=motion.shape)
        X,Y=np.meshgrid(record.x_m,record.y_m)
        mask=(X-source_x*1e-3)>0
        if plate:
            reference_speed=independent_lamb_a0(background.E,background.nu,background.rho,height*1e-3,frequency)
        else:
            reference_speed=independent_rayleigh_ratio(background.nu)*background.cs
        material_ids=geometry.material_id_map(X*1e3,Y*1e3,np.full(X.shape,.01))
        truth=np.where(material_ids==2,inclusion_material.E,background.E)
        cases.append(dict(label=label,model="lamb_a0_free" if plate else "rayleigh",f_hz=frequency,
                          rho=background.rho,nu=background.nu,thickness_m=height*1e-3 if plate else 0.,
                          lambda_bg_m=reference_speed/frequency,reference_speed_bg_m_s=reference_speed,
                          source_center_m=np.array([source_x,0.])*1e-3,source_width_m=.6e-3,
                          source_fwhm_m=.6e-3,
                          source_support_halfwidth_m=.6e-3*np.sqrt(np.log(1000)/(4*np.log(2))),
                          farfield_source_kind="line",has_inclusion=with_inclusion,
                          truth_young_pa=truth,inclusion_mask=material_ids==2,
                          inclusion_center_m=np.array([centre_x,0.])*1e-3,inclusion_radius_m=radius*1e-3,
                          boundary_exclusion_m=0.,record_info=record.info,
                          data=dict(motion=motion.astype(np.float32),x_m=record.x_m,row_m=record.y_m,t_s=t,
                                    valid_mask=mask,plane_type="enface",
                                    metadata=dict(source="actual_claude_elastodynamic_harmonic_fdtd",frequency_hz=frequency,
                                                  displacement_unit="m",phase_coherent=True,model_version=MODEL_VERSION,
                                                  solver_convergence_relative=record.info["convergencia_rel"],
                                                  snr_db=40,geometry_height_m=height*1e-3,cell_m=cell*1e-3))))
        manifest.append(dict(label=label,geometry=geometry.to_dict(),excitation=excitation.to_dict(),
                             settings=settings.to_dict(),record_info=record.info,
                             source_centers_mm=source_centers_mm(excitation),elapsed_s=time.perf_counter()-started,
                             cpu_snapshot_copy_workaround=True,
                             nominal_plate_thickness_mm=height if plate else None,
                             axial_solid_node_count=int(np.count_nonzero(solver.grid.ids[solver.grid.nx//2,solver.grid.ny//2,:])),
                             wavelength_bg_m=reference_speed/frequency,
                             warning="Continuum local model is conditional in heterogeneous regions. Free-plate boundaries are discretized; record cell/thickness resolution."))
        solver.release()
        savemat(HERE/"fdtd_gallery_cases.mat",dict(cases=np.array(cases,dtype=object),completion_count=len(cases)),do_compression=True)
        (HERE/"fdtd_gallery_manifest.json").write_text(json.dumps(manifest,indent=2,default=serialise),encoding="utf-8")
        print(label,"DONE",len(cases),manifest[-1]["elapsed_s"],flush=True)
    print("FDTD_GALLERY_EXPORT_FINISHED",flush=True)


if __name__=="__main__":main()
