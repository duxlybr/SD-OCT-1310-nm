# Galería experimental de velocidad y Young aparente

Las cinco imágenes `experimental_*.png` se guardan en
`../../Speed_Young_Maps`. Esta carpeta conserva el script reproducible,
los MAT completos (plano de entrada, velocidad, Young, máscaras y metadatos),
el CSV de métricas y los hashes SHA-256 de los dos propietarios científicos.
No se vuelve a leer el BIN raster de 16 GB ni se modifica la adquisición.

Se utilizan los planos MAT ya reconstruidos y el core final después de la
corrección del filtro direccional. Cada recálculo debe reproducir el número
de píxeles y la mediana de velocidad de la referencia final en
`results/extended_validation_2026-10-05/experimental_sensitivity`;
el script se detiene si no coincide. Los parámetros se fijaron antes del
renderizado: ROI 2–4 ms, coherencia mínima 0.2, ventana X de 1.2 mm,
ventana de fila de 1.2 mm en raster / 0.08 mm en B-mode, soporte mínimo 0.6,
amplitud relativa mínima 0.08, rechazo de ajuste 0.3 y sin suavizado.
La dirección seleccionada es 0° con sector ±35°.

La frecuencia de análisis es 1000 Hz para Luis3 y 2000 Hz para raster,
suministrada explícitamente según las condiciones experimentales descritas.
Estos encabezados antiguos no contienen los datos del generador y no los
adquieren por inferencia durante la carga.

Los grises son resultados ausentes o rechazados. Los mapas muestran toda
la extensión física reconstruida; no se recortan para ocultar zonas fallidas
ni se interpolan NaN. Las escalas de presentación son comunes: 0–4 m/s y
0–30 kPa. Los valores cuantitativos proceden de las matrices originales,
no de una imagen suavizada. La cobertura expresa soporte del estimador,
no exactitud, confianza calibrada ni porcentaje de tejido caracterizado.

## Hipótesis de Young

Todos los paneles de módulo se rotulan **Young aparente · modelo supuesto**.
Se asumen densidad 1000 kg/m³ y Poisson 0.495, homogeneidad, isotropía y
elasticidad pura. Son hipótesis; no se han medido para esta gelatina con
glicerina. Las máscaras de Young conservan exactamente el soporte de velocidad.

- Fase direccional: inversión Rayleigh mediante la raíz de la ecuación
  secular. Sólo es válida si la velocidad corresponde a una onda Rayleigh
  de un semiespacio elástico con borde libre.
- AIA `shear3d`: inversión de corte volumétrico
  `E = 2 rho (1 + nu) c_s^2`. Requiere que la estimación represente velocidad
  de corte y que el campo usado por AIA sea difuso e isotrópico.

La medición de velocidad no identifica el modo ni las condiciones de borde.
La adquisición sin contacto no demuestra por sí sola estas hipótesis.
No existe ground truth experimental; estas conversiones no validan un
Young cuantitativo de la muestra. Una adquisición monofrecuencia tampoco
identifica separadamente elasticidad y viscosidad.

## Profundidad y limitaciones

Los planos raster 0 y +0.10 mm son relativos al máximo OCT encontrado en
el intervalo FFT 50–700, dentro del recorte 1–700, con índice óptico 1.4 y
banda axial de 0.04 mm. Ese máximo es una interfaz candidata, **no una
superficie anatómica verificada**. La calibración óptica y las bandas cercanas
a DC aún requieren revisión. La repetibilidad de fase entre posiciones MB
tampoco está verificada por la existencia de disparos en el encabezado.
Un mapa a +0.10 mm no constituye una medida independiente del Young de esa
capa: un mismo modo superficial puede penetrar varios planos.

La referencia final de +0.25 mm no acepta píxeles en ninguno de estos métodos.
No se incluye un panel de esa profundidad en la galería; no hay evidencia
de soporte suficiente para un mapa de velocidad o módulo bajo estos parámetros.
Luis3 contiene sólo 11 píxeles aceptados sobre 52 350, aproximadamente
0.021 %. Se conserva todo el B-mode 1 independiente y no se unen los cuatro
meridianos para simular continuidad.

## Reproducción

Desde MATLAB R2025b, ejecutar el script
`render_experimental_speed_young_gallery.m`. Requiere los cuatro planos
guardados en `Desktop/OCE_fish/OCE_estimator_validation/experimental`
y el CSV final citado. El registro `experimental_gallery.log` y
`experimental_speed_young_metrics.csv` documentan esta ejecución.

El script y estos resultados son observacionales; no se añaden al catálogo
de pruebas mantenidas ni cambian el código de producción.
