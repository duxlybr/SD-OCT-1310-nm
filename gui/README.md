# OCT / OCE GUI

La aplicación mantenida está en **PYTHON_GUI** y procede de la versión optimizada
0.2.0. La versión 03 se conserva como archivo histórico recuperable; las nuevas
correcciones y funciones se realizan únicamente en la aplicación activa.

## Ejecutar

Abra uno de los lanzadores de esta carpeta:

- `run_gui_usb.bat`: GUI con cámara USB, ROI opcional e indicadores de patrones.
- `run_gui.bat`: GUI OCT/OCE estándar.
- `run_camera_roi_setup.bat`: calibración px/mm y ROI cuadrada de 15 × 15 mm.
- `run_alignment_live.bat`: monitor en vivo para alinear el espectrómetro contra
  una referencia (ver [PYTHON_GUI/README.md](PYTHON_GUI/README.md#alineación-del-espectrómetro-en-vivo)).

Desde PowerShell:

```powershell
cd C:\Users\proyecto.pi1081\Desktop\OCT_GUI\PYTHON_GUI
python run_camera_roi_setup.py  # Opcional; usar antes de abrir la GUI USB.
python run_gui_usb.py
```

La configuración se guarda en `config/camera_roi.json`. Las adquisiciones nuevas
se proponen en `data/acquisitions/`; puede elegir otra ruta desde la GUI.
Estas rutas son independientes del directorio desde el que se lanza Python.

## Organización

```text
OCT_GUI/
├── run_gui.bat / run_gui_usb.bat / run_camera_roi_setup.bat
├── PYTHON_GUI/                  aplicación activa
│   ├── octoce/                  GUI, motor, backends y configuración
│   ├── tests/                   pruebas automáticas
│   ├── diagnostics/             comprobaciones independientes
│   ├── matlab/                  lector y reconstrucción OCT
│   └── docs/                    arquitectura, hardware y formato binario
├── config/                      configuración local de cámara
├── data/
│   ├── acquisitions/            nuevas adquisiciones
│   ├── optimized/               datos originales de la optimizada
│   └── version_03/              datos originales de la 03
├── archive/
│   ├── 03_NEW_IMPLEMENTATION/   versión 03 congelada
│   └── exports/                 ZIP antiguo y recursos de referencia
├── 00_INSTRUCTIONS/             contexto histórico del proyecto
├── 01_LEGACY_READONLY/          referencias LabVIEW originales
├── 02_DOCUMENTATION/            documentación histórica y comparación
└── 04_NEW_IMPLEMENTATION/       diagnóstico LabVIEW independiente
```

El proyecto LabVIEW y sus referencias conservan su ubicación. Los datos existentes
se trasladaron sin cambiar sus nombres ni contenido. Los archivos históricos
pueden contener rutas antiguas como evidencia de su contexto original.

## Documentación y comprobaciones

- [GUI y adquisición](PYTHON_GUI/README.md).
- [USB, ROI e indicadores](PYTHON_GUI/README_USB.md).
- [Diferencias y decisión de consolidación](02_DOCUMENTATION/REORGANIZATION/VERSION_COMPARISON.md).
- [Verificación de archivos y pruebas](02_DOCUMENTATION/REORGANIZATION/VALIDATION.md).
- [Herramientas MATLAB](PYTHON_GUI/matlab/README.md).
- [Diagnósticos](PYTHON_GUI/diagnostics/README.md).
- [Archivo histórico](archive/README.md).

Pruebas de software desde `PYTHON_GUI`:

```powershell
python -m unittest discover -s tests
```

La ruta NI por lotes pasó pruebas físicas acotadas documentadas previamente.
La equivalencia de fase y el rendimiento en series largas siguen pendientes
de validación experimental; por eso la 03 permanece recuperable.
