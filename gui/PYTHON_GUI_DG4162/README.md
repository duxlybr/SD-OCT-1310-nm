# OCT / OCE Acquisition — aplicación activa (optimizada)

Aplicación de adquisición para el sistema SD-OCT/OCE con NI PCIe-6323,
NI PCIe-1433 y cámara lineal Sensors Unlimited GL2048R. La aplicación separa
el camino crítico de adquisición de la GUI, el procesamiento y el disco.
Esta es la única GUI Python mantenida; se lanza con `../run_gui_dg4162.bat`
(ver [README_DG4162.md](README_DG4162.md)). La GUI anterior está en
`legacy/gui/PYTHON_GUI` en la raíz del repositorio.
Las nuevas adquisiciones se proponen en `../data/acquisitions`; la
configuración ROI está en `../config`.

En MB y BM finitos con `sync>0`, la ruta NI nueva agrupa hasta 64 sweeps en un
solo armado AO/ctr0/ctr1. También admite MB estacionario con `sync=0`; el MB
móvil sin sync conserva la ruta anterior. AO ejecuta la trayectoria completa
del lote y PFI12/PFI13 emiten trenes finitos sincronizados con
`ao/StartTrigger`: un frame por sweep y, si OCE está habilitado, un pulso por
posición MB o por B-scan BM. En BM crosshair, un B-scan es el par X/Y:
PFI13 dispara solo en X, cada dos sweeps. Se guardan únicamente las A-lines
válidas, en el mismo orden del formato `.bin` anterior. Se reserva además al
menos un 5 % del tiempo de frame para que NI-IMAQ termine/rearme el buffer; los
puntos adicionales son un hold del galvo y no aparecen en el archivo.
El header registra el período efectivo del sweep, el hold no adquirido y el ancho
real del pulso OCE de esta ruta; el payload continúa siendo `uint16` crudo.

Para el ejemplo medido A=50, B=50, M=300, sync=50 se reducen los armados
planificados de 2500 a 40. **La ganancia de tiempo real todavía no está
validada para una serie experimental larga**. En pruebas físicas acotadas se
verificaron 80 posiciones MB en dos lotes (80 pulsos PFI13, buffers 0–79,
cero pérdidas) y BM crosshair de dos pares X/Y (cuatro buffers, dos pulsos
PFI13). La adquisición MB activa de 80 posiciones tardó 0,609 s. Una serie
larga todavía requiere verificar PFI12/PFI13, buffers e imagen sobre la muestra.

La inicialización NI-IMAQ presenta un costo fijo medido de ~6,4 s en
`imgRingSetup`. La GUI optimizada conserva la sesión de cámara hasta 30 s tras
una adquisición finita completada y la reutiliza si ROI y ajustes de cámara
coinciden; un ensayo de dos adquisiciones MB pasó de 7,040 s totales en la
primera a 0,112 s en la segunda, con buffers consecutivos y cero pérdidas.
La sesión se libera al cerrar la GUI, tras 30 s de inactividad, al cambiar la
configuración de cámara o si hubo error/parada. Durante esos 30 s NI MAX u otra
aplicación no podrán usar la PCIe-1433. La primera adquisición sigue pagando
el costo de inicialización; el código no lo oculta del tiempo total.

Primera prueba NI recomendada (galvos inmóviles en 0,0; diez posiciones MB):

```powershell
python -m diagnostics.diagnose_mb_chunks
```

Con M=300, sync=50 y 50 klps, PFI13 debe mostrar diez pulsos separados 7 ms
(≈142,86 Hz durante el lote), de 0,7 ms en alto, y la prueba debe terminar con
`healthy=True`. Si falla, use la copia 03 archivada y comparta el error antes de
intentar un escaneo largo. Después pruebe un MB pequeño desde esta GUI, con
los galvos en movimiento, y confirme la imagen y el `.bin`.

## Qué incluye esta versión

- GUI en Python/Tkinter con los controles solicitados: A-lines, B-scans,
  repeticiones M, puntos sync y longitudes X/Y.
- Modos BM y MB con orden de datos explícito.
- Patrones raster, crosshair, meridianos/polar, lineal horizontal/vertical,
  anillos concéntricos y espiral.
- Conversión predeterminada `X = 0.40607082 V/mm` y `Y = 0.40631516 V/mm`, editable en
  la configuración de hardware y registrada en cada archivo.
- AO0/AO1 precargados y temporizados por hardware.
- `ctr0 → PFI12` inicia cada buffer en el PCIe-1433; su generador de patrón
  produce los pulsos CC1 de A-line. `ctr1 → PFI13` inicia la excitación OCE.
- Fuera de los lotes optimizados, PFI13 usa lógica TTL de 5 V con tiempo alto configurable (10 µs por defecto)
  y tiempo bajo igual a nueve veces el alto: 10 % de ciclo útil en un tren de
  pulsos. En una adquisición normal se emite **un pulso finito por evento OCE**;
  los espacios entre eventos dependen del patrón/MB/BM y no tienen duty fijo.
  Para ver un tren breve en el osciloscopio, ejecutar
  `python -m diagnostics.check_pfi13_scope` desde esta carpeta (1000 pulsos, 0,1 s).
  Usar entrada de 1 MΩ y tierra D GND; el nivel físico no se calibra por software.
- Frecuencia solicitada ajustable hasta 147 klps. El periodo CC1 del ICD tiene
  resolución de 0,1 µs, así que DAQ y cámara usan la frecuencia efectiva
  cuantizada, que también se registra en el header.
- Puntos sync con interpolación quintic; no reciben trigger de cámara y no se
  guardan en el payload.
- `BFramesDelay` ajustable en µs: desplaza PFI13 respecto al primer PFI12. Si
  el pulso OCE rebasa la última A-line, AO mantiene la posición los puntos
  necesarios sin adquirir datos para que el pulso no sea truncado.
- Ring NI-IMAQ con dieciséis buffers por defecto, solicitud por número acumulativo y parada ante
  saltos, duplicados o pérdidas.
- Escritura `.bin` en un consumidor separado, con header JSON versionado y
  recuperación de archivos incompletos.
- Preview OCT desacoplado y limitado en frecuencia, con remoción estándar del
  espectro DC medio activada por defecto (conmutable sin alterar el raw),
  colormaps, ventana de intensidad por percentiles, cursores Z/lateral y perfil
  de fase relativa en la profundidad elegida. El Z bin puede fijarse con el
  deslizador o escribiendo su número exacto; el perfil de fase usa ese bin
  incluso si la imagen de preview está reducida. Si se atrasa, se omite un
  refresco; los datos crudos no se omiten.
- Reconstrucción diagnóstica con remuestreo λ→k mediante valores editables de
  inicio y fin (nm), compensación de dispersión (D2, D3) y FFT de 8192 con un
  solo rango axial visible. Los valores por defecto, `1466.61`/`1263.79 nm` y
  `D2 = −1.7`, `D3 = −2.5 rad`, se optimizaron con `FWHM_80_ALines_TDMS.m`
  (espejo a 4.05 mm, 2026-10-01; en MATLAB `lambdaIni_nm = 1263.79`,
  `lambdaFin_nm = 1466.61`, porque aquí el detector está invertido). La
  dispersión se aplica a la señal analítica en k uniforme, con la misma
  convención que MATLAB, y se registra en `calibration` del header. Solo
  afecta al preview: el `.bin` guarda siempre el espectro crudo. Deben
  re-optimizarse si se realinea el espectrómetro.
- **Ventana espectral** del preview (junto a *Remover DC*): Rectangular, Hann
  (predeterminada, la de siempre), Hamming, Blackman, Blackman-Harris,
  Tukey α=0.5, Kaiser β=8 y Gauss σ=0.4. Todas se escalan a la ganancia
  coherente de Hann, así que un reflector conserva su nivel en dB al cambiar de
  ventana: solo cambian el ancho de la PSF y los lóbulos laterales.
  *Rectangular* da la PSF más estrecha y coincide con el FWHM sin ventana de la
  caracterización MATLAB; las demás reducen lóbulos a costa de ensanchar el pico.
  Cambiarla reprocesa la imagen en pantalla; los datos crudos no cambian.
- Crosshair aparece como un B-scan lógico con cortes X–Z e Y–Z simultáneos y
  una cruz X/Y en la profundidad Z elegida. Se puede seleccionar cada sweep
  para inspeccionar su fase y fijar manualmente los límites verticales del plot.
- La vista OCT usa la mayor parte del panel; el colormap inicial es **Grises**
  y los límites fijos iniciales de fase son **−15 a +15 rad**. En alineación
  aparece a la derecha un zoom de 20 píxeles de profundidad centrado en Z.
- Se aceptan longitudes `X=0`, `Y=0` para adquisición estacionaria. El botón
  **Alineación continua** adquiere MB en el centro con M=1000 hasta pulsar
  Detener, sin archivo ni puntos sync.
  - PFI12 y PFI13 usan contadores continuos sincronizados por hardware.
  - **Tasa de la alineación** (campo bajo el botón): cuántos bloques, y por lo
    tanto cuántos pulsos PFI13 (uno por burst del transductor), se emiten por
    segundo.
    - Por defecto son **25 Hz**, la mitad de los 50 Hz fijos anteriores, para
      que el transductor ultrasónico no se sobrecaliente.
    - Rango permitido: de 1 Hz al máximo del hardware (50 Hz a 50 klps). El
      mínimo sube si el timeout de NI-IMAQ es menor que 2 s, porque el período
      debe caber en la mitad de ese timeout.
    - Un valor fuera de rango no inicia la alineación.
  - PFI13 permanece alto el 10 % del período (4 ms a 25 Hz).
  - **Cámara:** la tasa no cambia su frecuencia de línea. Para que NI-IMAQ
    pueda cerrar cada frame antes del siguiente trigger, la cámara se configura
    solo en esta alineación a 52,632 klps efectivos. Cada bloque de 1000
    A-lines ocupa 19 ms; el resto del período queda libre.
  - La GUI muestra ambas tasas en el log. La adquisición normal
  conserva su frecuencia configurada; MB/BM finitos con sync>0 usan lotes de
  hasta 64 sweeps, y MB estacionario con sync=0 también puede usar lotes.
- **Crosshair continuo** repite indefinidamente un B-scan lógico BM de
  1000 A-lines: 500 en X y 500 en Y, recorrido 10×10 mm, M=1. Es solo para
  preview, sin archivo ni OCE; Detener parquea los galvos.
- La ventana de intensidad puede ajustarse por percentiles o por límites
  absolutos negro/blanco en dB diagnósticos (`20·log10(|FFT|+1)`, no dBm).
  El B-scan permite seleccionar `Z inicio` y
  `Z fin` entre los bins FFT 1–4096 (por defecto 1–2048). La zona más lejana
  puede mostrar artefactos conjugados; ampliar la vista no crea datos
  full-range nuevos.
- El log de la GUI y la consola muestran el tiempo de adquisición en segundos
  al completar o detener, medido después del armado del backend.
- Las pestañas **Fase** y **Patrón XY** alternan entre la fase a la profundidad
  elegida y la trayectoria planificada; la segunda indica la última posición
  de segmento adquirida. En crosshair, X corresponde a AO0 y Y a AO1.
- Si **Guardar datos crudos** está marcado, no se lanza el trabajador de
  reconstrucción ni se emiten previews. El archivo conserva los valores k en
  su header, pero el payload sigue siendo espectro crudo sin correcciones.
- Backend de simulación para probar todo el flujo sin mover los galvos.
- El cierre no escribe la posición de park si el preflight de cámara falla antes
  del primer arranque de AO.

## Inicio rápido

Python 3.11–3.14 de 64 bits es compatible. Instale las dependencias en el mismo
intérprete con el que se inicia la GUI.

```powershell
cd C:\Users\proyecto.pi1081\Desktop\SD-OCT-1310-nm\gui\PYTHON_GUI_DG4162
py -3.11 -m pip install -r requirements-dg4162.txt
py -3.11 run_gui_dg4162.py
```

También se puede abrir `..\run_gui_dg4162.bat`.

## Habilitar el backend NI

```powershell
py -3.11 -m pip install -r requirements-hardware.txt
py -3.11 run_gui_dg4162.py
```

La GUI abre con **Hardware NI** seleccionado, pero no activa salidas hasta
presionar Inicio y confirmar el armado. Antes de adquirir, complete la lista de
puesta en marcha en [docs/HARDWARE_SETUP.md](docs/HARDWARE_SETUP.md). Seleccione
**Simulación** explícitamente si desea probar sin mover los galvos.

Se completó una adquisición de hardware controlada con `Dev1`/`img0`, 32 A-lines
de 2048 píxeles, sin buffers perdidos ni duplicados. Esto valida el transporte,
no la calibración óptica. Por defecto, el backend bloquea AO si `Trigger Mode`
sigue reportando `Internal`. Al armar hardware, la opción predeterminada
configura el rango OPR, `Fixed Exp`, polaridad alta y periodo/ancho CC1 antes de
habilitar AO.

## Alineación del espectrómetro en vivo

`run_alignment_live.bat` (o `python run_alignment_live.py`) abre un panel que
adquiere exactamente como **Alineación continua** (MB estacionario en 0,0;
bloques de 1000 A-lines; PFI12/PFI13 a 50 Hz; sin archivo) y compara cada
cuadro con una referencia espectral (`../config/alineacion_referencia.json`,
por defecto la mejor alineación, `Penetration_3/15um.tdms`). Cierre la GUI
principal y cualquier VI de LabVIEW que use `img0`/`Dev1` antes de iniciarlo.

Indicadores (semáforo verde/ámbar/rojo respecto a la referencia):

- **Equilibrio azul/rojo**: envolvente en px 600 / px 1300 (la diferencia RMS
  de forma aparece en el título de la gráfica principal).
- **Enfoque del espectrómetro**: contraste de franjas (amplitud AC / DC,
  demodulada en k) y su cociente azul/rojo. Solo es sensible al enfoque con el
  espejo a ≥ 0.8 mm (ideal 1.5–2.6 mm): cerca del retardo cero las franjas son
  demasiado anchas y el FWHM puede mejorar mientras el espectrómetro se
  desenfoca, lo que destruye la penetración. La pestaña **Contraste local**
  muestra el contraste a lo largo de la cámara (inclinación del plano focal).
- **Resolución del espectro**: FWHM de la transformada de la
  envolvente linealizada en k; no depende de la posición del espejo ni de la
  dispersión. Menor es mejor.
- **Ancho espectral al 50 %** y bordes sobre la cámara.
- **FWHM del espejo**: medido como `Penetration_Analysis_TDMS.m` (mismos λ,
  spline en k, FFT de 8192, FWHM directo y ajuste gaussiano). La **ventana
  PSF** puede ser automática (rango completo, como Penetration) o manual:
  arrastre sobre el A-scan o escriba desde/hasta en µm; doble clic vuelve a
  automática. En manual, la búsqueda del pico, el FWHM directo y el ajuste
  usan solo datos dentro de la ventana. Si el pico supera el nivel mediano
  del A-scan en menos de 15 dB (SNR), la tarjeta se pone en rojo y la barra
  inferior avisa de que el FWHM corresponde a ruido.
- **Cuentas máximas** y saturación.

La barra inferior resume la pérdida en cada lado del espectro y sugiere causas
posibles. "Fijar actual como referencia" guarda el espectro actual en `config/`
con fecha. El procesamiento (`octoce/alignment_metrics.py`) reproduce el de
MATLAB; `tests/test_alignment_live.py` verifica la paridad con la referencia
exportada. El análisis corre en su propio hilo y solo usa los espectros crudos
del preview, por lo que no interviene en el camino crítico de adquisición.

### Pipeline de alineación

El panel izquierdo guía la alineación completa tapando los brazos del
interferómetro (diafragmas de referencia y de muestra):

| Paso | Condición | Objetivo |
|---|---|---|
| 1. Nivel oscuro (opcional) | ambos brazos tapados | capturar el oscuro |
| 2. Referencia | muestra tapada | Ir con máximo en 50–65 % de saturación |
| 3. Forma espectral | solo referencia | forma igual a la referencia (cámara, rejilla) |
| 4. Muestra | referencia tapada | Is bajo el límite (√Ir+√Is)² ≤ 90 % |
| 5. Interferencia | ambos abiertos, espejo a 150–600 µm | sin saturación, visibilidad ≥ 0.7 |
| 6. Enfoque | espejo a 1.5–2.6 mm | máximo contraste, azul/rojo 1.0–1.3 (P3) |
| 7. Verificación | espejo a 150–600 µm | forma, PSF y caída de contraste como P3 |

Con Ir e Is capturados, la relación Is/Ir (que no depende del espectrómetro)
convierte el contraste en **visibilidad absoluta** y predice la saturación
antes de abrir ambos brazos. Si después se mueve un diafragma, una visibilidad
mayor que 1 avisa de que hay que recapturar los pasos 2 y 4. La caída de
contraste entre los puntos superficial y profundo se compara con la de
Penetration_3 entre las mismas profundidades. Al fijar el estado final se
guarda la nitidez espectral: si después baja más de un 15 % (por ejemplo al
optimizar el FWHM cerca de 0) la barra inferior avisa del desenfoque.

Los objetivos se editan en `../config/alineacion_objetivos.json`; cada sesión
guarda un informe JSON (capturas, puntos, caída de contraste, espectros Ir/Is)
en `../data/alignment_sessions/`. La lógica está en
`octoce/alignment_pipeline.py` y se prueba en `tests/test_alignment_pipeline.py`
(incluye la recuperación de una visibilidad sintética conocida).

## Semántica de BM y MB

- **BM**: por cada B-scan espacial se repite la línea completa M veces. Orden
  físico y de archivo: `bscan → repetición → A-line`; shape
  `[B, M, A, pixel]`.
- **MB**: en cada posición lateral se adquieren M A-lines antes de mover el
  galvo. Orden: `bscan → A-line → repetición`; shape `[B, A, M, pixel]`.

Estas siglas no son universales. Confirme que esta definición coincide con la
utilizada en el laboratorio antes de adquirir datos definitivos.

## Patrones

- **Raster**: X es el eje rápido y los B-scans se distribuyen en Y.
- **Crosshair**: cada B-scan lógico contiene dos sweeps consecutivos por el
  centro, primero X y luego Y. El archivo incorpora el eje `sweep_xy` de tamaño
  2; cada sweep conserva la cantidad de A-lines indicada.
- **Meridianos**: B diámetros únicos con ángulos en `[0, π)` dentro de la elipse
  definida por las longitudes X/Y.
- **Lineal**: recorre la misma línea horizontal o vertical por el centro en
  ambos sentidos. En BM el sentido alterna en cada repetición M; en MB alterna
  en cada B-scan y nunca invierte las M A-lines temporales de una posición.
  La comprobación física acotada `python -m diagnostics.diagnose_linear_bidirectional`
  completó ida/retorno horizontal y vertical, cuatro buffers consecutivos,
  cero pérdidas y cuatro pulsos PFI13.
- **Anillos concéntricos** (análogo polar del raster), con muestreo uniforme
  del disco: cada anillo lleva un número de A-lines proporcional a su radio,
  así que la separación en arco es la misma en todos (menos puntos en el
  centro, más hacia afuera).
  - **B** = número de anillos, a radios `(b+1)/B · L/2`. El paso radial es
    uniforme e igual a la distancia del centro al primer anillo; el anillo
    exterior mide exactamente `L/2`.
  - **A** = A-lines del anillo interior. El anillo b lleva `(b+1)·A`, repartidas
    a ángulos iguales que empiezan en +X y giran en sentido antihorario; el
    exterior lleva `B·A`. Por repetición son `A·B(B+1)/2` A-lines y la
    separación en arco es `2π·(L/2)/(B·A)`. Con `A ≈ 2π ≈ 6` esa separación
    iguala el paso radial.
  - **M** = repeticiones de cada anillo completo (BM) o de cada posición (MB).
  - **SS** = puntos sync antes de cada arco (BM) o de cada posición (MB).
  - **Por qué arcos:** la cámara NI-IMAQ adquiere frames de altura fija (A
    líneas en BM), así que el anillo b se adquiere como `b+1` arcos
    consecutivos de A líneas, cada uno con su trigger de cámara y su pulso
    PFI13. Entre arcos hay una transición sync muy corta: el galvo frena y
    vuelve a arrancar, igual que al inicio de cada línea raster.
  - Como los anillos tienen distinta longitud, el archivo se guarda plano en
    orden de adquisición:
    - BM: shape `[sweep, A, pixel]`, en orden anillo → M → arco;
    - MB: shape `[posición, M, pixel]`, en orden anillo → arco → A.
  - El preview muestra cada anillo completo, con el ángulo θ en el eje lateral.
  - Longitud X/Y = diámetros. Si son distintos, los anillos son elipses.
- **Espiral** (Arquímedes, a velocidad angular constante): un único recorrido
  continuo del centro (primera A-line) al borde `L/2` (última A-line).
  - **B** = número de vueltas; cada vuelta es un B-scan.
  - **A** = A-lines por vuelta. El radio crece linealmente con el ángulo, con un
    paso de ≈ `L/2 / B` por vuelta.
  - **M** y **SS** se usan igual que en los anillos.
  - La frecuencia de giro en BM es constante (`klps / A` vueltas/s) y se muestra
    en el resumen del plan. A frecuencias altas el galvo atrasa la fase y reduce
    el radio real; no hay compensación.
- En anillos y espiral, el eje lateral del preview es el ángulo θ (el cursor lo
  muestra en grados). La espiral usa el shape del raster (`[B, M, A]` en BM y
  `[B, A, M]` en MB). El header incluye `scan.polar_geometry` con la fórmula
  exacta de cada posición:
  - anillos: `N_b = (b+1)·A`, `p = arco·A + a`, `ρ = (b+1)/B`, `θ = 2π·p/N_b`;
  - espiral: `k = b·A + a`, `ρ = k/(A·B−1)`, `θ = 2π·k/A`;
  - en ambos casos, `x = cx + ρ·Lx/2·cos θ` y `y = cy + ρ·Ly/2·sin θ`.

Las longitudes son extensiones pico a pico centradas en `(0, 0)`; centro y
límites de tensión forman parte del modelo y pueden ampliarse como controles
cuando se confirme la geometría de la muestra.

## Formato de datos

Cada `.bin` contiene:

1. prefijo binario fijo de 64 bytes;
2. header JSON y padding hasta 64 KiB;
3. espectros crudos `uint16 little-endian` contiguos, sin puntos sync.

El prefijo se actualiza por bloque. Un archivo detenido conserva el conteo de
A-lines válidas y queda marcado `incomplete`. La especificación está en
[docs/BINARY_FORMAT.md](docs/BINARY_FORMAT.md).

Inspección de un archivo:

```powershell
python -m octoce.cli inspect ..\data\acquisitions\OCTOCE_20260911_120000.bin
```

Uso desde Python:

```python
from octoce.storage import open_memmap, read_info

info = read_info("acquisition.bin")
raw = open_memmap("acquisition.bin", logical_shape=info.complete)
```

Lectura en MATLAB (sin toolboxes):

```matlab
addpath('C:/Users/proyecto.pi1081/Desktop/SD-OCT-1310-nm/gui/PYTHON_GUI_DG4162/matlab')
[parametros, alines] = leer_octoce_bin('acquisition.bin');
disp(parametros.scan)
espectro = alines{1};  % uint16, pixeles_por_aline x 1
```

`alines` es un vector de celdas `1×N` en orden temporal de adquisición; cada
celda es un espectro crudo. Los raster BM bidireccionales y los sweeps lineales
BM de retorno se reordenan desde el orden espacial guardado para recuperar ese
orden temporal. El lector valida
firma, versión y CRC32, y admite archivos incompletos leyendo solo las A-lines
confirmadas. Para archivos muy grandes, cargar todas las celdas puede consumir
mucha RAM.

## Pruebas

```powershell
python -m unittest discover -s tests -v
```

Las pruebas automatizadas cubren trayectorias, conversiones V/mm, orden BM/MB, remoción DC, intensidad,
fase diagnóstica, preview,
archivo completo/incompleto, protección contra sobrescritura, secuencia de
armado DAQ y adquisiciones simuladas extremo a extremo para todos los modos y
patrones.

## Decisiones pendientes de confirmar

No se debe afirmar sincronización óptica final hasta resolver y medir:

- la acción exacta configurada en NI-IMAQ para el PFI12 que llega al PCIe-1433
  y cómo se enruta a una adquisición de línea/CC;
- polaridad, ancho y latencia trigger→exposición de la cámara;
- confirmar si la unidad de `BFramesDelay` debe permanecer en microsegundos o
  representa conteos discretos de frame en el sistema externo;
- diámetro real del haz sobre los espejos, posición de JP7 y posición de park;
- raster unidireccional o bidireccional;
- meridianos como diámetros de 180° o radios de 360°;
- calibración longitud de onda→k y compensación de dispersión para que el
  preview sea cuantitativo;
- si el lector existente exige otro contrato `.bin`.

El preview se etiqueta como diagnóstico; la simulación sigue disponible de
forma opcional, pero no es el modo de inicio.
