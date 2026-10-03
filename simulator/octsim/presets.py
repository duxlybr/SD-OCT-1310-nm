"""Ejemplos de demostración con parámetros tomados de la bibliografía.

Cada preset indica de dónde salen sus valores. Cuando un valor no está en la
fuente (p. ej. la viscosidad, que [Zvietcovich2019] no reporta en modelo
Kelvin-Voigt), se marca como SUPUESTO en el nombre del material o en la
descripción, y es editable en la GUI.

Conversión usada para pasar de velocidad de corte a módulo de Young:
mu = rho c_s^2 [Singh2022, Ec. (5)], E = 2 mu (1 + nu) [Singh2022, Ec. (3)].
"""
from __future__ import annotations

from typing import Callable

from .acquisition import AcquisitionConfig
from .config import SimulationConfig, ValidationSpec
from .excitation import ExcitationConfig
from .fdtd import FDTDSettings
from .geometry import Geometry, Inclusion, Layer
from .materials import Material
from .oct_signal import OCTSystem
from .processing import ProcessingConfig
from .speed import SpeedConfig

NU = 0.495                 # [Palmeri2017] mínimo recomendado
ETA_ASSUMED = 0.05         # Pa·s, SUPUESTO (las fuentes no reportan viscosidad Kelvin-Voigt)


def _E_from_cs(cs: float, rho: float = 1000.0, nu: float = NU) -> float:
    """E (kPa) desde c_s: mu = rho c_s^2 [Singh2022, Ec. (5)]; E = 2 mu (1+nu) [Singh2022, Ec. (3)]."""
    return 2 * rho * cs * cs * (1 + nu) / 1e3


def gelatin3() -> Material:
    """Gelatina 3 %: E = 3.97 kPa a 2 kHz, n ~ 1.35 [Zvietcovich2019, Métodos]."""
    return Material("Gelatina 3% [Zvietcovich2019]", E_kPa=3.97, nu=NU, rho=1000, eta_Pa_s=ETA_ASSUMED,
                    n=1.35, backscatter_db=-52, mu_oct_per_mm=1.0, color="#9ecae1")


def gelatin5() -> Material:
    """Gelatina 5 %: E = 12.36 kPa a 2 kHz (c_s = 2.03 m/s), n ~ 1.35 [Zvietcovich2019, Métodos]."""
    return Material("Gelatina 5% [Zvietcovich2019]", E_kPa=12.36, nu=NU, rho=1000, eta_Pa_s=ETA_ASSUMED,
                    n=1.35, backscatter_db=-50, mu_oct_per_mm=1.0, color="#4292c6")


def gelatin10() -> Material:
    """Gelatina 10 %: c_s = 3.11 m/s a 400 Hz [Zvietcovich2017] -> E = 28.9 kPa."""
    return Material("Gelatina 10% [Zvietcovich2017]", E_kPa=round(_E_from_cs(3.11), 2), nu=NU, rho=1000,
                    eta_Pa_s=ETA_ASSUMED, n=1.35, backscatter_db=-46, mu_oct_per_mm=1.0, color="#08519c")


def water(name: str = "Agua") -> Material:
    """Agua / humor acuoso: rho = 1000, c = 1480 m/s (se reduce en la simulación), n = 1.336
    (SUPUESTO estándar de índice del humor acuoso)."""
    return Material(name, E_kPa=0.0, nu=0.0, rho=1000, eta_Pa_s=0.0, n=1.336, backscatter_db=-90,
                    mu_oct_per_mm=0.1, alpha_db_cm_mhz=0.002, c_acoustic=1480, is_fluid=True, color="#deebf7")


def cornea_layers() -> list[Material]:
    """Modelo de 4 capas de córnea de [Zvietcovich2019, Métodos, "Numerical simulations"]:
    E_A..E_D = 18.75, 12, 5.07, 1.92 kPa, rho = 1000; n = 1.376 [Singh2017]."""
    vals = [("A", 18.75, "#a50f15"), ("B", 12.0, "#de2d26"), ("C", 5.07, "#fb6a4a"), ("D", 1.92, "#fcae91")]
    return [Material(f"Córnea capa {k} [Zvietcovich2019]", E_kPa=E, nu=NU, rho=1000, eta_Pa_s=ETA_ASSUMED,
                     n=1.376, backscatter_db=-55, mu_oct_per_mm=0.5, color=c) for k, E, c in vals]


# --------------------------------------------------------------------------------------
def rayleigh_gelatina() -> SimulationConfig:
    """Validación 1: onda de Rayleigh en un semiespacio de gelatina 5 %, ARF con contacto."""
    return SimulationConfig(
        name="validacion_rayleigh_gelatina5",
        description=("Semiespacio homogéneo de gelatina 5 % [Zvietcovich2019]. ARF con contacto "
                     "(portadora 954.9 kHz, 3 MPa como en [Nguyen2014]), pulso CH2 de 0.5 ms. Barrido MB "
                     "lineal de 10 mm. La dispersión k-f se compara con la onda de Rayleigh viscoelástica."),
        sources=["Zvietcovich2019", "Nguyen2014", "Palmeri2017", "Rayleigh1885"],
        geometry=Geometry(size_x_mm=14, size_y_mm=5, size_z_mm=6, layers=[Layer(gelatin5(), 0.0)],
                          bottom="absorbente", lateral="absorbente"),
        excitation=ExcitationConfig(mode="arf_contacto", regime="transitorio", pressure_MPa=3.0,
                                    shape="circulo", size_a_mm=0.4, center_x_mm=-4.5, focal_depth_mm=1.0,
                                    dof_mm=3.0, ch2_waveform="Pulso", ch2_freq_hz=1000, ch2_duty=0.5,
                                    ch2_delay_ms=2.0),
        acquisition=AcquisitionConfig(mode="MB", pattern="lineal", orientation="horizontal", alines=128,
                                      bscans=1, m_reps=400, sync_points=50, x_length_mm=10.0, y_length_mm=0.0,
                                      center_x_mm=0.5),
        fdtd=FDTDSettings(ppw=10, record_depth_mm=1.2),
        processing=ProcessingConfig(filter_low_hz=200, filter_high_hz=3000),
        speed=SpeedConfig(methods=("gradiente_fase", "tiempo_vuelo", "lfe", "kf"), window_mm=1.5),
        validation=ValidationSpec(model="rayleigh", tolerance_pct=5.0, checks=[
            {"nombre": "TOF B-mode cerca de la superficie", "plano": "bmode", "metodo": "tiempo_vuelo",
             "region": [-3.0, 5.0, 0.1, 0.5], "esperado": "teoria", "tol_pct": 10},
            {"nombre": "Gradiente de fase B-mode (superficie)", "plano": "bmode", "metodo": "gradiente_fase",
             "region": [-3.0, 5.0, 0.1, 0.5], "esperado": "teoria", "tol_pct": 10},
        ]),
    )


def lamb_placa_agua() -> SimulationConfig:
    """Validación 2: modo A0 de una placa sobre agua (mRLFE [Han2017]), ARF sin contacto."""
    plate = cornea_layers()[0]
    plate.name = "Placa tipo córnea, capa A [Zvietcovich2019]"
    return SimulationConfig(
        name="validacion_lamb_placa_agua",
        description=("Placa isótropa de 1.0 mm (E = 18.75 kPa, capa A del modelo de [Zvietcovich2019]) "
                     "sobre agua. Micro-tapping sin contacto con empuje de 200 us [Ambrozinski2016]: "
                     "p0 = 2.9 kPa en aire, que da I = p0^2/(2 rho c) = 1 W/cm^2, la I_SPPA reportada en "
                     "[Ambrozinski2016] (el pico de 7 kPa del chirp sobreestima la intensidad media). La "
                     "dispersión se compara con el modo A0 de la ecuación de Rayleigh-Lamb modificada "
                     "[Han2017]."),
        sources=["Zvietcovich2019", "Ambrozinski2016", "Han2017"],
        geometry=Geometry(size_x_mm=14, size_y_mm=4, size_z_mm=3.0,
                          layers=[Layer(plate, 1.0), Layer(water("Agua (humor acuoso)"), 0.0)],
                          bottom="absorbente", lateral="absorbente"),
        excitation=ExcitationConfig(mode="arf_sin_contacto", regime="transitorio", pressure_MPa=0.0029,
                                    shape="circulo", size_a_mm=0.5, center_x_mm=-4.5, ch2_waveform="Pulso",
                                    ch2_freq_hz=2500, ch2_duty=0.5, ch2_delay_ms=2.0, rise_time_us=40),
        acquisition=AcquisitionConfig(mode="MB", pattern="lineal", orientation="horizontal", alines=128,
                                      bscans=1, m_reps=400, sync_points=50, x_length_mm=10.0,
                                      y_length_mm=0.0, center_x_mm=0.5),
        oct=OCTSystem(depth_window_mm=1.4),
        fdtd=FDTDSettings(ppw=10, f_max_hz=4000, record_depth_mm=1.3),
        processing=ProcessingConfig(filter_low_hz=300, filter_high_hz=4000),
        speed=SpeedConfig(methods=("gradiente_fase", "tiempo_vuelo", "kf"), window_mm=1.5),
        validation=ValidationSpec(model="lamb_fluido", tolerance_pct=7.0),
    )


def bicapa_inclusion() -> SimulationConfig:
    """Demo con capas e inclusión: gelatina 3 % sobre 5 % con inclusión de gelatina 10 %."""
    incl = Inclusion(gelatin10(), shape="cilindro", center_mm=(1.2, 0.0, 1.3), size_mm=(0.75, 0.0, 1.0),
                     axis="z")
    return SimulationConfig(
        name="demo_bicapa_inclusion_raster",
        description=("Phantom bicapa de [Zvietcovich2019] (gelatina 3 %, 0.3 mm, sobre gelatina 5 %) con una "
                     "inclusión cilíndrica vertical de gelatina 10 % [Zvietcovich2017] (radio 0.75 mm). ARF "
                     "con contacto, adquisición MB raster 40 x 40 para video en-face, video B-mode y mapas "
                     "de velocidad. La geometría de la inclusión es un SUPUESTO de demostración."),
        sources=["Zvietcovich2019", "Zvietcovich2017", "Nguyen2014", "Palmeri2017"],
        geometry=Geometry(size_x_mm=8.5, size_y_mm=8.0, size_z_mm=4.0,
                          layers=[Layer(gelatin3(), 0.3), Layer(gelatin5(), 0.0)],
                          inclusions=[incl], bottom="absorbente", lateral="absorbente"),
        excitation=ExcitationConfig(mode="arf_contacto", regime="transitorio", pressure_MPa=3.0,
                                    shape="circulo", size_a_mm=0.4, center_x_mm=-2.0, focal_depth_mm=0.8,
                                    dof_mm=2.5, ch2_waveform="Pulso", ch2_freq_hz=1000, ch2_duty=0.5,
                                    ch2_delay_ms=1.0),
        acquisition=AcquisitionConfig(mode="MB", pattern="raster", alines=40, bscans=40, m_reps=300,
                                      sync_points=50, x_length_mm=5.0, y_length_mm=5.0, center_x_mm=0.5),
        fdtd=FDTDSettings(ppw=8, record_depth_mm=1.2),
        processing=ProcessingConfig(filter_low_hz=200, filter_high_hz=3000, enface_pixel_mm=0.05),
        speed=SpeedConfig(methods=("gradiente_fase", "tiempo_vuelo", "lfe", "kf"), window_mm=1.2),
        validation=ValidationSpec(model="rayleigh", layer=1, tolerance_pct=12.0, checks=[
            {"nombre": "Fondo en-face (TOF) vs Rayleigh 5 %", "plano": "enface", "metodo": "tiempo_vuelo",
             "region": "fondo", "esperado": "rayleigh:1", "tol_pct": 15},
            {"nombre": "Inclusión (TOF) vs Rayleigh gelatina 10 %", "plano": "enface", "metodo": "tiempo_vuelo",
             "region": "inclusion:0", "esperado": "rayleigh:2", "tol_pct": 20},
        ]),
    )


def reverberante_homogeneo() -> SimulationConfig:
    """Validación 3: estimador reverberante (Ec. 2 de [Zvietcovich2019]) en gelatina 5 % homogénea."""
    return SimulationConfig(
        name="validacion_reverberante_homogeneo",
        description=("Bloque finito (8 x 8 x 3 mm, bordes libres) de gelatina 5 % [Zvietcovich2019] excitado en "
                     "régimen armónico a 2 kHz por 16 contactos con posiciones y fases aleatorias para obtener un "
                     "campo difuso. La autocorrelación de cuadros en-face a 0.6 mm de profundidad se ajusta a la "
                     "Ec. (2) de [Zvietcovich2019] y se compara con c_s Kelvin-Voigt [Chen2004]. Las posiciones, "
                     "fases y la amplitud de contacto (10 Pa) son SUPUESTOS."),
        sources=["Zvietcovich2019", "Parker2017", "Chen2004"],
        geometry=Geometry(size_x_mm=8.0, size_y_mm=8.0, size_z_mm=3.0, layers=[Layer(gelatin5(), 0.0)],
                          bottom="libre", lateral="libre"),
        excitation=ExcitationConfig(mode="anillo_contactos", regime="armonico", pressure_MPa=1e-5,
                                    harmonic_hz=2000, n_sources=16, source_layout="aleatoria", ring_radius_mm=3.5,
                                    tip_radius_mm=0.25, random_phase=True),
        acquisition=AcquisitionConfig(mode="MB", pattern="raster", alines=40, bscans=40, m_reps=100,
                                      sync_points=50, x_length_mm=2.4, y_length_mm=2.4),
        fdtd=FDTDSettings(ppw=10, record_depth_mm=1.0, harmonic_min_periods=10, harmonic_max_periods=150),
        processing=ProcessingConfig(enface_pixel_mm=0.04, enface_depths_mm=(0.6,)),
        speed=SpeedConfig(methods=("lfe",), window_mm=0.8, reverb_model="3D"),
        validation=ValidationSpec(model="corte", checks=[
            {"nombre": "Reverberante a 0.6 mm vs corte 5 %", "plano": "enface_0.6", "metodo": "reverberante",
             "region": "fondo", "esperado": "corte:0", "tol_pct": 10},
        ]),
    )


def reverberante_anillo() -> SimulationConfig:
    """Demo: anillo de 8 contactos en fase a 2 kHz sobre el phantom bicapa de [Zvietcovich2019]."""
    return SimulationConfig(
        name="demo_reverberante_anillo_bicapa",
        description=("Reproduce el experimento de capas de [Zvietcovich2019]: gelatina 3 % (0.3 mm) sobre "
                     "gelatina 5 %, anillo impreso en 3D con 8 puntas en fase a 2 kHz, adquisición MB "
                     "cuasi-sincronizada y autocorrelación ajustada a la Ec. (2) en cuadros en-face a 0.15 y "
                     "0.6 mm. Bloque finito de bordes libres (cámara reverberante). Radio del anillo (2.5 mm) y "
                     "amplitud de contacto (10 Pa) son SUPUESTOS. Tolerancia indicativa del 20 %: la capa "
                     "superior mide ~lambda/2 a 2 kHz y la ventana de 0.8 mm mezcla ambas capas."),
        sources=["Zvietcovich2019", "Parker2017", "Ormachea2018"],
        geometry=Geometry(size_x_mm=8.0, size_y_mm=8.0, size_z_mm=3.0,
                          layers=[Layer(gelatin3(), 0.3), Layer(gelatin5(), 0.0)],
                          bottom="libre", lateral="libre"),
        excitation=ExcitationConfig(mode="anillo_contactos", regime="armonico", pressure_MPa=1e-5,
                                    harmonic_hz=2000, n_sources=8, source_layout="anillo", ring_radius_mm=2.5,
                                    tip_radius_mm=0.2),
        acquisition=AcquisitionConfig(mode="MB", pattern="raster", alines=40, bscans=40, m_reps=100,
                                      sync_points=50, x_length_mm=2.4, y_length_mm=2.4),
        fdtd=FDTDSettings(ppw=10, record_depth_mm=1.0, harmonic_min_periods=10, harmonic_max_periods=150),
        processing=ProcessingConfig(enface_pixel_mm=0.04, enface_depths_mm=(0.15, 0.6),
                                    speed_min_m_s=0.3, speed_max_m_s=10.0),
        speed=SpeedConfig(methods=("lfe",), window_mm=0.8, reverb_model="3D"),
        validation=ValidationSpec(model="corte", layer=1, checks=[
            {"nombre": "Reverberante a 0.6 mm vs corte 5 % (indicativo)", "plano": "enface_0.6",
             "metodo": "reverberante", "region": "fondo", "esperado": "corte:1", "tol_pct": 20},
            {"nombre": "Reverberante a 0.15 mm vs corte 3 % (indicativo)", "plano": "enface_0.15",
             "metodo": "reverberante", "region": "fondo", "esperado": "corte:0", "tol_pct": 20},
        ]),
    )


def reverberante_multifoco() -> SimulationConfig:
    """Reverberante con múltiples focos ARF modulados en AM a 1.5 kHz e inclusión esférica."""
    incl = Inclusion(gelatin10(), shape="esfera", center_mm=(0.6, 0.3, 0.8), size_mm=(0.7, 0.7, 0.7))
    return SimulationConfig(
        name="demo_reverberante_multifoco_inclusion",
        description=("Campo reverberante generado por 6 focos ARF con contacto en posiciones aleatorias, "
                     "AM a 1.5 kHz con fases aleatorias (variante con ARF del anillo de [Zvietcovich2019]); "
                     "gelatina 5 % con inclusión esférica de gelatina 10 %. Posiciones, fases y presión "
                     "(1.5 MPa) son SUPUESTOS de demostración."),
        sources=["Zvietcovich2019", "Parker2017", "Ormachea2018", "Palmeri2017"],
        geometry=Geometry(size_x_mm=8.0, size_y_mm=8.0, size_z_mm=3.5, layers=[Layer(gelatin5(), 0.0)],
                          inclusions=[incl], bottom="absorbente", lateral="absorbente"),
        excitation=ExcitationConfig(mode="arf_contacto", regime="armonico", pressure_MPa=1.5,
                                    harmonic_hz=1500, n_sources=6, source_layout="aleatoria",
                                    ring_radius_mm=3.0, size_a_mm=0.4, focal_depth_mm=0.8, dof_mm=2.0,
                                    random_phase=True, seed=3),
        acquisition=AcquisitionConfig(mode="MB", pattern="raster", alines=40, bscans=40, m_reps=100,
                                      sync_points=50, x_length_mm=3.2, y_length_mm=3.2),
        fdtd=FDTDSettings(ppw=10, record_depth_mm=1.2, harmonic_min_periods=10, harmonic_max_periods=60),
        processing=ProcessingConfig(enface_pixel_mm=0.05, enface_depths_mm=(0.5,)),
        speed=SpeedConfig(methods=("lfe", "gradiente_fase"), window_mm=1.0, reverb_model="2D"),
        validation=ValidationSpec(model="rayleigh", checks=[
            {"nombre": "Superficie (J0) vs Rayleigh 5 %", "plano": "enface", "metodo": "reverberante",
             "region": "fondo", "esperado": "teoria", "tol_pct": 12},
        ]),
    )


def cornea_curva() -> SimulationConfig:
    """Córnea curva de 4 capas sobre humor acuoso, limbo empotrado, barrido en meridianos."""
    layers = [Layer(m, 0.25) for m in cornea_layers()] + [Layer(water("Humor acuoso"), 0.0)]
    return SimulationConfig(
        name="demo_cornea_curva_meridianos",
        description=("Córnea de 4 capas de [Zvietcovich2019] (0.25 mm cada una, E = 18.75/12/5.07/1.92 kPa) "
                     "con superficie de radio 7.8 mm (SUPUESTO, ojo teórico de Le Grand), sobre humor "
                     "acuoso y con el borde empotrado (limbo). Empuje gaussiano de 1 ms con FWHM 0.71 mm "
                     "(sigma = 0.3 mm como en el FEM de [Zvietcovich2019]) por micro-tapping sin contacto "
                     "[Ambrozinski2016] con p0 = 1.2 kPa (SUPUESTO: reducido para que la córnea blanda no "
                     "supere ~1 um y no haya envolvimiento de fase). Se simulan 13 ms para incluir la "
                     "vibración residual del disparo anterior. Barrido MB en 8 meridianos con interpolación "
                     "en-face."),
        sources=["Zvietcovich2019", "Ambrozinski2016", "Singh2017"],
        geometry=Geometry(size_x_mm=10.0, size_y_mm=10.0, size_z_mm=4.2, surface="domo", dome_radius_mm=7.8,
                          layers=layers, bottom="absorbente", lateral="empotrado"),
        excitation=ExcitationConfig(mode="arf_sin_contacto", regime="transitorio", pressure_MPa=0.0012,
                                    shape="circulo", size_a_mm=0.71, ch2_waveform="Pulso", ch2_freq_hz=500,
                                    ch2_duty=0.5, ch2_delay_ms=1.0),
        acquisition=AcquisitionConfig(mode="MB", pattern="meridianos", alines=80, bscans=8, m_reps=300,
                                      sync_points=50, x_length_mm=7.0, y_length_mm=7.0),
        oct=OCTSystem(depth_window_mm=1.6),
        fdtd=FDTDSettings(ppw=8, record_depth_mm=1.3, duration_ms=13.0),
        processing=ProcessingConfig(filter_low_hz=150, filter_high_hz=2500, enface_pixel_mm=0.06,
                                    n_processing=1.376),
        speed=SpeedConfig(methods=("gradiente_fase", "tiempo_vuelo", "kf"), window_mm=1.5),
        validation=ValidationSpec(model="ninguno"),
    )


def rapido() -> SimulationConfig:
    """Prueba rápida (< 1 min): gelatina 5 % homogénea, raster pequeño."""
    cfg = bicapa_inclusion()
    cfg.name = "prueba_rapida"
    cfg.description = "Prueba rápida del flujo completo (malla gruesa, raster 20 x 20)."
    cfg.geometry = Geometry(size_x_mm=7, size_y_mm=6, size_z_mm=3, layers=[Layer(gelatin5(), 0.0)])
    cfg.acquisition = AcquisitionConfig(mode="MB", pattern="raster", alines=20, bscans=20, m_reps=200,
                                        sync_points=50, x_length_mm=4.0, y_length_mm=4.0, center_x_mm=0.5)
    cfg.fdtd = FDTDSettings(ppw=6, record_depth_mm=0.8)
    cfg.validation = ValidationSpec(model="rayleigh", tolerance_pct=12.0)
    return cfg


PRESETS: dict[str, Callable[[], SimulationConfig]] = {
    "Validación 1 - Rayleigh, gelatina 5 % (lineal MB)": rayleigh_gelatina,
    "Validación 2 - Lamb A0, placa sobre agua (sin contacto)": lamb_placa_agua,
    "Validación 3 - Reverberante 3D, gelatina 5 % homogénea": reverberante_homogeneo,
    "Demo 4 - Bicapa + inclusión (raster, en-face)": bicapa_inclusion,
    "Demo 5 - Reverberante, anillo de 8 contactos (bicapa)": reverberante_anillo,
    "Demo 6 - Reverberante, múltiples focos ARF + inclusión": reverberante_multifoco,
    "Demo 7 - Córnea curva de 4 capas (meridianos)": cornea_curva,
    "Prueba rápida": rapido,
}
