# Validación B-scan e inclusión doble con ocho excitaciones independientes

Los mapas están en `../Speed_Young_Maps/`. Esa carpeta contiene únicamente
imágenes PNG de velocidad/Young; los MAT, CSV, scripts y diagnósticos están aquí.
No se rellenan píxeles sin soporte ni se usa el material verdadero para ajustar
los estimadores. Los errores siguientes son medianas de errores absolutos
relativos sobre las regiones explícitas de evaluación, no intervalos de confianza.

## Inclusión doble y protocolo secuencial

Dos círculos solapados: cabeza de radio 2.2 mm y cola de radio 1.2 mm,
ambos de 24 kPa, en fondo de 12 kPa. Se resolvió la ecuación global SH escalar
con módulo de corte variable para ocho fuentes individuales a 0:45:315 grados.
Cada adquisición tiene una fuente y una fase independiente; no se suman
fasores entre disparos. Es una validación de ese modelo SH 2D, no del conjunto
completo de modos de una adquisición OCE tridimensional.

La ventana solicitada de 1.2 mm abarca 17 muestras (1.14286 mm). La máscara
de centros exige que el footprint completo permanezca en campo lejano,
a ≥2 longitudes de onda de referencia del soporte de la fuente. La máscara
no retira vecinos medidos del ajuste. El residuo del problema directo es
≤1.01e-13; la refinación espacial cambia el campo de ROI 3.48 % en norma L2
tras una sola escala global, y 1.80/1.91 % en los núcleos de cabeza/cola.
El ruido temporal es 25 dB. Consulte `fish_forward/fish_forward_summary.md`.

| Producto PG | Cobertura del ROI | Error mediano velocidad | Discrepancia mediana Young |
| --- | ---: | ---: | ---: |
| Direcciones individuales | 76.66–88.59 % | 0.89–1.38 % | 1.77–2.76 % |
| Fusión robusta de lentitudes, ≥4/8 | 100 % | 0.67 % | 1.34 % |

La fusión da **24.234 kPa** en la cabeza y **23.196 kPa** en la cola.
Las discrepancias medianas absolutas en sus núcleos puros son **1.74 %**
y **3.35 %**, con 1281 y 107 píxeles respectivamente. El fondo da 1.04 %.
El contorno blanco de las figuras es la geometría simulada de referencia,
no un borde detectado por la reconstrucción.

La fusión direccional tiene menor error global de velocidad (0.40 %), pero
mayor discrepancia en la cola (13.65 %). La mediana simple de las velocidades
PG también mejora el error global frente a la media robusta ponderada
(0.46 % frente a 0.67 %): no hay superioridad universal de la fusión propuesta.
La autocorrelación secuencial promedia correlaciones de cada adquisición,
sin términos cruzados entre fuentes. Su ventana de 2.4 mm no deja núcleo
puro en la cola pequeña; no permite afirmar que recupera ese material.

Los dos controles nulos (fase espacial independiente con tono coherente y
barajado temporal independiente por píxel) dan **0/28561** píxeles aceptados
para las fusiones PG/direccional. Son controles concretos, no una garantía
universal. Métricas: `estimators/fish_estimator_metrics.csv`,
`fish_fusion_common_support.csv`, `fish_regional_gallery_metrics.csv` y
`fish_null_controls.csv`.

## B-scan simulado: Rayleigh y Lamb

`bscan_simulation/evaluate_bscan_maps.m` usa una configuración prefijada:
ventana axial .04 mm; ventana lateral .8 mm para Rayleigh y media longitud
de onda para Lamb; coherencia .65, soporte .8, error de ajuste .30.
Las regiones de evaluación tienen 100 % de cobertura en estos ensayos.

| Caso / estimador | Error velocidad | Discrepancia Young |
| --- | ---: | ---: |
| Rayleigh exacto XZ, SNR20 dB, PG | 0.110 % | 0.220 % |
| Rayleigh exacto XZ, SNR20 dB, direccional | 1.857 % | 3.722 % |
| Rayleigh FDTD XZ, PG | 2.331 % | 4.654 % |
| Rayleigh FDTD XZ, direccional | 2.003 % | 4.045 % |
| Lamb físico con inclusión, núcleo, PG | 3.859 % | 14.564 % |
| Lamb físico con inclusión, núcleo, direccional | 0.530 % | 2.114 % |

Esto respalda elegir PG en un modo limpio y considerar el filtro direccional
cuando hay reflexiones/interferencia. No convierte Lamb→direccional y
Rayleigh→PG en una regla universal: en este Rayleigh FDTD ambos son similares.

**Exact XZ** significa solución analítica del modo Rayleigh en semiespacio
homogéneo, con perfil axial físico y velocidad modal conocida; se añade ruido.
**True FDTD XZ** significa corte X–Z de desplazamiento axial de una simulación
elastodinámica real con fuente, malla, absorbente y dominio finito. Se toma su
fasor estacionario convergido y se sintetiza una señal temporal armónica con
ruido; no reproduce los errores de adquisición/reconstrucción óptica del OCT.
La comparación FDTD usa la expectativa Rayleigh continua como referencia,
no una velocidad modal discreta exacta. X es lateral y Z es profundidad.

El caso Lamb es un corte de la solución global de placa Kirchhoff–Love con
rigidez variable. Su desplazamiento transversal es uniforme a través del
espesor según esa aproximación. Ni ese caso ni Rayleigh acreditan módulos
independientes por capa: las filas contienen el mismo modo observado a
profundidades distintas. Las interfaces mezcladas se muestran y se excluyen
sólo de las métricas de material puro, no de los mapas medidos.

## Luis3 independiente: por qué parecía todo gris

No era un fallo de renderizado. La configuración previa aceptaba sólo
11 de 52350 píxeles. La señal coherente está concentrada aproximadamente
entre Z=.254–.296 mm, más estrecha que la ventana axial previa de .08 mm.
La mayor parte del registro completo carece de soporte armónico suficiente.

Se evaluaron 720 combinaciones PG/direccionales y 8 AIA sobre los cuatro
B-modes **independientes**, sin concatenar fases. Con ventana prefijada
X=.9 mm / Z=.04 mm y tiempo 2–4 ms, PG acepta 232/149/96/78 píxeles en
B1–B4. B1 contiene un pico cercano a 1002.5 Hz y un paquete temprano localizado.
Diez controles de fase espacial aleatoria dan ≤2 píxeles PG aceptados frente
a 232 observados. Los controles direccionales permiten más falsos positivos:
por eso no se elige su mayor cobertura como prueba de mejor reconstrucción.

Esta señal permite un resultado exploratorio localizado, **no un mapa extenso
ni Young experimental validado**. La posición de la banda OCT y el borde
requieren revisión, y no existe referencia mecánica experimental. Los mapas
de Young se etiquetan como condicionales a un modelo, densidad y Poisson.
Consulte `experimental_bscan/` para las trazas, rechazos, controles y mapas.

La [comprobación directa del BIN actual](experimental_bscan/LEEME.md) distingue
los planos anteriores del default conservador: el detector heredado encuentra
2/75 bordes y el límite incremental pi deja 150 píxeles de soporte; PG acepta
cero. La entrada exploratoria explícita `max_in_search` con límite 2pi reproduce
exactamente el MAT anterior y sus 232 estimaciones B1. Esto comprueba la
dependencia de bordes/QC y reproducibilidad, no anatomía ni exactitud material.
Ambos parámetros están expuestos en el modo BIN interactivo.

La [comparativa FDTD ampliada](../fdtd_exact_comparison_2026-10-05/Resumen_comparativa.md)
añade nueve figuras pareadas con referencias Exact XZ; la galería final contiene
45 PNG. La regresión posterior a los controles UI conserva 50 PASS y los dos
fallos previos; registro: `canonical_after_ui.log`.

## Entradas MATLAB y parámetros

* `workflows/run_elastography_interactive.m`: `input_mode="bin"` o `"stepwise"`.
  En stepwise reutiliza reconstrucción, fase incremental y bordes; no relee BIN.
* `run_acquisition_stepwise.m`, sección 7C; `run_raster_enface_stepwise.m`,
  sección 9: activar `show_local_wave_maps` para abrir el análisis interactivo.
* `run_multi_excitation_elastography.m`: MAT, lista de BINs o productos stepwise,
  ajuste individual opcional, máscara de campo lejano y fusión robusta.

B-scan selecciona un segmento independiente en cada geometría. Enface usa
raster/espiral/anillos y sus posiciones físicas; los huecos interpolados sin
soporte no se convierten en mediciones. Los bordes anterior/posterior y su
máscara estructural limitan el plano. Cambiar bordes/profundidad requiere
reconstruir el plano; cambiar parámetros locales permite recalcular mapas.
Ventanas mayores reducen resolución; una ventana grande puede eliminar por
completo el núcleo de la cola pequeña. Coherencia, amplitud, soporte y error
de ajuste deben compararse con controles y estabilidad, no relajarse sólo
para colorear todo el campo.

Las recomendaciones de registro temporal, calibración y metadatos se detallan
en las notas de adquisición de esta carpeta. Especialmente: registrar el
flanco y/o waveform de excitación real en el reloj de adquisición, además del
log de comandos del generador, y asociarlo a cada posición y cada disparo.
