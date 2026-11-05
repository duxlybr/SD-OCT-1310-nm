"""Registro único de la bibliografía usada por el simulador.

Cada ecuación del código cita una clave de este diccionario con el formato
``[Clave, Ec. (n)]`` o ``[Clave, sección]``. Solo se listan obras cuya cita fue
verificada (título, revista, volumen, páginas y año); cuando el número de
ecuación no pudo verificarse se cita la obra sin número de ecuación.

Los archivos del repositorio citados como ``repo:<ruta>`` son fuentes internas
(mediciones del sistema SD-OCT 1310 nm o código heredado del grupo GIBIO).
"""
from __future__ import annotations

REFERENCES: dict[str, str] = {
    # --- Elastodinámica numérica -------------------------------------------------
    "Virieux1986": (
        "Virieux J. P-SV wave propagation in heterogeneous media: Velocity-stress "
        "finite-difference method. Geophysics 51(4):889-901 (1986)."
    ),
    "Graves1996": (
        "Graves RW. Simulating seismic wave propagation in 3D elastic media using "
        "staggered-grid finite differences. Bull. Seismol. Soc. Am. 86(4):1091-1106 (1996)."
    ),
    "Moczo2002": (
        "Moczo P, Kristek J, Vavrycuk V, Archuleta RJ, Halada L. 3D heterogeneous "
        "staggered-grid finite-difference modeling of seismic motion with volume harmonic "
        "and arithmetic averaging of elastic moduli and densities. Bull. Seismol. Soc. Am. "
        "92(8):3042-3066 (2002)."
    ),
    "Komatitsch2007": (
        "Komatitsch D, Martin R. An unsplit convolutional perfectly matched layer improved "
        "at grazing incidence for the seismic wave equation. Geophysics 72(5):SM155-SM167 "
        "(2007)."
    ),
    "Roden2000": (
        "Roden JA, Gedney SD. Convolution PML (CPML): An efficient FDTD implementation of "
        "the CFS-PML for arbitrary media. Microw. Opt. Technol. Lett. 27(5):334-339 (2000)."
    ),
    "Palmeri2017": (
        "Palmeri ML, Qiang B, Chen S, Urban MW. Guidelines for finite-element modeling of "
        "acoustic radiation force-induced shear wave propagation in tissue-mimicking media. "
        "IEEE Trans. Ultrason. Ferroelectr. Freq. Control 64(1):78-92 (2017). "
        "doi:10.1109/TUFFC.2016.2641299"
    ),
    # --- Mecánica de tejidos y ondas -----------------------------------------------
    "Singh2022": (
        "Singh M, Zvietcovich F, Larin KV. Introduction to optical coherence elastography: "
        "tutorial. J. Opt. Soc. Am. A 39(3):418-430 (2022)."
    ),
    "Chen2004": (
        "Chen S, Fatemi M, Greenleaf JF. Quantifying elasticity and viscosity from "
        "measurement of shear wave speed dispersion. J. Acoust. Soc. Am. 115(6):2781-2785 "
        "(2004). doi:10.1121/1.1739480"
    ),
    "Rayleigh1885": (
        "Lord Rayleigh. On waves propagated along the plane surface of an elastic solid. "
        "Proc. London Math. Soc. s1-17(1):4-11 (1885)."
    ),
    "Viktorov1967": (
        "Viktorov IA. Rayleigh and Lamb Waves: Physical Theory and Applications. "
        "Plenum Press, New York (1967)."
    ),
    "Lamb1917": (
        "Lamb H. On waves in an elastic plate. Proc. R. Soc. Lond. A 93(648):114-128 (1917)."
    ),
    "Han2017": (
        "Han Z, Li J, Singh M, Wu C, Liu CH, Raghunathan R, Aglyamov SR, Vantipalli S, "
        "Twa MD, Larin KV. Optical coherence elastography assessment of corneal "
        "viscoelasticity with a modified Rayleigh-Lamb wave model. J. Mech. Behav. Biomed. "
        "Mater. 66:87-94 (2017)."
    ),
    "Christensen1982": (
        "Christensen RM. Theory of Viscoelasticity: An Introduction, 2nd ed. Academic Press "
        "(1982). Principio de correspondencia elástico-viscoelástico."
    ),
    # --- Excitación por fuerza de radiación acústica -------------------------------
    "Nguyen2014": (
        "Nguyen TM, Song S, Arnal B, Huang Z, O'Donnell M, Wang RK. Visualizing "
        "ultrasonically induced shear wave propagation using phase-sensitive optical "
        "coherence tomography for dynamic elastography. Opt. Lett. 39(4):838-841 (2014). "
        "doi:10.1364/OL.39.000838"
    ),
    "Ambrozinski2016": (
        "Ambrozinski L, Song S, Yoon SJ, Pelivanov I, Li D, Gao L, Shen TT, Wang RK, "
        "O'Donnell M. Acoustic micro-tapping for non-contact 4D imaging of tissue "
        "elasticity. Sci. Rep. 6:38967 (2016). doi:10.1038/srep38967"
    ),
    "Kinsler2000": (
        "Kinsler LE, Frey AR, Coppens AB, Sanders JV. Fundamentals of Acoustics, 4th ed. "
        "Wiley (2000)."
    ),
    # --- Campos reverberantes -------------------------------------------------------
    "Zvietcovich2019": (
        "Zvietcovich F, Pongchalee P, Meemon P, Rolland JP, Parker KJ. Reverberant 3D "
        "optical coherence elastography maps the elasticity of individual corneal layers. "
        "Nat. Commun. 10:4895 (2019). doi:10.1038/s41467-019-12803-4"
    ),
    "Parker2017": (
        "Parker KJ, Ormachea J, Zvietcovich F, Castaneda B. Reverberant shear wave fields "
        "and estimation of tissue properties. Phys. Med. Biol. 62:1046-1061 (2017)."
    ),
    "Ormachea2018": (
        "Ormachea J, Castaneda B, Parker KJ. Shear wave speed estimation using reverberant "
        "shear wave fields: implementation and feasibility studies. Ultrasound Med. Biol. "
        "44(5):963-977 (2018)."
    ),
    "Aki1957": (
        "Aki K. Space and time spectra of stationary stochastic waves, with special "
        "reference to microtremors. Bull. Earthq. Res. Inst. Univ. Tokyo 35:415-456 (1957)."
    ),
    "Hoyt2008": (
        "Hoyt K, Castaneda B, Parker KJ. Two-dimensional sonoelastographic shear velocity "
        "imaging. Ultrasound Med. Biol. 34(2):276-288 (2008)."
    ),
    # --- Estimadores de velocidad ---------------------------------------------------
    "Zvietcovich2017": (
        "Zvietcovich F, Rolland JP, Yao J, Meemon P, Parker KJ. Comparative study of shear "
        "wave-based elastography techniques in optical coherence tomography. J. Biomed. "
        "Opt. 22(3):035010 (2017). doi:10.1117/1.JBO.22.3.035010"
    ),
    "WangLarin2014": (
        "Wang S, Larin KV. Shear wave imaging optical coherence tomography (SWI-OCT) for "
        "ocular tissue biomechanics. Opt. Lett. 39(1):41-44 (2014)."
    ),
    "McLaughlin2006": (
        "McLaughlin J, Renzi D. Shear wave speed recovery in transient elastography and "
        "supersonic imaging using propagating fronts. Inverse Problems 22(2):681-706 (2006)."
    ),
    "Knutsson1994": (
        "Knutsson H, Westin CF, Granlund G. Local multiscale frequency and bandwidth "
        "estimation. Proc. IEEE Int. Conf. Image Processing (ICIP-94), vol. 1, pp. 36-40 "
        "(1994)."
    ),
    "Manduca2001": (
        "Manduca A, Oliphant TE, Dresner MA, Mahowald JL, Kruse SA, Amromin E, Felmlee JP, "
        "Greenleaf JF, Ehman RL. Magnetic resonance elastography: non-invasive mapping of "
        "tissue elasticity. Med. Image Anal. 5(4):237-254 (2001)."
    ),
    "Bernal2011": (
        "Bernal M, Nenadic I, Urban MW, Greenleaf JF. Material property estimation for "
        "tubes and arteries using ultrasound radiation force and analysis of propagating "
        "modes. J. Acoust. Soc. Am. 129(3):1344-1354 (2011)."
    ),
    # --- OCT --------------------------------------------------------------------------
    "IzattChoma2008": (
        "Izatt JA, Choma MA. Theory of optical coherence tomography. En: Drexler W, "
        "Fujimoto JG (eds.), Optical Coherence Tomography: Technology and Applications, "
        "cap. 2, pp. 47-72. Springer (2008)."
    ),
    "Schmitt1999": (
        "Schmitt JM, Xiang SH, Yung KM. Speckle in optical coherence tomography. "
        "J. Biomed. Opt. 4(1):95-105 (1999)."
    ),
    "Faber2004": (
        "Faber DJ, van der Meer FJ, Aalders MCG, van Leeuwen TG. Quantitative measurement "
        "of attenuation coefficients of weakly scattering media using optical coherence "
        "tomography. Opt. Express 12(19):4353-4365 (2004)."
    ),
    "Choma2005": (
        "Choma MA, Ellerbee AK, Yang C, Creazzo TL, Izatt JA. Spectral-domain phase "
        "microscopy. Opt. Lett. 30(10):1162-1164 (2005)."
    ),
    "Song2013": (
        "Song S, Huang Z, Wang RK. Tracking mechanical wave propagation within tissue using "
        "phase-sensitive optical coherence tomography: motion artifact and its "
        "compensation. J. Biomed. Opt. 18(12):121505 (2013)."
    ),
    "Singh2017": (
        "Singh M, Han Z, Nair A, Schill A, Twa MD, Larin KV. Applanation optical coherence "
        "elastography: noncontact measurement of intraocular pressure, corneal "
        "biomechanical properties, and corneal geometry with a single instrument. "
        "J. Biomed. Opt. 22(2):020502 (2017). Índice de refracción corneal n = 1.376."
    ),
    "Loupas1995": (
        "Loupas T, Peterson RB, Gill RW. Experimental evaluation of velocity and power "
        "estimation for ultrasound blood flow imaging, by means of a two-dimensional "
        "autocorrelation approach. IEEE Trans. Ultrason. Ferroelectr. Freq. Control "
        "42(4):689-699 (1995)."
    ),
    "BornWolf1999": (
        "Born M, Wolf E. Principles of Optics, 7th ed. Cambridge University Press (1999). "
        "Coeficientes de Fresnel en incidencia normal."
    ),
    "SalehTeich2007": (
        "Saleh BEA, Teich MC. Fundamentals of Photonics, 2nd ed. Wiley (2007). "
        "Haz gaussiano: divergencia theta0 = lambda / (pi W0)."
    ),
    "Oppenheim2010": (
        "Oppenheim AV, Schafer RW. Discrete-Time Signal Processing, 3rd ed. Pearson (2010)."
    ),
    # --- Fuentes internas del repositorio --------------------------------------------
    "repo:LATEST": (
        "repo:characterization/LATEST.md - valores medidos del SD-OCT 1310 nm (campaña "
        "2026-09_final-alignment): lambda0 = 1317.97 nm, PSF axial 9.65 um, lateral 11.04 um, "
        "5.931 um/muestra nativa, sensibilidad 79.6 dB, roll-off -3.32 dB/mm, estabilidad "
        "de fase 0.636 mrad, 50 kHz."
    ),
    "repo:octoce": (
        "repo:gui/PYTHON_GUI_DG4162/octoce (scan.py, config.py) - planificador de barrido "
        "MB/BM, puntos sync, retardo BFramesDelay, período de segmento y disparo PFI13."
    ),
    "repo:dg4162": (
        "repo:gui/PYTHON_GUI_DG4162/octoce/dg4162.py - excitación OCE: CH1 portadora "
        "954.9 kHz con AM 100 % por CH2 (pulso/burst disparado por PFI13, retardo 2 ms)."
    ),
    "repo:Loupas": (
        "repo:OCE_workflow/src/+oce/+motion/estimateLoupasPhaseIncrement.m - estimador de "
        "Loupas mantenido por el flujo OCE (portado línea a línea)."
    ),
    "repo:PhaseDeriv": (
        "repo:OCE_workflow/inherited/Codes/PhaseDerivativeSpeed.m y "
        "SpeedEstimation_PhaseDeriv.m - velocidad por derivada de fase con ajuste de plano."
    ),
    "repo:mRLFE": (
        "repo:OCE_workflow/inherited/Codes/mRLFE.m y FindZeros_mRLFE.m - matriz 5x5 de la "
        "ecuación de Rayleigh-Lamb modificada (placa con fluido en una cara)."
    ),
    "repo:Reverb": (
        "repo:OCE_workflow/inherited/Codes/Reverb Codes (TheoreticalProfile.m, "
        "FitTheoreticalPlot.m, localloop_xy_*.m) - autocorrelación reverberante."
    ),
}


def cite(key: str) -> str:
    """Devuelve la cita completa de ``key`` (KeyError si no está registrada)."""
    return REFERENCES[key]


def bibliography_markdown() -> str:
    """Bibliografía completa en Markdown, ordenada por clave."""
    lines = ["# Referencias", ""]
    for key in sorted(REFERENCES):
        lines.append(f"- **[{key}]** {REFERENCES[key]}")
    return "\n".join(lines) + "\n"
