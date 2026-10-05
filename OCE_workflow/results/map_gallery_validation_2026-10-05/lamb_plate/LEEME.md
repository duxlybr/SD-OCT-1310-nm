# Placa física con inclusión: límite flexural Lamb A0

Este ensayo añade una propagación física con contraste constitutivo de
rigidez. No se prescribe una fase calculada a partir de una velocidad local.
Se resuelve globalmente, por diferencias centrales dispersas, el balance
de momentos de una placa Kirchhoff–Love de rigidez variable:

```
∂xx[D(wxx + ν wyy)] + 2 ∂xy[D(1−ν)wxy]
  + ∂yy[D(wyy + ν wxx)] − ρ h ω² w = F,
D(x,y) = E(x,y) h³ / [12(1−ν²)].
```

La discretización se deriva de la energía de curvatura:
`Bxx' D Bxx + Byy' D Byy + ν(Bxx' D Byy + Byy' D Bxx)
+ 2(1−ν)Bxy' D Bxy`. Cada `D` es una matriz diagonal espacial, dentro
del operador. Por ello una inclusión cambia la solución global, genera
reflexión, refracción e interferencia y modifica también el campo exterior.
No se sustituye el operador por una ecuación homogénea con `k(x,y)` pintado.

## Fundamento primario y alcance físico

[Lefebvre et al., Physical Review Letters 117, 074301 (2016)](https://link.aps.org/accepted/10.1103/PhysRevLett.117.074301),
ecuaciones 1–3, relacionan el movimiento fuera del plano con Kirchhoff–Love
y la dispersión A0 de baja frecuencia. Se usa esa aproximación flexural,
`D k⁴ = ρ h ω²`, coherente con la inversión `lamb_a0_thin` del core.
Este forward no es una solución elastodinámica tridimensional completa de
Rayleigh–Lamb.

[Lithospheric 3-D flexure modelling ... using variable elastic thickness,
Geophysical Journal International 196, 681–693 (2014)](https://academic.oup.com/gji/article/196/2/681/581691)
expone el tensor de momentos y su doble divergencia para rigidez espacial.
Aquí se emplea la misma forma de operador isotrópico, con contraste de E
y espesor constante; se agrega la inercia armónica de la placa.

Se asumen placa plana, caras libres, homogeneidad en el espesor, isotropía,
elasticidad lineal pura y ausencia de fluido, tensión y curvatura. No se
incluyen ruido OCT, calibración óptica ni un experimento real. Estos mapas
validan el estimador bajo este modelo específico; no validan Young
experimental ni cualquier régimen de Lamb.

## Parámetros fijados antes de estimar

- Fondo E=12 kPa; inclusión rígida E=24 kPa o blanda E=6 kPa.
- Densidad 1000 kg/m³, Poisson 0.495, espesor total 0.20 mm, frecuencia 60 Hz.
- Longitud de onda del fondo 4.9096 mm; `kh=0.256`. La inclusión rígida tiene
  `kh≈0.215` y la blanda `kh≈0.304`. Es un régimen flexural aproximado.
- Inclusión circular de radio 2 longitudes de onda del fondo, unos 9.82 mm.
- Dominio exterior ±12 λ en X y ±10 λ en Y. Fuente de presión lineal
  finita centrada en X=−8 λ; esponja cúbica compleja fuera de ±9 λ en X
  y ±7.5 λ en Y. El cierre exterior de diferencias no se interpreta como
  una frontera física de la región mostrada; la esponja lo separa.
- El signo de la esponja es `+i ρ h ω² loss` para `exp(iωt)` y representa
  amortiguamiento pasivo. No se afirma que sea una PML exacta.
- Antes de estimar, la huella geométrica admisible conserva X=−6...+7 λ
  e Y=±5.5 λ: al menos 2 λ de separación de fuente y esponja. Se conserva
  toda esa huella para el filtro espacial. Los mapas muestran ±4 λ,
  predeterminado por geometría y común a todos los casos.
- Se generan señales temporales reales desde el campo complejo resuelto,
  seis ciclos, 30 muestras por ciclo y ruido gaussiano temporal SNR 35 dB
  con semillas registradas. La amplitud lineal se normaliza a 100 nm y la
  presión se escala por el mismo factor.
- Método direccional 0° ±45°, ventana λ/2≈2.45 mm, coherencia mínima 0.65,
  soporte mínimo 0.90, amplitud relativa 0.04 y error circular máximo 0.22.
  No se optimizan contra la verdad ni se cambian para la inclusión blanda.
  No se suaviza ni se rellena el resultado.

## Controles y métricas

Se resuelven fondo homogéneo y ambas inclusiones a 18 y 24 puntos por λ
del fondo. Incluso la inclusión blanda tiene al menos 15 puntos por su
longitud de onda en la malla gruesa. Los residuos relativos algebraicos
están entre aproximadamente 4e−13 y 2e−12.

El control homogéneo a 24 puntos/λ da error absoluto mediano de velocidad
0.38 % y de Young 1.51 %. Este es un control de dispersión, no una
calibración aplicada después para corregir los mapas. El sesgo conocido
de diferencias centrales disminuye con el refinamiento.

Para la inclusión rígida en la malla fina, el núcleo da mediana de
0.34946 m/s y 23.77 kPa; errores absolutos medianos 0.55 % y 2.18 %.
El fondo separado de la interfaz da 0.29459 m/s y 12.00 kPa; errores
absolutos medianos 0.60 % y 2.41 %. En el mapa completo, incluidos los
bordes y el campo dispersado, esos errores son 0.73 % y 2.90 %.
La cobertura de este caso ideal es 100 %; no se extrapola a los datos
experimentales ruidosos.

Para la inclusión blanda, el núcleo fino da 0.24783 m/s y 6.012 kPa;
errores absolutos medianos 0.36 % y 1.46 %. En el mapa completo da
0.63 % y 2.51 %, con cobertura 99.995 %: dos píxeles rechazados permanecen
NaN. El refinamiento cambia la mediana aproximadamente 0.25 % y el campo
complejo 4.30 %. No se cambia ningún parámetro de rechazo o ventana.

Los CSV contienen todos los controles y la inclusión blanda. Las regiones
`inclusion_core` y `background_far` excluyen una ventana de distancia a la
interfaz **sólo para las métricas regionales**. No restringen la medición
ni ocultan esos píxeles en la figura. La referencia de velocidad es la
dispersión homogénea local derivada del material: cerca de interfaces,
un campo con varias ondas no tiene necesariamente esa velocidad local
única. La inversión `E∝c⁴` amplifica la desviación de velocidad.

El refinamiento 18→24 puntos/λ cambia la mediana de velocidad del mapa
rígido aproximadamente 0.24 %; la diferencia L2 del campo complejo es
3.24 % después de un único factor complejo global por normalización de
la fuerza. Ese factor no elimina gradientes o diferencias espaciales.
Dos mallas son un diagnóstico de resolución; no demuestran convergencia
asintótica completa. La escalera de la interfaz también cambia entre mallas.

## Archivos y reproducción

Ejecutar `render_physical_lamb_plate_gallery.m` en MATLAB R2025b desde
cualquier carpeta. Los MAT de forward existentes se reutilizan únicamente
si sus parámetros son idénticos. Los operadores físicos y las estimaciones
permanecen en esta carpeta; no se modifica producción ni el catálogo.
Para actualizar exclusivamente el dibujo desde los mapas ya guardados,
establecer `gallery_render_only=true` antes de ejecutar el script.

- `physical_plate_ppw*_contrast*.mat`: campo complejo, fuerza, rigidez,
  material, malla, esponja y residual.
- `physical_lamb_plate_maps.mat`: entradas temporales, máscaras, verdad,
  estimaciones originales, modelos de Young y procedencia.
- `physical_lamb_plate_metrics.csv` y `physical_lamb_plate_refinement.csv`:
  resultados cuantitativos de las seis soluciones.
- `*_error_diagnostic.png`: tres paneles con referencia, estimación y error.
  El panel de error usa escala común ±40 % y puede saturar en interfaces.
- En `../../Speed_Young_Maps` se guardan solamente los PNG de velocidad
  y Young, separados, con dos paneles: referencia y estimación. Las escalas
  comunes son 0.20–0.40 m/s y 4–28 kPa; el gris conserva píxeles rechazados.

Los hashes científicos y del script se guardan en `source_hashes.csv`.
