# Validacion estocastica independiente de velocidad

Se ejecutaron 80 realizaciones principales (4 campos x 4 semillas x 5 SNR), 8 realizaciones con huecos y 16 controles nulos. Cada realizacion se proceso con 3 metodos: 312 ejecuciones. Tiempo 148.3 s.

Frecuencia 1000 Hz; velocidad fisica 2.0 m/s; malla 61 x 61, paso 100 um, campo 6 x 6 mm; 80 tiempos a 50 us. Ventana 2.4 x 2.4 mm; retardo reverberante maximo 1 mm. El borde que no permite ventana completa cuenta como rechazo: la cobertura maxima es aproximadamente 37 El SNR corresponde al RMS global de movimiento limpio sobre la desviacion estandar de ruido temporal gaussiano. El error se calcula solamente en pixeles aceptados. No hay inpainting ni penalizacion oculta de NaN. Los rangos entre semillas son descriptivos; cuatro semillas no establecen intervalos de confianza.

## Resultados principales: mediana entre semillas

| Campo | SNR dB | Metodo | Error mediano % [min-max] | Cobertura % [min-max] | Error P95 % |
|---|---:|---|---:|---:|---:|
| axial_shear3d_xy | 0 | directional_phase | 17.34 [4.65-23.74] | 15.82 [9.41-25.21] | 28.38 |
| axial_shear3d_xy | 0 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | 0 | reverberant | 4.33 [4.05-5.85] | 28.46 [15.67-33.24] | 14.13 |
| axial_shear3d_xy | 5 | directional_phase | 16.51 [4.79-23.13] | 28.96 [18.11-31.95] | 29.94 |
| axial_shear3d_xy | 5 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | 5 | reverberant | 4.60 [4.50-5.95] | 38.00 [37.19-39.08] | 12.86 |
| axial_shear3d_xy | 10 | directional_phase | 16.28 [5.19-23.35] | 30.58 [19.35-34.75] | 29.17 |
| axial_shear3d_xy | 10 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | 10 | reverberant | 4.66 [4.46-5.75] | 39.95 [39.83-40.55] | 13.21 |
| axial_shear3d_xy | 20 | directional_phase | 16.45 [5.37-23.81] | 30.97 [20.77-35.88] | 29.75 |
| axial_shear3d_xy | 20 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | 20 | reverberant | 4.79 [4.38-5.66] | 40.70 [40.61-40.80] | 13.23 |
| axial_shear3d_xy | Inf | directional_phase | 16.37 [5.32-23.80] | 31.05 [21.10-35.93] | 29.65 |
| axial_shear3d_xy | Inf | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| axial_shear3d_xy | Inf | reverberant | 4.77 [4.38-5.66] | 40.71 [40.69-40.80] | 13.24 |
| planar | 0 | directional_phase | 0.75 [0.68-0.80] | 40.88 [40.88-40.88] | 1.65 |
| planar | 0 | phase_gradient | 0.17 [0.16-0.25] | 40.88 [40.88-40.88] | 0.44 |
| planar | 0 | reverberant | 1.01 [0.96-1.06] | 40.88 [40.88-40.88] | 1.39 |
| planar | 5 | directional_phase | 0.70 [0.69-0.72] | 40.88 [40.88-40.88] | 1.64 |
| planar | 5 | phase_gradient | 0.09 [0.08-0.12] | 40.88 [40.88-40.88] | 0.29 |
| planar | 5 | reverberant | 0.59 [0.57-0.59] | 40.88 [40.88-40.88] | 0.85 |
| planar | 10 | directional_phase | 0.71 [0.69-0.71] | 40.88 [40.88-40.88] | 1.64 |
| planar | 10 | phase_gradient | 0.06 [0.06-0.07] | 40.88 [40.88-40.88] | 0.17 |
| planar | 10 | reverberant | 0.41 [0.39-0.43] | 40.88 [40.88-40.88] | 0.56 |
| planar | 20 | directional_phase | 0.71 [0.70-0.71] | 40.88 [40.88-40.88] | 1.62 |
| planar | 20 | phase_gradient | 0.02 [0.02-0.02] | 40.88 [40.88-40.88] | 0.06 |
| planar | 20 | reverberant | 0.35 [0.34-0.36] | 40.88 [40.88-40.88] | 0.40 |
| planar | Inf | directional_phase | 0.70 [0.70-0.70] | 40.88 [40.88-40.88] | 1.61 |
| planar | Inf | phase_gradient | 0.00 [0.00-0.00] | 40.88 [40.88-40.88] | 0.00 |
| planar | Inf | reverberant | 0.35 [0.35-0.35] | 40.88 [40.88-40.88] | 0.35 |
| scalar2d_diffuse | 0 | directional_phase | 4.35 [2.83-4.67] | 19.34 [17.82-24.00] | 10.64 |
| scalar2d_diffuse | 0 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | 0 | reverberant | 2.99 [2.88-3.82] | 30.10 [27.63-32.03] | 8.68 |
| scalar2d_diffuse | 5 | directional_phase | 3.86 [1.73-6.48] | 28.76 [28.46-34.88] | 9.74 |
| scalar2d_diffuse | 5 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | 5 | reverberant | 2.95 [2.80-3.33] | 38.42 [37.79-38.67] | 8.41 |
| scalar2d_diffuse | 10 | directional_phase | 4.32 [1.73-6.55] | 31.42 [30.15-37.06] | 10.26 |
| scalar2d_diffuse | 10 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | 10 | reverberant | 2.94 [2.69-3.24] | 40.16 [39.94-40.31] | 8.35 |
| scalar2d_diffuse | 20 | directional_phase | 4.38 [1.83-6.53] | 31.87 [30.61-38.08] | 10.30 |
| scalar2d_diffuse | 20 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | 20 | reverberant | 2.93 [2.66-3.17] | 40.76 [40.69-40.77] | 8.35 |
| scalar2d_diffuse | Inf | directional_phase | 4.38 [1.79-6.48] | 31.94 [30.74-38.13] | 10.31 |
| scalar2d_diffuse | Inf | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| scalar2d_diffuse | Inf | reverberant | 2.94 [2.64-3.15] | 40.77 [40.77-40.80] | 8.37 |
| strong_reflection | 0 | directional_phase | 0.65 [0.58-0.69] | 32.44 [32.30-32.63] | 1.57 |
| strong_reflection | 0 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | 0 | reverberant | 2.11 [2.03-2.26] | 32.44 [32.30-32.63] | 3.87 |
| strong_reflection | 5 | directional_phase | 0.66 [0.62-0.73] | 36.66 [36.50-36.71] | 1.63 |
| strong_reflection | 5 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | 5 | reverberant | 0.77 [0.70-0.84] | 36.66 [36.50-36.71] | 1.91 |
| strong_reflection | 10 | directional_phase | 0.70 [0.69-0.72] | 39.16 [38.94-39.29] | 1.68 |
| strong_reflection | 10 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | 10 | reverberant | 0.57 [0.57-0.58] | 39.16 [38.94-39.29] | 0.98 |
| strong_reflection | 20 | directional_phase | 0.71 [0.70-0.71] | 40.88 [40.88-40.88] | 1.63 |
| strong_reflection | 20 | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | 20 | reverberant | 0.40 [0.40-0.41] | 40.88 [40.88-40.88] | 1.06 |
| strong_reflection | Inf | directional_phase | 0.70 [0.70-0.70] | 40.88 [40.88-40.88] | 1.63 |
| strong_reflection | Inf | phase_gradient | NaN [NaN-NaN] | 0.00 [0.00-0.00] | NaN |
| strong_reflection | Inf | reverberant | 0.39 [0.39-0.39] | 40.88 [40.88-40.88] | 1.06 |

## Controles nulos: falsos positivos

Un campo armonico espacialmente uniforme no tiene velocidad de propagacion identificable. El ruido temporal puro tampoco tiene ground truth de velocidad. Se informa la fraccion aceptada, sin etiquetarla como precision.

| Control | SNR dB | Metodo | Falsos positivos mediana % | Maximo % |
|---|---:|---|---:|---:|
| noise_only | NaN | directional_phase | 0.0000 | 0.0000 |
| noise_only | NaN | directional_phase | 0.0000 | 0.0000 |
| noise_only | NaN | directional_phase | 0.0000 | 0.0000 |
| noise_only | NaN | directional_phase | 0.0000 | 0.0000 |
| noise_only | NaN | phase_gradient | 0.0000 | 0.0000 |
| noise_only | NaN | phase_gradient | 0.0000 | 0.0000 |
| noise_only | NaN | phase_gradient | 0.0000 | 0.0000 |
| noise_only | NaN | phase_gradient | 0.0000 | 0.0000 |
| noise_only | NaN | reverberant | 0.0000 | 0.0000 |
| noise_only | NaN | reverberant | 0.0000 | 0.0000 |
| noise_only | NaN | reverberant | 0.0000 | 0.0000 |
| noise_only | NaN | reverberant | 0.0000 | 0.0000 |
| uniform_harmonic | 0 | directional_phase | 0.0000 | 0.0000 |
| uniform_harmonic | 0 | phase_gradient | 0.0000 | 0.0000 |
| uniform_harmonic | 0 | reverberant | 0.0000 | 0.0000 |
| uniform_harmonic | 10 | directional_phase | 33.5394 | 40.8761 |
| uniform_harmonic | 10 | phase_gradient | 0.0000 | 0.0000 |
| uniform_harmonic | 10 | reverberant | 0.0000 | 0.0000 |
| uniform_harmonic | Inf | directional_phase | 40.8761 | 40.8761 |
| uniform_harmonic | Inf | phase_gradient | 0.0000 | 0.0000 |
| uniform_harmonic | Inf | reverberant | 0.0000 | 0.0000 |

## Huecos medidos

Se incluyen un bloque 9 x 9, una franja 31 x 2 y aproximadamente 4 % de huecos aleatorios. La mascara es identica para los tres estimadores; todas las regiones excluidas permanecen NaN.

- planar / directional_phase: error 0.72 % [0.71-0.82], cobertura 36.31 % [36.00-36.49].
- planar / phase_gradient: error 0.07 % [0.06-0.09], cobertura 36.31 % [36.00-36.49].
- planar / reverberant: error 0.51 % [0.46-0.52], cobertura 36.31 % [36.00-36.49].
- strong_reflection / directional_phase: error 0.67 % [0.64-0.75], cobertura 33.80 % [33.47-34.05].
- strong_reflection / phase_gradient: error NaN % [NaN-NaN], cobertura 0.00 % [0.00-0.00].
- strong_reflection / reverberant: error 0.80 % [0.77-0.90], cobertura 33.80 % [33.47-34.05].

## Muestreo y limites

Los tres guardas de entrada (Nyquist temporal, menos de un ciclo, rango de velocidad descendente) se rechazaron: 3/3. El control de alias espacial ya adquirido muestra que el mapa no identifica por si solo la velocidad fisica original.

Velocidad fisica aliasada: 0.120 m/s; mediana medida: 0.219 m/s; 1521 pixeles aceptados. Ese resultado no debe contarse como exactitud.

Las ondas planas y reflejadas son campos escalares 2D. El campo bulk3D se genera con direcciones esfericas isotropicas y componente axial. No se valida anisotropia material, dispersion Lamb, reconstruccion OCT, conversion de fase a movimiento ni E experimental en este subestudio. Una imagen limpia, un residual pequeno o una cobertura mayor no prueban que el modelo de onda sea correcto.

Los CSV conservan metricas por realizacion, soporte comun entre los tres metodos, soporte comun con phase_gradient y percentil 95 de error. selected_raw_maps.mat contiene mapas sin suavizar, mascaras, diagnosticos y movimiento de casos representativos; validation_settings.mat fija todos los parametros.
