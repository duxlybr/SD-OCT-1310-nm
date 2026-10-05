# Mapas FDTD de velocidad y Young

Metodos de galeria por familia: Lamb A0 = directional_phase; Rayleigh = phase_gradient; ventana comun 1.2 mm. Se conservan las 30 comparaciones de phase_gradient/directional_phase y ventanas 0.9/1.2/1.5 mm fuera de la galeria. La eleccion es exploratoria a partir de los primeros cuatro casos y se mantiene para homogeneo/inclusion de cada familia; no constituye validacion independiente held-out ni optimalidad general. El sector puede suprimir componentes secundarios de placa y tambien recortar ondas de superficie curvadas/dispersadas. No se ajustaron ventanas, umbrales ni mascaras con ground truth de E.

El quinto forward Rayleigh con inclusion blanda de 6 kPa se genero despues de fijar PG para la familia Rayleigh. Se aplican el mismo metodo, ventana, umbrales y gates, independientemente del resultado: es una comprobacion adicional, no una validacion estadistica completa.

Publicacion automatica de galeria requiere residual mediano E <= 10 % en el caso homogeneo correspondiente con esa configuracion fija. Los casos que no pasan se renderizan solamente en diagnostic_maps; su inclusion correspondiente tampoco se publica. Un residual homogeneo de 10-20 % requiere revision adicional; > 20 % descarta el candidato para esta galeria.

Ademas, la inclusion requiere discrepancia mediana de E <= 20 % en ventanas enteramente dentro de su nucleo. Este es un criterio observacional fijado para seleccionar candidatos de esta galeria, no un umbral universal de exactitud del algoritmo o del modelo.

Cada extremo de cada ventana de ajuste esta a al menos dos longitudes de onda de fondo del borde X mas cercano de la fuente lineal; se excluyen bordes antes de filtrar. El campo lejano se expresa en longitudes de onda de fondo, sin afirmar que desaparece el campo dispersado por la inclusion.

En FDTD heterogeneo, E material es conocido pero no existe una velocidad local unica exacta impuesta a cada pixel. La inversion local produce Young aparente; los residuales frente a E constitutivo son una discrepancia diagnostica, no una prueba de ground truth de velocidad.

| Caso | Metodo | Ventana mm | Cobertura % | E fondo kPa | E inclusion kPa | Residual fondo % | Residual inclusion % | Min extremo/lambda |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| lamb_a0_homogeneous_12kPa | phase_gradient | 0.9 | 100.0 | 13.45 | NaN | 32.5 | NaN | 2.05 |
| lamb_a0_homogeneous_12kPa | directional_phase | 0.9 | 100.0 | 11.76 | NaN | 10.5 | NaN | 2.05 |
| lamb_a0_homogeneous_12kPa | phase_gradient | 1.2 | 100.0 | 13.18 | NaN | 23.9 | NaN | 2.05 |
| lamb_a0_homogeneous_12kPa | directional_phase | 1.2 | 100.0 | 11.55 | NaN | 9.1 | NaN | 2.05 |
| lamb_a0_homogeneous_12kPa | phase_gradient | 1.5 | 92.3 | 13.22 | NaN | 22.0 | NaN | 2.05 |
| lamb_a0_homogeneous_12kPa | directional_phase | 1.5 | 100.0 | 11.49 | NaN | 8.4 | NaN | 2.05 |
| lamb_a0_inclusion_24kPa | phase_gradient | 0.9 | 99.6 | 13.48 | 19.02 | 33.3 | 30.3 | 2.05 |
| lamb_a0_inclusion_24kPa | directional_phase | 0.9 | 100.0 | 13.10 | 16.55 | 13.3 | 31.0 | 2.05 |
| lamb_a0_inclusion_24kPa | phase_gradient | 1.2 | 90.1 | 14.38 | 18.73 | 29.3 | 29.0 | 2.05 |
| lamb_a0_inclusion_24kPa | directional_phase | 1.2 | 100.0 | 13.29 | 16.47 | 13.8 | 31.4 | 2.05 |
| lamb_a0_inclusion_24kPa | phase_gradient | 1.5 | 82.6 | 14.90 | 18.55 | 28.6 | 27.3 | 2.05 |
| lamb_a0_inclusion_24kPa | directional_phase | 1.5 | 100.0 | 13.36 | 16.43 | 13.8 | 31.6 | 2.05 |
| rayleigh_homogeneous_12kPa | phase_gradient | 0.9 | 100.0 | 11.46 | NaN | 4.8 | NaN | 2.01 |
| rayleigh_homogeneous_12kPa | directional_phase | 0.9 | 100.0 | 11.50 | NaN | 4.2 | NaN | 2.01 |
| rayleigh_homogeneous_12kPa | phase_gradient | 1.2 | 100.0 | 11.40 | NaN | 5.0 | NaN | 2.01 |
| rayleigh_homogeneous_12kPa | directional_phase | 1.2 | 100.0 | 11.56 | NaN | 3.6 | NaN | 2.01 |
| rayleigh_homogeneous_12kPa | phase_gradient | 1.5 | 100.0 | 11.34 | NaN | 5.5 | NaN | 2.01 |
| rayleigh_homogeneous_12kPa | directional_phase | 1.5 | 100.0 | 11.55 | NaN | 3.7 | NaN | 2.01 |
| rayleigh_inclusion_24kPa | phase_gradient | 0.9 | 100.0 | 11.80 | 18.75 | 9.3 | 21.9 | 2.01 |
| rayleigh_inclusion_24kPa | directional_phase | 0.9 | 100.0 | 12.96 | 15.36 | 11.2 | 36.0 | 2.01 |
| rayleigh_inclusion_24kPa | phase_gradient | 1.2 | 100.0 | 11.84 | 18.37 | 9.2 | 23.5 | 2.01 |
| rayleigh_inclusion_24kPa | directional_phase | 1.2 | 100.0 | 13.14 | 15.22 | 10.9 | 36.6 | 2.01 |
| rayleigh_inclusion_24kPa | phase_gradient | 1.5 | 100.0 | 11.82 | 17.48 | 8.8 | 27.2 | 2.01 |
| rayleigh_inclusion_24kPa | directional_phase | 1.5 | 100.0 | 13.30 | 15.15 | 11.0 | 36.9 | 2.01 |
| rayleigh_inclusion_6kPa | phase_gradient | 0.9 | 77.2 | 10.90 | 6.09 | 24.6 | 5.9 | 2.01 |
| rayleigh_inclusion_6kPa | directional_phase | 0.9 | 78.9 | 8.48 | 5.93 | 29.3 | 8.9 | 2.01 |
| rayleigh_inclusion_6kPa | phase_gradient | 1.2 | 50.2 | 9.90 | 6.16 | 24.8 | 3.9 | 2.01 |
| rayleigh_inclusion_6kPa | directional_phase | 1.2 | 77.2 | 8.26 | 5.97 | 31.2 | 8.7 | 2.01 |
| rayleigh_inclusion_6kPa | phase_gradient | 1.5 | 27.6 | 8.85 | 6.18 | 29.3 | 3.0 | 2.01 |
| rayleigh_inclusion_6kPa | directional_phase | 1.5 | 75.3 | 8.11 | 6.08 | 32.4 | 8.4 | 2.01 |
