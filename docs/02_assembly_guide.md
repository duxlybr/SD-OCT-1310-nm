# 2. Assembly and alignment guide

> Photographs of each step go in [`img/`](img/). CAD files are in
> [`../hardware/cad/`](../hardware/cad/).

## 0. Before starting

- Fix the optical-axis height at **≈ 10.5 cm** and keep it for every
  component.
- Use a **visible alignment laser** for the first pass; the 1310 nm SLD is
  invisible. Use an IR viewer/card once the SLD is switched in.
- Use the breadboard hole pattern and the Fusion 360 model as the placement
  reference.

## 1. Spectrometer

1. Mount the fiber output in the SM1FC adapter on translation stages (point
   source).
2. Place the 90° off-axis parabolic mirror so that the fiber end sits at its
   focal point.
3. **Collimation check:** project the beam over ≈ 2.5 m and adjust the fiber
   position until the beam diameter stays constant (≈ 2 cm).
4. Place the GR50A-0610 grating and select the first diffraction order.
5. Place the 45° off-axis parabolic mirror and the camera ≈ 20.32 cm from it;
   tilt the camera ≈ 20–25° and add a small vertical angle to avoid direct
   saturation.
6. Switch to the SLD and iterate grating, focusing mirror and camera position
   until the SLD spectral envelope appears in the acquisition software.
   Compare its shape with the certificate spectrum of the source.

## 2. Interferometer

1. Build a Twyman–Green interferometer with the CCM1-BS015/M beamsplitter and
   two mirrors to validate the spectrometer (spectral fringes, frame grabber,
   FFT reconstruction).
2. Mount the reference mirror on the PT1/M stage.
3. Align each arm with the other one blocked, optimizing power and direction;
   then unblock both and recombine at the beamsplitter.
4. Fine-tune mirror tilt, fiber coupling, iris aperture and reference-arm
   length until stable spectral fringes are observed.

## 3. Sample arm and scanner

1. Install the GVS002 motors and mirrors in the GCM102/M cage mount with the
   proper spacers and thermal isolation parts; keep the mirror orientation.
2. Attach the LSM04 scan lens with its cage adapter and insert the
   LSM04-matched dispersion compensator in the sample arm.
3. Wire the galvanometer drivers to the PCIe-6323 analog outputs and the
   trigger line to the PCIe-1433 (see [`../hardware/wiring/`](../hardware/wiring/)).
4. Leave the driver input scale factor at the factory setting
   (0.8 V/° mechanical); the calibration assumes it.

## 4. Final checks

- Stable fringes with the galvanometers powered.
- Zero delay located with the reference stage; sample signal within the first
  ≈ 3.45 mm.
- Proceed to [calibration](03_calibration.md).
