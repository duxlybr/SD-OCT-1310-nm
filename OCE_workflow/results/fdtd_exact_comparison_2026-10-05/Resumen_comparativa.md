# Comparativas Exact XZ / True FDTD XZ — 5 de octubre de 2026

Se exportaron nueve figuras pareadas a `../Speed_Young_Maps/`: ocho simulaciones
FDTD nuevas y el caso CPU previo de 12 kPa. Cada figura contiene velocidad arriba
y Young abajo, con cuatro columnas: Exact PG, FDTD PG, Exact direccional y FDTD
direccional. Comparten ejes, ventanas y escalas. Gris significa falta de soporte;
no se rellenan huecos ni suavizan los mapas numéricos.

## Diversidad y comparación controlada

Rayleigh: 6, 12 y 24 kPa, 1000/1500 Hz, Poisson 0.495/0.45, fuente lineal y puntual,
y una inclusión esférica de 24 kPa en fondo de 12 kPa. Lamb: placa de 12 kPa,
espesores nominales 0.6/1.2 mm y frecuencias 500/1000 Hz. La referencia Rayleigh
es el modo analítico homogéneo; Lamb utiliza el modo libre A0 con sus dos caras
sin tracción. Véase [verificación del A0](analytic_a0_reference.md).

El caso con inclusión compara con un **baseline analítico homogéneo**; no existe
una solución Exact XZ heterogénea en esta prueba. Su contorno blanco identifica
geometría material de referencia, no un borde reconstruido. La discrepancia de c
respecto al fondo homogéneo tampoco mide exactitud dentro de la inclusión.

Los campos nuevos provienen del solver elástico 3D del simulador, con presión
superficial y dominio finito. Se usa una sección XZ y la componente axial. Malla
objetivo de 20 muestras por longitud de onda, al menos 12 celdas por espesor Lamb,
CPML de 12 celdas. Los manifests conservan malla efectiva, espesor discretizado,
fuente, advertencias y convergencia. La fuente puede estar submuestreada; la
convergencia temporal no certifica convergencia espacial ni pureza modal.

Cada par usa los mismos ejes, tiempos y máscara; ruido de 30 dB con semillas
fijas independientes y normalización global de amplitud. El caso CPU previo
conserva su traza original con ruido, sin añadir ruido otra vez. Se excluyen
centros cuya ventana completa esté a menos de dos longitudes de onda de la fuente.
La velocidad B-scan es lateral: cada profundidad se estima independientemente.

Parámetros congelados: ventana X=0.5 lambda, Z=0, coherencia 0.65, amplitud 0.05,
soporte 0.8, error de ajuste 0.30, sector 0 grados ±45 grados, rango 0.2–8 m/s.
Young es una inversión condicional Rayleigh o A0 libre con espesor nominal,
densidad y Poisson conocidos. No se trata de una inversión elástica general.

## Resultados

Las discrepancias son medianas del error absoluto relativo en píxeles aceptados
del ROI, no error de la mediana. Se guardó también `paired_xz_common_support.csv`
para comparar sobre soporte común. La cobertura usa todo el ROI como denominador.

| Caso True FDTD | Estimador | Discrepancia c (%) | Discrepancia E (%) | Cobertura (%) |
|---|---|---:|---:|---:|
| rayleigh_12kPa_original_mesh010mm | phase_gradient | 1.92 | 3.82 | 90.91 |
| rayleigh_12kPa_original_mesh010mm | directional_phase | 2.31 | 4.61 | 90.91 |
| lamb_A0_12kPa_h060mm_1000Hz | phase_gradient | 5.22 | 14.12 | 91.67 |
| lamb_A0_12kPa_h060mm_1000Hz | directional_phase | 4.00 | 10.81 | 91.67 |
| lamb_A0_12kPa_h060mm_500Hz | phase_gradient | 4.27 | 13.51 | 91.67 |
| lamb_A0_12kPa_h060mm_500Hz | directional_phase | 2.85 | 8.99 | 91.67 |
| lamb_A0_12kPa_h120mm_1000Hz | phase_gradient | 17.24 | 42.56 | 85.62 |
| lamb_A0_12kPa_h120mm_1000Hz | directional_phase | 16.88 | 43.89 | 83.61 |
| rayleigh_12kPa_nu045_1500Hz | phase_gradient | 1.21 | 2.40 | 92.31 |
| rayleigh_12kPa_nu045_1500Hz | directional_phase | 2.05 | 4.07 | 92.31 |
| rayleigh_12kPa_point_source_1000Hz | phase_gradient | 1.02 | 2.03 | 91.67 |
| rayleigh_12kPa_point_source_1000Hz | directional_phase | 1.73 | 3.50 | 91.67 |
| rayleigh_12kPa_stiff_inclusion | phase_gradient | 13.04 | 14.72 | 91.67 |
| rayleigh_12kPa_stiff_inclusion | directional_phase | 12.55 | 14.09 | 91.67 |
| rayleigh_24kPa_1000Hz | phase_gradient | 1.19 | 2.39 | 92.31 |
| rayleigh_24kPa_1000Hz | directional_phase | 1.43 | 2.84 | 92.31 |
| rayleigh_6kPa_1000Hz | phase_gradient | 1.21 | 2.41 | 92.31 |
| rayleigh_6kPa_1000Hz | directional_phase | 3.11 | 6.23 | 92.31 |

En Rayleigh homogéneo, PG da aproximadamente 1–2% en velocidad y 2–4% en Young.
Lamb de 0.6 mm mejora con el filtro direccional en estos ensayos, pero conserva
8.99–10.81% de discrepancia en Young. Lamb de 1.2 mm presenta 42.56–43.89%:
se conserva como fallo visible. Mezcla modal, dominio/fuente y discretización
son posibles causas; esta validación no separa sus contribuciones.
El rendimiento depende del campo y del modelo de inversión; no hay una regla
universal «direccional para Lamb / PG para Rayleigh».

El caso de 500 Hz necesitó 42 ciclos (cambio entre bloques 0.447%); el intento
de 36 ciclos no convergió y permanece en `gpu/`. El par utiliza `gpu_extended/`.
Los otros campos exportados cumplen el criterio temporal de 0.5%.

El control CPU/GPU con malla gruesa equivalente da diferencia relativa L2
1.376e-07. Comprueba acuerdo entre backends, no exactitud física.

## Reproducción y archivos

Desde esta carpeta, con el Python del simulador:

```text
python generate_fdtd_variety.py --backend gpu --output-subdir gpu
python generate_fdtd_variety.py --backend gpu --output-subdir gpu_extended --case lamb_A0_12kPa_h060mm_500Hz --max-periods 96
python prepare_paired_xz_cases.py
```

Después ejecutar `evaluate_paired_xz.m` en MATLAB R2025b y
`python finalize_comparison.py`. Los MAT de campos/mapas permanecen locales;
los scripts, manifests, CSV y PNG permiten auditar y reproducir la validación.
La galería contiene sólo imágenes; el [inventario](../map_gallery_validation_2026-10-05/gallery_image_inventory.csv)
conserva dimensiones y hashes. La regresión final da 50 PASS y dos fallos previos:
conteo de archivos MIMT y preferencia preexistente de video filtrado.
No se alteraron goldens para obtener un gate verde.
