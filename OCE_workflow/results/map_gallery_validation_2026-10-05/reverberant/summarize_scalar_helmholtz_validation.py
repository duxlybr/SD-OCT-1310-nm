"""Record observational scores and current source hashes, outside the gallery."""
from pathlib import Path
import csv
import hashlib
import json
import platform
import shutil
import numpy
import scipy
import matplotlib


def read_rows(path):
    with path.open(encoding='utf-8-sig',newline='') as stream:
        return list(csv.DictReader(stream))


def main():
    root=Path(__file__).resolve().parent
    nominal=[r for r in read_rows(root/'scalar_helmholtz_metrics.csv')
             if r['case_name']=='stiff_inclusion']
    extra=read_rows(root/'scalar_helmholtz_robustness_metrics.csv')
    rows=nominal+extra
    labels={'stiff_inclusion':'Nominal: dx 0.1 mm; semilla 20261005',
            'source_seed_20261006':'dx 0.1 mm; semilla 20261006',
            'source_seed_20261007':'dx 0.1 mm; semilla 20261007',
            'grid_refinement_dx_0p075mm':'dx 0.075 mm; semilla 20261005'}
    regions={'core':'Núcleo','background':'Fondo','interface':'Interfaz','farfield':'Campo útil'}
    table=['| Ensayo | Región | Cobertura (%) | Error velocidad (%) | Error Young (%) | Young mediano (kPa) |',
           '|---|---|---:|---:|---:|---:|']
    for row in rows:
        table.append('| '+labels[row['case_name']]+' | '+regions[row['region']]+' | '+
                     ' | '.join(f"{float(row[k]):.3f}" for k in
                                ['coverage_pct','speed_median_abs_error_pct',
                                 'young_median_abs_error_pct','young_median_kpa'])+' |')
    text='''# Sensibilidad observacional de la inclusión rígida

Tres problemas directos adicionales de Helmholtz escalar se ejecutaron secuencialmente. Los materiales, fuentes físicas, radio de inclusión, frecuencia de 1800 Hz, ruido de 25 dB y ventana de 2.4 mm permanecen fijos. Las fases de las 24 fuentes cambian en dos ensayos mediante semillas predefinidas; el tercero conserva la semilla nominal y refina el paso espacial de 0.1 a 0.075 mm.

Se reprodujo el preámbulo del generador de ruido nominal para mantener los mismos números de ruido de medida en los ensayos con igual malla. El refinamiento tiene otro número de nodos; mantiene la semilla y SNR, y no se interpreta como comparación exacta de ruido píxel a píxel. Los resultados nominales, MAT y PNG de la galería no se sobrescribieron.

Los errores son medianas de errores absolutos relativos sobre píxeles aceptados. Se informa también cobertura sobre la región completa.

'''+ '\n'.join(table)+'''

La dependencia de la realización de las fuentes es moderada en el campo útil: error mediano de velocidad de 1.966–2.168% y Young de 3.914–4.320% entre las tres semillas. En el núcleo de la inclusión la variación es mayor: velocidad de 1.023–2.500% y Young de 2.057–4.937%. Todas las semillas aceptan el 100% de los 81 píxeles del núcleo conservador; la cobertura del campo útil supera 99.88%.

Con dx = 0.075 mm el error del campo útil disminuye de 2.008 a 1.487% en velocidad y de 3.995 a 2.975% en Young; el fondo mejora de 1.356 a 0.870% en velocidad. El núcleo cambia de 1.336 a 1.471% en velocidad y no mejora. La mediana firmada de velocidad en el fondo pasa de -1.240 a -0.310%, consistente con que la discretización contribuye al sesgo. Dos niveles de malla comprueban estabilidad; no prueban convergencia asintótica ni separan completamente error de malla, ajuste y realización del ruido.

Los ensayos finos usan 321 × 321 nodos. Sus regiones contienen 137 píxeles de núcleo, 4008 de fondo y 12477 de campo útil. La geometría de selección sigue expresada en unidades físicas y verifica que toda la ventana esté alejada más de dos longitudes de onda del fondo del soporte de 3σ de las fuentes, y fuera del absorbente.

Para reproducir estos tres ensayos, ejecutar `python run_scalar_helmholtz_robustness.py` desde esta carpeta con NumPy/SciPy disponibles y MATLAB en PATH. El script llama MATLAB con `-singleCompThread`, guarda cada campo y mapa en archivos de prefijo `scalar_helmholtz_robustness_`, y consolida los resultados en `scalar_helmholtz_robustness_metrics.csv`. Las verificaciones del problema directo se guardan en `scalar_helmholtz_robustness_diagnostics.json`. Ejecutar después `python summarize_scalar_helmholtz_validation.py` regenera este resumen y el manifiesto.

Esta sensibilidad corresponde a ondas escalares de corte antiplano, no a un ensayo experimental ni a un modelo completo de OCE 3D. Los mapas y el módulo de Young siguen condicionados al modelo físico del ensayo.
'''
    (root/'summary_scalar_helmholtz_robustness.md').write_text(text,encoding='utf-8')
    workflow=root.parents[2]
    sources=[root/'generate_scalar_helmholtz_fields.py',root/'estimate_scalar_helmholtz_maps.m',
             root/'render_scalar_helmholtz_maps.py',root/'run_scalar_helmholtz_robustness.py',
             root/'summarize_scalar_helmholtz_validation.py',
             workflow/'src/+oce/+dispersion/estimateLocalSpeedMap.m',
             workflow/'src/+oce/+elastography/invertYoungModulus.m']
    manifest={'python':platform.python_version(),'numpy':numpy.__version__,'scipy':scipy.__version__,
              'matplotlib':matplotlib.__version__,'matlab_executable':shutil.which('matlab.exe'),
              'nominal_phases_seed':20261005,'trial_phases_seeds':[20261006,20261007],
              'nominal_dx_m':.1e-3,'refinement_dx_m':.075e-3,'estimator_window_m':.0024,
              'sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}}
    (root/'reproducibility_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(root/'summary_scalar_helmholtz_robustness.md')
    print(root/'reproducibility_manifest.json')


if __name__=='__main__': main()
