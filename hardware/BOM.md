# Bill of materials

Main components of the SD-OCT 1310 nm system. Posts, post holders, bases,
cage rods, screws and generic mounts are not listed individually yet.

## Light source

| Qty | Component | Manufacturer | Part number | Notes |
|---|---|---|---|---|
| 1 | Superluminescent diode, 1310 nm | Inphenix | IPSDS1313-0321 | λ₀ = 1317.97 nm, Δλ = 90.29 nm, 10.14 mW (certificate) |
| 1 | FC fiber adapter (point source) | Thorlabs | SM1FC | On translation stages |
| — | Single-mode fiber patch cable | — | — | |

## Spectrometer

| Qty | Component | Manufacturer | Part number | Notes |
|---|---|---|---|---|
| 1 | 90° off-axis parabolic mirror | — | — | Collimation, ≈ 2 cm beam |
| 1 | Ruled reflective grating, 600 l/mm, NIR | Thorlabs | GR50A-0610 | First order |
| 1 | 45° off-axis parabolic mirror | — | — | Focusing, ≈ 20.32 cm to camera |
| 1 | InGaAs line-scan camera, 2048 px, 10 µm, 147 kHz | Sensors Unlimited | GL2048R-10A | Camera Link |

## Interferometer

| Qty | Component | Manufacturer | Part number | Notes |
|---|---|---|---|---|
| 1 | 50:50 cube beamsplitter, cage | Thorlabs | CCM1-BS015/M | |
| 1 | Linear translation stage | Thorlabs | PT1/M | Reference mirror |
| 2+ | Mirrors in kinematic mounts | — | — | Reference and steering |
| 2+ | Iris diaphragms | — | — | Power balance between arms |

## Sample arm and scanning

| Qty | Component | Manufacturer | Part number | Notes |
|---|---|---|---|---|
| 1 | Two-axis galvanometer system | Thorlabs | GVS002 | Driver scale 0.8 V/° (factory) |
| 1 | Galvanometer cage mount | Thorlabs | GCM102/M | |
| 1 | OCT scan lens, f = 54 mm | Thorlabs | LSM04 | 14.1 × 14.1 mm field |
| 1 | Dispersion compensator matched to LSM04 | Thorlabs | — | |

## Electronics and acquisition

| Qty | Component | Manufacturer | Part number | Notes |
|---|---|---|---|---|
| 1 | Camera Link frame grabber | National Instruments | PCIe-1433 | CC1 paces A-line exposure |
| 1 | Multifunction DAQ | National Instruments | PCIe-6323 | Galvo waveforms + trigger |
| — | SMB/BNC coaxial cables | — | — | Trigger to frame grabber |

## Calibration and characterization accessories

| Qty | Component | Manufacturer | Part number | Notes |
|---|---|---|---|---|
| 1 | 1951 USAF resolution target | Thorlabs | R1DS1P | Lateral resolution |
| 1 | Absorptive ND filter, NIR | Thorlabs | NENIR506A-C | OD 1.02 at 1310 nm |
| 1 | Three-dot target (3 mm spacing) | Thorlabs | (ATR206 accessory) | Galvanometer calibration |
| 1 | Micrometer translation stage + mirror | — | — | Axial calibration |
| 1 | Visible alignment laser | — | — | Initial alignment |
| — | Optical breadboards | Thorlabs | — | |
