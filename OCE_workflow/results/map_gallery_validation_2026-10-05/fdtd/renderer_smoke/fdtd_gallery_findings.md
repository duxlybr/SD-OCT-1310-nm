# Mapas FDTD de velocidad y Young

Metodo fijo de galeria: directional_phase, ventana 1.2 mm. Se conservan comparaciones con phase_gradient y ventanas 0.9/1.2/1.5 mm fuera de la galeria. No se selecciona el mapa por su parecido con la inclusion.

Cada extremo de cada ventana de ajuste esta a al menos dos longitudes de onda de fondo de la fuente; se excluyen bordes antes de filtrar. El campo lejano se expresa en longitudes de onda de fondo, sin afirmar que desaparece el campo dispersado por la inclusion.

En FDTD heterogeneo, E material es conocido pero no existe una velocidad local unica exacta impuesta a cada pixel. La inversion local produce Young aparente; los residuales frente a E constitutivo son una discrepancia diagnostica, no una prueba de ground truth de velocidad.

| Caso | Metodo | Ventana mm | Cobertura % | E fondo kPa | E inclusion kPa | Residual fondo % | Residual inclusion % | Min extremo/lambda |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| renderer_smoke_analytic_only | phase_gradient | 0.9 | 100.0 | 12.00 | NaN | 0.0 | NaN | 2.04 |
| renderer_smoke_analytic_only | directional_phase | 0.9 | 100.0 | 12.12 | NaN | 3.3 | NaN | 2.04 |
| renderer_smoke_analytic_only | phase_gradient | 1.2 | 100.0 | 12.00 | NaN | 0.0 | NaN | 2.04 |
| renderer_smoke_analytic_only | directional_phase | 1.2 | 100.0 | 12.18 | NaN | 2.8 | NaN | 2.04 |
| renderer_smoke_analytic_only | phase_gradient | 1.5 | 100.0 | 12.00 | NaN | 0.0 | NaN | 2.04 |
| renderer_smoke_analytic_only | directional_phase | 1.5 | 100.0 | 12.14 | NaN | 2.7 | NaN | 2.04 |
