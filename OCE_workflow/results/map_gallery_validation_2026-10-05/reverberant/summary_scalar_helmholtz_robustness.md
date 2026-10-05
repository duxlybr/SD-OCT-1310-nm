# Sensibilidad observacional de la inclusión rígida

Tres problemas directos adicionales de Helmholtz escalar se ejecutaron secuencialmente. Los materiales, fuentes físicas, radio de inclusión, frecuencia de 1800 Hz, ruido de 25 dB y ventana de 2.4 mm permanecen fijos. Las fases de las 24 fuentes cambian en dos ensayos mediante semillas predefinidas; el tercero conserva la semilla nominal y refina el paso espacial de 0.1 a 0.075 mm.

Se reprodujo el preámbulo del generador de ruido nominal para mantener los mismos números de ruido de medida en los ensayos con igual malla. El refinamiento tiene otro número de nodos; mantiene la semilla y SNR, y no se interpreta como comparación exacta de ruido píxel a píxel. Los resultados nominales, MAT y PNG de la galería no se sobrescribieron.

Los errores son medianas de errores absolutos relativos sobre píxeles aceptados. Se informa también cobertura sobre la región completa.

| Ensayo | Región | Cobertura (%) | Error velocidad (%) | Error Young (%) | Young mediano (kPa) |
|---|---|---:|---:|---:|---:|
| Nominal: dx 0.1 mm; semilla 20261005 | Núcleo | 100.000 | 1.336 | 2.691 | 24.354 |
| Nominal: dx 0.1 mm; semilla 20261005 | Fondo | 99.859 | 1.356 | 2.694 | 11.704 |
| Nominal: dx 0.1 mm; semilla 20261005 | Interfaz | 99.893 | 2.430 | 4.826 | 12.369 |
| Nominal: dx 0.1 mm; semilla 20261005 | Campo útil | 99.884 | 2.008 | 3.995 | 12.042 |
| dx 0.1 mm; semilla 20261006 | Núcleo | 100.000 | 2.500 | 4.937 | 22.815 |
| dx 0.1 mm; semilla 20261006 | Fondo | 99.953 | 1.594 | 3.163 | 11.633 |
| dx 0.1 mm; semilla 20261006 | Interfaz | 99.979 | 2.719 | 5.434 | 12.569 |
| dx 0.1 mm; semilla 20261006 | Campo útil | 99.971 | 2.168 | 4.320 | 12.067 |
| dx 0.1 mm; semilla 20261007 | Núcleo | 100.000 | 1.023 | 2.057 | 23.587 |
| dx 0.1 mm; semilla 20261007 | Fondo | 99.953 | 1.286 | 2.558 | 11.722 |
| dx 0.1 mm; semilla 20261007 | Interfaz | 99.893 | 2.690 | 5.401 | 12.639 |
| dx 0.1 mm; semilla 20261007 | Campo útil | 99.913 | 1.966 | 3.914 | 12.162 |
| dx 0.075 mm; semilla 20261005 | Núcleo | 100.000 | 1.471 | 2.920 | 24.465 |
| dx 0.075 mm; semilla 20261005 | Fondo | 100.000 | 0.870 | 1.739 | 11.926 |
| dx 0.075 mm; semilla 20261005 | Interfaz | 99.940 | 2.375 | 4.778 | 12.724 |
| dx 0.075 mm; semilla 20261005 | Campo útil | 99.960 | 1.487 | 2.975 | 12.246 |

La dependencia de la realización de las fuentes es moderada en el campo útil: error mediano de velocidad de 1.966–2.168% y Young de 3.914–4.320% entre las tres semillas. En el núcleo de la inclusión la variación es mayor: velocidad de 1.023–2.500% y Young de 2.057–4.937%. Todas las semillas aceptan el 100% de los 81 píxeles del núcleo conservador; la cobertura del campo útil supera 99.88%.

Con dx = 0.075 mm el error del campo útil disminuye de 2.008 a 1.487% en velocidad y de 3.995 a 2.975% en Young; el fondo mejora de 1.356 a 0.870% en velocidad. El núcleo cambia de 1.336 a 1.471% en velocidad y no mejora. La mediana firmada de velocidad en el fondo pasa de -1.240 a -0.310%, consistente con que la discretización contribuye al sesgo. Dos niveles de malla comprueban estabilidad; no prueban convergencia asintótica ni separan completamente error de malla, ajuste y realización del ruido.

Los ensayos finos usan 321 × 321 nodos. Sus regiones contienen 137 píxeles de núcleo, 4008 de fondo y 12477 de campo útil. La geometría de selección sigue expresada en unidades físicas y verifica que toda la ventana esté alejada más de dos longitudes de onda del fondo del soporte de 3σ de las fuentes, y fuera del absorbente.

Para reproducir estos tres ensayos, ejecutar `python run_scalar_helmholtz_robustness.py` desde esta carpeta con NumPy/SciPy disponibles y MATLAB en PATH. El script llama MATLAB con `-singleCompThread`, guarda cada campo y mapa en archivos de prefijo `scalar_helmholtz_robustness_`, y consolida los resultados en `scalar_helmholtz_robustness_metrics.csv`. Las verificaciones del problema directo se guardan en `scalar_helmholtz_robustness_diagnostics.json`. Ejecutar después `python summarize_scalar_helmholtz_validation.py` regenera este resumen y el manifiesto.

Esta sensibilidad corresponde a ondas escalares de corte antiplano, no a un ensayo experimental ni a un modelo completo de OCE 3D. Los mapas y el módulo de Young siguen condicionados al modelo físico del ensayo.
