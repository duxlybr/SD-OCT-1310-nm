# Simulador OCE · SD-OCT 1310 nm

Simulador con interfaz gráfica de una **adquisición OCE completa** con el
sistema SD-OCT 1310 nm de GIBIO-PUCP. Encadena cinco etapas:

1. **Propagación de ondas** elásticas en 3D (FDTD viscoelástico en GPU) en un
   medio con capas, inclusiones y superficie plana o curva.
2. **Excitación** por fuerza de radiación acústica, con o sin contacto, o por
   un anillo de contactos (campo reverberante). La presión se ingresa en MPa.
3. **Adquisición OCT**, con la temporización real de la GUI de adquisición
   `octoce`: modos MB/BM, patrones raster, crosshair, meridianos y lineal,
   puntos sync, BFramesDelay y retardo del DG4162.
4. **Señal OCT compleja**, con speckle, PSF, sensibilidad, roll-off y ruido de
   fase medidos.
5. **Procesamiento OCE:**
   - Loupas y corrección de superficie;
   - videos de propagación B-mode y en-face, con interpolación;
   - mapas de velocidad por cinco métodos;
   - validación automática contra la teoría.

Cada ecuación del código lleva su referencia bibliográfica exacta: ver
[`docs/MODELO_FISICO.md`](docs/MODELO_FISICO.md) y
[`docs/REFERENCIAS.md`](docs/REFERENCIAS.md). Los supuestos de cada
simulación se listan en la GUI (pestaña *Supuestos y referencias*) y en
`supuestos.md` dentro de la carpeta de resultados.

---

## Instalación y arranque (Windows)

1. Ejecute `setup_venv.bat`. Crea el entorno `.venv` con Python 3.14 e
   instala NumPy, SciPy, matplotlib, imageio-ffmpeg y, si hay GPU NVIDIA,
   CuPy (`cupy-cuda13x`).
2. Ejecute `run_simulator.bat` para abrir la GUI.

Desde la línea de comandos (sin GUI):

```bash
.venv/Scripts/python.exe -m octsim --list
```

```bash
.venv/Scripts/python.exe -m octsim --preset 1
```

```bash
.venv/Scripts/python.exe -m octsim --config mi_simulacion.json
```

Sin GPU el simulador funciona en CPU con NumPy, mucho más lento: use mallas
pequeñas.

## Uso de la GUI

| Pestaña (izquierda) | Contenido |
|---|---|
| **Medio** | Dimensiones X, Y, Z; superficie plana o domo; fondo y laterales (libre, rígido o empotrado, absorbente). Tabla de **capas** y tabla de **inclusiones** (esfera, elipsoide, cilindro, caja). Cada capa o inclusión tiene sus propiedades: E, ν, ρ, η (Kelvin-Voigt), n, retrodispersión, atenuación OCT y acústica. |
| **Excitación** | ARF con contacto, ARF sin contacto o anillo de contactos; régimen transitorio o armónico (reverberante). **Presión en MPa**. Área y geometría de excitación (círculo, elipse, rectángulo, línea, anillo, punto) con su posición y tamaño. Foco y profundidad de foco. Forma de onda, frecuencia, ciclos y retardo del CH2. Número, disposición y fases de las fuentes reverberantes. |
| **Adquisición OCT** | Plan de barrido como en `octoce` (A-lines, B-scans, M, sync, longitudes, BFramesDelay, frecuencia de línea), con la temporización resultante. Parámetros medidos del sistema OCT. |
| **Simulación** | Celda (auto), puntos por longitud de onda, f_max, C-PML, duración, registro y backend. *Estimar recursos* calcula malla, memoria y tiempo. |
| **Procesamiento** | Loupas, índice de procesamiento, corrección de superficie, filtros temporal y de velocidades, interpolación en-face, profundidades en-face extra, B-scans con video y estimadores de velocidad. |
| **Validación / Salida** | Modelo teórico, tolerancias, comprobaciones por región (JSON), carpeta y video. |

La pestaña **Medio** muestra en vivo la geometría, la excitación y el
patrón. La pestaña **Teoría** muestra las curvas de dispersión de cada
material. Tras *Simular* se habilitan:

- **Video B-mode** y **Video en-face** (con reproducción y selector de
  profundidad);
- **Mapas de velocidad** (en-face, B-mode y en-face a profundidad, con
  opción de E estimado);
- **Dispersión k-f**;
- **Validación**: tabla, y verdad del FDTD frente a OCT.

La casilla *Reutilizar campo FDTD* evita repetir la propagación cuando solo
cambian los parámetros de OCT o de procesamiento.

## Resultados

Cada simulación guarda sus resultados en `results/<nombre>/`, una carpeta por
simulación:

- **Configuración y textos:** `config.json`, `supuestos.md`,
  `referencias.md` y `resumen.json` (tiempos, malla, validación y advertencias).
- **Videos:** `video_bmode_B<n>.mp4`, `video_enface_superficie.mp4` y
  `video_enface_<z>mm.mp4`.
- **Figuras:** `geometria.png`, `teoria.png`, `estructural.png`,
  `instantaneas.png`, `velocidad_enface.png`, `velocidad_bmode.png`,
  `dispersion_kf.png`, `validacion.png` y `cadena_oct.png`.
- **Datos:** `datos.npz` (velocidades, fasores, mapas y k-f) y
  `campo_fdtd_cache.npz` (caché de la propagación).

`results/` está excluida de git, como el resto de los datos del repositorio.

## Ejemplos de demostración validados

Los valores provienen de la bibliografía; lo que no aparece en la fuente se
marca como SUPUESTO en el propio preset. Los resultados son de la última
corrida (RTX 5060 Ti) y se regeneran con `--preset N`:

| # | Ejemplo (fuentes de los valores), tiempo | Comprobación | Medido | Esperado | Error | Tol. |
|---|---|---|---|---|---|---|
| 1 | **Rayleigh, gelatina 5 % (lineal MB)** (gelatina 5 % [Zvietcovich2019]; ARF 3 MPa [Nguyen2014]), 87 s | Dispersión k-f vs teoría | 1.969 m/s | 1.944 m/s | +2.2 % | ±5 % |
|  |  | TOF B-mode cerca de la superficie | 1.949 m/s | 1.943 m/s | +0.3 % | ±10 % |
|  |  | Gradiente de fase B-mode (superficie) | 1.954 m/s | 1.943 m/s | +0.5 % | ±10 % |
|  |  | Cadena OCT vs verdad FDTD | r = 0.999 | r → 1, ganancia 1 | -2.4 % | ±15 % |
| 2 | **Lamb A0, placa sobre agua (sin contacto)** (placa capa A [Zvietcovich2019] sobre agua; AµT [Ambrozinski2016]; mRLFE [Han2017]), 46 s | Dispersión k-f vs teoría | 1.901 m/s | 2.021 m/s | +2.9 % | ±7 % |
|  |  | Cadena OCT vs verdad FDTD | r = 0.999 | r → 1, ganancia 1 | +0.5 % | ±15 % |
| 3 | **Reverberante 3D, gelatina 5 % homogénea** (gelatina 5 % [Zvietcovich2019]; 16 contactos aleatorios a 2 kHz), 25 s | Reverberante a 0.6 mm vs corte 5 % | 2.155 m/s | 2.051 m/s | +5.1 % | ±10 % |
|  |  | Cadena OCT vs verdad FDTD | r = 0.997 | r → 1, ganancia 1 | +0.4 % | ±15 % |
| 4 | **Bicapa + inclusión (raster, en-face)** (bicapa 3 %/5 % [Zvietcovich2019] + inclusión 10 % [Zvietcovich2017]; raster 40×40), 112 s | Dispersión k-f vs teoría | 2.041 m/s | 1.944 m/s | +6.1 % | ±12 % |
|  |  | Fondo en-face (TOF) vs Rayleigh 5 % | 1.823 m/s | 1.944 m/s | -6.2 % | ±15 % |
|  |  | Inclusión (TOF) vs Rayleigh gelatina 10 % | 3.129 m/s | 2.970 m/s | +5.4 % | ±20 % |
|  |  | Cadena OCT vs verdad FDTD | r = 1.000 | r → 1, ganancia 1 | -2.6 % | ±15 % |
| 5 | **Reverberante, anillo de 8 contactos (bicapa)** (anillo de 8 puntas a 2 kHz sobre bicapa [Zvietcovich2019] (indicativo)), 39 s | Reverberante a 0.6 mm vs corte 5 % (indicativo) | 1.761 m/s | 2.051 m/s | -14.1 % | ±20 % |
|  |  | Reverberante a 0.15 mm vs corte 3 % (indicativo) | 1.417 m/s | 1.242 m/s | +14.1 % | ±20 % |
|  |  | Cadena OCT vs verdad FDTD | r = 0.985 | r → 1, ganancia 1 | -1.9 % | ±15 % |
| 6 | **Reverberante, múltiples focos ARF + inclusión** (6 focos ARF AM 1.5 kHz + inclusión esférica), 68 s | Superficie (J0) vs Rayleigh 5 % | 1.958 m/s | 1.950 m/s | +0.4 % | ±12 % |
|  |  | Cadena OCT vs verdad FDTD | r = 0.992 | r → 1, ganancia 1 | -3.8 % | ±15 % |
| 7 | **Córnea curva de 4 capas (meridianos)** (córnea de 4 capas del FEM de [Zvietcovich2019], n = 1.376 [Singh2017]; meridianos), 72 s | Cadena OCT vs verdad FDTD | r = 0.991 | r → 1, ganancia 1 | -3.3 % | ±15 % |
| 8 | **Prueba rápida** (gelatina 5 %, raster 20×20), 38 s | Dispersión k-f vs teoría | 1.953 m/s | 1.945 m/s | +6.0 % | ±12 % |
|  |  | Cadena OCT vs verdad FDTD | r = 0.999 | r → 1, ganancia 1 | -2.1 % | ±15 % |

Todas las comprobaciones resultaron **APROBADAS** en la corrida del 2026-10-03. "Cadena OCT" compara los incrementos de desplazamiento superficial medidos con el OCT simulado (Loupas + corrección de [Song2013]) con la verdad del FDTD; el error mostrado es el de la ganancia. En las filas k-f, "Medido" y "Esperado" son medianas en la banda analizada y el error es la mediana del error punto a punto (en placas, frente a la raíz de la mRLFE más cercana, porque la superficie libre pasa del modo A0 al modo tipo Rayleigh por encima de ~1.8 kHz).

## Pruebas

```bash
.venv/Scripts/python.exe -m unittest discover -s tests -v
```

Las 21 pruebas cubren:

- **Teoría:** Rayleigh exacto, Kelvin-Voigt, límites de Lamb e insensibilidad
  a la velocidad del fluido.
- **FDTD:** equivalencia GPU/NumPy en tres combinaciones de contorno, y
  velocidad de fase de Rayleigh dentro del 2 %.
- **Adquisición:** **equivalencia exacta con `octoce`** en posiciones,
  período de segmento, hold y número de disparos.
- **Procesamiento:** Loupas y corrección de Song.
- **Cadena OCT:** recupera un movimiento conocido.
- **Estimadores:** onda plana, TOF y campo reverberante Monte Carlo.
- **Extremo a extremo:** una simulación completa pequeña.
- **GUI:** carga todos los presets.

## Estructura

```
simulator/
├── octsim/
│   ├── references.py    bibliografía (claves citadas en todo el código)
│   ├── materials.py     propiedades y velocidades (Kelvin-Voigt)
│   ├── geometry.py      bloque, capas, domo, inclusiones
│   ├── excitation.py    ARF con/sin contacto, anillo, formas CH2
│   ├── fdtd.py          solver 3D velocidad-esfuerzo, C-PML, kernels CUDA
│   ├── acquisition.py   plan MB/BM y temporización (equivalente a octoce)
│   ├── oct_signal.py    A-scans complejos, speckle, ruido, movimiento -> fase
│   ├── processing.py    Loupas, corrección de superficie, filtros, en-face
│   ├── speed.py         gradiente de fase, TOF, LFE, k-f, reverberante
│   ├── theory.py        Rayleigh, Lamb/mRLFE, corte Kelvin-Voigt
│   ├── validation.py    comparación con la teoría y con la verdad FDTD
│   ├── pipeline.py      flujo completo y caché
│   ├── export.py, figures.py, video.py
│   ├── presets.py       ejemplos de demostración
│   └── gui.py, cli.py
├── tests/               pruebas unittest
├── docs/                MODELO_FISICO.md, REFERENCIAS.md
├── setup_venv.bat, run_simulator.bat
└── requirements.txt, requirements-gpu.txt
```
