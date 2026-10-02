# GUI OCT/OCE USB + generador RIGOL DG4162

Copia de `gui/PYTHON_GUI` (variante USB) con control del generador DG4162 y
series de adquisiciones desde Excel. La GUI original no se modifica.

Arranque: `gui\run_gui_dg4162.bat` → `run_gui_dg4162.py` → `octoce.gui_dg4162.main()`.

Requisitos adicionales (Python 3.11, NI-VISA ya instalado):

```
py -3.11 -m pip install -r requirements-dg4162.txt
```

No abra el generador desde Ultra Sigma mientras la GUI está abierta.

## Configuración de referencia (STATE 4: `1040octoacus1000.RSF`)

| Canal | Configuración |
|-------|---------------|
| CH1 | Senoidal 948.07 kHz, 500 mVpp, AM 100 % con fuente EXT, carga 50 Ω |
| CH2 | Pulso 2 kHz, 1 Vpp, offset 0.452 V, High-Z, burst disparado por EXT (1 ciclo), retardo 6 ms (típico 2 ms) |

La GUI controla la amplitud de CH1 y, en CH2, la frecuencia, la forma de onda
y el retardo del burst. El resto queda como esté en el panel.

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
   - **Conectar / leer:** solo lectura. Se ejecuta también al abrir la GUI.
   - **Copiar del equipo:** copia los valores actuales del generador a los campos.
   - **Aplicar ahora:** programa los valores con OUTPUT1 apagado y OUTPUT2 encendido.
   - En cada adquisición (botón *Iniciar adquisición*) la GUI programa y
     verifica los valores (~0,1 s) y enciende OUTPUT1 antes del armado del
     hardware NI. Justo antes del primer trigger, el motor verifica que OUTPUT1
     siga encendido. OUTPUT1 se apaga al terminar, al detener o ante un error.
     OUTPUT2 queda encendido mientras la GUI está abierta.
   - La alineación continua MB verifica OUTPUT1 y lo enciende si está
     apagado; lo apaga al detenerla. El crosshair continuo no toca el
     generador.
   - **Error al adquirir:** se eliminan el `.bin` fallido, su `_dg4162.json` y
     la foto/video USB, y se repite la adquisición con el mismo nombre. Se
     admiten como máximo 3 reintentos. *Detener* cancela un reintento
     pendiente. En una secuencia, si fallan los reintentos, la secuencia se
     detiene.
   - **Al cerrar la GUI:** se apagan OUTPUT1 y OUTPUT2, y CH1/CH2 vuelven a los
     valores leídos en la primera conexión (estado base).
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

## Diagnóstico

```
py -3.11 diagnostics\dg4162_check.py                  # solo lectura
py -3.11 diagnostics\dg4162_check.py --write-test     # programa, OUTPUT1 queda OFF
```

Nota de firmware 00.01.14: `:OUTPn?` y `:OUTPn:POL?` devuelven una línea
vacía extra. `DG4162Controller` la lee inmediatamente. Esperarla con timeout
costaba ~2 s por consulta y causaba la demora de ~10 s antes de OUTPUT1.

## Interfaz

- La vista de la cámara USB empieza como un cuadrado.
- El plot del patrón X/Y usa la misma escala en X e Y.

## Pruebas

```
py -3.11 -m unittest discover -s tests
```

`tests/test_dg4162.py` usa un DG4162 simulado y no necesita el equipo.
