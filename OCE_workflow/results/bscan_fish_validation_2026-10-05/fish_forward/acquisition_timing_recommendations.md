# Registro temporal de OCE por excitación: propuesta basada en la GUI actual

Esta nota propone una extensión de adquisición; no modifica la GUI ni atribuye el protocolo simulado de ocho excitaciones a un protocolo publicado. Una orden SCPI y su respuesta describen control por software. Para comparar fases y posiciones, hacen falta referencias de la excitación y de la cámara observadas en hardware, con sus relojes y su incertidumbre documentados.

## Evidencia en el código actual

Se revisó `GUI/PYTHON_GUI_DG4162/octoce` del repositorio Desktop. `storage.py:72` guarda `created_utc`, que es creación de la cabecera por el proceso; no es un timestamp de exposición. La cabecera `OCTOCE1`, versión 1.0, tiene capacidad de 64 KiB. Guarda configuración de barrido, orden de ejes, política de almacenamiento, calibración, hash de trayectoria, retardos/periodos de cámara y OCE, orden de arranque e integridad de buffers. Los periodos son programados o readback de configuración, no una tabla de flancos físicos observados.

`gui_dg4162.py:947-988` habilita el generador durante el armado y añade `generator.settings`, `generator.state` y la identificación del trabajo de secuencia. `dg4162.py` consulta forma, frecuencia, amplitud, AM y parámetros de burst. El readback permite verificar la programación, pero no mide el inicio de cada burst ni la fuerza sobre la muestra. `backends/base.py:23-28` devuelve índices de buffers y `elapsed_s`; el backend calcula ese tiempo con el reloj del proceso.

`backends/ni_daq.py` configura cámara y OCE para arrancar con `/Dev1/ao/StartTrigger`. La salida PFI12 dispara un segmento; el patrón de PCIe-1433 genera CC1 por A-line válida. PFI13 dispara la excitación según MB/BM. Hay evidencia de un inicio hardware compartido dentro de ese plan. No se encontró un registro de eventos, una referencia de reloj compartida con PCIe-1433/DG4162, ni una medición de su desfase y deriva. Esto identifica una limitación de la evidencia guardada, no demuestra que el equipo físico esté desincronizado.

## Qué reloj y qué señal conviene observar

Guardar los tiempos de envío, retorno y readback SCPI con UTC y un contador monotónico del PC, etiquetados `host`. Sirven para orden y diagnóstico. NI explica que el `t0` de un waveform convencional puede derivarse del reloj del sistema y de la lectura del buffer; no debe confundirse con un flanco capturado en hardware. [NI: waveform timestamps](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z000000P9Q9SAK&l=en-SG).

Observar en un mismo contador/digitalizador: PFI13, la referencia efectiva del generador y CC1 o una señal que identifique la exposición/A-line. Registrar frecuencia y origen del reloj, tick de cada flanco, polaridad, incertidumbre, canales y tratamiento de desbordamiento. Si los dispositivos admiten compartir referencia/reloj de muestreo, documentar las rutas y verificar el bloqueo. Compartir solamente un start trigger no sustituye la sincronización de relojes. Las explicaciones de NI sobre sincronización y retardo hasta la primera muestra fundamentan esta distinción; su configuración específica DSA no se presupone compatible con las tarjetas de este sistema. [NI: synchronization basics](https://www.ni.com/en/support/documentation/supplemental/10/dynamic-signal-acquisition--dsa--synchronization-basics.html), [NI: start trigger and first sample delay](https://knowledge.ni.com/KnowledgeArticleDetails?id=kA00Z0000019M5PSAU&l=en-US).

El conteo de eventos con buffer puede capturar el contador al llegar cada flanco y transferirlo después por DMA: el tiempo queda determinado en hardware aunque el PC lea más tarde. La disponibilidad de contadores/rutas se debe comprobar en el equipo; ctr0/ctr1 ya cumplen funciones de salida en la GUI. [NI: buffered event counting](https://www.ni.com/en/support/documentation/supplemental/21/buffered-event-counting.html).

El manual DG4000 indica que **AM externa no produce Sync del canal modulado**. Por tanto, no asumir Sync de CH1 como referencia en la configuración actual CH1 AM por CH2. Sync de CH2 en burst N ciclos señala inicio/fin del burst; comprobar su modo y observarlo junto con la envolvente analógica cuando sea posible. El manual distingue latencia típica de burst (<300 ns), retardo programable y referencia de 10 MHz. La latencia típica no es una garantía de jitter ni la hora de una orden SCPI. Registrar siempre canal, modo y referencia concreta. [RIGOL DG4000 User Guide, capítulos 7, 10 y 13](https://www.rigol.com/dam/global/downloads/brochures/en/user-manual/waveform-generators/DG4000_UserGuide_EN.pdf).

PFI13 es una orden hardware; Sync/envolvente de CH2 representa un evento electrónico posterior. Ninguno demuestra por sí solo el inicio de fuerza en la muestra: también existen retardo de electrónica, transductor y propagación. Si hay una referencia de presión/fuerza/vibración disponible, guardarla y su ubicación. De lo contrario declarar `reference_kind=generator_envelope`, con retardo mecánico desconocido.

## Esquema concreto propuesto

Mantener la cabecera compacta y un único registro temporal versionado, propiedad del almacenamiento actual. Referenciar un sidecar HDF5/NPZ con nombre relativo, tamaño, SHA256 y esquema; no caben tiempos por A-line en 64 KiB para una adquisición larga. La propuesta legible por máquina está en `acquisition_timing_proposal.json`; contiene tipos y campos, no datos medidos inventados.

| Registro | Campos principales |
|---|---|
| Reloj | `clock_id`, dominio, dispositivo/ruta, frecuencia medida y nominal, epoch, ancho del contador, desbordamiento, incertidumbre, fuente de referencia, estado de bloqueo |
| Adquisición/excitación | IDs persistentes, trabajo/repetición, fuente y posición/ángulo nominal, coordenadas observadas si existen, ajustes/readback y sus tiempos host, referencia de fase, coherencia declarada y evidencia |
| Evento | `event_id`, excitación, tipo (PFI13, Sync, envolvente, CC1), tick y reloj, polaridad, observado/planificado/desconocido, incertidumbre |
| A-line | índice cronológico y de almacenamiento, segmento/B/M/sweep, raster fila/columna o polar ángulo/radio, coordenadas/voltajes comandados, posición observada opcional, trigger/exposición, excitación asociada, validez/pérdida/duplicación |
| Calibración | relación entre clocks, retardo trigger→exposición, definición de timestamp (flanco/inicio/centro de exposición), retardo referencia→fuerza conocido o desconocido, fecha y método |

Usar `null/unknown` cuando no existe una medida. Para datos antiguos, conservar que frecuencia y excitación son declaradas por el usuario o inferidas; el nombre del archivo no convierte esos parámetros en readback ni reconstruye timestamps perdidos.

## MB, BM, raster y polar

En MB la GUI produce un trigger OCE por grupo M en una posición. Guardar el ID y referencia real de **cada grupo**: el reinicio de fase no debe suponerse idéntico solamente porque la frecuencia programada sea la misma. Mantener el eje temporal M en orden cronológico.

En BM cada repetición de B-scan tiene posiciones medidas en distintos tiempos. El almacenamiento puede invertir espacialmente barridos reversos para que X sea creciente, pero el tiempo original de cada A-line debe sobrevivir esa permutación. El par `(stored_index, chronological_index)` hace explícita la relación. En raster guardar fila, posición, sentido, segmento, pausas y flyback, aunque esas muestras no se almacenen. En polar guardar ángulo/radio y coordenadas Cartesianas reales/comandadas; no asignar un tiempo de fila uniforme si la trayectoria no lo es.

El trabajo primario de Schmidt et al. demuestra que el movimiento de barrido introduce fase intra-B-scan y desfase entre planos; su recuperación asíncrona usa correcciones dependientes del tiempo, posición y líneas completas, incluyendo tiempos muertos. Es apoyo para conservar esas relaciones, no prueba de que su protocolo de B-scans pareados ni su demodulación funcione automáticamente con cualquier burst o con ocho excitaciones independientes. [Schmidt et al., JBO 2025, DOI 10.1117/1.JBO.30.12.124506](https://doi.org/10.1117/1.JBO.30.12.124506).

Para una armónica estacionaria y la convención `Re[P exp(+iωt)]`, medir una posición con desplazamiento temporal τ añade `exp(+iωτ)` al fasor. Corregir por `exp(−iωτ)` requiere conocer τ y la referencia de fase; un burst transitorio o una fase que cambia no se resuelve con ese factor constante. Entre excitaciones independientes, fusionar estimaciones o estadísticas/autocorrelaciones propias de cada adquisición mientras no exista evidencia de coherencia de fase; no sumar fasores crudos con fases de inicio desconocidas.

## Presupuesto temporal y control de adquisición

La relación analítica es `Δφ=2πfΔt`. A 2 kHz, 1/10/100 µs equivalen a 0.72°/7.2°/72°. Un objetivo ilustrativo de 5° exige ≤6.94 µs a 2 kHz y ≤13.89 µs a 1 kHz; elegir el presupuesto a partir del método y resolución espacial, no presentar esos valores como especificación medida del sistema. Un desfase constante global no cambia el gradiente espacial dentro de una adquisición coherente; diferencias entre posiciones sí pueden aparentar un número de onda. El desajuste de frecuencia produce deriva `2πΔfT`.

Antes de estimar, medir repetidamente el desfase PFI13→referencia del generador→CC1, incluyendo cada modo/chunk y ambos sentidos de barrido. Reportar media, dispersión, máximos, flancos perdidos y deriva; guardar baseline previo, referencia durante el burst y muestras tras su final. Verificar amplitud/frecuencia/armónicos observados y seleccionar la ventana estacionaria con un criterio publicado en los resultados. Conservar rechazos y cobertura, no únicamente los mapas aceptados. Fijar parámetros de reconstrucción antes de comparar geometrías de referencia. Estos son controles propuestos; todavía no se han realizado en el equipo experimental.

Fuentes primarias y código revisados el 2026-10-05. No se cambió la GUI ni se afirma validación temporal experimental.
