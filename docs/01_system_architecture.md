# 1. System architecture

## Design requirements

| Requirement | Target |
|---|---|
| Central wavelength | ≈ 1310 nm (lower scattering in tissue than shorter NIR windows, at the cost of higher water absorption) |
| Axial resolution | 8–11 µm |
| Imaging depth | ≈ 3 mm |
| Lateral scanning | Two axes, for B-scans and volumes |
| Modularity | Spectrometer, interferometer, reference arm, sample arm and scanner can be aligned and modified independently |

For motion-based acquisition (specimens transported through the imaging
plane) the system additionally requires continuous B-scan streaming,
deterministic hardware timing of every B-scan, a sufficient B-scan rate, a
transverse field of view of at least 6 mm, and compatibility with imaging
through a glass window and a water layer.

SD-OCT was chosen over swept-source OCT mainly for its lower expected
implementation cost and because the spectrometer could be built and aligned
in-house from catalog components.

## Subsystems

### Spectrometer (detection unit)

- **Source:** Inphenix IPSDS1313-0321 SLD (λ₀ = 1317.97 nm,
  Δλ = 90.29 nm FWHM, 10.14 mW), delivered by single-mode fiber.
- **Point source:** fiber end in a Thorlabs SM1FC adapter mounted on
  translation stages, near the focal plane of the collimating mirror.
- **Collimation:** 90° off-axis parabolic mirror (no chromatic aberration),
  beam diameter ≈ 2 cm.
- **Dispersion:** Thorlabs GR50A-0610 ruled reflective grating, 600 l/mm,
  first diffraction order.
- **Focusing:** 45° off-axis parabolic mirror; camera ≈ 20.32 cm away,
  tilted ≈ 20–25° to follow the inclined spectral plane, with a small
  vertical angle to avoid direct saturation.
- **Detector:** Sensors Unlimited GL2048R-10A InGaAs line-scan camera
  (2048 px, 10 µm pitch, up to 147 kHz) → NI PCIe-1433 via Camera Link.

### Interferometer (Twyman–Green, free space)

- 50:50 cube beamsplitter Thorlabs CCM1-BS015/M.
- **Reference arm:** mirror on a Thorlabs PT1/M linear stage to set the
  zero-delay position.
- **Sample arm:** steering mirrors, iris, Thorlabs GVS002 two-axis
  galvanometer in a GCM102/M cage mount, Thorlabs LSM04 scan lens
  (f = 54 mm, 14.1 × 14.1 mm field) and the LSM04-matched dispersion
  compensator.

### Scanning and synchronization

- NI PCIe-6323 generates the galvanometer waveforms (analog out) and the
  buffer trigger (SMB/BNC to the frame grabber).
- A-line exposures are paced by camera-control line CC1 of the PCIe-1433.
- All timing derives from the 100 MHz PCIe-6323 base clock (10 ns
  resolution, 50 ppm).

## Mechanical design

- Optical axis height: ≈ 10.5 cm above the breadboard.
- Virtual assembly in Autodesk Fusion 360 from Thorlabs STEP files, organized
  in the same subassemblies as the physical system. It is a mechanical and
  spatial planning tool, not an optical ray-trace.
- The cage-mounted sample arm allows the scan lens to face down (vertical,
  used for imaging fry) or horizontally.

## Signal chain

Source → interferometer → spectral interference → grating + line camera →
background subtraction → λ-to-k resampling → window → FFT → depth profile.
See the [processing pipeline](../processing/matlab/README.md).
