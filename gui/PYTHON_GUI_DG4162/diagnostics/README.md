# Diagnósticos independientes

Ejecute estos módulos desde `PYTHON_GUI` para resolver correctamente los imports:

```powershell
python -m diagnostics.diagnose_mb_chunks --help
python -m diagnostics.diagnose_usb_video --help
```

| Módulo | Finalidad |
|---|---|
| diagnose_mb_chunks | Lotes finitos MB estacionarios y conteo de pulsos |
| diagnose_bm_crosshair | Pares X/Y y trigger OCE por B-scan lógico |
| diagnose_linear_bidirectional | Ida y retorno lineal horizontal/vertical |
| diagnose_warm_imaq | Reutilización de sesión NI-IMAQ |
| diagnose_alignment_50hz | Alineación MB continua |
| diagnose_camera_setup | Configuración de cámara lineal |
| diagnose_ni_usb_together | Convivencia NI y cámara USB |
| diagnose_usb_video | Codificación y decodificación MP4 USB |
| diagnose_pfi13_single_pulse | Pulso OCE individual |
| check_pfi13_scope | Tren breve para medir en osciloscopio |

Los módulos pueden activar hardware al ejecutar su función principal. Consulte
el encabezado de cada archivo y la guía `../docs/HARDWARE_SETUP.md` antes de
ejecutar una medición. Esta reorganización solo comprueba imports y software;
no ejecuta sus funciones de adquisición.
