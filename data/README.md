# Data

Lightweight data only.

| Folder | Content |
|---|---|
| [`calibration/`](calibration/) | Calibration tables used by the processing code (λ axis, axial fit, galvanometer batch results) |
| [`samples/`](samples/) | Small example acquisitions for testing the processing code (a few B-scans) |

Characterization results are kept in
[`../characterization/`](../characterization/).

## Raw data policy

- Raw `.tdms` acquisitions (≈ 205 MB/s, several GB per run) are **not**
  versioned; see the root `.gitignore`.
- Store them on institutional storage and reference their location in the
  corresponding characterization campaign or experiment notes.
- Datasets supporting publications may be released on Zenodo or OSF with a
  DOI, linked from here.
