# Validacion estocastica independiente de velocidad

Se ejecutaron 80 realizaciones principales (4 campos x 4 semillas x 5 SNR), 8 realizaciones con huecos y 16 controles nulos. Cada realizacion se proceso con 3 metodos: 312 ejecuciones. Tiempo 137.9 s.

Frecuencia 1000 Hz; velocidad fisica 2.0 m/s; malla 61 x 61, paso 100 um, campo 6 x 6 mm; 80 tiempos a 50 us. Ventana 2.4 x 2.4 mm; retardo reverberante maximo 1 mm. El borde que no permite ventana completa cuenta como rechazo: la cobertura maxima es aproximadamente 36.79 % del campo completo.

El SNR corresponde al RMS global de movimiento limpio sobre la desviacion estandar de ruido temporal gaussiano. El error se calcula solamente en pixeles aceptados. No hay inpainting ni penalizacion oculta de NaN. Los rangos entre semillas son descriptivos; cuatro semillas no establecen intervalos de confianza.

## Resultados principales: mediana entre semillas

| Campo | SNR dB | Metodo | Error mediano % [min-max] | Cobertura % [min-max] | Error P95 % |
|---|---:|---|---:|---:|---:|
| axial_shear3d_xy | 0 | directional_phase | 15.80 [5.22-28.29] | 11.64 [4.25-21.77] | 23.51 |
| axial_shear3d_xy | 0 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | 0 | reverberant | 3.76 [2.84-5.45] | 26.23 [13.20-30.48] | 13.52 |
| axial_shear3d_xy | 5 | directional_phase | 16.39 [4.23-26.14] | 24.44 [12.95-28.51] | 27.91 |
| axial_shear3d_xy | 5 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | 5 | reverberant | 4.03 [3.70-5.02] | 34.36 [33.32-35.10] | 11.76 |
| axial_shear3d_xy | 10 | directional_phase | 16.46 [4.55-26.37] | 26.48 [16.26-29.72] | 27.63 |
| axial_shear3d_xy | 10 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | 10 | reverberant | 4.16 [3.73-4.75] | 35.96 [35.85-36.47] | 11.70 |
| axial_shear3d_xy | 20 | directional_phase | 16.70 [4.60-26.73] | 26.91 [16.77-30.18] | 27.62 |
| axial_shear3d_xy | 20 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | 20 | reverberant | 4.34 [3.65-4.76] | 36.63 [36.52-36.71] | 11.64 |
| axial_shear3d_xy | Inf | directional_phase | 16.64 [4.57-26.60] | 27.04 [16.98-30.23] | 27.60 |
| axial_shear3d_xy | Inf | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | Inf | reverberant | 4.35 [3.64-4.76] | 36.64 [36.60-36.71] | 11.65 |
| planar | 0 | directional_phase | 0.72 [0.64-0.79] | 36.79 [36.79-36.79] | 1.40 |
| planar | 0 | phase_gradient | 0.14 [0.13-0.22] | 36.79 [36.79-36.79] | 0.39 |
| planar | 0 | reverberant | 0.99 [0.95-1.04] | 36.79 [36.79-36.79] | 1.31 |
| planar | 5 | directional_phase | 0.67 [0.66-0.69] | 36.79 [36.79-36.79] | 1.32 |
| planar | 5 | phase_gradient | 0.07 [0.07-0.10] | 36.79 [36.79-36.79] | 0.23 |
| planar | 5 | reverberant | 0.57 [0.56-0.59] | 36.79 [36.79-36.79] | 0.76 |
| planar | 10 | directional_phase | 0.68 [0.67-0.69] | 36.79 [36.79-36.79] | 1.28 |
| planar | 10 | phase_gradient | 0.05 [0.04-0.06] | 36.79 [36.79-36.79] | 0.15 |
| planar | 10 | reverberant | 0.41 [0.38-0.41] | 36.79 [36.79-36.79] | 0.53 |
| planar | 20 | directional_phase | 0.67 [0.66-0.68] | 36.79 [36.79-36.79] | 1.26 |
| planar | 20 | phase_gradient | 0.02 [0.01-0.02] | 36.79 [36.79-36.79] | 0.05 |
| planar | 20 | reverberant | 0.35 [0.33-0.36] | 36.79 [36.79-36.79] | 0.39 |
| planar | Inf | directional_phase | 0.67 [0.67-0.67] | 36.79 [36.79-36.79] | 1.25 |
| planar | Inf | phase_gradient | 0.00 [0.00-0.00] | 36.79 [36.79-36.79] | 0.00 |
| planar | Inf | reverberant | 0.34 [0.34-0.34] | 36.79 [36.79-36.79] | 0.34 |
| scalar2d_diffuse | 0 | directional_phase | 4.17 [3.18-4.78] | 13.60 [11.77-19.32] | 9.51 |
| scalar2d_diffuse | 0 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | 0 | reverberant | 2.34 [2.20-3.54] | 27.64 [25.37-28.78] | 6.58 |
| scalar2d_diffuse | 5 | directional_phase | 3.68 [1.78-6.14] | 23.54 [21.90-29.78] | 8.81 |
| scalar2d_diffuse | 5 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | 5 | reverberant | 2.10 [1.98-2.87] | 34.52 [33.97-34.88] | 5.90 |
| scalar2d_diffuse | 10 | directional_phase | 4.12 [1.66-6.32] | 26.86 [22.74-33.03] | 8.92 |
| scalar2d_diffuse | 10 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | 10 | reverberant | 2.07 [1.79-2.86] | 36.12 [35.93-36.28] | 5.83 |
| scalar2d_diffuse | 20 | directional_phase | 4.17 [1.72-6.38] | 27.34 [23.70-33.97] | 9.08 |
| scalar2d_diffuse | 20 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | 20 | reverberant | 2.07 [1.83-2.85] | 36.67 [36.63-36.68] | 5.83 |
| scalar2d_diffuse | Inf | directional_phase | 4.17 [1.70-6.36] | 27.51 [23.68-33.94] | 9.10 |
| scalar2d_diffuse | Inf | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | Inf | reverberant | 2.07 [1.83-2.84] | 36.70 [36.68-36.71] | 5.83 |
| strong_reflection | 0 | directional_phase | 0.61 [0.55-0.65] | 29.16 [29.02-29.27] | 1.36 |
| strong_reflection | 0 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | 0 | reverberant | 2.57 [2.40-2.71] | 29.16 [29.02-29.27] | 3.18 |
| strong_reflection | 5 | directional_phase | 0.63 [0.60-0.70] | 32.96 [32.81-33.03] | 1.34 |
| strong_reflection | 5 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | 5 | reverberant | 0.91 [0.83-0.97] | 32.96 [32.81-33.03] | 1.35 |
| strong_reflection | 10 | directional_phase | 0.69 [0.65-0.70] | 35.22 [34.99-35.31] | 1.32 |
| strong_reflection | 10 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | 10 | reverberant | 0.20 [0.20-0.20] | 35.22 [34.99-35.31] | 0.46 |
| strong_reflection | 20 | directional_phase | 0.68 [0.68-0.69] | 36.79 [36.79-36.79] | 1.28 |
| strong_reflection | 20 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | 20 | reverberant | 0.34 [0.33-0.35] | 36.79 [36.79-36.79] | 0.65 |
| strong_reflection | Inf | directional_phase | 0.68 [0.68-0.68] | 36.79 [36.79-36.79] | 1.27 |
| strong_reflection | Inf | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | Inf | reverberant | 0.33 [0.33-0.33] | 36.79 [36.79-36.79] | 0.64 |

## Controles nulos: falsos positivos

Un campo armonico espacialmente uniforme no tiene velocidad de propagacion identificable. El ruido temporal puro tampoco tiene ground truth de velocidad. Se informa la fraccion aceptada, sin etiquetarla como precision.

| Control | SNR dB | Metodo | Falsos positivos mediana % | Maximo % |
|---|---:|---|---:|---:|
| noise_only | NaN | directional_phase | 0.0000 | 0.0000 |
| noise_only | NaN | phase_gradient | 0.0000 | 0.0000 |
| noise_only | NaN | reverberant | 0.0000 | 0.0000 |
| uniform_harmonic | 0 | directional_phase | 0.0000 | 0.0000 |
| uniform_harmonic | 0 | phase_gradient | 0.0000 | 0.0000 |
| uniform_harmonic | 0 | reverberant | 0.0000 | 0.0000 |
| uniform_harmonic | 10 | directional_phase | 0.0000 | 0.0000 |
| uniform_harmonic | 10 | phase_gradient | 0.0000 | 0.0000 |
| uniform_harmonic | 10 | reverberant | 0.0000 | 0.0000 |
| uniform_harmonic | Inf | directional_phase | 0.0000 | 0.0000 |
| uniform_harmonic | Inf | phase_gradient | 0.0000 | 0.0000 |
| uniform_harmonic | Inf | reverberant | 0.0000 | 0.0000 |

## Huecos medidos

Se incluyen un bloque 9 x 9, una franja 31 x 2 y aproximadamente 4 % de huecos aleatorios. La mascara es identica para los tres estimadores; todas las regiones excluidas permanecen NaN.

- planar / directional_phase: error 0.68 % [0.68-0.73], cobertura 34.30 % [34.23-34.42].
- planar / phase_gradient: error 0.06 % [0.05-0.08], cobertura 34.30 % [34.23-34.42].
- planar / reverberant: error 0.53 % [0.51-0.55], cobertura 34.30 % [34.23-34.42].
- strong_reflection / directional_phase: error 0.60 % [0.58-0.66], cobertura 30.32 % [29.63-30.82].
- strong_reflection / phase_gradient: error NaN % [NaN-NaN], cobertura 0.00 % [0.00-0.00].
- strong_reflection / reverberant: error 0.94 % [0.76-0.98], cobertura 30.32 % [29.63-30.82].

## Muestreo y limites

Los tres guardas de entrada (Nyquist temporal, menos de un ciclo, rango de velocidad descendente) se rechazaron: 3/3. El control de alias espacial ya adquirido muestra que el mapa no identifica por si solo la velocidad fisica original.

Velocidad fisica aliasada: 0.120 m/s; mediana medida: 0.219 m/s; 1369 pixeles aceptados. Ese resultado no debe contarse como exactitud.

Las ondas planas y reflejadas son campos escalares 2D. El campo bulk3D se genera con direcciones esfericas isotropicas y componente axial. No se valida anisotropia material, dispersion Lamb, reconstruccion OCT, conversion de fase a movimiento ni E experimental en este subestudio. Una imagen limpia, un residual pequeno o una cobertura mayor no prueban que el modelo de onda sea correcto.

Los CSV conservan metricas por realizacion, soporte comun entre los tres metodos, soporte comun con phase_gradient y percentil 95 de error. selected_raw_maps.mat contiene mapas sin suavizar, mascaras, diagnosticos y movimiento de casos representativos; validation_settings.mat fija todos los parametros.

## Frecuencia introducida y soporte realizado

La ventana efectivamente realizada es 25 x 25 muestras, extension entre extremos 2.40 x 2.40 mm; 36.79 % es la cobertura maxima con una ventana completa en esta malla. Se utilizan 80 muestras temporales, duracion 3.95 ms y 3.95 ciclos fisicos; retardos AIA realizados: 0.10 a 1.00 mm.

Se mantiene una onda verdadera de 1000 Hz y 2 m/s, con SNR 10 dB y semilla 5171009; solo cambia la frecuencia introducida al estimador. Este control no calibra la frecuencia experimental.

| Frecuencia introducida Hz | Metodo | Sesgo % | Error mediano % | Cobertura % |
|---:|---|---:|---:|---:|
| 900 | phase_gradient | -9.97 | 9.97 | 36.79 |
| 900 | directional_phase | -9.50 | 9.50 | 36.79 |
| 900 | reverberant | -10.36 | 10.36 | 36.79 |
| 950 | phase_gradient | -4.97 | 4.97 | 36.79 |
| 950 | directional_phase | -4.46 | 4.46 | 36.79 |
| 950 | reverberant | -5.36 | 5.36 | 36.79 |
| 1000 | phase_gradient | 0.04 | 0.05 | 36.79 |
| 1000 | directional_phase | 0.57 | 0.70 | 36.79 |
| 1000 | reverberant | -0.37 | 0.37 | 36.79 |
| 1050 | phase_gradient | 5.05 | 5.05 | 36.79 |
| 1050 | directional_phase | 5.60 | 5.60 | 36.79 |
| 1050 | reverberant | 4.61 | 4.61 | 36.79 |
| 1100 | phase_gradient | 10.05 | 10.05 | 36.79 |
| 1100 | directional_phase | 10.63 | 10.63 | 36.79 |
| 1100 | reverberant | 9.59 | 9.59 | 36.79 |

La relacion c=omega/k introduce sensibilidad directa a la frecuencia asumida. Coherencia alta y cobertura estable no sustituyen un valor correcto de frecuencia. Reproducir: startup; addpath(esta carpeta); run_speed_robustness_validation; run_frequency_detuning_probe.
