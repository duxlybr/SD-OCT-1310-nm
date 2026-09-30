# Acquisition

Hardware control and data acquisition, implemented in LabVIEW.

| Folder | Content |
|---|---|
| [`labview/`](labview/) | VIs for camera acquisition, galvanometer waveform generation, triggering and TDMS streaming |
| [`camera_config/`](camera_config/) | Camera Link / NI-IMAQ camera files and serial configuration commands for the GL2048R-10A |

## Responsibilities

- Generate the bidirectional triangular fast-axis waveform and the slow-axis
  waveform (PCIe-6323 analog outputs).
- Generate the buffer trigger for the frame grabber (PCIe-6323 counter).
- Configure line rate, integration time and active pixels of the camera.
- Stream raw spectra (2048 px × 16 bit) to disk as `.tdms` at ≈ 205 MB/s
  (50 kHz) without dropped frames.

## Conventions

- Save a header with every acquisition: line rate, N_A, N_w, number of
  B-scans, drive voltages (V_pp X/Y), κ factors and timestamp.
- Save VIs for the LabVIEW version stated in this README once added.
