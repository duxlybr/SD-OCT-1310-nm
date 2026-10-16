# Modelo físico y numérico del simulador OCE

Este documento reúne **todas las ecuaciones** que usa el simulador, con la
referencia exacta de cada una (las claves `[Clave]` están en
[`REFERENCIAS.md`](REFERENCIAS.md) y en `octsim/references.py`). Cada ecuación
aparece también citada en el código fuente, en el módulo indicado.

Convenciones: SI internamente (m, s, Pa, kg/m³); en la GUI se usan mm, kPa,
ms y MPa. `x`, `y` laterales; `z` es la profundidad física, positiva hacia
dentro de la muestra (dirección del haz OCT y del empuje ARF). El
desplazamiento `u_z > 0` se aleja de la sonda.

---

## 1. Materiales (`materials.py`)

Medio isótropo, lineal, viscoelástico de Kelvin-Voigt.

| Magnitud | Ecuación | Referencia |
|---|---|---|
| Módulo de corte | `mu = E / (2 (1 + nu))` | [Singh2022, Ec. (3)] |
| Primer parámetro de Lamé | `lambda = E nu / ((1 + nu)(1 - 2 nu))` | ley de Hooke isótropa [Singh2022, Ec. (1)] |
| Velocidad de corte | `c_s = sqrt(mu / rho)` | [Singh2022, Ec. (5)] |
| Velocidad longitudinal | `c_p = sqrt((lambda + 2 mu) / rho)` | [Singh2022, Ec. (10)] |
| Módulo complejo (Kelvin-Voigt) | `mu*(w) = mu + i w eta` | [Singh2022, Ec. (9)] |
| Velocidad de fase de corte | `c(w) = sqrt(2 (mu² + w² eta²) / (rho (mu + sqrt(mu² + w² eta²))))` | [Chen2004] |
| Atenuación ultrasónica | `alpha [Np/m] = alpha0 [dB/cm/MHz] · f [MHz] · 100 · ln(10)/20` | definición de dB/neper |

**Supuesto de compresibilidad.** Se simula con `nu ≥ 0.495` (no 0.4999)
porque el paso temporal explícito está limitado por `c_p`. Es el mínimo
recomendado por [Palmeri2017] ("Poisson's ratio must be greater than 0.495"
para al menos un orden de magnitud entre `c_p` y `c_s`). El efecto en la onda
de Rayleigh es despreciable: `c_R/c_s` = 0.9547 (ν = 0.495) frente a 0.9553
(ν = 0.4999), es decir, un sesgo de 0.06 % (raíz exacta de [Rayleigh1885],
verificada en `tests/test_physics.py`).

**Fluidos** (agua, humor acuoso): `mu = 0`, `lambda = rho c_f²`. En la
simulación, `c_f` se reduce a la mayor `c_p` de los sólidos. Para el modo A0
de la ecuación de Rayleigh-Lamb modificada [Han2017], usar `c_f = 10 c_s` en
lugar de 1480 m/s cambia la velocidad en menos de 0.1 % (prueba
`test_fluid_speed_reduction_is_negligible_for_a0`).

## 2. Geometría (`geometry.py`)

- Bloque `X × Y × Z` con capas conformes a la superficie superior: un punto
  pertenece a la capa `j` si su profundidad bajo la superficie local cae en el
  intervalo acumulado de espesores de esa capa.
- Domo (córnea): sagita `z_s(r) = R - sqrt(R² - r²)`. La huella es circular,
  de diámetro `min(X, Y)` (limbo). Se asume `R = 7.8 mm` (ojo teórico de Le
  Grand), valor editable.
- Inclusiones (esfera, elipsoide, cilindro en x/y/z, caja), cada una con
  propiedades biomecánicas y ópticas propias.
- Contornos laterales y de fondo: libre (vacío), rígido o empotrado
  (velocidad nula), o absorbente (C-PML, sección 4).

## 3. Excitación (`excitation.py`)

| Modelo | Ecuación | Referencia |
|---|---|---|
| Intensidad de onda plana | `I = p0² / (2 rho c)` | [Kinsler2000] |
| ARF con contacto (fuerza de volumen) | `F = 2 alpha I / c` | [Palmeri2017, Ec. (1)] |
| Coeficiente de reflexión en intensidad | `R = ((Z2 - Z1)/(Z2 + Z1))²` | [Kinsler2000] |
| ARF sin contacto (micro-tapping) | `P = (1 + R) I / c_aire ≈ 2 I / c_aire` | [Ambrozinski2016, Métodos] |
| Anillo de contactos | esfuerzo normal `sigma0 sin(w t + phi_i)` sobre N puntas | [Zvietcovich2019, Métodos] |
| Tracción como fuerza de volumen | `f = P / h` en la primera celda sólida | discretización de la tracción superficial |

- **Distribución espacial de la ARF con contacto:**
  `I(x, y, z) = I0 · S(x, y) · G(z) · exp(-2 ∫ alpha dz)`.
  - `S` es la forma lateral elegida: círculo/elipse gaussianos, rectángulo o
    línea súper-gaussianos, o anillo.
  - `G` es una gaussiana axial con FWHM igual a la profundidad de foco.
  - La atenuación de intensidad se acumula desde el foco.

  Todo esto son supuestos del simulador, explícitos en la GUI.
- **Modulación temporal:** el CH1 (954.9 kHz) lleva AM del 100 % con el CH2
  [repo:dg4162]. La ARF es ∝ intensidad ∝ `p²` [Palmeri2017, Ec. (1)], de modo
  que la fuerza sigue `m(t)²`, donde `m(t) ∈ [0, 1]` es la envolvente del CH2
  (pulso, gaussiana, semiseno, Hanning…). Esa envolvente se suaviza con el
  tiempo de subida del transductor (supuesto).
- **Régimen armónico con focos ARF:** `m_i(t) = (1 + sin(w t + phi_i))/2`.
  La fuerza contiene DC, `f` y `2f`, y se extraen los armónicos `f` y `2f`.
- **Valores de referencia de los ejemplos:**
  - contacto, ~3 MPa a 7.5 MHz sobre agar [Nguyen2014];
  - sin contacto, `I_SPPA ≈ 1 W/cm²` (pico de chirp de 7 kPa) con empuje de
    200 µs [Ambrozinski2016].

## 4. Solver elastodinámico FDTD 3D (`fdtd.py`)

**Ecuaciones de gobierno** (velocidad-esfuerzo):

```
rho dv_i/dt = d sigma_ij / dx_j + f_i                               [Virieux1986; Graves1996]
sigma_ij = lambda e_kk delta_ij + 2 mu e_ij + 2 eta de_ij/dt        [Singh2022, Ecs. (1) y (9)]
```

La viscosidad volumétrica es nula (supuesto), de modo que `mu* = mu + i w eta`
y `lambda* = lambda`.

**Discretización.** Malla escalonada de segundo orden en espacio y tiempo
(leapfrog) [Virieux1986], extendida a 3D [Graves1996]. Las variables se ubican así:

- `sigma_ii` en `(i, j, k)`;
- `v_x` en `(i+½, j, k)`, `v_y` en `(i, j+½, k)` y `v_z` en `(i, j, k+½)`;
- `sigma_xy` en `(i+½, j+½, k)`, `sigma_xz` en `(i+½, j, k+½)` y `sigma_yz` en `(i, j+½, k+½)`.

La parte elástica del esfuerzo se integra en el tiempo, y la viscosa
`2 eta D` se suma con la tasa de deformación actual `D`.

**Medios heterogéneos** [Graves1996; Moczo2002]:

- la densidad se promedia aritméticamente en los nodos de velocidad;
- `mu` y `eta` se promedian armónicamente en los nodos de corte (cero si
  algún vecino es cero).

Así se obtienen una superficie libre por formalismo de vacío y el
deslizamiento en interfaces sólido-fluido.

**Bordes absorbentes** con C-PML [Komatitsch2007; Roden2000]:

```
d/dx -> d/dx / kappa + psi,   psi^n = b psi^(n-1) + a (d/dx)^n
b = exp(-(d/kappa + alpha) dt),   a = d (b - 1) / (kappa (d + kappa alpha))
d(x) = d0 (x/L)^N,   d0 = -(N + 1) c_p ln(R) / (2 L),   alpha(x) = alpha_max (1 - x/L)
```

Se usa `N = 2`, `kappa = 1` y `alpha_max = pi f_dominante`.

**Estabilidad (derivación propia).** Sea un modo de Fourier en la malla
escalonada, con `s² = (4/h²) sin²(k h / 2) ≤ 12/h²` en 3D. El esquema leapfrog
con amortiguamiento viscoso evaluado con medio paso de retraso da la ecuación
característica

```
r² - (2 - a - b) r + (1 - b) = 0,   a = M s² dt² / rho,   b = eta_M s² dt / rho
```

Sus raíces cumplen `|r| ≤ 1` si `b ≤ 2` y `a + 2b ≤ 4`. Con `s²_max = 12/h²` se obtiene

```
M dt² + 2 eta_M dt ≤ rho h² / 3,   M = lambda + 2 mu,   eta_M = 2 eta
```

Con `eta = 0` se reduce al criterio clásico `c_p dt sqrt(3) / h ≤ 1`
[Graves1996]. El simulador usa el 85 % de ese límite.

**Tamaño de celda** (la restricción más severa):

- 10 puntos por longitud de onda de corte a `f_max`, donde `f_max` es la
  frecuencia en que el espectro de la fuente cae −20 dB;
- 10 muestras por FWHM de la distribución de fuerza [Palmeri2017, "Mesh
  resolution"];
- 4 celdas por capa.

**Régimen armónico.** Se simula hasta el estado estacionario y se demodula
la velocidad a `h f0` sobre un número entero de periodos:
`V_h = (2/W) Σ v(t) e^{-i h w0 t}`, y luego `U_h = V_h / (i h w0)`
[Oppenheim2010]. La convergencia se declara cuando el cambio relativo de `V_1`
entre ventanas sucesivas es menor que la tolerancia.

**Implementación.**

- **GPU:** kernels CUDA propios (CuPy `RawKernel`).
- **CPU:** implementación NumPy de referencia, con la misma aritmética.

Las dos coinciden hasta ~3·10⁻⁷ (redondeo float32): prueba
`test_gpu_kernels_match_numpy_reference`. El rendimiento es de ~1.1·10⁹
actualizaciones de celda por segundo en una RTX 5060 Ti.

## 5. Adquisición OCT simulada (`acquisition.py`)

Replica la semántica del planificador de la GUI de adquisición [repo:octoce].
La equivalencia se verifica contra `octoce` en las pruebas.

- **Modos:** `MB` (B→A→M, un disparo PFI13 por posición) y `BM` (B→M→A, un
  disparo por barrido; en crosshair solo en X).
- **Patrones:** raster, crosshair, meridianos (`theta = pi b / B`) y lineal
  (ida y vuelta). Las posiciones son idénticas a `ScanPlanner._line`.
- **Período de línea:** cuantizado a 0.1 µs del CC1 de la cámara.
- **Período uniforme de segmento** (`optimized_scan_period_ticks`):
  `ticks = max(sync + activas + hold, activas + ceil(0.05 activas), ceil(retardo_OCE f / 0.9))`.
- **Temporización:** primera A-line activa en `sync / f_línea`; PFI13 en
  `+ BFramesDelay`; excitación del DG4162 `ch2_delay` después [repo:dg4162].
- **Superposición lineal (transitorio):** el campo en cada A-line es la suma
  de las respuestas a los disparos previos dentro de la duración simulada. La
  respuesta se desvanece con un coseno en sus últimos 0.5 ms y se avisa si la
  vibración residual no se extinguió.
- **Régimen armónico:** `u(t) = Re Σ U_h e^{i h w t}` con el tiempo absoluto
  de cada A-line (generador libre en fase con el reloj).

## 6. Señal OCT (`oct_signal.py`)

Se usan los parámetros medidos del SD-OCT 1310 nm [repo:LATEST]:
- λ0 = 1317.97 nm;
- PSF axial de 9.65 µm y lateral de 11.04 µm;
- 5.931 µm/muestra;
- 79.6 dB de sensibilidad y −3.32 dB/mm de roll-off;
- 0.636 mrad de estabilidad de fase;
- 50 kHz de frecuencia de línea.

| Elemento | Ecuación | Referencia |
|---|---|---|
| A-scan | `A(d) = Σ a_s h(d - d_s) e^{i 2 k0 d_s} + ruido` | [IzattChoma2008] |
| Camino óptico | `OPL(z) = gap + z_s + ∫ n dz` | [IzattChoma2008] |
| Speckle | `a_s` gaussianos complejos circulares | [Schmitt1999] |
| Atenuación | potencia ∝ `exp(-2 mu z)` | [Faber2004] |
| Reflexión especular | `R = ((n1 - n2)/(n1 + n2))²` | [BornWolf1999] |
| Divergencia del haz | `theta0 = lambda0 / (pi W0)` | [SalehTeich2007] |
| Ruido de fase | `sigma_phi ~ 1/sqrt(SNR)` más 0.636 mrad común | [Choma2005; Singh2022, Ec. (17)] |
| Movimiento → camino | `dOPL(z) = n(z) u(z) - Σ_interfaces (n_debajo - n_encima) u(z_j)` | derivación de camino óptico; artefacto de [Song2013] |
| Fase | `phi = 4 pi dOPL / lambda0` | consistente con [Nguyen2014, Ec. (1)] |

- **Envolvente desplazada a primer orden:** `A0(d - dOPL) ≈ A0 - dOPL A0'`.
  El simulador avisa si `|dOPL|` supera ¼ de la resolución axial.
- **Reflexiones especulares:** se desplazan con el `dOPL` de su propia
  interfaz.
- **Representación de las A-scans:** son A-scans en banda base, sin la rampa
  de fase axial `(-1)^m` que introduce una FFT sin centrar. El término axial
  del estimador de Loupas mide solo la rotación de fase del speckle.

## 7. Procesamiento (`processing.py`)

| Paso | Ecuación | Referencia |
|---|---|---|
| Incremento de fase | Loupas 2D, portado línea a línea | [Loupas1995]; [repo:Loupas] |
| Fase → desplazamiento | `du = -dphi lambda0 / (4 pi n)` | [Nguyen2014, Ec. (1)] |
| Corrección de superficie | `du(z) = (dOPL + (n - 1) dOPL_sup) / n`; `du_sup = dOPL_sup` | [Song2013] |
| Filtro temporal | FIR pasabanda (Hamming), `filtfilt` | [Oppenheim2010] |
| Filtro espacial de velocidades | anillo en k con bordes gaussianos, 0.2–10 m/s | [Zvietcovich2019, Métodos] |
| Fasor armónico | `P = (2/M) Σ u(t_m) e^{-i w t_m}` con tiempos reales | [Zvietcovich2019, Ec. (7)] |
| En-face | Delaunay lineal o Clough-Tocher cúbica sobre una malla cartesiana | interpolación estándar |

La fase de superficie se toma con la ventana de Loupas centrada en la
reflexión más brillante bajo el borde detectado, para no mezclarla con
speckle interno de menor SNR.

## 8. Estimadores de velocidad (`speed.py`)

| Método | Ecuación | Referencia |
|---|---|---|
| Gradiente de fase | plano `phi = p00 + p10 x + p01 z` por ventana; `c = 2 pi f / sqrt(p10² + p01²)`; rechazo si el IC 95 % supera el 15 % | [repo:PhaseDeriv]; [Zvietcovich2017] |
| Tiempo de vuelo | `|grad T| = 1/c` (eikonal), plano local de `T` | [McLaughlin2006]; [WangLarin2014] |
| Número de onda local | filtros log-normales; `rho = sqrt(rho_i rho_{i+1}) (q_{i+1}/q_i)^{B²/8}`; `c = f/rho` | [Knutsson1994]; [Manduca2001] |
| Dispersión k-f | `U(k, w) = FFT2{u(x, t)}`; `c = w / k_pico` con seguimiento de cresta | [Singh2022, Ecs. (19)-(20)]; [Bernal2011] |
| Reverberante ⊥ | `B/B0 = (3/2)[j0(kD) - j1(kD)/(kD)]` | [Zvietcovich2019, Ec. (2)] |
| Reverberante ∥ | `B/B0 = 3 j1(kD)/(kD)` | [Zvietcovich2019, Ec. (3)] |
| Onda superficial 2D | `B/B0 = J0(kD)` | [Aki1957] |
| Curvatura (rápido) | `k² = C (1 - r) / (D² - r D1²)`, C = 5/10/4 | [Hoyt2008]; [repo:Reverb] |
| Solo fase | `|P| = 1` | [Ormachea2018] |
| Módulo de Young | `mu = rho c_s²`, `E ≈ 3 mu`, `c_s = c_R / 0.955` | [Singh2022, Ecs. (4), (5) y (12)] |

**Detalles de implementación:**

- **LFE:** la fórmula del cociente sale directamente de la definición del
  filtro log-normal. Con `B = 2√2` octavas [Knutsson1994] el cociente es lineal.
- **Autocorrelación:** por Wiener-Khinchin con relleno `2N-1`, dividida por el
  número de muestras solapadas (`correc` de [repo:Reverb]), y **sin restar la
  media**. Con ventanas del orden de λ, restar la media sesga `c` en −20 %
  (verificado con campos Monte Carlo).
- **Dispersión k-f:** la cresta se sigue desde la frecuencia más baja con
  energía significativa, con un salto máximo en k entre frecuencias vecinas.
  Es la idea de `maximum_wavenumber_jump_per_m` de OCE_workflow.
- **Placas (Lamb):** el valor medido se compara con la raíz más cercana de la
  mRLFE.

## 9. Teoría para validar (`theory.py`)

- **Rayleigh viscoelástico:** ecuación secular de [Rayleigh1885] con módulos
  complejos, por correspondencia [Christensen1982], resuelta con Newton
  complejo. Se usa `c = 1 / Re(1/c_R*)`.
- **Lamb A0 y demás modos de una placa con fluido debajo:** matriz 5×5 de la
  mRLFE [Han2017], portada de [repo:mRLFE] con `d` = semiespesor. Las raíces
  son los mínimos de `1/cond(M)`. La placa libre es el caso `rho_f = 0`
  [Lamb1917].
- **Límite de placa delgada (Kirchhoff):** `c = sqrt(w) (D/(rho h))^(1/4)`,
  `D = E h³ / (12 (1 - nu²))` [Viktorov1967].
- **Aproximaciones de referencia:**
  - `c_R ≈ 0.955 c_s` [Singh2022, Ec. (12)];
  - Scholte `≈ 0.846 c_s` [Singh2022, Ec. (13)];
  - `c_R ≈ c_s (0.87 + 1.12 nu)/(1 + nu)` [Viktorov1967].

## 10. Limitaciones conocidas

- **Modelo lineal (pequeñas deformaciones).** La GUI avisa del riesgo de
  envolvimiento de fase cuando `|du|` por A-line supera la mitad de
  `lambda0/(4n)`.
- **Ondas P más lentas que en tejido** (`nu = 0.495`). En medios muy viscosos
  pueden dominar lejos de la fuente, donde la onda de corte ya se atenuó. El
  filtro espacial de velocidades las elimina, como en el procesamiento real.
- **Campo reverberante sobre capas delgadas.** En una capa de espesor ~λ/2 (la
  gelatina 3 % de 0.3 mm a 2 kHz) la autocorrelación con ventana de 0.8 mm
  mezcla ambas capas y el contraste en profundidad se atenúa (demo 5).
- **Galvanómetros ideales y disparo sin jitter.** El jitter es opcional en la
  pestaña OCT.
- **Sin efecto fotoelástico:** el índice de refracción no cambia con la
  deformación.
- **Domo en escalera:** su superficie se aproxima con la celda elegida.
