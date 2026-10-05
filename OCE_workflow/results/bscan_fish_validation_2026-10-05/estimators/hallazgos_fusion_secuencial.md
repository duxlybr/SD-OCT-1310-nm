# Ocho excitaciones individuales sobre dos inclusiones

PG y sector direccional: ventana 1.2 mm, C >= .65, amplitud relativa .05, soporte .75, error circular <= .30 rad. Fusion: al menos cuatro de ocho, consenso relativo en lentitud <= 20 %; amplitudes y fases globales no se suman.

Young es aparente en interfaces y regiones dispersadas; el coeficiente material conocido no fija una velocidad de fase local exacta. Se conserva toda la cobertura rechazada como NaN. AIA secuencial promedia productos internos de cada experimento, con ventana 2.4 mm; no demuestra campo isotropico. No se interpreta cobertura mayor como exactitud.

| Producto | Cobertura % | Error velocidad % | Discrepancia Young % | Error velocidad material puro % |
|---|---:|---:|---:|---:|
| phase_gradient_excitation_000 | 76.66 | 1.02 | 2.03 | 0.84 |
| phase_gradient_excitation_045 | 78.61 | 1.20 | 2.41 | 0.94 |
| phase_gradient_excitation_090 | 88.59 | 1.04 | 2.07 | 0.87 |
| phase_gradient_excitation_135 | 82.18 | 1.38 | 2.76 | 1.04 |
| phase_gradient_excitation_180 | 80.18 | 0.89 | 1.77 | 0.75 |
| phase_gradient_excitation_225 | 82.12 | 1.38 | 2.75 | 1.04 |
| phase_gradient_excitation_270 | 88.58 | 1.03 | 2.07 | 0.87 |
| phase_gradient_excitation_315 | 78.60 | 1.21 | 2.41 | 0.94 |
| phase_gradient_arithmetic_speed_mean | 100.00 | 0.68 | 1.36 | 0.56 |
| phase_gradient_speed_median | 100.00 | 0.46 | 0.93 | 0.38 |
| phase_gradient_arithmetic_slowness_mean | 100.00 | 0.68 | 1.35 | 0.55 |
| phase_gradient_slowness_median | 100.00 | 0.46 | 0.93 | 0.38 |
| phase_gradient_robust_slowness | 100.00 | 0.67 | 1.34 | 0.55 |
| directional_phase_excitation_000 | 97.14 | 0.75 | 1.50 | 0.56 |
| directional_phase_excitation_045 | 95.66 | 0.48 | 0.95 | 0.39 |
| directional_phase_excitation_090 | 96.52 | 0.82 | 1.63 | 0.69 |
| directional_phase_excitation_135 | 97.06 | 0.54 | 1.08 | 0.44 |
| directional_phase_excitation_180 | 96.78 | 0.71 | 1.41 | 0.57 |
| directional_phase_excitation_225 | 97.07 | 0.54 | 1.08 | 0.44 |
| directional_phase_excitation_270 | 96.53 | 0.82 | 1.64 | 0.69 |
| directional_phase_excitation_315 | 95.67 | 0.48 | 0.96 | 0.39 |
| directional_phase_arithmetic_speed_mean | 100.00 | 0.40 | 0.80 | 0.31 |
| directional_phase_speed_median | 100.00 | 0.35 | 0.69 | 0.30 |
| directional_phase_arithmetic_slowness_mean | 100.00 | 0.41 | 0.81 | 0.32 |
| directional_phase_slowness_median | 100.00 | 0.35 | 0.69 | 0.30 |
| directional_phase_robust_slowness | 100.00 | 0.40 | 0.80 | 0.32 |
| aia_individual_excitation_000 | 95.13 | 0.82 | 1.65 | 0.63 |
| aia_individual_excitation_045 | 94.57 | 1.82 | 3.61 | 1.76 |
| aia_individual_excitation_090 | 95.13 | 0.66 | 1.32 | 0.39 |
| aia_individual_excitation_135 | 94.87 | 1.77 | 3.52 | 1.65 |
| aia_individual_excitation_180 | 94.59 | 0.80 | 1.60 | 0.58 |
| aia_individual_excitation_225 | 94.85 | 1.77 | 3.51 | 1.67 |
| aia_individual_excitation_270 | 95.13 | 0.66 | 1.32 | 0.39 |
| aia_individual_excitation_315 | 94.58 | 1.82 | 3.61 | 1.75 |
| sequential_ensemble_autocorrelation | 95.32 | 0.94 | 1.87 | 0.80 |

Comparaciones de fusion en soporte comun de cada familia:

| Metodo | Fusion | Pixeles comunes | Error velocidad % |
|---|---|---:|---:|
| phase_gradient | arithmetic_speed_mean | 28561 | 0.68 |
| phase_gradient | speed_median | 28561 | 0.46 |
| phase_gradient | arithmetic_slowness_mean | 28561 | 0.68 |
| phase_gradient | slowness_median | 28561 | 0.46 |
| phase_gradient | robust_slowness | 28561 | 0.67 |
| directional_phase | arithmetic_speed_mean | 28561 | 0.40 |
| directional_phase | speed_median | 28561 | 0.35 |
| directional_phase | arithmetic_slowness_mean | 28561 | 0.41 |
| directional_phase | slowness_median | 28561 | 0.35 |
| directional_phase | robust_slowness | 28561 | 0.40 |
