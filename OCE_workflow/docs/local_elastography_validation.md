# Validación de mapas locales de velocidad y módulo de Young

La [validación ampliada](../results/extended_validation_2026-10-05/Resumen_validacion.md)
incluye varias semillas y SNR, controles sin propagación, sensibilidad FDTD a
malla/paso temporal y barridos de Young y planos experimentales. Detectó y
corrigió la fuga de movimiento uniforme del filtro direccional. Las tablas
de este documento corresponden al conjunto inicial; el resumen ampliado y
sus CSV describen los resultados finales de esa revisión.

Los resultados muestran que conviene seleccionar el estimador según el campo de ondas. El gradiente de fase funciona mejor en los ejemplos de Lamb dominados por un solo modo; el filtro direccional permite recuperar ondas reflejadas y parcialmente difusas; la autocorrelación requiere distinguir un campo planar de uno de corte volumétrico. Los métodos nuevos no superan a los originales en todos los casos.

## Campos y referencias independientes

[export_simulator_wave_cases.py](../workflows/export_simulator_wave_cases.py) genera ocho campos analíticos y ejecuta opcionalmente un caso elastodinámico con el simulador de Claude, sin modificarlo. La semilla es `20261004`. Se incluyen ondas planas limpias y ruidosas, dos ondas opuestas, 96 direcciones planares aleatorias, 1500 ondas de corte 3D con polarización transversal, dos modos A0 y un campo con atenuación lateral rápida. El ruido blanco se añade al movimiento real antes de la proyección armónica; el SNR indicado corresponde a esa etapa y mejora con el promedio temporal.

La referencia Rayleigh se obtiene de la raíz secular del semiespacio. La referencia A0 se calcula con la ecuación escalar de Rayleigh–Lamb, independientemente de la matriz 5×5 del simulador. Las velocidades A0 obtenidas por ambas implementaciones coinciden a menos de `6e-9` en error relativo en estos dos ejemplos. Todos los medios analíticos son homogéneos, isotrópicos, elásticos, sin tensión inicial y con `E=12000 Pa`, `rho=1000 kg/m^3` y `nu=0.495`.

El caso FDTD usa presión acústica sin contacto de 7 kPa, una fuente lineal, superficie libre y bordes laterales e inferior absorbentes. El dominio mide 9×3.4×4 mm, la celda 0.15 mm y el registro abarca 8 ms. Se analiza la componente de 1 kHz de la velocidad axial superficial. La velocidad de referencia es `c_R=1.912581 m/s`, el valor esperado para el semiespacio continuo homogéneo. **No es la velocidad exacta del dominio finito discretizado.** Se excluyen la región próxima a la fuente y los bordes de la comparación; no se hizo un estudio de convergencia de malla.

## Comparación de velocidad

Cada celda contiene **error absoluto relativo mediano en porcentaje (cobertura)**. El error usa solamente los píxeles aceptados por cada método. La cobertura usa todos los píxeles de referencia finita y soporte medido; incluye la pérdida por bordes de las ventanas y por rechazo de calidad. Una cobertura menor puede disminuir el error al descartar regiones difíciles.

Las ventanas miden 2.5 mm en los campos analíticos y 1.5 mm en FDTD. No se aplica suavizado de visualización a las métricas. La columna original de autocorrelación usa un fasor normalizado a RMS 1 y el modelo físico correcto: esférico 3D para corte volumétrico y `J0` planar para los demás casos. El CSV conserva además los resultados originales sin normalización y con el modelo alternativo.

La tabla y la figura se obtienen de `estimator_metrics.csv`. El JSON auxiliar del exportador usa una ROI interior con ventana completa (`evaluation_mask`), por lo que sus errores y coberturas pueden diferir de este CSV; no se mezclan ambas definiciones de soporte.

| Campo | Fase original | LFE original | Autocorr. original normalizada | Fase nueva | Direccional nueva | AIA nueva |
|---|---:|---:|---:|---:|---:|---:|
| Rayleigh plana, sin ruido | <0.001 (56.7%) | 0.193 (56.7%) | 4.03 (56.7%) | <0.001 (56.7%) | 0.287 (56.7%) | 0.795 (56.7%) |
| Rayleigh plana, SNR 5 dB | 0.0271 (56.7%) | 1.20 (56.7%) | 4.03 (56.7%) | 0.0391 (56.7%) | 0.283 (56.7%) | 0.822 (56.7%) |
| Rayleigh reflejada, SNR 10 dB | 0.271 (56.7%) | 0.876 (56.7%) | 4.04 (56.7%) | Sin soporte | 0.280 (55.9%) | 0.679 (55.9%) |
| Rayleigh difusa 2D, SNR 10 dB | 13.3 (12.1%) | 1.42 (56.7%) | 3.37 (56.7%) | Sin soporte | 1.06 (40.0%) | 1.86 (56.0%) |
| Corte difuso 3D, SNR 10 dB | 9.86 (9.2%) | 13.2 (56.7%) | 2.62 (56.7%) | Sin soporte | 4.46 (53.4%) | 3.63 (56.0%) |
| Lamb A0, 0.4 mm, 60 Hz | 0.0635 (56.7%) | 6.53 (56.7%) | 0.966 (56.7%) | 0.0729 (56.7%) | 2.26 (56.7%) | 0.320 (56.7%) |
| Lamb A0, 0.8 mm, 1 kHz | 0.0175 (56.7%) | 0.632 (56.7%) | 4.97 (56.7%) | 0.0230 (56.7%) | 0.179 (56.7%) | 0.562 (56.7%) |
| Rayleigh atenuada, SNR 0 dB | 0.155 (50.4%) | 9.25 (56.7%) | 5.07 (56.7%) | 0.0812 (20.5%) | 1.45 (20.5%) | 0.797 (20.5%) |
| FDTD sin contacto, 1 kHz | 8.02 (78.6%) | 12.4 (78.6%) | 5.63 (78.6%) | 3.77 (67.9%) | 2.81 (67.9%) | 3.27 (67.9%) |

En los mismos 209 píxeles aceptados del caso FDTD, el error del gradiente original es 7.61%, frente a 3.77% del nuevo gradiente y 2.81% del direccional. La autocorrelación original normalizada tiene 5.19% frente a 3.27% de AIA. Esta comparación sobre soporte común separa parte del beneficio de selección del beneficio del estimador.

En corte difuso 3D, la autocorrelación original normalizada con el modelo correcto conserva una ventaja: 2.61% frente a 3.63% sobre soporte común. En ondas planas y Lamb, el gradiente original ya es excelente y ligeramente mejor que el nuevo en varios ejemplos. No se justifica reemplazar todos los métodos originales por uno solo ni afirmar una mejora universal.

Los nuevos controles permiten ajustar frecuencia física, intervalo temporal, tamaño de ventana, dirección, apertura angular, amplitud mínima, coherencia, soporte y residuo del ajuste. Un mapa visualmente uniforme no constituye por sí solo una validación. Los productos numéricos mantienen los huecos rechazados; el suavizado opcional pertenece a la visualización.

## Inversión de Young separada del error de velocidad

Para aislar la inversión se entrega la **velocidad de fase verdadera** a ambos modelos. La fórmula original `3*rho*(c/0.955)^2` corresponde aproximadamente a Rayleigh casi incompresible y no sirve como conversión general de todas las ondas.

| Modelo conocido | Velocidad de fase (m/s) | Young original desde velocidad verdadera (Pa) | Young nuevo con modelo correcto (Pa) |
|---|---:|---:|---:|
| Rayleigh en semiespacio | 1.912581 | 12032.46 | 12000 |
| Corte volumétrico | 2.003342 | 13201.54 | 12000 |
| A0 libre, 0.4 mm, 60 Hz | 0.410597 | 554.56 | 12000 |
| A0 libre, 0.8 mm, 1 kHz | 1.645127 | 8902.52 | 12000 |

La inversión A0 libre elimina aquí errores de −95.38% y −25.81% causados exclusivamente por aplicar Rayleigh a Lamb. El error numérico de la inversión del modelo correcto, usando velocidad verdadera, queda por debajo de `4e-11%`. Eso verifica la implementación bajo un modelo conocido; no demuestra que ese modelo describa una muestra experimental.

La aproximación A0 de placa delgada devuelve 11323.89 Pa para el primer caso, un error de −5.63%, aunque `kh=0.3673` cumpla el umbral `kh<0.6`. Por tanto, el umbral es una condición de ingeniería y no una garantía universal de exactitud. El segundo caso tiene `kh=3.0554` y esa aproximación rechaza todos los píxeles. Para cuantificación bajo condiciones de placa libre conocidas, se prefiere `lamb_a0_free`.

En FDTD, los mapas nuevos producen medianas de Young de 11285 Pa, 11334 Pa y 11585 Pa con Rayleigh para fase, direccional y AIA, respectivamente, frente al material introducido de 12000 Pa. Usar corte volumétrico sobre el mismo mapa AIA produciría 10559 Pa. La incertidumbre de la velocidad y la selección del modelo siguen contribuyendo al resultado final.

## Interpretación experimental y física

La ausencia de contacto no determina por sí sola si se observan Rayleigh, Lamb, ondas volumétricas o una mezcla. Las capas raster muestran la velocidad de la onda observada a distintas profundidades; una velocidad de superficie detectada en profundidad no equivale automáticamente al módulo independiente de esa capa. Densidad, coeficiente de Poisson, espesor y condiciones de frontera son supuestos explícitos.

Rayleigh requiere un semiespacio adecuado. A0 libre requiere una placa plana sin fluido, tensión inicial ni anisotropía. La velocidad de grupo de tiempo de vuelo no se debe introducir como velocidad de fase: en el límite flexional A0, `c_g=2*c_p` y la conversión delgada de Young depende de `c_p^4`.

La autocorrelación 3D axial usa el perfil `1.5*(j0-j1/q)` en XY y `0.75*(j0+j1/q)` en XZ; no se confunde con `J0` de un campo planar. La formulación sigue [Asemani et al. (2024)](https://doi.org/10.3390/acoustics6020023). El filtrado direccional está motivado por [Schmidt et al. (2025)](https://doi.org/10.1117/1.JBO.30.12.124506); la implementación actual usa un sector elegido y ajuste circular local, no la reproducción exacta de su banco DPGA de 32 direcciones. La separación de compresión y movimiento común mediante IDA de [Asemani et al. (2025)](https://doi.org/10.1109/TBME.2024.3464104) es una posible extensión y no está implementada aquí.

Las adquisiciones experimentales no tienen referencia mecánica independiente. En ellas se evalúan soporte, espectro, coherencia, residuos, estabilidad ante parámetros y repetibilidad; no se asigna un porcentaje de exactitud de Young. Estos ejemplos usan una sola semilla y medios homogéneos, por lo que no establecen el desempeño en inclusiones, interfaces, anisotropía, tensión ni viscoelasticidad.

## Observación de los BIN experimentales

Se procesaron ambos BIN por bloques y se conservaron los datos originales.
Luis3 se exploró como B-mode independiente a 1 kHz; el raster como planos
en-face a 2 kHz, con pasos X/Y de dos posiciones y profundidades propuestas
de 0, 0.1 y 0.25 mm. La superficie se propuso con el máximo en el intervalo
FFT 50–700. **El borde anatómico y la repetibilidad de fase no están verificados.**

El registro completo contiene 8 ms. Una exploración del intervalo 2–4 ms,
con coherencia armónica mínima 0.2 y ventana lateral de 1.2 mm, conservó más
soporte que el registro completo. Esta elección usa menos muestras y puede
aumentar el ajuste de ruido: no identifica un retardo de excitación ni demuestra
exactitud. El intervalo 4–8 ms no produjo mapas aceptados con esos parámetros.

| Plano raster propuesto | Direccional 0°, cobertura | AIA planar, cobertura |
| --- | ---: | ---: |
| Superficie, intervalo 2–4 ms | 8.72% | 12.64% |
| 0.1 mm bajo superficie, intervalo 2–4 ms | 7.48% | 10.96% |
| 0.25 mm bajo superficie | 0% | 0% |

En Luis3 la cobertura del gradiente direccional fue muy escasa: 0.109% y
0.147% para las direcciones 0° y 180° en 2–4 ms. Los denominadores corresponden
al plano completo; no se comparan directamente con el área en-face del raster.
La diferencia de velocidades entre perfiles planar y volumétrico vuelve a
mostrar dependencia del modelo. No se calculó Young experimental sin una
hipótesis mecánica revisada ni se rellenaron las regiones rechazadas.

Los 91 resultados exploratorios, cuatro planos de movimiento, parámetros,
mapas y PNG están en `OCE_fish/OCE_estimator_validation/experimental`.
`README_observations.md`, `experimental_observations.csv` y
`experimental_temporal_observations.csv` describen el soporte, frecuencia,
intervalo, condiciones y máscaras. No constituyen ground truth experimental.

## Reproducción y artefactos

Desde PowerShell, con el entorno Python del simulador y MATLAB R2025b:

```powershell
$repo = 'C:\Users\proyecto.pi1081\Desktop\SD-OCT-1310-nm'
$sim = Join-Path $repo '.claude\worktrees\oct-simulator-gui-python-9d18ef\simulator'
$out = Join-Path $env:TEMP 'codex_oce_benchmark'
& (Join-Path $sim '.venv\Scripts\python.exe') `
    (Join-Path $repo 'OCE_workflow\workflows\export_simulator_wave_cases.py') `
    --simulator $sim --output (Join-Path $out 'simulator_cases.mat') --with-fdtd
```

```matlab
addpath('C:/Users/proyecto.pi1081/Desktop/SD-OCT-1310-nm/OCE_workflow/workflows');
out = fullfile(tempdir,'codex_oce_benchmark');
report = evaluate_elastography_estimators(fullfile(out,'simulator_cases.mat'),out);
```

Los resultados para inspección están en `C:/Users/proyecto.pi1081/Desktop/OCE_fish/OCE_estimator_validation/`: `comparison.png`, `estimator_metrics.csv` y `demo_plane.mat`. El último contiene el contrato `data` de una onda reflejada y se puede abrir desde la interfaz interactiva. El conjunto completo de campos y productos numéricos permanece en `tempdir/codex_oce_benchmark`; no se incorpora una adquisición grande ni un fixture binario al repositorio.
