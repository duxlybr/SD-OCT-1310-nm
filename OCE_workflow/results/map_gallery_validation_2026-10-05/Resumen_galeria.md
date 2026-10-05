# Galería de mapas de velocidad y Young

Las imágenes están en `../Speed_Young_Maps/`. Esa carpeta contiene únicamente
PNG de velocidad y/o Young, con referencias del simulador cuando corresponde.
Los datos numéricos, parámetros, scripts, bibliografía, controles, diagnósticos
y hashes están aquí, fuera de la galería. No se rellenan píxeles rechazados ni
se aplica suavizado a los mapas publicados.

## Casos de propagación y referencias

**Lamb A0 en el límite flexural de placa delgada.** El forward resuelve una
placa Kirchhoff–Love con rigidez `D(x,y)` dentro del operador de momentos,
incluyendo reflexión, transmisión y dispersión por la inclusión. Usa fondo de
12 kPa e inclusiones rígida de 24 kPa y blanda de 6 kPa, espesor de 0.20 mm,
60 Hz, densidad de 1000 kg/m³ y Poisson 0.495. La malla publicada tiene
24 puntos por longitud de onda de fondo; la fuente lineal y el absorbente
quedan fuera del área mostrada. Cada ventana completa publicada permanece a
más de 3.5 longitudes de onda del soporte de 3 sigma de la fuente. La referencia
de velocidad es la dispersión homogénea local del modelo; cerca de una interfaz
el campo dispersado puede carecer de un único número de onda local.

| Placa, malla fina | Error absoluto mediano de velocidad | Error absoluto mediano de Young | Young mediano del núcleo |
|---|---:|---:|---:|
| Homogénea, control fuera de galería | 0.38% | 1.51% | 11.88 kPa |
| Inclusión rígida, núcleo | 0.55% | 2.18% | 23.77 kPa |
| Inclusión blanda, núcleo | 0.36% | 1.46% | 6.012 kPa |

Los mapas completos de inclusión tienen errores medianos de velocidad/Young
de 0.73/2.90% (rígida) y 0.63/2.51% (blanda). Se mantuvieron iguales ventanas,
dirección y rechazo. El refinamiento de 18 a 24 puntos por longitud de onda
cambia las medianas de velocidad alrededor de 0.25%; dos mallas no demuestran
por sí solas convergencia asintótica. Véanse las métricas, las diferencias del
campo complejo y la bibliografía en `lamb_plate/`.

**Campo reverberante escalar 2D de corte.** El forward resuelve
`div(mu grad U) + rho omega² U = -F`, con medias armónicas de `mu` en las caras
de la malla, 24 fuentes periféricas y absorbente exterior. No se construye la
fase desde un mapa de velocidad prescrito. Fondo 12 kPa, inclusiones 24/6 kPa,
1800 Hz, SNR temporal 25 dB, ventana de 2.4 mm y estimación AIA scalar2d. La
inversión de Young es condicional al modelo escalar de corte; no representa
elastodinámica 3D ni una simulación completa de medición OCT.

| Reverberante, campo útil | Error absoluto mediano de velocidad | Error absoluto mediano de Young | Cobertura del campo útil |
|---|---:|---:|---:|
| Homogéneo | 1.44% | 2.88% | 99.96% |
| Inclusión rígida | 2.01% | 3.99% | 99.88% |
| Inclusión blanda | 2.76% | 5.47% | 99.94% |

Cada ventana completa tiene una separación mínima de 2.77 longitudes de onda
de fondo desde el soporte de 3 sigma de las fuentes y 4.7 mm desde el
absorbente. Dos semillas adicionales mantienen errores medianos de velocidad
del campo útil de 1.97–2.17%. Una malla de 0.075 mm reduce el error del campo
útil a 1.49%; la mejora no es uniforme en el núcleo. La máscara del núcleo
conservador incluye sólo ventanas completamente interiores y tiene 81 píxeles
en la malla nominal. Datos y resúmenes en `reverberant/`.

**FDTD elastodinámico del simulador de Claude.** Se ejecutan placa libre y
semiespacio aproximado, con y sin inclusión, usando una fuente no contactante.
La ventana publicada permanece fija en 1.2 mm. La comparación exploratoria
entre seis configuraciones por caso lleva a usar filtrado direccional para
Lamb y gradiente de fase sin filtro angular para toda la familia Rayleigh.
El sector mejora el campo multimodal de la placa, pero recorta componentes
curvadas del campo Rayleigh dispersado. Las comparaciones con ambos métodos y
ventanas 0.9/1.5 mm permanecen en `fdtd/`. La elección se evaluó sobre esos mismos
casos: no constituye validación independiente ni prueba de optimalidad general.
Una inclusión Rayleigh blanda de 6 kPa se simula después de elegir el método,
manteniendo la misma configuración, como comprobación adicional.
Todas las ventanas aceptadas están a dos
longitudes de onda de fondo del soporte activo de la fuente gaussiana,
truncado por el propio simulador en amplitud 0.001.

La exportación incorpora una copia local de los snapshots CPU: `asnumpy`
devolvía una vista y el borrado del acumulador anulaba los fasores exportados
y falseaba la comprobación de estacionariedad. El adaptador observacional
copia resultados antes del borrado; no modifica las ecuaciones ni archivos
del simulador. La tentativa nula permanece fuera de la galería, en
`fdtd/invalid_cpu_alias_attempt/`.

La placa FDTD homogénea tiene Young mediano de 11.554 kPa frente a 12 kPa y
discrepancia absoluta mediana de 9.09%. Su cambio armónico final es 1.47%,
superior al objetivo de 0.5%; la imagen indica esa limitación. La coherencia
temporal de la señal reconstruida desde el fasor no prueba la estacionariedad
del solver. La inclusión de esa placa presenta cerca de 29% de discrepancia
en ventanas totalmente interiores y permanece como diagnóstico.

Con gradiente sin sector, el Rayleigh homogéneo tiene discrepancia mediana
de Young de 5.02%. La inclusión rígida recupera Young mediano de 21.83 kPa
frente a 24 kPa en ventanas totalmente interiores: discrepancia mediana de
9.04%, sobre 58 píxeles con ventanas totalmente interiores. En toda la
inclusión, incluyendo ventanas que mezclan su interfaz, la mediana es
18.37 kPa y la discrepancia mediana 23.47%; la diferencia cuantifica la pérdida
de resolución local. Es Young aparente por una inversión local de semiespacio, y el campo
dispersado cerca de interfaces no tiene por qué coincidir con esa referencia
homogénea. El resultado direccional para la misma inclusión tiene discrepancia
de 33.70% en el núcleo y queda fuera de la galería, conservado como comparación.

La comprobación posterior Rayleigh con inclusión blanda recupera 6.065 kPa
frente a 6 kPa en 54 píxeles con ventanas totalmente interiores: discrepancia
mediana 3.54%. Acepta sólo el 50.15% del campo lejano con ventanas completas;
la interferencia deja una zona importante rechazada. En el fondo, la
discrepancia es 17.36% en ventanas puras y 24.81% si se incluye la interfaz.
Su imagen es una recuperación parcial del núcleo, no una recuperación
completa y exacta del fondo. Mantiene los mismos parámetros; no se rellenó
la zona dispersada ni se alteró la elección del estimador tras conocerla.

La selección de esta galería exige discrepancia mediana del homogéneo de
Young <=10% con la ventana y el rechazo fijos y el método elegido por familia,
y, para publicar una inclusión FDTD,
discrepancia mediana de Young en su núcleo <=20%. Son criterios observacionales
para elegir ejemplos de esta galería; no garantizan desempeño general. Todos
los candidatos, incluidos los excluidos, conservan sus métricas y motivos en
`fdtd/fdtd_gallery_findings.md`.

## Datos experimentales

Los cinco PNG provienen de los BIN indicados por el usuario, reutilizando los
planos reconstruidos y recalculando con el núcleo final. Las frecuencias se
asumen a partir de los nombres y de las instrucciones: Luis3 1000 Hz y raster
2000 Hz. Los BIN antiguos no incluyen los parámetros del generador.

| Plano y estimador | Cobertura sobre área completa | Velocidad mediana | Young aparente mediano |
|---|---:|---:|---:|
| Luis3 B-mode, direccional | 0.021% | 1.812 m/s | 10.77 kPa |
| Raster 0.00 mm, direccional | 6.32% | 2.334 m/s | 17.88 kPa |
| Raster +0.10 mm, direccional | 4.80% | 2.498 m/s | 20.46 kPa |
| Raster 0.00 mm, AIA shear3d | 12.64% | 2.166 m/s | 14.02 kPa |
| Raster +0.10 mm, AIA shear3d | 10.96% | 2.190 m/s | 14.34 kPa |

Young experimental es **aparente y supuesto**: densidad 1000 kg/m³, Poisson
0.495 y conversión Rayleigh para el método direccional o corte volumétrico
para AIA shear3d. La señal no acredita por sí sola ninguno de esos modelos.
Los planos son relativos a una superficie OCT candidata; la identificación
anatómica y la repetibilidad de fase entre posiciones permanecen sin verificar.
No hay ground truth experimental. A +0.25 mm no hubo soporte suficiente para
publicar un mapa recuperado. La adquisición Luis3 sólo aporta 11 píxeles
aceptados: su figura conserva el área completa y esa escasez.

El campo lejano experimental no puede certificarse con estos archivos porque
no se documenta suficientemente la posición espacial de la excitación. Su
soporte procede de los criterios de señal/ajuste, sin máscaras construidas
para hacer el mapa más denso. Productos y supuestos en `experimental/`.

## Reproducción e inventario

Los scripts y rutas concretas se documentan dentro de cada subcarpeta. El
core utilizado es `src/+oce/+dispersion/estimateLocalSpeedMap.m` y
`src/+oce/+elastography/invertYoungModulus.m`; las fuentes y productos permiten
abrir cada `data` en el workflow interactivo existente. Esta ampliación sólo
crea artefactos observacionales y no cambia producción ni los BIN.

Ejecute `audit_map_gallery.py` con el Python del simulador para comprobar
que `Speed_Young_Maps` contiene únicamente PNG legibles. Guarda inventario,
resoluciones y hashes SHA-256 en `gallery_image_inventory.csv/.json`, aquí.
El inventario final identifica exactamente las imágenes entregadas.

La entrega final contiene **16 PNG**: 4 de placa flexural (velocidad y Young
separados para dos inclusiones), 3 de campo reverberante escalar, 4 del FDTD
elastodinámico y 5 experimentales. Algunas imágenes contienen ambos mapas,
y las simulaciones escalares/placa incluyen además su referencia.
