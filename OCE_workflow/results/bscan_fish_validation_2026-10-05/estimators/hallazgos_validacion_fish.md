# Reconstrucción de dos inclusiones con ocho excitaciones independientes

Los nueve PNG publicados corresponden a ocho excitaciones individuales de 0 a 315 grados y su fusión PG. Cada adquisición conserva su fase y ruido propios; la combinación usa estimaciones de lentitud, sin suma coherente de campos. Los píxeles grises de los mapas individuales siguen rechazados. El contorno blanco es la geometría material de referencia simulada, no una estimación del borde.

El forward resuelve `div(mu grad U) + rho omega^2 U = -F` en un medio escalar de corte: fondo 12 kPa y unión de dos círculos de 24 kPa. Tiene una fuente por adquisición y es independiente del estimador. No simula OCT ni elastodinámica vectorial completa. El coeficiente material es conocido; cerca de interfaces y ondas dispersadas no constituye una velocidad de fase local exacta. Por eso los mapas de módulo se identifican como **Young aparente**.

Los parámetros se fijaron antes de evaluar el forward: frecuencia 1800 Hz, ventana solicitada 1,2 mm, coherencia mínima 0,65, amplitud relativa 0,05, soporte mínimo 0,75 y RMS circular máximo 0,30 rad. La ventana real tiene 17 muestras, con span de 1,142857 mm. La fusión requiere al menos cuatro de ocho adquisiciones y acuerdo de lentitud a ±20 % del ancla mediana, con pesos de calidad limitados. Una máscara de centros conserva todas las muestras de ajuste y asegura que todo extremo de ventana quede al menos a dos longitudes de onda del soporte de su fuente. No se usa verdad material para seleccionar píxeles de la estimación.

| Resultado principal | PG robusto | Direccional robusto |
|---|---:|---:|
| Cobertura del ROI | 100 % | 100 % |
| Error mediano absoluto relativo de velocidad | 0,669 % | 0,403 % |
| Discrepancia mediana de Young en núcleo grande, 1281 píxeles | 1,743 % | 1,970 % |
| Discrepancia mediana de Young en núcleo pequeño, 107 píxeles | 3,352 % | 13,653 % |

PG conserva mejor la inclusión pequeña aunque el sector direccional obtiene menor error global, dominado por el fondo. PG se eligió para las imágenes principales antes de inspeccionar los resultados porque un sector estrecho puede recortar componentes curvadas y dispersadas. Se conservan todas las alternativas y sus métricas fuera de la galería.

Las adquisiciones PG individuales cubren entre 76,66 % y 88,59 % del ROI. Comparando la fusión con **cada adquisición sobre exactamente su soporte común**, el error mediano de velocidad disminuye entre 24,1 % y 49,4 %. Esto separa precisión de aumento de cobertura. La mediana simple de lentitud obtiene un error global menor, 0,464 %, que la fusión ponderada, 0,669 %; esta prueba no demuestra superioridad universal de la ponderación.

La autocorrelación secuencial promedia `U_j(r) conj(U_j(r+lag))` calculados dentro de cada adquisición; no utiliza productos entre campos. Con ventana solicitada 2,4 mm alcanza cobertura del 95,32 % y error global del 0,940 %. Quedan 245 píxeles de núcleo puro en la inclusión grande y **ninguno** en la pequeña. Esta ausencia es consecuencia geométrica de la apertura y no autoriza afirmar que AIA resuelve esa inclusión. Ocho fuentes finitas tampoco demuestran un campo difuso isotrópico.

La segunda realización usa los mismos campos forward con otro ruido temporal independiente de 25 dB. Conservando todos los parámetros, PG mantiene cobertura del 100 %, error global de velocidad del 0,66955 % y discrepancias de Young del 1,7544 % / 3,3539 % en ambos núcleos. El cambio mediano de velocidad frente al primer ruido es del 0,00756 %. Se comprueba estabilidad a ese ruido, no generalización a otro medio.

Dos controles destructivos conservan la amplitud y reemplazan la relación espacial de fase por fases independientes, o permutan los tiempos independientemente por posición. La fusión PG y direccional acepta **0/28561 píxeles** en ambos controles. Son dos realizaciones observadas, sin garantía universal de rechazo de artefactos.

Un forward independiente de 0 grados con paso de 62,5 µm se compara al de 71,43 µm, eliminando solamente el ruido temporal exportado. En el soporte común, la diferencia mediana de velocidad es del 0,175 % para PG y del 0,164 % para el sector; percentiles 95 del 0,505 % / 0,302 %. La interpolación se utiliza únicamente en esta comparación numérica, nunca para mapas. Las aperturas nativas difieren ligeramente, 1,125 mm / 1,142857 mm; es una comprobación de un caso, no una demostración completa de convergencia de malla.

El control adicional de ambigüedad rechaza un ancla mediana sin ninguna medida retenida a la mitad de la tolerancia. Cuatro campos de 2 m/s y cuatro de 3 m/s no fabrican 2,4 m/s. El guard no cambia ningún píxel de los cuatro mapas fusionados de estas dos realizaciones de ruido; cada punto válido tiene al menos cuatro medidas próximas al ancla en PG y cinco en direccional. Este control conservador no demuestra un único modo físico.

Los CSV `fish_estimator_metrics`, `fish_fusion_common_support`, `fish_individual_fusion_common_support`, `fish_regional_gallery_metrics`, `fish_noise2_fusion_metrics`, `fish_null_controls`, `fish_grid_estimator_metrics`, `fish_grid_common_support` y `fish_ambiguity_guard_check` contienen los números sin redondear. Los scripts y MAT reproducibles permanecen en esta carpeta; la galería contiene sólo PNG.
