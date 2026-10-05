# Luis3: soporte experimental, pulso y B-scans independientes

El mapa gris inicial reflejaba rechazo científico. No había un problema de
renderizado: la configuración direccional inicial X1.2/Z0.08 mm y ROI2–4 ms
aceptaba sólo **11 de 52350 píxeles (0.021%)**. El registro completo con esos
parámetros aceptaba cero. Es necesario distinguir estas figuras exploratorias
de la **entrada BIN actual con los defaults conservadores**, que también
produce **cero estimaciones** al no encontrar bordes suficientes.

## Procedencia y medición

Se estudiaron los cuatro MB independientes de
`OCE_150A_4B_400M_150SS_300mVpp_1000Hz_luis3.bin` (orientaciones de header
0/45/90/135 grados). No se concatenaron B-scans, tiempos ni fases. Las primeras
figuras y el barrido utilizan planos MAT guardados previamente: reconstrucción
con perfil `spectral_domain_1310`, n=1.4, crop FFT1–700, búsqueda50–700,
`max_in_search`, stride lateral2, Loupas axial3, umbral OCT relativo -35dB y
coherencia IQ0.2. El máximo es una **superficie candidata sin validación
anatómica**, próxima al borde inferior del intervalo de búsqueda. La óptica
tampoco tiene calibración independiente confirmada.

Cada plano contiene `[698 profundidad,75 posiciones,399 incrementos]`:
x0–9.933mm, dx0.134228mm; z0.004229–2.951543mm,
dz0.004229mm; t0.010–7.970ms, dt20us, tasa50000Hz. Los tiempos corresponden al
punto medio de incrementos. Los **1000Hz** son la frecuencia de análisis
indicada por el experimento; no se infieren del nombre. Este BIN antiguo carece
de sección de generador. La repetibilidad del retardo/respuesta entre posiciones
MB no está verificada. No existe referencia mecánica experimental.

## Comparación controlada de la entrada BIN actual

`check_current_bin_input.m` realizó una lectura acotada del Bscan1 con el mismo
crop, selección, perfil y gates del plano anterior, usando el default actual
`inherited_threshold` y límite incremental pi. Resultado:

| Entrada Bscan1 | Bordes finitos | Máscara OCT/movimiento | PG aceptados |
|---|---:|---:|---:|
| MAT anterior, máximo candidato | 75/75 | 44398/52350 | 232 |
| BIN actual, detector heredado y límite pi | 2/75 | 150/52350 | **0** |
| BIN explícito exploratorio, máximo y límite2pi | 75/75 | 44398/52350 | 232 |

Los dos bordes que encuentra el detector heredado tienen mediana0.215657mm;
la mediana del máximo previo es0.211429mm. La diferencia máxima común es
4.229um. Antes del límite incremental, el soporte por borde/OCT/coherencia
del BIN heredado contiene1192 píxeles; el límite pi deja150. Este control se
aplica al registro completo, antes de seleccionar la ROI del estimador.
La corrección axial de Loupas puede exceder pi; el límite configurable es un
rechazo conservador, **no una demostración universal de alias o de Nyquist**.

`check_exploratory_bin_input.m` cambió explícitamente sólo superficie a máximo
y límite a2pi, sin cambiar el default de producción. Recuperó **exactamente**
el plano anterior: diferencia máxima de fase0rad, máscara OCT y máscara PG
idénticas, diferencia máxima de velocidades0m/s. Esto verifica reproducción y
dependencia del soporte; **no** verifica anatomía, propagación, registro MB,
modo Rayleigh ni exactitud material. El usuario debe revisar el OCT/borde y
decidir con evidencia qué entrada está justificada.

Los cuatro PNG PG de la galería declaran en el título que provienen del MAT
anterior con `max_in_search`. No representan desempeño del BIN con defaults
actuales ni certifican el conversor STEPWISE con bordes anatómicos validados.
La prueba de conversión STEPWISE es un contrato sintético: dimensiones,
bordes, máscara OCT, tiempos/profundidades y geometría; no un ground truth
experimental.

## Señal transiente y causa del rechazo

El desglose inicial Bscan1 con X1.2/Z0.08mm conserva44398 píxeles OCT,
4864 con coherencia armónica≥0.2 en ROI2–4ms,4531 tras amplitud direccional,
4080 centros con ventana completa,175 con soporte local≥0.6, y11 tras error
de ajuste circular≤0.3. Con el registro completo, la coherencia deja551 y el
ajuste final cero. `initial_rejection_counts.csv` guarda cada etapa.

**Hay señal real localizada**, además de ruido. Las trazas enfocadas cerca de
x≈5mm muestran un paquete con aproximadamente tres oscilaciones entre2–5ms.
La FFT sin padding tiene resolución125.313Hz y pico1002.506Hz, compatible con
la frecuencia indicada; no mide la frecuencia con precisión arbitraria.
La selección diagnóstica de banda/punto usa energía armónica y no modifica
los parámetros del mapa.

| Bscan | Banda enfocada z(mm) | x(mm) | RMS2–4ms / previo0–2ms | Fracción espectral500–1500Hz |
|---|---:|---:|---:|---:|
| 1 | 0.216 | 4.97 | 5.64 | 28.6% |
| 2 | 0.237 | 4.97 | 8.72 | 49.0% |
| 3 | 0.347 | 4.83 | 1.05 | 6.65% |
| 4 | 0.355 | 5.10 | 2.25 | 8.97% |

El foco es fuerte en Bscan1/2 y menos claro en3/4. La envolvente filtrada
500–1500Hz sirve como diagnóstico, puede producir ringing en un registro
corto y no demuestra monomodalidad. El R² del centro temporal de envolvente
contra x es menor que0.007 en los cuatro B-scans: **no aparece un frente global
de llegada que justifique aquí una velocidad por correlación de retardos**.
Esto tampoco descarta propagación local. La respuesta cercana al foco puede
mezclar excitación directa, campo cercano e interferencia; kx pequeño cerca
del foco produce velocidades PG grandes y un Young aparente muy alto.

## Barrido y referencia declarada

`run_independent_luis3_study.m` hizo720 ensayos: cuatro B-scans independientes,
PG y direccional0/180, cinco ventanas temporales, X0.6/0.9/1.2mm y
Z0/0.02/0.04/0.08mm. Se añadieron ocho AIA con apertura resuelta
X/Z1.2mm y lag0.6mm (scalar2d y shear3d). No se relajaron los gates armónicos:
C0.2, amplitud relativa0.08, soporte0.6, error0.3, c0.2–10m/s; no smoothing.

La referencia exploratoria PG usa X0.9/Z0.04mm (7x9 muestras), ROI2–4ms.
La banda axial más estrecha reduce mezcla de señal superficial y ruido
profundo. No se eligió un parámetro por error contra un ground truth inexistente.
El core actual fue ejecutado nuevamente sobre los cuatro planos guardados:

| Bscan | PG aceptados | Cobertura del plano | Mediana c(m/s) | Mediana Young aparente(kPa) |
|---|---:|---:|---:|---:|
| 1 | 232 | 0.443% | 3.099 | 31.51 |
| 2 | 149 | 0.285% | 3.647 | 43.64 |
| 3 | 96 | 0.183% | 3.796 | 47.28 |
| 4 | 78 | 0.149% | 3.816 | 47.78 |

Young utiliza **Rayleigh supuesto**, rho1000kg/m3 y nu0.495, mediante el dueño
`invertYoungModulus`; semiespacio homogéneo/isótropo/elástico y superficie libre.
No se ha identificado ese modo ni esas condiciones de borde en Luis3. Estos
valores son **aparentes y condicionales**, no módulos validados del gel.

Para la misma referencia, direccional0 acepta60/1/2/0 píxeles y direccional180
84/13/20/0. AIA acepta cero en ambos modelos para los cuatro B-scans: no hay
soporte suficiente para esa apertura/modelo; no se prueba que el material no
pueda generar ondas reverberantes bajo otra adquisición.

ROI2–6ms aumenta modestamente la cobertura PG a244/178/104/89, pero cambia
la mediana Bscan1 a2.573m/s frente3.099m/s en2–4ms. Con el registro completo
PG acepta138/96/29/18 y con0–2ms o4–8ms, cero en esta referencia. La dependencia
de ROI es una limitación relevante del transiente, no una precisión ganada por
seleccionar una región favorable.

## Controles de falsa estructura

Bscan1: diez semillas fijadas rotan independientemente la fase armónica de
cada posición lateral, compartida entre sus profundidades, conservando la
estructura axial y el residual temporal. Se prueba también un shuffle temporal
común. Los resultados son diagnósticos, **no p-values**:

| Método | Observado | Fases independientes, rango aceptados | Shuffle común |
|---|---:|---:|---:|
| PG | 232 | 0–2 | 0 |
| Direccional0 | 60 | 0–44 | 3 |
| Direccional180 | 84 | 0–171 | 0 |

La gran reducción PG es compatible con estructura de fase espacial real en
ese plano, pero no certifica que toda esa estructura sea una onda propagante.
El sector opuesto puede aceptar más píxeles bajo un control que con los datos:
**mayor cobertura por sí sola no prueba mejor método ni mejor exactitud**.

## Archivos y reproducción

- Galería `results/Speed_Young_Maps`: cuatro
  `experimental_luis3_bmodeN_phase_gradient_rayleigh_full_and_zoom.png`.
  Muestran campo adquirido completo y zoom axial explícito0.18–0.46mm.
  Gris conserva todas las regiones sin estimación; no se suaviza ni rellena.
- `archived_gallery`: antiguo PNG direccional Bscan1 conservado.
- `independent_bscan_trials.csv`, `bmode1_phase_controls.csv`: barrido/controles.
- `fixed_pg_speed_apparent_Young_metrics.csv`, `fixed_pg_core_hashes.csv`:
  referencias actuales y hashes SHA256 del core utilizado.
- `fixed_pg_reference_manifest.mat`, `luis3_bmodeN_fixed_pg_reference.mat`:
  parámetros, máscaras, velocidades e inversión condicional; sin copiar el BIN.
- `luis3_bmodeN_focused_packet.png`, `focused_packet_metrics.csv`:
  trazas/envolvente/espectro y soporte diagnóstico, fuera de galería.
- `current_bin_input_check.*`, `exploratory_max_surface_input.*`: lecturas BIN
  acotadas y comparación explícita de entrada/defaults.

Ejecute scripts desde esta carpeta mediante `run` en MATLAB R2025b. Los
resultados anotan la procedencia; los scripts no alteran los BIN originales.
Las figuras de diagnóstico con coherencia, bordes, señal/espectro permanecen
fuera de la galería solicitada de mapas de velocidades/Young.
