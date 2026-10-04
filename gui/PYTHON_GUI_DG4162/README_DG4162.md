# GUI OCT/OCE USB + generador RIGOL DG4162

Copia de `gui/PYTHON_GUI` (variante USB) con control del generador DG4162 y
series de adquisiciones desde Excel. La GUI original no se modifica.

Arranque: `gui\run_gui_dg4162.bat` → `run_gui_dg4162.py` → `octoce.gui_dg4162.main()`.

Requisitos adicionales (Python 3.11, NI-VISA ya instalado):

```
py -3.11 -m pip install -r requirements-dg4162.txt
```

No abra el generador desde Ultra Sigma mientras la GUI está abierta.

## Configuración base del generador (valores por defecto)

| Canal | Configuración |
|-------|---------------|
| CH1 | Senoidal 954.9 kHz (resonancia del transductor), 500 mVpp, offset −0.7 mV DC, **AM siempre activa con fuente EXT** (100 %), carga 50 Ω, sin burst |
| CH2 | Pulso 1 kHz (ciclo 50 %), 1 Vpp, offset 0.452 V, High-Z, sin modulación, burst disparado por EXT (flanco +), 1 ciclo, retardo 2 ms |

Al detectar el generador, y antes de cada adquisición o de *Aplicar ahora*, la GUI verifica esta configuración base y corrige lo que no coincida (registrado en la consola). La frecuencia de resonancia, el offset y la profundidad AM de CH1, la amplitud/offset de CH2, los ciclos por burst y los valores por defecto del panel se editan en *Configuración del generador…* (`gui/config/dg4162_base.json`; el botón *Valores por defecto* los restablece y
*Tomar del generador* adopta lo que esté cargado en el equipo). Al cerrar la GUI se apaga OUTPUT1, OUTPUT2 queda encendido y queda programada esta configuración.

En cada adquisición la GUI programa la amplitud de CH1 y, en CH2, la
frecuencia, la forma de onda, el retardo y los **ciclos por burst** (campo del
panel y columna `ch2_ciclos` del Excel).

Formas de onda de CH2, todas verificadas en el equipo (conservan burst,
amplitud y offset):
- Pulso, Gaussiana, Pulso gaussiano
- Cuadrada, Senoidal, Semiseno, Haversine
- Hanning, Blackman, Triangular, Trapecio
- Rampa, Rampa negativa, Exp. creciente, Exp. decreciente
- Sinc, Lorentz

## Cambios respecto a la GUI USB

1. **Carpeta y nombre separados.** El nombre se escribe sin extensión. Si
   queda vacío, se usa el nombre por defecto. Si el archivo ya existe se añade
   `_1`, `_2`…; nunca se sobrescribe. La etiqueta verde indica el nombre final.
2. **Nombre por defecto:** `OCE_100A_100B_400M_200SS_300mVpp_2000Hz`.
   - Prefijo: `OCE` para MB-mode y `OCT` para BM-mode.
   - Campos: A-lines, B-scans, M-reps, SyncSamples, mVpp de CH1 y Hz de CH2.
   - Sin el control del generador activo, se omiten `mVpp` y `Hz`.
   - El botón **Sugerido** copia el nombre por defecto al cuadro para editarlo.
3. **Panel DG4162.**
   - **Luz de comunicación:** verde = comunicación OK; gris = sin comunicación.
     La GUI busca el generador cada 2 s y conecta sola al encenderlo o
     reconectar el USB. Sin comunicación, los botones del generador quedan
     desactivados y una adquisición con "Controlar DG4162" marcado avisa en
     lugar de iniciarse.
   - **Leer estado:** solo lectura.
   - **Copiar del equipo:** copia los valores actuales del generador a los campos.
   - **Aplicar ahora:** programa los valores con OUTPUT1 apagado y OUTPUT2 encendido.
   - En cada adquisición (botón *Iniciar adquisición*) la GUI programa y
     verifica los valores (~0,1 s) y enciende OUTPUT1 antes del armado del
     hardware NI. Justo antes del primer trigger, el motor verifica que OUTPUT1
     siga encendido. OUTPUT1 se apaga al terminar, al detener o ante un error.
     OUTPUT2 queda siempre encendido, también tras cerrar la GUI.
   - La alineación continua MB verifica OUTPUT1 y lo enciende si está
     apagado; lo apaga al detenerla.
   - **Crosshair continuo: OUTPUT1 estrictamente apagado.** Al iniciarlo la GUI
     apaga OUTPUT1 y lo verifica (si no puede, no inicia); durante el loop el
     controlador rechaza cualquier intento de encenderlo y el vigía lo apaga en
     ≤ 2 s si se enciende desde el panel. Se desbloquea al detenerlo.
   - **Error al adquirir:** se eliminan el `.bin` fallido, su `_dg4162.json` y
     la foto/video USB, y se repite la adquisición con el mismo nombre. Se
     admiten como máximo 3 reintentos. *Detener* cancela un reintento
     pendiente. En una secuencia, si fallan los reintentos, la secuencia se
     detiene.
   - **Al cerrar la GUI:** se apaga OUTPUT1, OUTPUT2 queda encendido y queda programada la
     configuración base (*Configuración del generador…*).
   - **Reglas de seguridad de las salidas:**
     - Ningún parámetro cambia con OUTPUT1 encendido: toda escritura que no sea
       encender/apagar una salida comprueba OUTPUT1 justo antes y lo apaga
       (`DG4162Controller.write`). Si no se apaga, el cambio no se envía.
     - OUTPUT2 permanece encendido (también al cerrar la GUI): se enciende al conectar y el vigía de
       comunicación lo vuelve a encender en ≤ 2 s si se apaga (panel o
       cambio de parámetros).
     - OUTPUT1 nunca se enciende con CH1 por encima del límite (1 Vpp; 5 Vpp
       solo en modo con contacto confirmado). Protege, por ejemplo, tras
       encender el generador, que arranca con CH1 a 5 Vpp.
     - Cada vez que una regla actúa queda registrado en la consola.
   - Junto a cada `.bin` se guarda `<nombre>_dg4162.json` con los valores
     programados y el estado leído del equipo.
4. **Límite de voltaje de CH1.**
   - *Sin contacto:* máximo 1 Vpp (límite del amplificador). Por encima, la
     adquisición queda bloqueada.
   - *Con contacto:* máximo 5 Vpp. Por encima de 1 Vpp se pide confirmación
     explícita.
5. **Secuencia desde Excel.**
   - **Crear plantilla…** genera un `.xlsx` con ejemplos, listas desplegables
     y una hoja de instrucciones.
   - Cada fila es una adquisición, con columnas para:
     - modo, patrón, A, B, M y SS;
     - excitación, mVpp de CH1, y Hz, forma de onda y retardo de CH2;
     - repeticiones, espera y nombre.
   - Las celdas vacías toman el valor actual de la GUI.
   - **Cargar y validar** revisa todas las filas, incluido el límite de voltaje,
     y muestra los nombres de archivo previstos.
   - **Iniciar secuencia** confirma una sola vez y muestra el progreso.
     **Detener secuencia** aborta la adquisición en curso.
   - **Tiempos.**
     - Al cargar el Excel se muestra el tiempo estimado total y el de cada
       adquisición (columna *Estimado*).
     - Durante la secuencia se ven, cada segundo, el tiempo real transcurrido,
       el restante, el total estimado y la hora prevista de fin. La columna
       *Real* registra cuánto tardó cada adquisición, incluidos los reintentos.
     - El estimado parte de la duración mínima de cada adquisición más ≈ 3 s de
       preparación. Tras cada adquisición se reajusta con las duraciones reales
       de la sesión: `real ≈ escala · mínimo + preparación`, sobre las últimas
       20 adquisiciones.
     - Las esperas `espera_s` se cuentan exactas.
     - Al terminar se registran el tiempo real y el estimado inicial.
   - El patrón admite también `Anillos` y `Espiral` (ver `README.md`, *Patrones*).

## Diagnóstico

```
py -3.11 diagnostics\dg4162_check.py                  # solo lectura
py -3.11 diagnostics\dg4162_check.py --write-test     # programa, OUTPUT1 queda OFF
```

Nota de firmware 00.01.14: `:OUTPn?` y `:OUTPn:POL?` devuelven una línea
vacía extra. `DG4162Controller` la lee inmediatamente. Esperarla con timeout
costaba ~2 s por consulta y causaba la demora de ~10 s antes de OUTPUT1.

## Interfaz

- **Plan de adquisición** (incluye *Configuración de hardware…*) y
  **Generador DG4162** (incluye *Secuencia desde Excel…*) son secciones
  desplegables; ambas empiezan abiertas.
- λ inicial/final para k y dispersión D2/D3 están en *Configuración de hardware…*.
- **Cámara USB (⚙):**
  - *Al adquirir:* sin captura, foto o video.
  - *Área a guardar:* FOV completo o solo la ROI de 15 × 15 mm.
  - *Setup de cámara · calibrar ROI…* (antes `run_camera_roi_setup.bat`).
    Parte de la ROI guardada (rojo discontinuo) y las flechas +X/+Y muestran
    la orientación de los galvos. Al cerrar el setup se guarda automáticamente
    la ROI aprobada, o solo la inversión X/Y si es lo único que cambió.
  - *Invertir X/Y* voltea la imagen (vista, foto y video) para que +X/+Y de
    los galvos queden a la derecha/abajo.
  - Brillo: la cámara solo admite 0–255 (0 = más oscuro).
- La ventana arranca maximizada; F11 activa o desactiva la pantalla completa.
- La vista de la cámara USB empieza como un cuadrado.
- El plot del patrón X/Y usa la misma escala en X e Y.

## Pruebas

```
py -3.11 -m unittest discover -s tests
```

`tests/test_dg4162.py` usa un DG4162 simulado y no necesita el equipo.
