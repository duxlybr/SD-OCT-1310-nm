# Fish: problema directo escalar con ocho excitaciones individuales

Se generaron **ocho soluciones independientes**, una por dirección nominal entrante `0:45:315°`. Cada solución contiene una sola fuente lineal de apertura finita. No se sumaron fuentes simultáneas ni fasores entre adquisiciones. Las fases globales de inicio son independientes y están guardadas; no se presupone coherencia de fase entre adquisiciones.

El problema directo es `div(μ grad U)+ρ ω² U = −F`, con `μ = E/[2(1+ν)]`. El operador conserva flujo mediante medias armónicas de μ en las caras. La inclusión produce reflexión, transmisión y difracción a través de la PDE; no se dibuja una fase a partir del mapa local de velocidades. Una única factorización por malla se reutiliza para resolver los ocho vectores de fuerza separados. El interior observado no tiene pérdidas y el absorbente es un término de masa complejo periférico.

Este es un modelo de corte escalar antiplano 2D. No reproduce Lamb, Rayleigh, toda la elastodinámica 3D, OCT ni fuerza experimental sin contacto. La comparación de Young será condicional a `bulk_shear`: `E=2ρ(1+ν)c²`. `truth_speed` contiene el coeficiente material de velocidad escalar, no una promesa de que el campo interferente tenga un gradiente de fase único en cada píxel.

## Geometría y parámetros fijados

| Parte | Centro (mm) | Radio (mm) | Young (kPa) |
|---|---|---:|---:|
| Cabeza | (−1, 0) | 2.2 | 24 |
| Cola | (2.3, 0) | 1.2 | 24 |
| Fondo | — | — | 12 |

La distancia entre centros es 3.3 mm y la suma de radios 3.4 mm: el solapamiento axial es **0.1 mm**. La inclusión es la unión de ambos discos, del mismo material; no hay una interfaz constitutiva entre cabeza y cola.

- `ρ=1000 kg/m³`, `ν=0.495`, `f=1800 Hz`.
- Velocidad material escalar: fondo 2.00334 m/s; cabeza y cola 2.83315 m/s. Longitud de onda del fondo: 1.11297 mm.
- Dominio: ±15 mm; 421² nodos; `dx=1/14 mm≈0.0714286 mm`, equivalentes a 15.58 puntos por longitud de onda del fondo.
- Absorbente a partir de `max(|x|,|y|)=13.8 mm`; condición exterior Dirichlet.
- Cada fuente está centrada a 12 mm del origen, en sentido opuesto a la dirección entrante. Anchura normal gaussiana `σ=0.15 mm`; semiapertura transversal supergaussiana de 7 mm. La fuerza se anula bajo una amplitud relativa de `10⁻³`.
- Los centros de fuente (mm), en orden angular, son `(−12,0)`, `(−8.485,−8.485)`, `(0,−12)`, `(8.485,−8.485)`, `(12,0)`, `(8.485,8.485)`, `(0,12)`, `(−8.485,8.485)`.
- El ángulo es la dirección **nominal entrante**; la apertura finita y la inclusión pueden alterar direcciones locales. Se exporta `real(U exp(−iωt))`; la convención MATLAB `+iωt` recupera `conj(U)` y utiliza ese ángulo físico.
- Exportación: `197×197×160` muestras por adquisición, ejes aproximadamente ±7 mm; 40 muestras/ciclo, cuatro ciclos. Ruido blanco temporal de 25 dB, semilla distinta por adquisición. El RMS del fasor se normaliza a 10 nm escalando consistentemente la fuerza, sin cambiar el campo de fase.

La máxima fracción de norma L2 cuadrada de la fuerza que coincide con el inicio del borde absorbente es 0.01755%, en direcciones diagonales; se conserva y se documenta. Ninguna fuerza ni absorbente está dentro del campo observado.

## Máscaras y campo lejano

La máscara `data.valid_mask` se calcula antes de estimar usando la distancia al soporte de la fuerza, no el parecido al mapa verdadero. La cota normal conservadora del soporte es `σ sqrt(2 log(1000))=0.55754 mm`. Se exige separación de al menos dos longitudes de onda del fondo. El ROI nominal es el cuadrado ±6 mm.

Para la ventana completa de **1.0 mm** se comprobó la distancia de todos sus extremos, incluyendo las esquinas continuas: mínimo 2.02169 λ del soporte de fuente y 7.3 mm del absorbente. Los 28,561 píxeles del ROI cumplen en todas las direcciones. El residual relativo del sistema discreto es ≤1.002×10⁻¹³; esto no demuestra convergencia al continuo.

El fixture guarda núcleos circulares conservadores para esa ventana: cabeza 1369 píxeles, cola 148; fondo 21,828. Estas máscaras afectan solo evaluación. Las ventanas puras obtenidas por erosión binaria exacta de los discos contienen algo más de soporte y se enumeran aparte.

Los parámetros del estimador deben recalcular la máscara de ventana completa a partir de `data.valid_mask` cuando cambie la ventana. En esta malla, una ventana nominal de **1.2 mm** usa 17 muestras y extremos separados 1.14286 mm. La intersección de máscaras completas de las ocho direcciones conserva 28,549/28,561 píxeles del ROI; si se exige toda la apertura continua nominal de 1.2 mm, conserva 28,537. Se excluyen unas pocas esquinas diagonales. Cada extremo real de los ajustes aceptados sigue a ≥2 λ del soporte de fuente.

| Ventana nominal | Muestras | ROI completo común a 8 | Cabeza pura | Cola pura |
|---|---:|---:|---:|---:|
| 1.0 mm | 15 | 28,561 | 1457 | 167 |
| 1.2 mm | 17 | 28,549 | 1281 | 107 |
| 3.0 mm | 43 | 23,605 | 5 | 0 |
| 4.0 mm | 57 | 19,461 | 0 | 0 |

Por tanto, una AIA de 3–4 mm mezcla necesariamente materiales en casi toda la inclusión, sobre todo en la cola. No se deben usar núcleos definidos para 1 mm para atribuir precisión material a una ventana mayor. `fish_window_geometry.csv` conserva conteos y distancias por dirección; `fish_window_geometry_summary.json` conserva la intersección común. Estas son restricciones geométricas declaradas, sin ajuste de parámetros a resultados estimados.

## Controles observacionales

`fish_individual_fields_noise2.mat` conserva exactamente los ocho fasores físicos y cambia únicamente la realización de ruido. Las dos series tienen SNR medido 24.994–25.005 dB y correlación de ruido absoluta <0.00050. `fish_forward_noise_comparison.csv` guarda la comprobación por dirección.

`fish_grid_check_000deg.mat` repite solo la adquisición de 0° a `dx=1/16 mm=0.0625 mm`, 481² nodos y la misma ventana física de 1 mm. Su residual es 1.37×10⁻¹³. Se interpola este campo sobre la malla nominal y se ajusta una sola escala compleja global para retirar la normalización de fuerza y una fase global; no se retiran gradientes ni diferencias espaciales.

| Región | Diferencia relativa L2 del campo | Diferencia de fase mediana absoluta |
|---|---:|---:|
| ROI completo | 3.483% | 0.02744 rad |
| Núcleo cabeza | 1.801% | 0.00994 rad |
| Núcleo cola | 1.911% | 0.01072 rad |
| Fondo | 3.625% | 0.03208 rad |
| Interfaz | 2.678% | 0.01603 rad |

Dos mallas comprueban estabilidad del campo y conservan la geometría nominal, aunque cambie la discretización de la interfaz. No son una prueba de convergencia asintótica ni garantizan el desempeño de ningún estimador. Las métricas de mapas deben evaluarse por separado y conservar cobertura, especialmente en la cola pequeña.

## Contrato y reproducción

- `fish_individual_fields.mat`: `data8{j}` y `cases{j}.data`, ocho adquisiciones estándar; `phasors8{j}`; `angles_deg`; geometría; referencias `truth_speed` y `truth_young`; máscaras. Cada caso incluye `truth_young_pa`, `direction_deg`, `f_hz`, `density_kg_m3`, `poisson_ratio`, fuente, distancias y residual.
- `fish_individual_fields_noise2.mat`: mismo problema directo, ocho realizaciones de ruido alternativas.
- `fish_grid_check_000deg.mat`: un solo caso de refinamiento, separado de los ocho nominales.
- `*_full_forward_phasors.npz`: campos completos del dominio para auditoría física.
- `*_diagnostics.json`: configuración, distancias, fases, fuerza, residuales, versiones y hash de fuente.
- `fish_forward_contract.json`: variables MAT, esquema y hashes del generador/verificador.

Ejecutar `generate_fish_individual_fields.py` genera nominal y ruido alternativo; `generate_fish_individual_fields.py --grid-check` genera el control. Después ejecutar `verify_fish_forward.py` y `audit_fish_window_geometry.py`. Requieren NumPy/SciPy. Todos estos archivos permanecen fuera de la galería. No se modifica producción ni el simulador de Claude.

El protocolo de ocho adquisiciones es una comparación propia diseñada para este ensayo. No se atribuye a la bibliografía un protocolo experimental publicado de ocho fuentes, ni se presenta su desempeño como resultado experimental.
