"""Audit final raw-phase comparisons and summarize their actual results."""
from pathlib import Path
import csv,json,math
HERE=Path(__file__).resolve().parent
def read(name):return list(csv.DictReader((HERE/name).open(encoding='utf-8')))
rows=read('raw_unwrap_speed_young_metrics.csv');filtered=read('raw_unwrap_speed_young_metrics_filtered.csv')
fish=read('fish_raw_pd2d_metrics.csv');luis=read('luis3_raw_pd2d_metrics.csv')
ablation=read('unwrap_stage_ablation_metrics.csv')
assert len(ablation)==45
for r in ablation:
    if r['raw_method']=='tie_dct':assert int(r['raw_iterations_executed'])==int(r['raw_iterations_requested'])
    if r['modal_method']=='tie_dct':
        assert int(r['modal_iterations_executed']) in [0,int(r['modal_iterations_requested'])]
assert len(rows)==84 and len(filtered)==18 and len(fish)==3 and len(luis)==3
assert all(r['estimator']=='phase_derivative_2d' for r in rows+filtered)
assert all(int(r['raw_iterations_executed'])==8 for r in rows+filtered+luis if r['unwrap_method']=='tie_dct')
null=[r for r in rows if 'shuffle_null' in r['case_label']]
assert len(null)==6 and all(int(r['accepted_pixels'])==0 for r in null)
def val(v):
    x=float(v);return 'sin soporte' if not math.isfinite(x) else f'{x:.3f}'
table=['| Caso | Error c TIE8 (%) | Error E TIE8 (%) | Cobertura (%) |', '|---|---:|---:|---:|']
for r in rows:
    if r['source']=='true_fdtd_xz' and r['unwrap_method']=='tie_dct':
        table.append('| {} | {} | {} | {} |'.format(r['case_label'],val(r['speed_discrepancy_homogeneous_pct']),
            val(r['young_discrepancy_constitutive_pct']),val(r['coverage_pct'])))
fishTable=['| Unwrap | Cobertura ROI (%) | Error c (%) | Error E (%) | Cabeza (kPa) | Cola (kPa) |',
           '|---|---:|---:|---:|---:|---:|']
for r in fish:
    fishTable.append('| {} | {} | {} | {} | {} | {} |'.format(r['unwrap_method'],*[val(r[k]) for k in
        ['coverage_pct','speed_error_pct','young_error_pct','head_median_kpa','tail_median_kpa']]))
experimental=['| Unwrap profundidad-tiempo | Píxeles | Mediana c (m/s) | Young aparente (kPa) |', '|---|---:|---:|---:|']
for r in luis:experimental.append('| {} | {} | {} | {} |'.format(r['unwrap_method'],r['accepted_pixels'],
    val(r['speed_median_m_s']),val(r['apparent_young_median_kpa'])))
report='''# Fase cruda, unwrap y phase derivative 2D — 5 de octubre de 2026

El nuevo procesamiento parte de `angle(IQ)` nativa, envuelta en [-pi,pi].
El orden es: reconstrucción compleja → fase cruda → unwrap → eliminación de
fase estática/promedios y colocación geométrica → proyección armónica y filtro
direccional opcional → unwrap de fase modal → derivadas locales → velocidad/Young.
Los bordes e intensidad/coherencia OCT definen soporte; no filtran la fase antes
del unwrap. No se usa Loupas ni diferencia temporal en esta rama.

## Métodos y estimador

Se comparan `sequential`, `least_squares_dct` y `tie_dct`. El nombre en la
bibliografía/código original es **TIE-DCT**, correspondiente al TIE_DTC solicitado.
TIE realiza una solución inicial y **8 correcciones obligatorias**, sin parada
por convergencia. También se ensayan presupuestos fijos 4/8/12 en la ablación.
La solución TIE final conserva fase cruda más múltiplos enteros de 2pi;
mínimos cuadrados puede modificar la fase por su ajuste de gradientes inconsistente.

Las máscaras irregulares usan el mismo operador de Neumann en grafo, registrado
en procedencia; sólo componentes rectangulares utilizan DCT. No se interpolan
huecos ni conectan componentes separados. Aplicar el algoritmo profundidad-tiempo
es una adaptación de unwrap 2D con métrica de píxeles, no una TIE física temporal.

`phase_derivative_2d` estima derivadas de un ajuste polinómico local robusto
(orden2), con pesos de amplitud limitados y rechazo de soporte/error/alias.
Enface y bulk XZ: c=omega/sqrt(kx²+krow²). B-scan de ondas guiadas: c=omega/abs(kx),
con fase independiente por profundidad; su forma modal axial no se convierte
en kz de propagación. El caso bulk oblicuo de 30 grados verifica ambas derivadas.
Los ajustes no unen pistones desconocidos de componentes desconectados.

## Comparación controlada

14 casos y 84 mapas numéricos principales: los nueve pares Exact/FDTD previos,
cuatro controles Lamb (fase estática aleatoria, ruido0.20rad, alias temporal y
tiempos desordenados), y una onda bulk analítica oblicua con dos realizaciones
de ruido. Esta última no es FDTD y se etiqueta explícitamente.

La observación simulada es fase óptica estática +4pi*n*u/lambda+ruido, envuelta
sin ningún filtro: lambda1310nm, n1.4, pico u0.8um (2.5um en alias), 40 muestras
por ciclo, 160 muestras, ruido base0.03rad. Se mantienen campos forward previos,
no se pinta velocidad en su fase. Es un modelo de observación controlado;
no reproduce toda la formación de speckle/OCT. El antiguo caso CPU utiliza
el fasor recuperado de su traza guardada con ruido, declarado en la validación
anterior. Los ocho nuevos FDTD conservan sus campos forward originales.

El unwrap óptico principal es tiempo-profundidad por cada posición adquirida
independientemente, dimensiones[3 1]. Se registra también el unwrap modal:
por fila en B-scan guiado, 2D espacial en enface/bulk. La selección del mismo
método en ambas etapas es el ensayo principal; la ablación separa sus efectos.

Ventana X0.5lambda, Z0 en guiadas, coherencia0.65, amplitud0.05, soporte0.8,
error0.30, rango0.2–8m/s, sin relleno ni suavizado. Sólo centros cuya ventana
entera está a dos longitudes de onda de la fuente entran al análisis.
Los pares y métodos comparten señales, ejes, máscaras, ventanas, escalas y ROI.
`raw_unwrap_common_support.csv` permite comparar sobre píxeles comunes.

'''+ '\n'.join(table)+'''

La discrepancia de c en la inclusión está referida al fondo homogéneo y no mide
exactitud dentro de la inclusión. Exact XZ es baseline homogéneo, no la solución
heterogénea. Young se compara con el material constitutivo pero sigue siendo
una inversión modal local condicional. El Lamb grueso conserva una discrepancia
de Young de aproximadamente43%; el unwrap no separa sus modos físicos.

El ensayo con fase estática aleatoria muestra diferencias visibles entre unwraps.
En el resto de campos bien muestreados y con portadora suave pueden coincidir:
no se introducen diferencias artificiales. El error óptico se calcula quitando
únicamente el pistón temporal constante por voxel frente a la fase conocida.
Pistones absolutos son inobservables. Una congruencia de wrap pequeña no prueba
recuperación correcta: el control alias presenta errores ópticos grandes y puede
producir mapas coloreados incorrectos. El control temporal desordenado rechaza
los seis mapas (cero píxeles) con los parámetros congelados.

Se añaden tres pares Lamb con filtro direccional después del unwrap óptico:
`raw_unwrap_speed_young_metrics_filtered.csv`. Para la placa0.6mm el error FDTD
de c baja de5.24% a4.00%, y E de14.02% a10.89%; el mismo filtro introduce sesgo
en el modo analítico limpio. No justifica aplicarlo universalmente.

## Pez enface y excitaciones individuales

Se parte de ocho campos físicos scalar-SH independientes, no de una suma
reverberante ni de una solución elástica3D completa. Cada campo se observa como
fase óptica cruda con portadora estática aleatoria; unwrap temporal por voxel,
PD2D espacial y fusión robusta con al menos4/8 estimaciones concordantes.
Malla de observación0.142857mm, ventana1.2×1.2mm, ROI±5mm y fuentes a12mm.
Su geometría mantiene el soporte del ROI en campo lejano. Fondo12kPa; ambas
inclusiones24kPa. Los contornos blancos son referencia material, no detección
estimada de bordes. No se rellena el resultado.

'''+ '\n'.join(fishTable)+'''

Los núcleos evaluados tienen261 píxeles en cabeza y12 en cola (erosión0.9mm);
la cola es pequeña y su estadística es limitada. TIE8 mantiene contraste y
cobertura; mínimos cuadrados extiende cobertura pero reduce contraste.

## Luis3 experimental

Se reconstruyó directamente el BIN: fase cruda700×75×400, t original a50kHz,
un solo B-scan; 38687voxeles con soporte OCT/borde. Se conserva el máximo OCT
candidato explícitamente exploratorio, sin certificación anatómica. No se aplica
el gate pi del incremento Loupas a la fase absoluta. La misma ventana0.9×0.04mm,
1000Hz y ROI2–4ms se usa con los tres métodos; coherencia0.2, demás gates fijos.

'''+ '\n'.join(experimental)+'''

Esto es soporte localizado y dependiente del procesamiento, no un mapa completo
ni Young experimental validado. Rayleigh, rho1000 y nu0.495 son supuestos, no
modo/calibración demostrados. Mayor número de píxeles no establece exactitud.
La figura contiene campo completo y zoom explícito0.18–0.46mm.

## Uso, reproducción y verificación

La ablación mantiene fijo el unwrap modal mientras cambia el óptico, y después
mantiene fija la señal óptica mientras cambia el modal. En la portadora estática
aleatoria, los tres unwraps sólo temporales recuperan fase con RMSE≈0.03rad;
imponer continuidad profundidad-tiempo produce RMSE≈0.85–2.43rad aunque algunos
mapas permanezcan limpios. Por ello la interfaz inicia en dominio óptico
`temporal`; `temporal_depth` conserva su carácter de supuesto adicional.
En Luis3, el unwrap sólo temporal acepta cero píxeles con los tres métodos
y parámetros congelados. Con TIE profundidad-tiempo, 4/8/12 correcciones aceptan
9/22/8 píxeles: más iteraciones no establecen mayor exactitud. Sin ground truth
no se elige un presupuesto por cantidad de píxeles coloreados.

- `workflows/run_elastography_interactive.m`: BIN o stepwise, nueva entrada
  raw y PD2D; controles de unwrap, dominio temporal/profundidad y presupuesto TIE.
- `workflows/run_phase_unwrap_comparison.m`: mismos inputs y comparación de
  tres unwraps; Young requiere elegir explícitamente el modelo mecánico.
- Ejecutar `prepare_raw_phase_cases.py`, después `evaluate_raw_phase_maps.m`;
  `prepare_fish_raw_phase.py` y `evaluate_fish_raw_maps.m` para el pez;
  `export_raw_luis3.m` y `evaluate_luis3_raw_maps.m` para el BIN.
- `evaluate_unwrap_stage_ablations.m` aísla etapas/dominios e iteraciones; sus CSV y
  [hallazgos](Hallazgos_ablaciones_unwrap.md) están en esta carpeta.
  Datos volumétricos MAT quedan locales. Las preparaciones reutilizan los
  MAT/NPZ forward previos; si faltan, regenérelos con los scripts de las
  carpetas `fdtd_exact_comparison_2026-10-05` y `bscan_fish_validation_2026-10-05`.
- Figuras PNG de velocidad/Young exclusivamente en `../Speed_Young_Maps/`;
  inventario/hash en la carpeta hermana `map_gallery_validation_2026-10-05`.

Regresión completa:51 PASS,2 fallos previos (144/151 archivos MIMT y opción
preexistente de video filtrado). Goldens intactos. Tests nuevos verifican fase
conocida, wraps activos, presupuesto fijo, máscaras, cortes independientes,
onda bulk oblicua, fase curva, componentes desconectados y entrada raw nativa.
La interfaz pasó el cambio de dominio manteniendo el presupuesto TIE.
Después del gate completo se verificaron de nuevo el núcleo y la interfaz:
se omiten ejes singleton sin cambiar resultados y se admite el redondeo de
single(±pi), conservando rechazo de fase fuera de rango. Pruebas afectadas PASS.
La galería final contiene65 PNG (20 nuevos en este ensayo), sin otros archivos.

Referencias primarias:

- [Zhao et al., Robust 2D phase unwrapping based on TIE](https://doi.org/10.1088/1361-6501/aaec5c).
- [Liu, Kijanka y Urban, DV-OCE2D](https://doi.org/10.1364/BOE.416661).
- [Zvietcovich et al., ACUS confocal](https://doi.org/10.1364/OL.410593).

El estimador implementa derivadas polinómicas robustas de fase modal desenvuelta;
es una extensión local documentada, no reproducción literal de todo el protocolo
de esos artículos.
'''
(HERE/'Resumen_comparativa.md').write_text(report,encoding='utf-8')
(HERE/'numerical_audit.json').write_text(json.dumps(dict(main_evaluations=84,filtered_evaluations=18,
    fish_methods=3,experimental_methods=3,stage_ablations=45,fixed_tie_corrections=8,null_accepted_pixels=0,
    all_estimator_methods='phase_derivative_2d',no_prefilter_before_raw_unwrap=True),indent=2))
print('RAW_PHASE_COMPARISON_AUDIT_PASS',len(rows),len(filtered))
