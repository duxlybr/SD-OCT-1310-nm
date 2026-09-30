# Wiring and synchronization

| Signal | From | To | Connection |
|---|---|---|---|
| Fast-axis galvanometer drive (X) | PCIe-6323 analog output | GVS002 driver X | Differential command, ±10 V range |
| Slow-axis galvanometer drive (Y) | PCIe-6323 analog output | GVS002 driver Y | Differential command, ±10 V range |
| Buffer / frame trigger | PCIe-6323 counter output | PCIe-1433 trigger input | SMB/BNC coaxial |
| A-line exposure | PCIe-1433 CC1 | GL2048R-10A | Camera Link |
| Image data | GL2048R-10A | PCIe-1433 | Camera Link |

Timing: all edges derive from the PCIe-6323 100 MHz base clock (10 ns
resolution, 50 ppm).

To add: channel numbers, terminal block pinout and a wiring diagram
(`wiring_diagram.svg`/`.png`).
