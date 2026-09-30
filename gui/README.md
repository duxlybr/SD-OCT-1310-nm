# GUI

User interfaces used to operate the instrument.

| Folder | Tool | Main settings |
|---|---|---|
| [`characterization/`](characterization/) | Characterization tool: live A-line, averaged A-line, peak position, SNR | 8192-point FFT, averaging of 80 A-lines |
| [`imaging/`](imaging/) | Imaging tool: live B-scan preview and acquisition control | 4096-point FFT, N_A, field of view, number of B-scans |

Both tools apply the SD-OCT reconstruction chain (background subtraction,
k-linearization, Hann window, FFT), differing only in the transform length and
averaging. The maintained offline processing lives in `src/+oce/` and
`workflows/`; its interactive tuners are in `src/+oce/+interaction/`.
