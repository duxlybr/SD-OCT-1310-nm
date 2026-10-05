# Entrada física para mapas de ondas

`oce.acquisition.loadWaveMotionPlane(binFile, options)` lee posiciones MB por
bloques y conserva únicamente el plano solicitado. `oce.acquisition.buildWaveMotionPlane`
convierte los productos existentes de STEPWISE:

```matlab
data = oce.acquisition.buildWaveMotionPlane( ...
    acquisition_state, phase_result, border_result, options);
```

En el modo incremental predeterminado no vuelve a leer el BIN ni calcula una
nueva fase. Requiere la reconstrucción validada, la geometría de adquisición,
`phase_result.depth_resolved` y el producto de `oce.borders.detectAndMask`.
Una fase superficial aislada no contiene información para reconstruir planos
profundos ni B-scans. El modo explícito de fase cruda descrito abajo reutiliza
el volumen complejo y permite `phase_result=[]`.

La entrada incremental debe tener cantidad `phase_increment`, en radianes y
layout `lateral_depth_time`: Loupas o `unwrap_then_difference` del dueño de
movimiento. Una fase directamente envuelta se rechaza con un mensaje que
indica elegir uno de esos estimadores. El conversor no añade un unwrap ni
convierte arbitrariamente una fase envuelta en movimiento real.

## Opciones del conversor de productos

| Campo | Predeterminado | Significado |
|---|---:|---|
| `phase_product` | `"phase_increment"` | Ruta incremental existente; `"raw_wrapped"` conserva fase óptica nativa para comparar unwrap |
| `plane_type` | `"auto"` | Bmode angular; enface para raster/polar |
| `bmode_index` | 1 | Un B-mode independiente |
| `depth_offset_mm` | 0 | Distancia bajo cada borde anterior |
| `depth_band_mm` | 0.04 | Espesor axial de agregación del plano |
| `intensity_floor_db` | -35 | Umbral relativo adicional a la máscara OCT existente |
| `coherence_threshold` | 0.15 | Coherencia IQ de la medición, distinta de la coherencia armónica |
| `lateral_stride`, `raster_line_stride` | 1 | Decimación del plano de salida; en BIN también selección de posiciones leídas |
| `preview_bmode` | 1 | Línea estructural a revisar en enface |
| `phase_registration_status` | `"unverified"` | Declaración: `unverified`, `assumed_repeatable` o `verified` |
| `min_interpolation_resultant` | 0.5 | Rechazo adicional de discordancia circular entre incrementos interpolados |
| `max_triangle_edge_mm` | `[]` | Máximo borde de triángulo polar; vacío utiliza 2.5 veces la diagonal de espaciados radial/angular nativos |
| `max_phase_step_rad` | pi | Límite de incremento admitido antes de la colocación/interpolación |

`verified` sólo debe declararse cuando una verificación independiente de la
repetibilidad espacial respalda la adquisición. El código conserva esa
declaración, **no realiza registro ni prueba esa condición**. Un flag de trigger
o un período del generador no son evidencia suficiente por sí solos.

El conversor exige que todo el soporte axial del estimador esté dentro de los
bordes. Con `anterior_posterior`, un posterior ausente o anterior al borde
anterior invalida la columna. La máscara `border_result.intensityMask` se
propaga conservando todos los píxeles que contribuyen a un soporte Loupas.
Las capas no se recortan contra el posterior para aparentar estar dentro de
la muestra: un plano que lo excede permanece inválido.
La banda también debe alojar el soporte axial de la fase ya calculada. Por
ejemplo, 20 muestras Loupas a4.23um ocupan aproximadamente80um: una banda de
40um no puede contener ese soporte y queda vacía. El conversor no cambia la
ventana del estimador ni amplía silenciosamente la banda. Revise ambos
parámetros aguas arriba. Un offset0 designa la banda cercana al borde; su
soporte finito no es una medición infinitamente delgada de la interfaz.

La profundidad incluye el origen del crop FFT y el centro del soporte axial.
El tiempo incluye el inicio del crop y el punto medio de cada incremento. La
agregación axial utiliza incrementos reales ponderados por intensidad y
coherencia IQ. No los vuelve a envolver con `angle(exp(i*phase))`; la corrección
axial de Loupas puede producir incrementos fuera de la rama principal.
El límite incremental configurable es un rechazo conservador y se aplica al
registro completo antes de la ROI armónica. No certifica alias ni Nyquist:
una corrección Loupas fuera de pi no prueba por sí sola una medición inválida.
Cambiarlo requiere revisión de la medición, no sólo buscar mayor cobertura.

## Fase cruda y colocación después de unwrap

Ambos dueños de entrada aceptan `phase_product="raw_wrapped"`. Extraen
`angle(complex_volume)` en radianes, con convención explícita `angle_IQ`.
"Cruda" designa la fase óptica sin procesamiento de movimiento: la
reconstrucción OCT conserva su calibración, fondo, ventana espectral y FFT
registrados en la procedencia. No se calcula Loupas, diferencia temporal,
suavizado, promedio axial ni interpolación espacial antes del unwrap.

```matlab
options.phase_product = "raw_wrapped";
raw = oce.acquisition.buildWaveMotionPlane( ...
    acquisition_state, [], border_result, options);
% También: raw = oce.acquisition.loadWaveMotionPlane(binFile, options);
unwrapOptions = struct('method', "tie_dct", 'iterations', 8, ...
    'dimensions', [3 1], ...
    'valid_mask', repmat(raw.valid_mask,1,1,size(raw.wrapped_phase,3)));
unwrapped = oce.motion.unwrapPhase(raw.wrapped_phase, unwrapOptions);
data = oce.acquisition.finalizeUnwrappedWavePlane(raw, unwrapped);
% Los filtros y el estimador actúan sobre data.motion a continuación.
```

`raw.wrapped_phase` tiene layout `depth_native_position_time`. Conserva todas
las muestras temporales originales y sus tiempos, sin el desplazamiento de
medio intervalo de una diferencia. `raw.row_m` conserva profundidades FFT
originales, sin el centro de una ventana Loupas. `raw.valid_mask` es el soporte
de bordes, intensidad y coherencia IQ; los valores medidos rechazados siguen
disponibles para diagnóstico. El unwrap debe recibir esta máscara expandida
a tiempo, además de la finitud de las mediciones. La cantidad cruda no recibe
el límite incremental `max_phase_step_rad`.

La dimensión de posición nativa contiene adquisiciones con fase óptica de
speckle independiente. Por eso el contrato admite unwrap temporal `[3]` o
profundidad/tiempo `[3 1]`/`[1 3]`, independientemente por posición. El
finalizador rechaza unwrap que una la dimensión 2 de posiciones adquiridas,
productos sin cantidad `unwrapped_phase`/unidades `rad` y presupuestos TIE-DCT
que no documenten las iteraciones fijas ejecutadas. Nunca concatena B-modes.

El finalizador reutiliza sólo `unwrapped.values` y registra método, dimensiones,
iteraciones y diagnósticos en `metadata.raw_unwrap`. Primero elimina la media
temporal de cada voxel nativo para retirar el pistón óptico estático. Después
promedia una banda enface con pesos de intensidad/coherencia y aplica los
operadores geométricos existentes. `motion` contiene fase óptica desenvuelta
con media retirada; **no es un incremento ni una velocidad temporal**. La
estimación armónica de velocidad de propagación admite esta señal real.
`metadata.processing_order` conserva el orden y declara que los filtros y la
estimación aún están pendientes.

El modo raw conserva ambos bordes y `intensityMask` existentes en STEPWISE;
BIN directo conserva el candidato anterior. No cambia el detector de bordes.
El promedio enface exige toda la banda dentro del crop y posterior, con
todos sus contribuyentes válidos. Las fases desenvueltas pueden superar pi:
el finalizador omite los controles incrementales/circulares de la ruta Loupas
y mantiene finitud, soporte y geometría. La coherencia armónica se verifica
después por el estimador, no por el resultante de fase óptica instantánea.

Para un B-scan polar, `raw.x_m` conserva el arco nativo potencialmente no
uniforme; el remuestreo se aplaza hasta después de unwrap y retirada del
pistón. Enface conserva posiciones nativas hasta ese mismo punto, incluido
en raster. No interpola fases envueltas a una malla cartesiana.

La salida raw necesita memoria proporcional a profundidad × posiciones
nativas seleccionadas × tiempo; un raster completo puede necesitar varios
GB. El bloque de espectros/complejos continúa acotado, pero conservar fase
cruda impide reducir primero la banda a una traza promedio. Para acotar el
producto utilice el crop de profundidad y los strides existentes y conserve
su procedencia; esa selección no equivale a filtrar o rellenar la fase.

## Geometría y huecos

`oce.acquisition.applyWaveEnfaceOperator` usa el operador sparse que ya produce
`buildAcquisitionGeometry`: colocación exacta en raster e interpolación lineal
en polar. No implementa otro triangulador. Cada contribuyente debe ser válido;
no se renormalizan pesos para rellenar vecinos ausentes. Se conservan NaN fuera
del casco adquirido, dentro del hueco central de anillos y sobre triángulos
demasiado largos. Las métricas de soporte/resultante quedan en
`metadata.enface_qc`. La interpolación de valores es real y lineal: el
resultante circular sirve sólo como diagnóstico de discordancia, no como
estimador de fase.

Las posiciones de un B-scan polar se convierten a distancia acumulada entre
posiciones adquiridas. Si no son uniformes —por ejemplo una espiral— se
remuestrea ese segmento independiente a un arco uniforme, conservando NaN y
exigiendo ambos contribuyentes. No se cierra la costura de un anillo ni se
unen turnos. `metadata.bmode_qc` conserva el eje nativo y si fue remuestreado.
Un B-scan sobre arco es un corte curvo, por lo que el estimador cartesiano sólo
aproxima propagación local a lo largo del arco. No equivale a un corte recto
en el plano x/z. Enface evita esa aproximación de geometría curva.

La malla cartesiana polar puede ser más fina que el muestreo nativo. No crea
resolución física ni demuestra ausencia de alias: revisar `native_spacing_mm`
y las posiciones adquiridas. La colocación geométrica no certifica que las
excitaciones consecutivas tengan la misma fase, retardo o respuesta.

## Producto común

`motion` es real single `[row,column,time]`; `x_m` es columna y `row_m` fila,
ambas en metros; `t_s` está en segundos. `valid_mask`, `structural_db` y
`coherence` tienen dimensiones `[row,column]`. `offsets` conserva el borde y
la profundidad relativa; `preview` aporta OCT de una línea para revisar
bordes. `metadata.load_options` guarda los controles realmente aplicados,
cantidad/estimador y procedencia, frecuencia (NaN cuando falta generador),
crop, geometría y limitaciones de repetibilidad. No se infiere frecuencia del
nombre de archivo ni del período de trigger.

El lector BIN mantiene memoria de espectros/complejos acotada al bloque;
el plano temporal y la malla de salida sí consumen memoria proporcional a su
tamaño. Para una exploración rápida se puede decimar, registrando el cambio de
muestreo. La superficie BIN predeterminada usa `inherited_threshold`, dueño
existente de bordes; `max_in_search` y `manual_index` son elecciones explícitas.
El BIN directo no inventa un posterior que no haya sido detectado. Para
conservar ambos bordes de una ejecución ya validada, use STEPWISE.
