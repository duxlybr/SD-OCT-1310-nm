"""Geometry-only fit-footprint audit; no estimated maps or GT-based tuning."""
from pathlib import Path
import csv
import json
import numpy as np
from scipy.io import loadmat
from scipy.ndimage import minimum_filter
from generate_fish_individual_fields import SOURCE_RADIUS,SOURCE_NORMAL_SUPPORT,BACKGROUND_LAMBDA,ABSORBER_START

HERE=Path(__file__).resolve().parent


def main():
    value=loadmat(HERE/'fish_individual_fields.mat',variable_names=
                  ['x_m','row_m','roi_mask','head_mask','tail_mask','inclusion_mask'],simplify_cells=True)
    X,Y=np.meshgrid(value['x_m'],value['row_m']);roi=np.asarray(value['roi_mask'],bool)
    dx=float(np.mean(np.diff(value['x_m'])));records=[]; masks={}
    for width_mm in [1.,1.2,3.,4.]:
        width=width_mm*1e-3;p=width/(2*dx);half=int(np.floor(p+16*np.spacing(p)))
        size=2*half+1
        head_pure=minimum_filter(np.asarray(value['head_mask'],np.uint8),size=size,mode='constant',cval=0).astype(bool)&roi
        tail_pure=minimum_filter(np.asarray(value['tail_mask'],np.uint8),size=size,mode='constant',cval=0).astype(bool)&roi
        union_pure=minimum_filter(np.asarray(value['inclusion_mask'],np.uint8),size=size,mode='constant',cval=0).astype(bool)&roi
        safe_all_actual=roi.copy();safe_all_nominal=roi.copy()
        for angle in range(0,360,45):
            th=np.deg2rad(angle);c=np.cos(th);s=np.sin(th)
            distance=SOURCE_RADIUS+X*c+Y*s-SOURCE_NORMAL_SUPPORT
            measured=(distance>=2*BACKGROUND_LAMBDA)&(np.maximum(abs(X),abs(Y))<ABSORBER_START)
            complete=minimum_filter(measured.astype(np.uint8),size=size,mode='constant',cval=0).astype(bool)
            safe=roi&complete
            actual_gap=distance-(abs(c)+abs(s))*half*dx
            nominal_gap=distance-(abs(c)+abs(s))*width/2
            safe_nominal=safe&(nominal_gap>=2*BACKGROUND_LAMBDA)
            safe_all_actual&=safe;safe_all_nominal&=safe_nominal
            records.append({'nominal_window_mm':width_mm,'window_samples':size,
                            'actual_endpoint_span_mm':2*half*dx*1e3,'angle_deg':angle,
                            'roi_pixels':int(roi.sum()),'complete_farfield_roi_pixels':int(safe.sum()),
                            'continuous_nominal_safe_roi_pixels':int(safe_nominal.sum()),
                            'minimum_actual_fit_endpoint_source_gap_wavelengths':float(actual_gap[safe].min()/BACKGROUND_LAMBDA),
                            'minimum_continuous_nominal_window_gap_over_original_roi_wavelengths':float(nominal_gap[roi].min()/BACKGROUND_LAMBDA),
                            'pure_head_pixels':int((head_pure&safe).sum()),
                            'pure_tail_pixels':int((tail_pure&safe).sum()),
                            'pure_union_pixels':int((union_pure&safe).sum())})
        masks[str(width_mm)]={'complete_farfield_all8_roi_pixels':int(safe_all_actual.sum()),
                              'continuous_nominal_all8_roi_pixels':int(safe_all_nominal.sum()),
                              'head_pure_all8_pixels':int((head_pure&safe_all_actual).sum()),
                              'tail_pure_all8_pixels':int((tail_pure&safe_all_actual).sum()),
                              'union_pure_all8_pixels':int((union_pure&safe_all_actual).sum())}
    with (HERE/'fish_window_geometry.csv').open('w',encoding='utf-8',newline='') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(records[0]));writer.writeheader();writer.writerows(records)
    (HERE/'fish_window_geometry_summary.json').write_text(json.dumps(masks,indent=2),encoding='utf-8')
    print(json.dumps(masks,indent=2))


if __name__=='__main__':main()
