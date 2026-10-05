"""Independent observational checks of exported scalar forward fixtures.

No estimator truth, production mutation, or cross-acquisition phase sum is
used. The grid check compares the same 0-degree experiment on two meshes;
its one global complex scale accounts for the documented force normalization.
"""
from pathlib import Path
import csv
import hashlib
import json
import numpy as np
from scipy.io import loadmat, whosmat
from scipy.interpolate import RegularGridInterpolator

HERE=Path(__file__).resolve().parent


def get_list(value):
    if isinstance(value,list): return value
    if isinstance(value,np.ndarray) and value.dtype==object: return list(value.ravel())
    return [value]


def main():
    names=['phasors8','x_m','row_m','t_s','angles_deg','truth_speed','truth_young',
           'head_core_mask','tail_core_mask','background_mask','interface_mask','roi_mask']
    nominal=loadmat(HERE/'fish_individual_fields.mat',variable_names=names,simplify_cells=True)
    refined=loadmat(HERE/'fish_grid_check_000deg.mat',variable_names=names,simplify_cells=True)
    U0=get_list(nominal['phasors8'])[0]
    U1=np.asarray(refined['phasors8'])
    xx=np.asarray(nominal['x_m']);yy=np.asarray(nominal['row_m'])
    X,Y=np.meshgrid(xx,yy)
    interp=RegularGridInterpolator((refined['row_m'],refined['x_m']),U1,
                                  bounds_error=False,fill_value=np.nan)
    finer=interp(np.column_stack((Y.ravel(),X.ravel()))).reshape(X.shape)
    roi=np.asarray(nominal['roi_mask'],bool)
    scale=np.vdot(finer[roi],U0[roi])/np.vdot(finer[roi],finer[roi])
    records=[]
    for label,key in [('roi','roi_mask'),('head_core','head_core_mask'),('tail_core','tail_core_mask'),
                      ('background','background_mask'),('interface','interface_mask')]:
        m=np.asarray(nominal[key],bool)
        delta=U0[m]-scale*finer[m]
        phase=np.angle(U0[m]*np.conj(scale*finer[m]))
        records.append({'comparison':'0deg_dx_1over14mm_vs_1over16mm','region':label,
                        'pixels_on_nominal_grid':int(m.sum()),
                        'field_relative_l2_after_single_global_complex_scale':float(np.linalg.norm(delta)/np.linalg.norm(U0[m])),
                        'phase_abs_median_rad':float(np.median(abs(phase))),
                        'phase_abs_p95_rad':float(np.percentile(abs(phase),95)),
                        'global_scale_abs':float(abs(scale)),'global_scale_phase_rad':float(np.angle(scale))})
    with (HERE/'fish_forward_grid_comparison.csv').open('w',encoding='utf-8',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(records[0]));writer.writeheader();writer.writerows(records)
    # Load data8 only (not the duplicate cases payload) for empirical SNR and
    # second-noise realization checks, using the known PDE phasors directly.
    first=get_list(loadmat(HERE/'fish_individual_fields.mat',variable_names=['data8'],simplify_cells=True)['data8'])
    second=get_list(loadmat(HERE/'fish_individual_fields_noise2.mat',variable_names=['data8'],simplify_cells=True)['data8'])
    phasors=get_list(nominal['phasors8']);noise_records=[]
    assert len(first)==len(second)==len(phasors)==8
    assert np.array_equal(nominal['angles_deg'],np.arange(0,360,45))
    for index,(a,b,U) in enumerate(zip(first,second,phasors)):
        assert a['motion'].shape==(len(yy),len(xx),160)
        assert np.array_equal(a['x_m'],b['x_m']) and np.array_equal(a['valid_mask'],b['valid_mask'])
        assert np.all(np.isfinite(a['motion'])) and np.all(np.isfinite(b['motion']))
        assert a['metadata']['simultaneous_source_count']==1
        assert not a['metadata']['phase_coherent_between_acquisitions']
        m=np.asarray(a['valid_mask'],bool)
        signal=np.real(U[:,:,None]*np.exp(-2j*np.pi*1800*a['t_s']))
        noise1=np.asarray(a['motion'],float)-signal
        noise2=np.asarray(b['motion'],float)-signal
        power=np.mean(signal[m]**2)
        n1=noise1[m].ravel();n2=noise2[m].ravel()
        noise_records.append({'angle_deg':int(nominal['angles_deg'][index]),
                              'empirical_noise1_snr_db':float(10*np.log10(power/np.mean(n1**2))),
                              'empirical_noise2_snr_db':float(10*np.log10(power/np.mean(n2**2))),
                              'noise_realization_correlation':float(np.corrcoef(n1,n2)[0,1]),
                              'valid_pixels':int(m.sum()),'motion_shape':str(a['motion'].shape),
                              'simultaneous_source_count':1})
        del signal,noise1,noise2,n1,n2
    with (HERE/'fish_forward_noise_comparison.csv').open('w',encoding='utf-8',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(noise_records[0]));writer.writeheader();writer.writerows(noise_records)
    contract={'nominal_file':str(HERE/'fish_individual_fields.mat'),
              'noise2_file':str(HERE/'fish_individual_fields_noise2.mat'),
              'refined_file':str(HERE/'fish_grid_check_000deg.mat'),
              'nominal_variables':whosmat(HERE/'fish_individual_fields.mat'),
              'individual_acquisitions':8,'angles_deg':list(range(0,360,45)),
              'scalar_shear_model':'bulk_shear','density_kg_m3':1000,'poisson_ratio':.495,
              'frequency_hz':1800,'source_sum_performed':False,
              'grid_comparison_interpretation':'Same experiment, two meshes; global scale only; no asymptotic convergence claim',
              'sha256_sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in
                                [HERE/'generate_fish_individual_fields.py',Path(__file__)]}}
    (HERE/'fish_forward_contract.json').write_text(json.dumps(contract,indent=2),encoding='utf-8')
    print('Verified eight individual data structures, noise independence, and refinement comparison.')
    print('ROI field refinement relative L2:',records[0]['field_relative_l2_after_single_global_complex_scale'])
    print('Noise SNR range:',min(r['empirical_noise1_snr_db'] for r in noise_records),
          max(r['empirical_noise2_snr_db'] for r in noise_records))


if __name__=='__main__':main()
