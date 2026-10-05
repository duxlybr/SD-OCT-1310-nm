# Resumen de validación ampliada de OCE

Fecha de cierre: **2026-10-05**, America/Lima. Se conservaron mapas numéricos sin suavizar, máscaras de rechazo, parámetros, registros y scripts de reproducción. El nombre de la carpeta de resultados es `results`.

## Hallazgos principales

- El control sin propagación reveló fuga espectral del filtro direccional. Se corrigió eliminando el promedio espacial complejo antes del padding y referenciando la amplitud al movimiento medido. En los **16 controles sintéticos**, el máximo soporte falso final fue **0.00%** para los tres métodos. Esto cubre los controles ensayados, no garantiza rechazo universal.
- En FDTD, el método direccional conserva aproximadamente **2,8%** de error mediano en las mallas de 0,10 y 0,15 mm. En la malla de 0,15 mm el gradiente original tiene **7,61%** sobre los mismos 209 píxeles.
- La elección del método sigue dependiendo del campo: el gradiente es muy preciso para ondas planas; AIA supera al direccional en el campo de corte difuso 3D. No hay un método ganador universal.
- La inversión A0 libre recuperó sus referencias bajo el modelo conocido. Aplicar Rayleigh a A0 generó errores de **-96.50% a -0.98%**. El umbral `kh≤0,6` de la aproximación delgada aceptó 7/54 referencias y permitió hasta **13.33%** de error.
- Los planos experimentales continúan con soporte localizado y dependiente de parámetros. A +0,25 mm no se aceptaron velocidades en los barridos. La superficie y la sincronización espacial siguen sin verificar.

## Alcance y archivos

| Estudio | Casos / evaluaciones finales | Artefactos |
| --- | ---: | --- |
| Velocidad estocástica | 80 realizaciones principales + 8 con huecos + 16 controles; 312 ejecuciones de método | [CSV por realización](speed_robustness/speed_robustness_trials.csv), [resumen detallado](speed_robustness/hallazgos_velocidad.md) |
| Frecuencia suministrada | 5 frecuencias × 3 métodos = 15 evaluaciones | [CSV](speed_robustness/frequency_detuning_probe.csv) |
| FDTD sin contacto | 3 mallas + 1 paso temporal alternativo; 12 estimaciones nuevas y 24 originales | [métricas](fdtd_resolution/estimator_metrics.csv), [coordenadas comunes](fdtd_resolution/mesh_common_coordinates.csv), [configuración](fdtd_resolution/fdtd_settings.json) |
| Young | 90 referencias físicas, incluidas 54 A0; 234 conversiones y 1296 perturbaciones de entrada | [modelos](young_sensitivity/young_model_comparison.csv), [sensibilidad](young_sensitivity/young_input_sensitivity.csv) |
| Datos experimentales | 180 barridos de parámetros + 20 perturbaciones de control | [CSV](experimental_sensitivity/experimental_sensitivity_trials.csv) |
| Regresión del repositorio | 50 PASS, 2 FAIL preexistentes | [resultados](regression_results.csv), [registro](regression.log) |

Las evaluaciones que reutilizan un mismo campo o plano no son adquisiciones independientes. El número de ejecuciones no constituye una medida de evidencia estadística. Los resultados anteriores a la corrección están conservados en `before_directional_fix`; los de la validación inicial están en `previous_validation` y no se mezclan con los mapas finales.

## Velocidad: ruido, mezcla de ondas y soporte

Campos homogéneos independientes con `c=2 m/s`, `f=1000 Hz`, cuatro semillas, 61×61 posiciones a 100 µm y 80 tiempos a 50 µs. El SNR temporal usa RMS del movimiento limpio dividido por la desviación del ruido gaussiano. Ventana 2,4×2,4 mm; máximo lag AIA 1 mm. Con la ventana completa, la cobertura máxima del campo es 36,79%; los bordes cuentan como rechazo. Se corrigió también el redondeo flotante al resolver ventanas y lags exactamente enteros.

Ejemplo a **SNR 5 dB**, mediana entre semillas; rango de las medianas de error entre corchetes:

| Campo | Método ilustrado | Error absoluto mediano % [mín–máx] | Cobertura mediana % |
| --- | --- | ---: | ---: |
| Onda plana | phase_gradient | 0.07 [0.07–0.10] | 36.79 |
| Reflexión fuerte | directional_phase | 0.63 [0.60–0.70] | 32.96 |
| Difuso planar 2D | reverberant | 2.10 [1.98–2.87] | 34.52 |
| Corte difuso 3D | reverberant | 4.03 [3.70–5.02] | 34.36 |

![Robustez y cobertura](speed_robustness.png)

![Referencia, estimado y error](speed_examples.png)

Los métodos ilustrados corresponden a hipótesis explícitas; todas las combinaciones de método/campo se conservan en los CSV. El error se calcula sobre la máscara aceptada; una cobertura menor puede reducirlo. Las bandas son mínimo–máximo entre cuatro semillas, no intervalos de confianza. Los huecos medidos permanecen NaN.

![Control de movimiento uniforme](directional_null_comparison.png)

Los tres guardas de entrada (Nyquist temporal, menos de un ciclo, rango de velocidad descendente) rechazaron las solicitudes inválidas. Un control espacial ya aliasado devolvió una velocidad aparente distinta de la física: el mapa por sí solo no identifica de manera única ese alias. En la prueba de frecuencia, suministrar 1100 Hz a una onda de 1000 Hz desplazó la velocidad aproximadamente 10%, aun con ajuste temporal alto. Revisar frecuencia y muestreo forma parte de la interpretación.

## FDTD: resolución espacial y temporal

Simulador de Claude sin modificaciones: material elástico homogéneo de 12 kPa, ν=0,495, ρ=1000 kg/m³, superficie libre, pulso gaussiano sin contacto y dominio 9×3,4×4 mm. Se mantuvo 1,2 mm de espesor físico PML. Celdas 0,20/0,15/0,10 mm, Courant 0,85; un caso adicional a 0,15 mm usa Courant 0,50. Se muestreó 8 ms a 40 µs, derivó el desplazamiento axial y analizó 1 kHz con ventana 1,5 mm.

| Caso | Error direccional % | Error original sobre soporte común % | Cobertura % | Píxeles comunes |
| --- | ---: | ---: | ---: | ---: |
| fdtd_cell_0.20mm_courant_0.85 | 3.68 | 9.09 | 93.75 | 150 |
| fdtd_cell_0.15mm_courant_0.85 | 2.76 | 7.61 | 67.86 | 209 |
| fdtd_cell_0.10mm_courant_0.85 | 2.84 | 7.49 | 65.45 | 432 |
| fdtd_cell_0.15mm_courant_0.50 | 2.76 | 7.60 | 67.86 | 209 |

![Malla FDTD](fdtd_validation.png)

![Mapas direccionales FDTD](fdtd_resolution/directional_maps.png)

La diferencia mediana absoluta direccional entre 0,15 y 0,10 mm, interpolando exclusivamente para comparar coordenadas físicas comunes, fue **0.460%** en 180 coordenadas. El resultado numérico no se rellena. La reducción de Courant produjo cambios muy pequeños en las medianas, que se conservan en el CSV. AIA no aceptó velocidades en la malla de 0,20 mm con estos parámetros.

Esta es una prueba de sensibilidad, sin extrapolación Richardson ni orden de convergencia demostrado. La referencia de 1,912581 m/s corresponde al semiespacio continuo, no a la solución exacta del dominio finito. Las mallas tienen distintos muestreos y ventanas discretas realizadas.

## Young: modelo conocido y sensibilidad de entrada

Se generaron 54 referencias A0 mediante una ecuación secular forward independiente: E=3/12/30 kPa, h=0,1/0,3/1 mm, f=300/1000/2000 Hz, ν=0,45/0,495. Se añadieron 36 referencias Rayleigh/corte. No se generó la referencia con la función de inversión. El error numérico máximo del modelo correcto fue **8.58e-08%**. Es una verificación bajo un modelo ideal conocido, no una estimación de exactitud experimental.

![Elección del modelo](young_sensitivity/young_model_bias.png)

![Sensibilidad de Young](young_sensitivity/young_input_sensitivity.png)

En A0, sobreestimar la velocidad un 5% produjo errores de Young de **10.46% a 21.06%**; un +10% produjo **21.48% a 45.31%**. La densidad transmite su error aproximadamente de forma lineal. Espesor y Poisson también afectan la conversión; se rechazaron 90 perturbaciones de Poisson no físicas. Las bandas de las figuras describen escenarios deterministas, no incertidumbre medida. No se aplicó este cálculo a los BIN experimentales.

## Experimentos: sensibilidad y controles

Se reutilizaron los cuatro planos de movimiento guardados de los BIN suministrados; no se releyó el raster de 16,4 GB. Frecuencias nominales externas: Luis3 1 kHz, raster 2 kHz. Se compararon intervalo completo y 2–4 ms; coherencia 0,2/0,4/0,6; ventanas 0,8/1,2/1,8 mm. Para B-mode la ventana axial fue 0,08 mm. No se optimizaron estos valores contra una verdad experimental inexistente.

Referencia predeclarada: 2–4 ms, coherencia 0,2, ventana lateral 1,2 mm:

| Plano | Método / modelo | Cobertura % | Velocidad mediana m/s |
| --- | --- | ---: | ---: |
| luis3_bmode1_offset_0p00mm | directional_phase / scalar2d | 0.021 | 1.812 |
| raster_offset_0p00mm | directional_phase / scalar2d | 6.320 | 2.334 |
| raster_offset_0p00mm | reverberant / scalar2d | 12.640 | 2.460 |
| raster_offset_0p00mm | reverberant / shear3d | 12.640 | 2.166 |
| raster_offset_0p10mm | directional_phase / scalar2d | 4.800 | 2.498 |
| raster_offset_0p10mm | reverberant / scalar2d | 10.960 | 2.490 |
| raster_offset_0p10mm | reverberant / shear3d | 10.960 | 2.190 |
| raster_offset_0p25mm | directional_phase / scalar2d | 0.000 | nan |
| raster_offset_0p25mm | reverberant / scalar2d | 0.000 | nan |
| raster_offset_0p25mm | reverberant / shear3d | 0.000 | nan |

![Mapas por profundidad](experimental_depth_maps.png)

![Sensibilidad de parámetros](experimental_parameter_sensitivity.png)

Los CSV guardan IoU, retención de píxeles y cambios de velocidad en soporte compartido respecto de la referencia del mismo método/modelo. Una IoU alta mide estabilidad, no exactitud. Se ensayaron shuffle temporal común y reemplazo de la fase armónica por fases independientes conservando amplitud/residuo. El máximo soporte aceptado de estas 20 perturbaciones fue **0.440%**; son diagnósticos de semilla fija, no p-values. Los supuestos de superficie y repetibilidad permanecen abiertos. En los registros cortos, una coherencia mayor puede reflejar también ajuste de ruido.

## Regresión, procedencia y reproducción

Regresión canónica con `UpdateBaseline=false`: **50 aprobadas, 2 fallos preexistentes, 0 omitidas**. Los fallos son el inventario MIMT (151 esperados/144 presentes) y el contrato de vídeo filtrado (test espera false, workflow previo true). No se alteraron goldens ni tolerancias para ocultarlos. La regresión local incluye ahora el movimiento uniforme direccional y el redondeo de lags.

MATLAB R2025b, CPU, `-singleCompThread`; Python 3.14.3, NumPy 2.5.3, Matplotlib 3.11.2. [source_hashes.csv](source_hashes.csv) identifica los propietarios científicos al cierre. Los datos BIN originales se conservaron. Los scripts son validación observacional guardada en `results`, no nuevos tests redundantes del catálogo.

Desde MATLAB, configure el directorio de esta validación y ejecute:

```matlab
validationRoot = 'C:/Users/proyecto.pi1081/Desktop/SD-OCT-1310-nm/OCE_workflow/results/extended_validation_2026-10-05';
workflowRoot = fileparts(fileparts(validationRoot));
run(fullfile(workflowRoot,'startup.m'));
addpath(validationRoot,fullfile(validationRoot,'speed_robustness'), ...
    fullfile(validationRoot,'young_sensitivity'),fullfile(validationRoot,'fdtd_resolution'));
run_speed_robustness_validation;
run_frequency_detuning_probe;
run_young_sensitivity;
run(fullfile(validationRoot,'experimental_sensitivity','run_experimental_sensitivity.m'));
run_fdtd_evaluation;
export_validation_maps;
```

Los generadores Python `young_sensitivity/generate_young_reference_cases.py` y `fdtd_resolution/run_fdtd_resolution.py` usan el entorno del simulador. El segundo vuelve a ejecutar las cuatro simulaciones. `render_validation_summary.py` reconstruye las figuras y este resumen desde CSV; `young_sensitivity/render_young_sensitivity.py` reconstruye las figuras de Young. Consulte cada cabecera para paths de entrada y requisitos.
