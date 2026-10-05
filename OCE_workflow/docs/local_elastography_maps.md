# Mapas locales interactivos de OCE

Abra `workflows/run_elastography_interactive.m` en MATLAB R2025b y ejecute las
secciones. `source_file=[]` abre una interfaz con selector BIN/MAT. Para los
dos ejemplos experimentales suministrados, configure manualmente **1000 Hz**
para Luis3 y **2000 Hz** para raster. Es la frecuencia mecánica de análisis,
no la portadora ultrasónica, el período entre posiciones ni la tasa A-line.
Los archivos nuevos proporcionan la frecuencia cuando el generador está
documentado en el encabezado. La ausencia de generador queda como dato ausente.

## Dos entradas y geometría

En `run_elastography_interactive.m`, `input_mode="bin"` lee el archivo por
bloques; `input_mode="stepwise"` consume `acquisition_state` y `border_result`
ya calculados. La segunda entrada usa `oce.acquisition.buildWaveMotionPlane`:
no repite lectura BIN ni FFT. El driver inicia con `phase_product="raw_wrapped"`
y `phase_derivative_2d`: conserva `angle(IQ)` en la rejilla nativa de
profundidad, posición y tiempo. Una fase óptica absoluta envuelta requiere
unwrap antes de ser usada como señal mecánica.

La interfaz inicia con unwrap óptico temporal por voxel independiente: la fase
estática de distintos dispersores puede ser aleatoria. `temporal_depth` añade
un supuesto de continuidad entre profundidades y permanece disponible para
comparación explícita. Un mapa de velocidad más limpio no demuestra que ese
supuesto recupere mejor el movimiento crudo. La rama incremental previa sigue
disponible mediante `phase_product="phase_increment"` y reutiliza `phase_result`.

También puede activar `show_local_wave_maps` en la sección **7C** de
`run_acquisition_stepwise.m` o **9** de `run_raster_enface_stepwise.m`.
La sección enface calcula fase de profundidad sólo al activar este análisis:
una traza superficial sola no contiene las capas inferiores. La ventana de
la interfaz conserva los parámetros de reconstrucción bloqueados cuando
recibe un plano en memoria; para cambiar bordes/profundidad/B-mode, reconstruya
el plano en la sección MATLAB y vuelva a abrir la interfaz.

| Plano | Geometrías | Interpretación |
| --- | --- | --- |
| `bmode` | B-mode independiente en angular/lineal, raster y polar | Velocidad de fase lateral a lo largo del corte; nunca se unen B-modes |
| `enface` | Raster, espiral y círculos concéntricos | Propagación XY mediante las posiciones físicas y el operador enface mantenido |

En polar, interpolación geométrica no equivale a medir los espacios vacíos:
los huecos, contribuyentes inválidos y triángulos excesivos deben conservar
NaN. Un corte curvo requiere interpretar su coordenada como distancia sobre
la trayectoria, no como un corte cartesiano recto. La repetibilidad temporal
entre posiciones debe revisarse; `phase_registration_status` documenta
`unverified`, `assumed_repeatable` o `verified`. Un trigger en el encabezado
no cambia automáticamente ese estado a verificado.

Los bordes anterior/posterior y la máscara de intensidad del stepwise limitan
las mediciones admitidas. No se reemplazan por máximos OCT al convertir el
plano. En BIN independiente, revise la propuesta del detector de superficie;
`max_in_search` es una propuesta de señal brillante que requiere revisión,
no una interfaz anatómica certificada. La selección del borde condiciona
profundidad, banda, soporte y espesor físico de una inversión Lamb.

## Procedimiento

1. Seleccione un archivo. En raster, espiral o anillos use `enface`; en meridianos/lineal use
   `bmode` y seleccione una adquisición independiente. No se concatenan fases
   entre B-modes.
2. Ajuste el intervalo FFT que contiene la muestra y el intervalo de búsqueda
   de superficie. La profundidad es relativa a la superficie local; 0 mm
   muestra la superficie, 0.1/0.25/0.5 mm exploran regiones inferiores. El
   espesor axial del plano controla la agregación y mezcla entre capas.
   Use **Revisar OCT y superficie** después de cargar. `max_in_search` propone
   el máximo en el rango; `inherited_threshold` aplica el detector anterior y
   `manual_index` permite fijar un borde plano. Ninguno certifica una interfaz
   anatómica. Las bandas cercanas a DC de estos archivos requieren revisión.
   La coherencia OCT y el promedio axial controlan el soporte de la medición;
   son distintos del rechazo por coherencia armónica del estimador.
3. Pulse **Cargar / reconstruir plano**. La lectura selecciona posiciones y
   procesa bloques; no necesita cargar los 16.4 GB del raster en memoria.
   Los pasos X/Y permiten una exploración inicial más rápida y cambian el
   muestreo físico, por lo que un paso grande puede perder ondas cortas.
4. Configure frecuencia y período temporal que contiene la onda. Examine
   primero la amplitud y calidad; un intervalo con pocos ciclos o sin onda
   no permite inferir una velocidad estable. La proyección armónica no
   convierte automáticamente un pulso dispersivo en onda monomodal.
   **Señal temporal / espectro** abre un mapa seleccionable: pulse un punto
   para revisar la traza, la frecuencia elegida y el intervalo de análisis.
   El relleno de ceros del espectro mejora su dibujo, no su resolución real.
5. Ajuste método, ventanas, dirección, soporte y rechazo; pulse **Recalcular**.
   Ventanas mayores reducen varianza pero mezclan heterogeneidad y reducen la
   resolución del mapa. Comparar métodos es más informativo que forzar cobertura.
6. Seleccione un modelo de Young sólo con una hipótesis física defendible.
   **Exportar MAT + PNG** guarda entrada, medición sin suavizar, presentación,
   máscaras, parámetros y supuestos. El resultado en memoria está en
   `wave_map_ui.UserData`.

Un cambio de reconstrucción exige volver a cargar. Un cambio de estimador sólo
exige recalcular. Los valores NaN permanecen visibles como fondo gris; el
suavizado visual conserva huecos y nunca alimenta la inversión de Young.
`quality` es un diagnóstico de señal/ajuste, no una probabilidad ni un intervalo
de confianza calibrado. Un mapa uniforme o una gran cobertura no demuestran
exactitud sin referencia.

Para una calibración óptica independiente, `initial_options.OCTSystemOptions`
acepta el contrato existente del sistema. No se adopta automáticamente el
preview guardado en GUI como calibración cuantitativa.

## Estimadores y elección del modelo

| Método | Uso principal | Limitación relevante |
| --- | --- | --- |
| `phase_derivative_2d` | Derivadas locales del fasor mecánico tras unwrap; polinomio robusto de orden 1 o 2 | El unwrap no separa ondas interferentes ni identifica el modo físico |
| `phase_gradient` | Campo dominado por una dirección y fase local coherente | Interferencia entre ondas opuestas o varios modos sesga el gradiente |
| `directional_phase` | Onda propagante con reflexiones; aislar una dirección del fasor | Filtro angular y ventana finitos; no separa modos con igual dirección/número de onda cercano |
| `reverberant` + `scalar2d` | Campo difuso escalar de ondas en un plano, perfil J0 | No es el modelo axial de un campo volumétrico de corte |
| `reverberant` + `shear3d` | Campo de corte isotrópico, múltiples direcciones y componente axial observada | Campo incompleto/anisótropo o ventanas pequeñas invalidan la hipótesis difusa |

La dirección se refiere a la **propagación física**, con la convención
`real(P*exp(i*omega*t))`; el sector Fourier apunta en sentido opuesto.
Pruebe la dirección opuesta si la energía filtrada
es insuficiente. Una banda angular estrecha elimina reflexiones pero puede
eliminar la onda deseada o distorsionar un campo curvo.
El filtro elimina previamente el promedio espacial complejo del movimiento
armónico (por fila de profundidad en B-mode). Así evita interpretar la fuga
espectral de un movimiento uniforme como propagación. La amplitud mínima se
compara también con el campo medido antes del filtro; una banda casi vacía no
se normaliza a su propio ruido. Esta sustracción exige una apertura suficiente
para resolver la onda y no identifica por sí sola el modo físico.

### Fase cruda, unwrap y derivada 2D

`workflows/run_phase_unwrap_comparison.m` ejecuta la comparación controlada.
En la interfaz, **Entrada de fase = raw_wrapped** activa este orden:

1. Reconstrucción OCT y selección de soporte mediante bordes/intensidad;
   extracción de fase envuelta sin Loupas, diferencia temporal, suavizado,
   interpolación geométrica ni selección de banda axial.
2. `oce.motion.unwrapPhase` sobre tiempo (`raw_unwrap_domain="temporal"`,
   `dimensions=3`) o tiempo y profundidad (`"temporal_depth"`, `[3 1]`),
   independientemente en cada posición adquirida. Se usa el registro completo;
   no se enlazan posiciones con speckle distinto ni B-modes independientes.
3. `oce.acquisition.finalizeUnwrappedWavePlane`: retiro del promedio temporal,
   agregación axial real e interpolación geométrica con soporte medido.
4. Selección temporal, ajuste armónico con tendencia y Hann, filtro direccional
   opcional, unwrap de la fase **del fasor mecánico**, derivada local y QC.

La interfaz comienza con `temporal` en el modo crudo; `temporal_depth` queda
como comparación con un prior axial explícito. La continuidad del movimiento no implica continuidad de la fase
óptica absoluta entre scatterers de distintas profundidades. Imponer esa
continuidad puede introducir saltos temporales aun con un muestreo temporal
resuelto. La comparación del dominio de unwrap es parte de la validación.

El unwrap óptico recupera movimiento del scatterer; el unwrap modal permite
derivar la fase espacial de la onda. Son productos distintos. Cambiar método
o iteraciones vuelve a desenvolver el mismo producto crudo; cambiar sólo las
ventanas del estimador reutiliza ese producto, sin repetir lectura o FFT.
El MAT exportado conserva la entrada cruda y la procedencia del procesamiento.

| Unwrap | Comportamiento |
| --- | --- |
| `sequential` | Primero tiempo y luego profundidad; respeta los segmentos válidos y depende del orden |
| `least_squares_dct` | Poisson de mínimos cuadrados sobre gradientes envueltos; puede cambiar los valores de fase si los gradientes ruidosos son inconsistentes |
| `tie_dct` | TIE DCT con correcciones enteras; devuelve fase cruda más múltiplos de `2*pi`, con un presupuesto fijo de correcciones |

`tie_dct` implementa el método TIE DCT mencionado como TIE_DTC. El control
`unwrap_iterations=8` significa **un solve inicial y ocho correcciones**, sin
parada por convergencia. Los otros métodos registran cero correcciones ejecutadas.
En componentes válidos rectangulares se usa DCT/Neumann; en componentes con
huecos se resuelve el mismo operador mediante un grafo enmascarado, registrado
en diagnósticos. Los huecos quedan NaN y cada componente tiene un pistón
desconocido; la derivada no mezcla componentes desconectados en un ajuste.
Véase [Zhao et al., 2018](https://doi.org/10.1088/1361-6501/aaec5c).

La derivada 2D estima `c=omega/hypot(kx,krow)` para `pd_geometry="in_plane"`,
siguiendo el principio de derivación local de la fase mecánica utilizado por
[Zvietcovich et al., 2020, ecuación 2](https://pmc.ncbi.nlm.nih.gov/articles/PMC10041740/).
El filtrado direccional y la estimación local 2D también se describen en
[Liu, Kijanka y Urban, 2021](https://doi.org/10.1364/BOE.416661).
El polinomio robusto de segundo orden es una extensión de implementación:
aproxima la curvatura local y evalúa las derivadas en el centro de la ventana;
el primer orden permite comparar un frente local plano. No se presenta como
reproducción literal de esos algoritmos. El filtro direccional precede este
unwrap modal, siempre después del unwrap óptico.

`pd_geometry="auto"` usa `in_plane` en enface y `lateral` en B-scan. En Rayleigh
o Lamb, profundidad representa la estructura modal y puede cambiar de signo;
`lateral` calcula `omega/abs(kx)` con una constante independiente por fila,
sin interpretar ese cambio de fase axial como propagación. Para un campo bulk
oblicuo medido en XZ seleccione `in_plane`; una proyección lateral produce
`c/abs(cos(theta))`. La selección debe basarse en la geometría física.

La autocorrelación angular usa las distancias físicas X/Y/Z; el muestreo
anisótropo de un B-mode no debe tratarse como píxeles cuadrados. Para movimiento
axial de un campo 3D isotrópico, los perfiles normalizados son:

* XY (en-face): `B(q) = 3/2 [j0(q) - j1(q)/q]`.
* XZ (B-mode): `B(q) = 3/4 [j0(q) + j1(q)/q]`.
* Campo escalar planar isotrópico: `B(q) = J0(q)`.

Aquí `q=k*r`, `j0/j1` son Bessel esféricas y `J0` es Bessel cilíndrica. El
modelo no se selecciona usando el aspecto más limpio del mapa: requiere una
hipótesis de propagación. No se aplica un perfil planar a corte volumétrico
simplemente porque los datos se presentan en un plano XY.

## Young y profundidad

`none` es el inicio recomendado durante la exploración. Para medios elásticos,
isótropos y homogéneos:

* Corte volumétrico: `E = 2(1+nu)*rho*c_s^2`.
* Rayleigh de semiespacio libre: `E = 2(1+nu)*rho*(c_R/beta(nu))^2`, con
  beta calculado de la ecuación secular de Rayleigh.
* Lamb A0 de placa libre en régimen delgado:
  `E = 12(1-nu^2)*rho*c_phase^4/(omega^2*h^2)`.
* `lamb_a0_free`: inversión numérica de la ecuación completa Rayleigh–Lamb
  para la rama A0 subsónica de una placa libre, con espesor total conocido.
  Permite salir del límite de placa delgada; conserva las hipótesis de
  homogeneidad, elasticidad, isotropía, ausencia de fluido y de pretensión.
  Para `kh<0.01` se usa el límite asintótico por cancelación de precisión;
  `diagnostics.a0_small_kh_asymptotic_used` identifica esos píxeles.

La aproximación Lamb se rechaza fuera del límite configurado `k*h`. Ese límite
es una política conservadora de aproximación, no una frontera física universal.
No se sustituye velocidad de grupo por velocidad de fase: en el límite flexural
`c_group = 2*c_phase`. Espesor desconocido, fluido, pretensión, curvatura,
anisotropía o varios modos impiden usar esta fórmula como Young cuantitativo.
La dispersión viscosa requiere un modelo de inversión multifrecuencia; una
velocidad armónica aislada no identifica por separado elasticidad y viscosidad.

En raster, los planos inferiores contienen la onda medida a esa profundidad.
Rayleigh y Lamb comparten una estructura modal que penetra varias profundidades:
un mapa en cada plano no equivale automáticamente al Young independiente de
cada capa. La adquisición MB además requiere repetibilidad de la excitación y
de la fase entre posiciones; la presencia de disparos documentados no mide
experimentalmente su jitter.

El lector conserva el perfil/calibración OCT mantenidos. Las diferencias entre
la configuración de previsualización del encabezado y el perfil usado se
documentan; antes de cuantificación experimental deben revisarse la orientación
espectral, compensación de dispersión, profundidad y calibración lateral. El
índice óptico se aplica a profundidad, separado de densidad/Poisson mecánicos.

## Ocho excitaciones individuales y campo lejano

Abra `workflows/run_multi_excitation_elastography.m`. Acepta el MAT `data8`,
una lista de BINs o productos stepwise por adquisición. Modifique las
opciones locales y, opcionalmente, ajuste cada adquisición con la misma
interfaz. Después ejecute la sección de fusión. Las ocho direcciones son
0:45:315 grados sobre el mismo medio; cada disparo mantiene su propia fase,
intervalo temporal y máscara. No se suman fasores de distintos disparos.

`estimateMultiExcitationSpeedMap` ajusta cada campo con el propietario local y
combina **lentitudes** (`1/c`) mediante consenso robusto. Una mediana sirve
como ancla sin peso; la calidad influye con peso limitado, para que un solo
campo muy coherente no domine. Con cuatro de ocho como soporte mínimo y
20 % de tolerancia relativa, desacuerdo y falta de soporte quedan visibles.
Además, se rechaza un consenso si ninguna medida retenida está a menos de
la mitad de esa tolerancia respecto al ancla mediana. Así, cuatro medidas
de 2 m/s y cuatro de 3 m/s no fabrican una velocidad intermedia de 2,4 m/s.
`diagnostics.ambiguous_consensus_mask` registra este rechazo conservador por
hueco alrededor del ancla; el control no demuestra que exista un solo modo.
La dispersión entre disparos es un diagnóstico empírico, no un intervalo
estadístico de confianza. Una media simple puede resultar más precisa en
algunos campos: compare métricas sobre soporte común.

`data.valid_mask` define muestras realmente observadas. El campo opcional
`data.analysis_mask` es una máscara lógica de **centros de salida**, con true
por defecto: restringe donde se estima, pero conserva vecinos medidos para
el ajuste. Use una máscara geométrica erosionada por la ventana completa
para excluir fuente/campo cercano. La validación usa al menos dos longitudes
de onda de referencia desde el soporte de la fuente hasta todo el footprint;
este criterio es operativo y no garantiza ausencia de dispersión o reflexiones.
Cambiar la ventana exige recalcular esa máscara. La verdad constitutiva sólo
se usa para métricas, nunca para llenar huecos o seleccionar ajustes.

El B-scan produce `omega/abs(kx)`: excitaciones con ángulos oblicuos distintos
pueden dar proyecciones distintas aun en material homogéneo. No las fusione
como velocidad de corte sin conocer/corregir la geometría de propagación.
Los mapas en distintas profundidades de un modo Rayleigh o Lamb tampoco
acreditan Young independiente de cada capa.

## Validación reproducible

`workflows/export_simulator_wave_cases.py` importa el simulador de Claude sin
modificarlo, crea casos con verdad conocida y exporta mapas de sus estimadores
originales. Ejecute `--help` para rutas y opciones; después, en MATLAB:

```matlab
addpath(fullfile(pwd,'workflows'));
report = evaluate_elastography_estimators(case_file, results_directory);
```

El CSV informa cobertura, sesgo, error absoluto mediano y RMSE relativo. El MAT
contiene los productos para inspección y comparación de soporte. Los campos
analíticos prueban al estimador; una simulación FDTD incorpora más física, pero
su velocidad modal prevista y su material constitutivo no son referencias
intercambiables. Los ensayos experimentales sin ground truth permiten evaluar
soporte y consistencia, no demostrar exactitud ni garantizar un mapa perfecto.

Consulte la [comparación cuantitativa](local_elastography_validation.md) para
los nueve casos evaluados, soporte común y situaciones donde el método original
conserva mejor desempeño.

## Bibliografía nueva y fundamento

* Asemani et al., **Angular Integral Autocorrelation for Speed Estimation in
  Shear-Wave Elastography**, Acoustics 6, 413–435 (2024).
  [Artículo y ecuaciones de AIA](https://doi.org/10.3390/acoustics6020023).
* Schmidt et al., **Asynchronous optical coherence elastography and directional
  phase gradient analysis**, JBO 30, 124506 (2025).
  [Texto completo](https://pmc.ncbi.nlm.nih.gov/articles/PMC12447186/).
  La implementación local es un gradiente robusto después de filtrar una
  dirección seleccionada; no reproduce el protocolo AsyncOCE ni el banco de
  32 direcciones y combinación completa de DPGA del artículo.
* Asemani et al., **Integrated Difference Autocorrelation: A Novel Approach to
  Estimate Shear Wave Speed in the Presence of Compression Waves**, IEEE TBME (2025).
  [Artículo](https://doi.org/10.1109/TBME.2024.3464104). Motiva distinguir
  movimiento global de propagación; IDA no se implementa en esta primera versión.
* Singh, Zvietcovich y Larin, **Introduction to optical coherence elastography:
  tutorial**, JOSA A 39, 418–430 (2022).
  [Tutorial](https://doi.org/10.1364/JOSAA.444808).
* Zvietcovich et al., **Reverberant 3D optical coherence elastography maps the
  elasticity of individual corneal layers**, Nature Communications 10, 4895
  (2019). [Modelo reverberante axial](https://doi.org/10.1038/s41467-019-12803-4).
* Han et al., **Optical coherence elastography assessment of corneal
  viscoelasticity with a modified Rayleigh–Lamb wave model**, JMBBM 66, 87–94
  (2017). [Artículo](https://doi.org/10.1016/j.jmbbm.2016.11.004).
  Las condiciones sólido–fluido requieren una ecuación modificada; no quedan
  cubiertas por el modelo de placa libre.

## Bordes, QC del incremento y muestreo nativo

En BIN puede ajustar `surface_peak_threshold_db` y `max_phase_step_rad` en
la interfaz, además del intervalo/método de superficie. El segundo es un
límite configurable de QC sobre el incremento de Loupas durante el registro:
no es una prueba universal de alias; la corrección axial puede devolver más
de pi radianes. Valores bajos pueden excluir una posición por eventos fuera
del intervalo armónico elegido. Compare trazas, máscara y bordes antes de
cambiarlo. Un máximo brillante puede ser artefacto: no acredita anatomía.

La conversión polar conserva el muestreo nativo en procedencia, aunque
remuestree a un eje uniforme. La rejilla interpolada no demuestra Nyquist
físico: la comprobación local usa actualmente los ejes finales. Revise las
separaciones reales y la longitud de onda más corta prevista antes de adquirir;
interpolar más fino no recupera una onda ya aliased.

Para mayor precisión, priorice un registro de waveform/TTL real por excitación
y grupo M en reloj común con la cámara; mantenga también los timestamps SCPI
como diagnóstico de software. Guarde frecuencia mecánica y portadora separadas,
forma/duración/ciclos, fase de inicio, amplitud, retardo y referencia observados;
posiciones y tiempos cronológicos por A-line, sentidos de barrido/flyback;
calibración X/Y/Z e índice óptico, bordes y espesor; densidad/Poisson, carga de
fluido y condiciones de frontera. El log de comandos por sí solo no verifica
el jitter. Véanse las [recomendaciones temporales y esquema propuesto](../results/bscan_fish_validation_2026-10-05/fish_forward/acquisition_timing_recommendations.md).
