# OCT / OCE GUI

La aplicación mantenida está en **PYTHON_GUI_DG4162**: adquisición OCT/OCE con
hardware NI, cámara USB (ROI, foto/video) y control del generador RIGOL DG4162,
incluidas las series programadas desde Excel.

## Ejecutar

- `run_gui_dg4162.bat`: GUI de adquisición. El setup de la cámara (ROI de
  15 × 15 mm e inversión X/Y) se abre desde ⚙ *Cámara USB*.
- `run_alignment_live.bat`: monitor en vivo para alinear el espectrómetro contra
  una referencia (ver [PYTHON_GUI_DG4162/README.md](PYTHON_GUI_DG4162/README.md)).

Requisitos (Python 3.11, NI-VISA instalado):

```powershell
py -3.11 -m pip install -r PYTHON_GUI_DG4162\requirements-dg4162.txt
```

## Organización

```text
gui/
├── run_gui_dg4162.bat / run_alignment_live.bat
├── PYTHON_GUI_DG4162/      aplicación activa
│   ├── octoce/             GUI, motor, backends, DG4162, secuencias
│   ├── tests/              pruebas automáticas
│   ├── diagnostics/        comprobaciones independientes (incluye dg4162_check.py)
│   ├── matlab/             lector y reconstrucción OCT
│   └── docs/               arquitectura, hardware y formato binario
├── config/                 calibración de cámara y referencias de alineación
└── data/                   adquisiciones locales (no se suben a GitHub)
```

La GUI anterior (`PYTHON_GUI`) y sus lanzadores están en `legacy/gui/`.

## Documentación

- [GUI DG4162](PYTHON_GUI_DG4162/README_DG4162.md)
- [GUI y adquisición](PYTHON_GUI_DG4162/README.md)
- [Herramientas MATLAB](PYTHON_GUI_DG4162/matlab/README.md)
- [Diagnósticos](PYTHON_GUI_DG4162/diagnostics/README.md)

Pruebas desde `PYTHON_GUI_DG4162`:

```powershell
py -3.11 -m unittest discover -s tests
```
