"""Render deterministic parameter-sweep observations from MATLAB CSV files."""
from pathlib import Path
import csv
import json
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parent


def records(name):
    with (ROOT / name).open(encoding='utf-8-sig') as stream:
        values = list(csv.DictReader(stream))
    numeric = ('true_E_pa', 'true_density_kg_m3', 'true_poisson_ratio', 'true_thickness_m',
               'frequency_hz', 'truth_phase_speed_m_s', 'truth_kh', 'assumed_speed_m_s',
               'assumed_density_kg_m3', 'assumed_poisson_ratio', 'assumed_thickness_m',
               'perturbation_value', 'young_pa', 'relative_error_pct', 'kh_inferred')
    for row in values:
        for key in numeric:
            if key in row:
                row[key] = float(row[key])
        row['accepted'] = row.get('accepted', '0').lower() in ('1', 'true')
        row['a0_asymptotic_used'] = row.get('a0_asymptotic_used', '0').lower() in ('1', 'true')
    return values


def interval(rows, perturbation, value, model='lamb_a0_free'):
    selected = [r['relative_error_pct'] for r in rows
                if r['perturbation'] == perturbation
                and abs(r['perturbation_value'] - value) < 1e-8
                and r['reference_model'] == model and r['accepted']]
    return [float(v) for v in np.percentile(selected, [0, 50, 100])] if selected else [np.nan]*3


def main():
    comparison = records('young_model_comparison.csv')
    sensitivity = records('young_input_sensitivity.csv')
    A0 = [r for r in comparison if r['reference_model'] == 'lamb_a0_free']
    correct = [r for r in comparison if r['selected_model'] == r['reference_model']]
    thin = [r for r in A0 if r['selected_model'] == 'lamb_a0_thin']
    rayleigh = [r for r in A0 if r['selected_model'] == 'rayleigh']
    unique = [r for r in A0 if r['selected_model'] == 'lamb_a0_free']
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10})
    figure, axis = plt.subplots(figsize=(10.5, 6.1))
    exact = np.array([r['relative_error_pct'] for r in unique])
    kh = np.array([r['truth_kh'] for r in unique])
    ungated = np.array([100*(12*(1-r['true_poisson_ratio']**2)*r['true_density_kg_m3']
                            * r['truth_phase_speed_m_s']**4
                            / ((2*np.pi*r['frequency_hz'])**2*r['true_thickness_m']**2)
                            / r['true_E_pa']-1) for r in unique])
    axis.scatter(kh, exact, s=34, color='#0072B2', label='A0 libre exacta, modelo conocido', zorder=4)
    axis.scatter([r['truth_kh'] for r in rayleigh], [r['relative_error_pct'] for r in rayleigh],
                 s=36, color='#D55E00', label='Conversión Rayleigh sobre A0', marker='s')
    accepted = kh <= 0.6
    axis.scatter(kh[accepted], ungated[accepted], color='#009E73', s=70,
                 marker='^', label='A0 delgada: gate kh ≤ 0.6 aceptado', zorder=5)
    axis.scatter(kh[~accepted], ungated[~accepted], color='#888888', s=40,
                 marker='x', label='A0 delgada fuera del gate: fórmula sólo diagnóstica')
    axis.axvline(0.6, color='#009E73', linestyle='--', linewidth=1)
    axis.axhline(0, color='#334155', linewidth=0.8)
    axis.set_xscale('log'); axis.set_ylim(-103, 7)
    axis.set_xlabel('kh de la referencia A0 (k = 2πf/c de fase, h = espesor total)')
    axis.set_ylabel('Error relativo de Young (%)')
    figure.suptitle('Inversión de 54 referencias A0 independientes', y=.98, fontsize=14)
    axis.grid(alpha=0.22, which='both')
    handles, labels = axis.get_legend_handles_labels()
    figure.legend(handles, labels, loc='lower center', bbox_to_anchor=(.5,.005), ncol=2, frameon=False, fontsize=8.5)
    figure.text(.5, .925, f'Error numérico máximo A0: {np.max(np.abs(exact)):.2g}% · '
              f'Umbral delgado: {accepted.sum()}/54 aceptados; error máximo {abs(ungated[accepted]).max():.2f}%',
              ha='center', va='center', fontsize=9)
    figure.tight_layout(rect=(0,.16,1,.89)); figure.savefig(ROOT / 'young_model_bias.png', dpi=180); plt.close(figure)

    figure, axes = plt.subplots(2, 2, figsize=(12.8, 8.6))
    factors = np.array([0.9, 0.95, 1.05, 1.1])
    colors = {'lamb_a0_free': '#0072B2', 'rayleigh': '#D55E00', 'bulk_shear': '#009E73'}
    names = {'lamb_a0_free': 'A0 libre', 'rayleigh': 'Rayleigh', 'bulk_shear': 'Corte volumétrico'}
    for perturbation, axis, title in [('speed_factor', axes[0,0], 'Error supuesto de velocidad de fase'),
                                     ('density_factor', axes[0,1], 'Error supuesto de densidad'),
                                     ('thickness_factor', axes[1,0], 'Error supuesto de espesor: sólo A0')]:
        for model in colors:
            if perturbation == 'thickness_factor' and model != 'lamb_a0_free':
                continue
            bounds = np.asarray([interval(sensitivity, perturbation, f, model) for f in factors])
            axis.fill_between(100*(factors-1), bounds[:,0], bounds[:,2],
                              color=colors[model], alpha=0.18)
            axis.plot(100*(factors-1), bounds[:,1], marker='o', color=colors[model],
                      label=names[model], linestyle='-' if model!='bulk_shear' else ':')
        axis.set_title(title); axis.set_xlabel('Perturbación de entrada (%)'); axis.set_ylabel('Error de Young (%)')
        axis.axhline(0, color='#334155', linewidth=0.7); axis.grid(alpha=0.2); axis.legend(fontsize=9)
    deltas = np.array([-0.03, -0.01, 0.01, 0.03])
    axis=axes[1,1]
    for model in colors:
        bounds=np.asarray([interval(sensitivity, 'poisson_delta', d, model) for d in deltas])
        axis.fill_between(deltas, bounds[:,0], bounds[:,2], color=colors[model], alpha=0.18)
        axis.plot(deltas,bounds[:,1],color=colors[model],marker='o',label=names[model])
    axis.set_title('Cambio absoluto supuesto de Poisson'); axis.set_xlabel('Δν (se rechazan ν ≥ 0.5)')
    axis.set_ylabel('Error de Young (%)'); axis.axhline(0,color='#334155',linewidth=.7)
    axis.grid(alpha=.2); axis.legend(fontsize=9)
    figure.suptitle('Sensibilidad condicional: perturbaciones una a la vez', fontsize=14)
    figure.text(0.5, .007, 'Línea: mediana; banda: mínimo–máximo entre referencias aceptadas. No son intervalos de incertidumbre experimental.',
                ha='center', fontsize=9)
    figure.tight_layout(rect=(0,.025,1,.95)); figure.savefig(ROOT / 'young_input_sensitivity.png',dpi=180); plt.close(figure)

    stats = {
        'reference_cases': len(correct), 'A0_reference_cases': len(unique),
        'model_comparison_rows': len(comparison), 'sensitivity_rows': len(sensitivity),
        'exact_max_abs_error_pct': max(abs(r['relative_error_pct']) for r in correct if r['accepted']),
        'thin_gate_accepted_count': int(accepted.sum()), 'thin_gate_coverage_pct': float(100*accepted.mean()),
        'thin_gate_max_abs_error_pct': float(abs(ungated[accepted]).max()),
        'wrong_rayleigh_min_error_pct': min(r['relative_error_pct'] for r in rayleigh),
        'wrong_rayleigh_max_error_pct': max(r['relative_error_pct'] for r in rayleigh),
        'wrong_rayleigh_median_error_pct': float(np.median([r['relative_error_pct'] for r in rayleigh])),
        'sensitivity_rejections': sum(not r['accepted'] for r in sensitivity),
        'sensitivity_exception_ids': sorted(set(r['exception_id'] for r in sensitivity if r['exception_id'])),
        'correct_model_rejections': sum(not r['accepted'] for r in correct),
        'a0_asymptotic_used_count': sum(r['a0_asymptotic_used'] for r in comparison+sensitivity),
        'speed_sensitivity_a0': {str(round(100*(f-1))):interval(sensitivity,'speed_factor',f) for f in factors},
        'density_sensitivity_a0': {str(round(100*(f-1))):interval(sensitivity,'density_factor',f) for f in factors},
        'thickness_sensitivity_a0': {str(round(100*(f-1))):interval(sensitivity,'thickness_factor',f) for f in factors},
    }
    (ROOT / 'summary_statistics.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
    with (ROOT / 'thin_ungated_diagnostic.csv').open('w',newline='',encoding='utf-8') as stream:
        writer=csv.writer(stream); writer.writerow(['case_id','truth_kh','thin_formula_young_pa','relative_error_pct','gate_accepted'])
        for r,e,a in zip(unique,ungated,accepted):
            writer.writerow([r['case_id'],r['truth_kh'],r['true_E_pa']*(1+e/100),e,int(a)])
    print(json.dumps(stats,indent=2))


if __name__ == '__main__':
    main()
