# Ablaciones del unwrap óptico y modal

Se ejecutaron 45 reconstrucciones con los mismos parámetros de la comparación
principal: Lamb A0 de 12 kPa, 0,6 mm y 1000 Hz con fase estática aleatoria
independiente por píxel (Exact XZ y True FDTD), y Luis3 B-scan 1 real. No se
ajustaron ventanas, umbrales ni intervalos para obtener más cobertura.

Las etapas se aislaron: al cambiar el unwrap óptico se mantuvo `sequential`
para el fasor modal; al cambiar el unwrap modal se mantuvo unwrap óptico
temporal `sequential`. Además, TIE se ejecutó con 4, 8 y 12 correcciones fijas,
tanto ópticas como modales, en los dos dominios. Cada presupuesto se ejecutó
completo, sin detenerse por convergencia.

## La fase óptica no admite automáticamente continuidad axial

Con unwrap óptico **temporal**, los tres métodos recuperaron la fase mecánica
del control Lamb hasta el ruido impuesto: RMSE temporal de 0,02989 rad en
Exact y 0,02990 rad en FDTD. Los tres tuvieron 770 píxeles admitidos de 840
del ROI (91,67 %) y resultados iguales a precisión numérica.

Al añadir profundidad, las curvas temporales cambiaron aunque algunos mapas
de velocidad conservaron un aspecto uniforme. Para Exact, con unwrap modal
fijo `sequential`:

| Unwrap óptico | Dominio | RMSE temporal de fase (rad) | Cobertura (%) | Error mediano absoluto de velocidad (%) |
| --- | --- | ---: | ---: | ---: |
| sequential | temporal | 0,02989 | 91,67 | 0,00810 |
| least_squares_dct | temporal | 0,02989 | 91,67 | 0,00810 |
| tie_dct, 8 correcciones | temporal | 0,02989 | 91,67 | 0,00810 |
| sequential | tiempo + profundidad | 2,03760 | 77,74 | 0,18948 |
| least_squares_dct | tiempo + profundidad | 0,84671 | 91,67 | 0,10087 |
| tie_dct, 8 correcciones | tiempo + profundidad | 1,04856 | 91,67 | 0,03889 |

La fase estática óptica pertenece a cada scatterer; el movimiento continuo
no hace continua esa fase entre profundidades. El mapa limpio no demuestra
que las trazas ópticas hayan sido recuperadas correctamente. Para OCT nativo
se recomienda comenzar con `raw_unwrap_domain="temporal"`; `temporal_depth`
queda como prior axial explícito que debe validarse.

En FDTD, los métodos temporales compartieron un error mediano de velocidad
de 5,241 % y una discrepancia de Young de 13,995 %. Recuperar bien la fase
óptica impuesta no elimina la discrepancia del campo FDTD respecto al modo
homogéneo de referencia. Sobre los mismos 650 píxeles del soporte común del
dominio tiempo-profundidad, los errores de velocidad fueron 8,308 % para
sequential, 4,767 % para LS y 5,002 % para TIE. Es una comparación sobre
soporte común, no una garantía de superioridad universal.

Cambiar sólo el unwrap modal sobre la misma fase óptica temporal produjo
mapas iguales en ambos controles Lamb. En este caso, la diferencia principal
se origina en la etapa óptica y en su dominio, no en el unwrap modal.

## Un número mayor de correcciones TIE no garantiza más exactitud

Con unwrap temporal, los controles Lamb fueron idénticos para 4/8/12
correcciones. Con tiempo-profundidad, el RMSE óptico de Exact fue
0,98750/1,04856/1,06848 rad: aumentar el presupuesto no mejoró ese error.
Los mapas cambiaron mucho menos que las trazas. En FDTD, respecto a 8
correcciones, el cambio mediano de velocidad en soporte común fue 0,473 %
para 4 y 0,091 % para 12; los percentiles 95 fueron 3,812 % y 1,135 %.
No se interpreta estabilidad de un mapa como convergencia a la verdad óptica.

## Luis3: soporte insuficiente e inestabilidad entre métodos

Se conservaron 38 687 vóxeles nativos de entrada. Frecuencia 1000 Hz, intervalo
2–4 ms, ventanas X=0,9 mm y profundidad=0,04 mm, coherencia mínima 0,2,
amplitud mínima 0,05, soporte 0,8 y error máximo 0,3 rad. Se mantuvo el máximo
OCT como borde **candidato**; no constituye validación anatómica.

Con unwrap óptico temporal, los tres métodos dieron **cero ventanas válidas**;
cambiar sólo el unwrap modal tampoco recuperó mediciones válidas. El motivo
registrado es que el modelo local no ajusta las ventanas soportadas. La figura
temporal adicional muestra esta ausencia como gris: no es un fallo de dibujo
ni una velocidad cero.

Con tiempo-profundidad y unwrap modal fijo sequential, LS admitió 27 píxeles
(0,0514 % del corte), con mediana de 4,010 m/s y Young aparente de 52,755 kPa;
TIE de 8 correcciones admitió 22 (0,0419 %), con 2,294 m/s y 17,261 kPa.
Sequential siguió sin píxeles válidos. No existe soporte común entre los tres
para comparar exactitud experimental, ni ground truth mecánico.

Al variar simultáneamente las correcciones ópticas y modales TIE en
tiempo-profundidad, se admitieron **9/22/8 píxeles** para 4/8/12. Sólo ocho
píxeles son comunes con el resultado de 8 correcciones. Respecto a éste, el
cambio mediano de velocidad fue 10,17 % con 4 y 2,61 % con 12; cambiaron
15 y 14 posiciones de la máscara. Estos parches no sustentan un mapa material
estable de Luis3. Los valores de Young conservan la hipótesis Rayleigh y se
presentan como aparentes.

## Archivos reproducibles

- `evaluate_unwrap_stage_ablations.m`: ejecución completa sin alterar producción.
- `unwrap_stage_ablation_metrics.csv`: los 45 resultados y presupuestos ejecutados.
- `unwrap_stage_ablation_common_support.csv`: comparación sobre píxeles comunes.
- `unwrap_tie_iteration_stability.csv`: cambios respecto al presupuesto de 8.
- `unwrap_stage_ablation_products.mat`: mapas, máscaras y opciones para inspección.
- `unwrap_stage_ablations.log`: registro de ejecución.

Ejecute desde MATLAB:

```matlab
run('results/unwrap_comparison_2026-10-05/evaluate_unwrap_stage_ablations.m');
```
