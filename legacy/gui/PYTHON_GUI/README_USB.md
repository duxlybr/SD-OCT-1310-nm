# GUI OCT/OCE con cámara USB

Esta es una **variante separada**. La entrada original `run_gui.py` y su GUI
siguen sin cambios. La variante muestra video USB a la derecha del B-scan en
BM, MB y todos los patrones de escaneo. En alineación continua muestra a la vez
el B-scan, el zoom de 20 píxeles alrededor del Z seleccionado y la cámara USB.
El zoom usa los mismos controles Z, intensidad y mapa de color de la GUI sin USB.

La cámara se muestra en la parte inferior derecha de la misma ventana, junto a
las pestañas Fase y Patrón XY. El divisor horizontal permite ajustar el espacio
entre ambos paneles.
El divisor entre el B-scan y la fila inferior también permite ajustar sus alturas:
arrastre la línea horizontal hacia arriba o abajo. Inicialmente el B-scan ocupa
el 70 % del espacio de visualización y la fila inferior el 30 %.
El botón pequeño **⚙**, sobre la cámara, abre una ventana con los controles
de conexión, captura, foco, ROI e indicadores. Al cerrarla se conservan sus valores;
la imagen de cámara continúa integrada en la GUI. Los campos **Z inicio** y **Z fin**
están arriba del B-scan, con **Z visible** a la derecha de Z fin; los controles de
cursor y Z bin exacto quedan debajo. **Límites en dB** está activado por defecto.
La barra de adquisición, buffers, pérdidas, cola,
ETA y velocidad están en el encabezado azul. Los mensajes de consola salen al
CMD desde el que se inició la aplicación.

La pestaña Patrón XY incluye los recorridos sync reales como líneas discontinuas
naranjas con flechas: desde park al primer punto y entre segmentos, incluyendo
repeticiones y cambios de sweep. Para planes grandes muestra hasta 160 segmentos
distribuidos por todo el plan y hasta 64 vértices por transición, sin generar todos
los buffers de adquisición para dibujar. Los puntos sync no reciben trigger de
cámara ni se guardan en el payload.

## Inicio

```powershell
cd C:\Users\proyecto.pi1081\Desktop\OCT_GUI\PYTHON_GUI
python -m pip install -r requirements-usb.txt
python run_gui_usb.py
```

También se puede abrir `run_gui_usb.bat` con Python 3.11. La cámara conectada
Logitech C525 funcionó en este equipo con el índice USB `0` a 640×480. Si
Windows cambia el índice, seleccione otro en el panel **Cámara USB** y pulse
**Conectar**. La captura y el refresco visual son independientes del hilo NI:
solo se conserva el fotograma USB más reciente, sin acumular una cola.

La GUI inicia siempre en **pantalla completa**, sin abrir automáticamente el
ajuste de cámara. Para ajustar foco y brillo, pulse **⚙** y luego
**Ajustar foco y brillo · vista grande**. En esa ventana de ajuste, F11 alterna
pantalla completa. Los controles muestran el valor solicitado y el
valor realmente leído; se advierte si el controlador no confirma el foco
manual o no aplica el ajuste. Al reconectar la cámara se restauran los últimos
valores manuales confirmados. El intervalo admitido depende del controlador
USB; también se pueden escribir valores numéricos fuera de los deslizadores.

En **Captura USB** elija **Sin captura**, **Foto** o **Video**. Foto guarda un
PNG nuevo justo antes de iniciar OCT; Video abre un MP4 y espera a que su
primer fotograma esté escrito **antes** de iniciar OCT, y lo cierra al
completar, detener o fallar la adquisición. Si la cámara o el codificador
fallan al preparar la captura, OCT no empieza. Con archivo OCT, se guarda
junto al `.bin` como `nombre_usb.png` o `nombre_usb.mp4`; sin archivo OCT,
se usa `USB_fecha_hora.png` o `USB_fecha_hora.mp4` en la carpeta de salida.
Los nombres existentes no se sobrescriben. En alineación, la captura y la vista
USB siguen disponibles junto al zoom. El archivo `.bin` no contiene
fotogramas USB.

La captura USB no está sincronizada por hardware con PFI12/PFI13. El video
comienza antes de OCT, pero su cadencia depende de la cámara y el codificador.
Si se activa **Guardar**, OCT continúa sin preview como en la GUI principal,
mientras el video USB permanece visible. Para maximizar el rendimiento de una
adquisición extensa sin video, use la GUI principal.

Esta variante hereda los controles OCT de la GUI principal: loop crosshair
BM 10×10 mm (500 A-lines en X y 500 en Y), límites de intensidad en dB,
rango Z del B-scan, selección exacta de Z bin por texto o deslizador y tiempo
de adquisición en el log. Durante el loop crosshair
el video USB permanece visible, también durante la alineación continua MB.

## Setup opcional de escala y ROI

Antes de abrir la GUI USB, ejecute `python run_camera_roi_setup.py` o abra
`run_camera_roi_setup.bat`. Para otra cámara use `--camera 1` (o su índice).

1. Coloque una referencia de medida conocida en el mismo plano de adquisición.
2. Seleccione **Línea**, **Cuadrado** o **Elipse / círculo** e introduzca su medida
   real en mm: longitud de la línea, lado del cuadrado o diámetro de la elipse.
   Para la elipse seleccione el diámetro horizontal o vertical conocido.
   Pulse **Congelar / reiniciar**.
3. Dibuje con dos clics o arrastrando sobre la imagen. En el cuadrado y la elipse,
   los puntos definen esquinas opuestas; el cuadrado mantiene lados iguales.
   Ajuste los puntos arrastrándolos o mueva la figura arrastrando su interior.
4. Pulse **Aprobar geometría**. Se calcula px/mm usando la imagen original,
   independientemente del tamaño de la ventana. **Editar geometría** permite
   volver a ajustarla. Cambiar la figura, medida o diámetro exige aprobar de nuevo
   y volver a seleccionar el centro.
5. Haga clic en el centro deseado, que debe corresponder al origen XY
   del escaneo (galvos en 0 V). Aparece la ROI cuadrada de **15 × 15 mm**.
   Puede hacer nuevos clics para cambiar el centro. Si no cabe en el sensor,
   el setup exige otro centro o escala; no desplaza la ROI automáticamente.
6. Pulse **Guardar ROI**. Se guarda `../config/camera_roi.json`, fuera del código,
   con índice de cámara, resolución, escala, centro y orientación de ejes.

La GUI carga ese archivo al iniciar y recorta únicamente la vista USB. Sin
archivo funciona con la imagen completa. **Usar ROI guardada** permite alternar
el recorte, y **Recargar calibración ROI** carga cambios sin reiniciar la GUI.
Si cambia el índice o la resolución, se muestra la imagen completa con un aviso
y se desactivan los indicadores métricos hasta recalibrar.

El setup supone escala uniforme, imagen sin rotación respecto a los ejes XY y
calibración en el plano observado. X positivo apunta a la derecha e Y positivo
hacia abajo; use las casillas de inversión si los galvos tienen otro sentido.
Recalibre si cambia el zoom óptico, la cámara o su posición. El recorte redondea
a píxeles enteros (error de tamaño de hasta medio píxel).

## Indicadores opcionales de adquisición

Active **Indicador rojo del patrón** para superponer geometría calibrada:

- Meridianos: círculo con FOV X = Y; elipse si X e Y difieren.
- Crosshair: cruz con las longitudes X/Y seleccionadas.
- Raster: borde rectangular del FOV X/Y.
- Lineal: segmento horizontal o vertical según orientación.
- Alineación continua de A-lines: punto rojo en el centro calibrado.

Al adquirir se utiliza la configuración activa, incluyendo el crosshair continuo
de 10 × 10 mm; en reposo se usan los parámetros seleccionados. Las figuras se
recortan al borde de la vista. Estos indicadores empiezan desactivados y requieren
calibración válida, incluso si se muestra la imagen completa.

Las fotos y los MP4 conservan los fotogramas originales completos sin indicadores;
el recorte y la superposición afectan la vista de la GUI. No modifican las señales
de adquisición. Para añadir geometría de futuros patrones, registre un renderer
en `octoce.camera_roi.OUTLINE_RENDERERS`, que devuelve primitivas y coordenadas
en mm; un patrón desconocido no muestra una figura inventada.
