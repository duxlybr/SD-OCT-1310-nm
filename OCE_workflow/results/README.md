# Resultados de validación OCE

La [comparativa desde fase cruda con phase derivative 2D](unwrap_comparison_2026-10-05/Resumen_comparativa.md)
compara unwrap secuencial, mínimos cuadrados DCT y TIE-DCT de 8 correcciones
fijas. Incluye pares Exact/FDTD, controles de ruido/alias, el pez enface con
8 excitaciones independientes y Luis3 leído directamente del BIN. Los filtros,
promedios y estimadores se aplican después del unwrap óptico; se documenta
también el unwrap modal y la ablación de sus etapas.

La [comparativa ampliada Exact XZ / True FDTD XZ](fdtd_exact_comparison_2026-10-05/Resumen_comparativa.md)
añade nueve figuras con ambos estimadores, velocidad y Young en la misma figura:
Rayleigh con rigidez/fuente/Poisson variables e inclusión, y Lamb con dos espesores
y dos frecuencias. Incluye el caso Lamb de mayor discrepancia y sus límites.
El inventario actualizado registra las imágenes de todos los ensayos y verifica
que la galería sólo contiene PNG.

La [galería Speed_Young_Maps](Speed_Young_Maps/) contiene únicamente imágenes
de mapas de velocidad y Young: Lamb con inclusiones, campo reverberante y
datos experimentales. El [resumen y la reproducción de esa galería](map_gallery_validation_2026-10-05/Resumen_galeria.md)
están fuera de la carpeta de imágenes.

La [validación B-scan y del pez con ocho excitaciones individuales](bscan_fish_validation_2026-10-05/Resumen_validacion.md)
contiene la nueva comparación Rayleigh analítico/FDTD, Lamb con inclusión,
los cuatro B-modes independientes de Luis3 y la fusión de dos inclusiones.
En el pez, la fusión PG recupera 24.234/23.196 kPa en cabeza/cola de 24 kPa,
con 100 % de cobertura del ROI y sin relleno. Los ensayos y límites de
interpretación, incluida la señal experimental localizada, están en ese resumen.

Abra el [resumen de validación ampliada](extended_validation_2026-10-05/Resumen_validacion.md). Incluye figuras, tablas, límites físicos y comandos de reproducción.

La validación del 5 de octubre de 2026 contiene:

- 104 realizaciones sintéticas y 312 ejecuciones de los estimadores, con ruido, reflexiones, campos difusos, huecos y controles sin propagación.
- 4 simulaciones FDTD para sensibilidad a malla y paso temporal.
- 90 referencias mecánicas, 234 conversiones de Young y 1296 perturbaciones de sus entradas.
- 200 evaluaciones de los planos experimentales, incluidos 20 controles de fase/tiempo.
- CSV por ejecución, mapas MAT sin suavizado, figuras PNG/SVG, parámetros, hashes de código y registros MATLAB.

Se corrigió una fuga espectral direccional detectada por los controles: el movimiento uniforme dejó de producir mapas falsos en los casos ensayados. En FDTD, el error direccional fue 2,76% frente a 7,61% del gradiente original sobre los mismos 209 píxeles de la malla de 0,15 mm.

![Comparación FDTD](extended_validation_2026-10-05/fdtd_validation.png)

La exactitud experimental permanece sin verificar. Las regiones rechazadas siguen vacías y a +0,25 mm no hubo soporte suficiente. La regresión completa conserva 50 pruebas aprobadas y los dos fallos preexistentes documentados en el resumen.

Los resultados finales están en `extended_validation_2026-10-05/`. `before_directional_fix/` conserva la comparación anterior al arreglo; `previous_validation/` conserva la validación inicial. Los archivos grandes de entrada permanecen en sus ubicaciones originales.
