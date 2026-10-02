# Herramientas MATLAB OCT/OCE

La carpeta activa reúne las herramientas de ambas versiones:

| Función | Uso |
|---|---|
| leer_octoce_bin | Lee y valida el archivo .bin, devolviendo espectros en orden temporal |
| reconstruir_raster_oct | Reconstruye raster BM/MB completo con parámetros FFT y profundidad |
| explorar_raster_oct | Visor interactivo de B-scans y en face de un volumen reconstruido |
| raster_enface_medicion | Reconstrucción en face mediante memoria mapeada y medición X/Y en mm |

```matlab
addpath('C:/Users/proyecto.pi1081/Desktop/OCT_GUI/PYTHON_GUI/matlab');
explorar_raster_oct();
% O reconstrucción en face con medición:
raster_enface_medicion();
```

Los selectores parten de `OCT_GUI/data`; navegue a `version_03`, `optimized` o
`acquisitions`. También puede pasar una ruta de archivo explícita. La profundidad
se expresa en bins FFT; no existe una escala axial calibrada en mm.

`explorar_raster_oct` y `reconstruir_raster_oct` se incorporaron desde la 03.
Conservan su algoritmo y límites originales: la reconstrucción completa carga
los espectros en RAM, usa `hann`/`prctile` según los componentes MATLAB disponibles,
y rechaza raster bidireccional. Para grandes archivos, `raster_enface_medicion`
evita cargar todo el payload; consulte [README_ENFACE.md](README_ENFACE.md).

La integración se verificó por dependencias y hashes del lector común. No se
ejecutó MATLAB durante esta reorganización.
