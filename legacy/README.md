# legacy/ — archivos candidatos a eliminar

Esta carpeta guarda los archivos que el repositorio ya no usa, para revisarlos
antes de borrarlos. Cada elemento conserva su ruta original dentro de
`legacy/`, de modo que se puede restaurar con un solo `git mv`.

## Movido aquí (82 archivos, ~0,7 MB)

| Ruta original | Tamaño | Por qué no se usa |
|---|---|---|
| `gui/PYTHON_GUI/` | 0,7 MB (69) | GUI anterior. Su sustituta es `gui/PYTHON_GUI_DG4162`, que contiene el mismo código más el DG4162. |
| `gui/run_gui.bat`, `gui/run_gui_usb.bat`, `gui/run_camera_roi_setup.bat` | < 1 KB | Lanzadores que ya no se usan. |
| `gui/PYTHON_GUI_DG4162/run_gui*.py/.bat`, `run_camera_roi_setup.py/.bat`, `README_USB.md` | 8 KB (7) | Entradas antiguas dentro de la GUI nueva. El setup de cámara se abre desde la GUI (⚙ Cámara USB). |
| `gui/READMES/README_old.md`, `gui/characterization/`, `gui/imaging/` | < 1 KB | README antiguo y carpetas vacías. |

`gui/run_alignment_live.bat` ahora apunta a `PYTHON_GUI_DG4162`, que tiene el
mismo monitor de alineación (archivo idéntico).

## Candidatos que NO se movieron (requieren decisión)

| Ruta | Tamaño | Bloqueo |
|---|---|---|
| `OCE_workflow/third_party/MIMT/sources/`, `examples/`, `demo scripts/`, `template4ods/`, `contour_plots.pdf` | **~8,6 MB (34)**: casi todo el peso del repositorio | OCE no los usa: solo los usan los demos de MIMT y `im2ods`. Pero `tests/contract/test_interactive_acquisition_architecture.m` (`assert_mimt_tree`) exige exactamente 151 archivos MIMT. Moverlos obliga a cambiar ese recuento a 117, y las reglas de `OCE_workflow/AGENTS.md` piden autorización explícita para modificar un contrato de preservación. |
| `OCE_workflow/inherited/` | 1,4 MB | Las pruebas de OCE exigen que exista como árbol de referencia (`test_canonical_helper_ownership_contract`, `test_final_architecture_contract`). |

## Restaurar o eliminar

Para restaurar un elemento:

```bash
git mv "legacy/gui/PYTHON_GUI" "gui/PYTHON_GUI"
```

Para eliminarlos todos:

```bash
git rm -r legacy
```

## Almacenamiento en GitHub

Mover o borrar archivos **no reduce** el tamaño del repositorio en GitHub: el
historial conserva todas las versiones anteriores (hoy unos 9 MB empaquetados,
de los cuales ~7,5 MB son los recursos de MIMT). Para recuperar ese espacio hay
que borrar los archivos y además reescribir el historial con `git filter-repo`
y hacer *force push*. Es una operación irreversible para los clones existentes,
así que conviene decidirla aparte.
