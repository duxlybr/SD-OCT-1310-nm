# Configuración local

El setup opcional guarda aquí `camera_roi.json`: índice de cámara, resolución,
escala px/mm, centro e inversión de ejes. La GUI USB lo carga al iniciar.
No se suministra una calibración ficticia: debe medirse con la cámara real.

Se calibra desde la GUI (`run_gui_dg4162.bat`): ⚙ *Cámara USB* →
*Setup de cámara · calibrar ROI…*; los cambios se guardan al cerrar el setup.

`alineacion_referencia.json` es la referencia espectral del monitor de
alineación (`run_alignment_live.bat`). Se genera desde MATLAB con
`Exportar_Referencia_Alineacion.m` (repositorio SD-OCT-1310-nm,
`characterization/Codes`) a partir de la mejor alineación, por defecto
`Penetration_3/15um.tdms`. Las referencias que se fijen desde el monitor se
guardan aquí con la fecha en el nombre; la predeterminada no se sobrescribe.

`alineacion_objetivos.json` contiene los objetivos del pipeline de alineación
(bandas de potencia de los brazos, profundidades del espejo, visibilidad,
cociente azul/rojo del contraste y la curva de contraste frente a profundidad
de Penetration_3). Puede editarse; si se borra se usan los valores por defecto.
