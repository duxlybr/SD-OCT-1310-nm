"""Independent far-field Rayleigh modal and true FDTD XZ displacement cases."""
from pathlib import Path
import json
import os
import sys
for key in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ[key] = "1"
import numpy as np
from scipy.io import savemat

HERE = Path(__file__).resolve().parent
WORKFLOW = HERE.parents[2]
SIMULATOR = WORKFLOW.parent / ".claude/worktrees/oct-simulator-gui-python-9d18ef/simulator"
sys.path[:0] = [str(SIMULATOR), str(WORKFLOW / "workflows"),
               str(WORKFLOW / "results/map_gallery_validation_2026-10-05/fdtd")]
from export_simulator_wave_cases import independent_rayleigh_ratio
from generate_fdtd_gallery import SnapshotBackend
from octsim.materials import Material
from octsim.geometry import Geometry, Layer
from octsim.excitation import ExcitationConfig
from octsim.fdtd import FDTDSolver, FDTDSettings, surface_k_index


def observed(phasor, x, z, mask, f, noise_db, seed, description):
    t = np.arange(160) / (40 * f)
    motion = np.real(phasor[..., None] * np.exp(2j*np.pi*f*t))
    rng = np.random.default_rng(seed)
    sigma = np.sqrt(np.mean(motion[mask]**2)) * 10**(-noise_db/20)
    motion += rng.normal(0, sigma, motion.shape)
    return dict(motion=motion.astype(np.float32), x_m=x, row_m=z, t_s=t,
                valid_mask=mask, plane_type="bmode",
                metadata=dict(description=description, frequency_hz=f,
                              displacement_unit="m", snr_db=noise_db))


def main():
    rho=1000.; nu=.495; E=12000.; f=1000.
    cs=np.sqrt(E/(2*(1+nu)*rho))
    cp=np.sqrt(E*(1-nu)/((1+nu)*(1-2*nu)*rho))
    cr=independent_rayleigh_ratio(nu)*cs
    k=2*np.pi*f/cr; p=np.sqrt(1-(cr/cp)**2); q=np.sqrt(1-(cr/cs)**2)
    x=np.arange(101)*.08e-3; z=np.arange(121)*.01e-3
    X,Z=np.meshgrid(x,z)
    # Exact homogeneous traction-free half-space eigenfunction, Xu et al.
    # GJI228(2022), Appendix A4, DOI10.1093/gji/ggab370. Normalization is a
    # global displacement scale; it cannot change measured phase gradients.
    shape=-np.exp(-p*k*Z)+2/(1+q*q)*np.exp(-q*k*Z)
    P=10e-9*shape/shape[0,0]*np.exp(-1j*k*X)
    cases=[]
    for noise_db in [60,20]:
        cases.append(dict(label=f"rayleigh_exact_xz_snr{noise_db}", model="rayleigh",
                          frequency_hz=f, density_kg_m3=rho, poisson_ratio=nu,
                          thickness_m=0., truth_speed_m_s=np.full(X.shape,cr),
                          truth_young_pa=np.full(X.shape,E), score_mask=(X>.8e-3)&(X<7.2e-3)&(Z>.05e-3)&(Z<1.15e-3),
                          speed_reference_scope="Exact homogeneous modal lateral speed, identical at each sampled depth",
                          data=observed(P,x,z,np.ones(X.shape,bool),f,noise_db,20261015+noise_db,
                                        "Exact far-field Rayleigh axial eigenfunction in XZ; not a depthwise material inversion")))
    savemat(HERE/"bscan_forward_cases.mat",dict(cases=np.array(cases,dtype=object)),do_compression=True)
    print("Exact modal cases saved; cr",cr,flush=True)

    material=Material(name="Bscan_background_12kPa",E_kPa=12,eta_Pa_s=0,nu=nu,rho=rho)
    geom=Geometry(size_x_mm=14,size_y_mm=4,size_z_mm=3,
                  layers=[Layer(material,0)],lateral="absorbente",bottom="absorbente")
    excitation=ExcitationConfig(mode="arf_sin_contacto",regime="armonico",
                               pressure_MPa=.007,shape="linea",size_a_mm=1.,size_b_mm=12,
                               center_x_mm=-5.5,harmonic_hz=f,n_sources=1,
                               ring_radius_mm=0,random_phase=False,ramp_periods=2)
    settings=FDTDSettings(cell_mm=.1,backend="cpu",pml_cells=12,record_stride=1,
                          record_margin_mm=0,record_depth_mm=1.1,harmonics=1,
                          harmonic_window_periods=2,harmonic_min_periods=12,
                          harmonic_max_periods=36,harmonic_tol=.005)
    def progress(fraction,message):
        if "periodos" in message or fraction==0: print(message,flush=True)
    solver=FDTDSolver(geom,excitation,settings,(-1,5,-.1,.1),progress=progress)
    solver.backend=SnapshotBackend(solver.backend)
    print(solver.describe(),flush=True)
    record=solver.run_harmonic()
    jc=solver._slice_index()
    surface_k=surface_k_index(solver.grid.ids)[:,jc]
    midpoint=solver.grid.nx//2
    surface_z=record.slice_z_m[surface_k[midpoint]]
    keepx=(record.slice_x_m>=-1e-3)&(record.slice_x_m<=5e-3)
    depth=record.slice_z_m-surface_z
    keepz=(depth>=-1e-12)&(depth<=1e-3+1e-12)
    x=record.slice_x_m[keepx]; z=depth[keepz]
    P=record.slice_U[1][keepx,:][:,keepz].T.copy()
    assert np.all(np.isfinite(P)) and np.any(np.abs(P)>0), "Invalid forward field"
    X,Z=np.meshgrid(x,z)
    source_half=1e-3*np.sqrt(np.log(1000)/(4*np.log(2)))
    source_distance=X+5.5e-3-source_half
    mask=source_distance>=2*cr/f
    score=mask&(X>.8e-3)&(X<4.2e-3)&(Z<=.6e-3)
    cases.append(dict(label="rayleigh_true_fdtd_xz",model="rayleigh",frequency_hz=f,
                      density_kg_m3=rho,poisson_ratio=nu,thickness_m=0.,
                      truth_speed_m_s=np.full(P.shape,cr),truth_young_pa=np.full(P.shape,E),
                      score_mask=score,source_distance_m=source_distance,wavelength_bg_m=cr/f,
                      speed_reference_scope="Continuum Rayleigh expectation for a homogeneous finite numerical half-space; diagnostic discrepancy, not exact discrete modal ground truth",
                      record_info=record.info,
                      data=observed(P,x,z,mask,f,30,20261018,
                                    "True FDTD XZ slice of axial displacement; source support and full fit must stay >=2 background wavelengths away")))
    savemat(HERE/"bscan_forward_cases.mat",dict(cases=np.array(cases,dtype=object)),do_compression=True,long_field_names=True)
    (HERE/"fdtd_forward_manifest.json").write_text(
        json.dumps(dict(geometry=geom.to_dict(),excitation=excitation.to_dict(),settings=settings.to_dict(),
                        record_info=record.info,cpu_snapshot_copy_workaround=True,
                        source_half_support_m=source_half),indent=2,default=lambda v:v.tolist() if isinstance(v,np.ndarray) else str(v)),encoding="utf-8")
    solver.release()
    print("BSCAN_FORWARD_FINISHED",flush=True)


if __name__=="__main__":main()
