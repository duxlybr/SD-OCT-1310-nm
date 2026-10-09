## Offset XY del escaneo

Los campos **Offset X · centro** y **Offset Y · centro** desplazan el recorrido
en mm. **Guardar offsets iniciales** conserva el ajuste de centrado en
`config/galvo_offsets.json`, compartido entre las GUIs de esta aplicación;
**Volver a 0,0** modifica solo el plan actual. La alineación continua MB observa
el punto elegido y el crosshair continuo se centra en ese mismo offset.

Se valida el recorrido completo contra el FOV nominal de la **LSM04**:
**14,1 × 14,1 mm**, ±7,05 mm por eje alrededor del cero, además de los límites
eléctricos y angulares GVS002. El gráfico XY mantiene el FOV fijo para mostrar
el desplazamiento; los centros se guardan en el header del .bin. No se añaden
A-lines y los espectros guardados siguen crudos. El offset es lateral XY:
no cambia la profundidad Z ni la distancia axial al transductor.
Referencia: [Thorlabs LSM04](https://www.thorlabs.com/catalogpages/V21/957.pdf).

Al intentar adquirir en **Simulación**, aparece una advertencia que exige
confirmación explícita (respuesta inicial **No**), también en modos continuos.
