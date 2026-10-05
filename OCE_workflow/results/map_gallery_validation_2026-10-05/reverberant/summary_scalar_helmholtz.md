# Mapas reverberantes con inclusiones: validación escalar 2D

Se resolvió un problema directo heterogéneo de Helmholtz de corte antiplano:

`div(μ grad U) + ρ ω² U = -F`, con `μ = E/[2(1+ν)]`.

El campo complejo procede de la solución de esa PDE. La distribución local de velocidades no se utilizó para dibujar una fase artificial. El operador usa diferencias de flujo con medias armónicas de μ en las caras, que representan reflexión y transmisión en la inclusión. Las 24 fuentes gaussianas periféricas, con fases fijas, producen ondas que interfieren. La región interior es elástica y sin pérdidas; únicamente el borde externo tiene un término de masa imaginario absorbente y condición exterior de Dirichlet.

El problema escalar representa un desplazamiento de corte antiplano. No reproduce toda la elastodinámica 3D, Lamb, Rayleigh, el proceso OCT ni la fuerza experimental sin contacto. Young es condicional a esta hipótesis: `E = 2ρ(1+ν)c²`. Estos resultados no constituyen validación experimental.

## Parámetros y campo lejano

- Dominio de 24 × 24 mm; 241 × 241 nodos; paso de 0.1 mm.
- Densidad: 1000 kg/m³; ν = 0.495; frecuencia: 1800 Hz.
- Fondo: 12 kPa; inclusión de radio 2.2 mm: 24 kPa o 6 kPa. Un control adicional es homogéneo de 12 kPa.
- Fuentes: 24 centros en un anillo de radio 10 mm; anchura gaussiana σ = 0.16 mm; semilla 20261005. El absorbente comienza a 10.3 mm.
- Ruido blanco temporal: 25 dB respecto al RMS global de desplazamiento en la máscara previa al ajuste; 240 muestras, 40 muestras/ciclo.
- Estimador: AIA `scalar2d`, ventana cuadrada de 2.4 mm, lag máximo de 0.9 mm, intervalo de velocidad 0.8–4 m/s. Coherencia mínima 0.35, soporte mínimo 0.75 y error de ajuste máximo 0.35. No se modificaron E ni la ventana en función del resultado o del mapa verdadero.
- Suavizado: 0; no se rellenan huecos. Las imágenes conservan los mapas aceptados originales y muestran rechazo en gris.

La máscara previa al ajuste excluye el absorbente y cualquier punto situado a menos de dos longitudes de onda del fondo del soporte de 3σ de las fuentes. Las imágenes se limitan a `r ≤ 4.8 mm` y `max(|x|,|y|) ≤ 4.5 mm`. Para **cada ventana cuadrada completa** de este campo se comprobó su distancia al soporte de las fuentes y al absorbente:

- Longitud de onda del fondo: 1.11297 mm.
- Distancia mínima desde la ventana al soporte de 3σ de cualquier fuente: **3.08603 mm = 2.77279 λ**.
- Separación mínima entre la ventana completa y el absorbente: **4.7 mm**.
- Residual relativo del sistema lineal discreto: 1.15–1.66 × 10⁻¹³.

El residual verifica la solución del sistema discretizado; no demuestra convergencia al continuo. El paso implica aproximadamente 7.87 puntos/longitud de onda en la inclusión blanda, 11.13 en el fondo y 15.74 en la rígida, de modo que la dispersión numérica forma parte del error observado.

## Resultados

El error reportado es la mediana de `100*abs(estimado/verdadero - 1)` sobre píxeles aceptados de cada región. La cobertura utiliza todos los píxeles verdaderos de la región como denominador.

| Caso | Región | Cobertura (%) | Error velocidad (%) | Error Young (%) | Young mediano (kPa) |
|---|---|---:|---:|---:|---:|
| Homogéneo | Campo útil completo | 99.956 | 1.442 | 2.875 | 11.682 |
| Homogéneo | Región central de control | 100 | 0.993 | 1.996 | 11.920 |
| Homogéneo | Fondo de control | 99.953 | 1.400 | 2.784 | 11.694 |
| Inclusión rígida | Campo útil completo | 99.884 | 2.008 | 3.995 | 12.042 |
| Inclusión rígida | Núcleo de inclusión | 100 | 1.336 | 2.691 | 24.354 |
| Inclusión rígida | Fondo | 99.859 | 1.356 | 2.694 | 11.704 |
| Inclusión blanda | Campo útil completo | 99.942 | 2.763 | 5.475 | 11.015 |
| Inclusión blanda | Núcleo de inclusión | 100 | 2.094 | 4.144 | 5.751 |
| Inclusión blanda | Fondo | 99.906 | 1.558 | 3.093 | 11.645 |

Los mapas detectan las dos inclusiones y conservan el contraste. La ventana espacial mezcla materiales cerca de la interfaz y ensancha el borde. En la región de interfaz el error mediano de Young es 4.826% para la inclusión rígida y 8.335% para la blanda. El núcleo conservador incluye solo 81 píxeles: su radio es 0.503 mm, ya que se exige que toda la ventana cuadrada permanezca dentro de la inclusión. El fondo conservador incluye 2128 píxeles y el campo útil completo 6893. Las regiones del control homogéneo sirven únicamente para comparar zonas espaciales; no existe una interfaz material en ese caso.

No se seleccionaron semillas favorables ni se ocultaron rechazos. Las tres simulaciones usan la misma configuración de fuentes. Este ensayo prueba inclusiones en un caso escalar ideal con ruido moderado; quedan por estudiar atenuación viscoelástica, número y distribución de fuentes, anisotropía, convergencia de malla y ruido/decorrelación OCT.

La sensibilidad a dos semillas adicionales y a una malla de 0.075 mm está documentada en `summary_scalar_helmholtz_robustness.md`, con métricas separadas en `scalar_helmholtz_robustness_metrics.csv`. Esos ensayos conservan los materiales y parámetros del estimador y no modifican los mapas nominales de la galería.

## Archivos y reproducción

Todos los archivos de este ensayo están en esta carpeta, fuera de la galería:

- `generate_scalar_helmholtz_fields.py`: problema directo reproducible.
- `scalar_helmholtz_fields.mat`: campos y mapas verdaderos; también máscaras de evaluación.
- `forward_diagnostics.json`: residual, geometría y verificación del campo lejano.
- `estimate_scalar_helmholtz_maps.m`: estimación MATLAB con los parámetros fijos anteriores.
- `scalar_helmholtz_maps.mat`: mapas originales y máscaras aceptadas.
- `scalar_helmholtz_metrics.csv`: métricas separadas para núcleo, fondo, interfaz y campo útil.
- `render_scalar_helmholtz_maps.py`: renderizado Matplotlib con escala común, referencia y contorno verdadero.
- `rendered_gallery_files.json`: rutas absolutas de las tres imágenes finales.
- `reproducibility_manifest.json`: hashes de fuentes del ensayo y de las funciones MATLAB utilizadas.

Desde PowerShell, con Python que disponga de NumPy/SciPy/Matplotlib:

```powershell
python 'C:/Users/proyecto.pi1081/Desktop/SD-OCT-1310-nm/OCE_workflow/results/map_gallery_validation_2026-10-05/reverberant/generate_scalar_helmholtz_fields.py'
matlab.exe -singleCompThread -batch "addpath('C:/Users/proyecto.pi1081/Desktop/SD-OCT-1310-nm/OCE_workflow/results/map_gallery_validation_2026-10-05/reverberant'); estimate_scalar_helmholtz_maps;"
python 'C:/Users/proyecto.pi1081/Desktop/SD-OCT-1310-nm/OCE_workflow/results/map_gallery_validation_2026-10-05/reverberant/render_scalar_helmholtz_maps.py'
```

Las tres imágenes PNG se escriben exclusivamente en `OCE_workflow/results/Speed_Young_Maps` con prefijo `reverberant_scalar2d_`. No se modifica código de producción ni el simulador de Claude.
