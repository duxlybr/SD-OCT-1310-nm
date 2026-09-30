# Characterization

This folder keeps the characterization results of the SD-OCT 1310 nm system
up to date. Every time the system is re-aligned, modified or re-measured, the
results are recorded here as a new **campaign**, so that the current
performance of the instrument and its evolution over time are always
available.

The measurement procedures are described in
[`../docs/04_characterization_methods.md`](../docs/04_characterization_methods.md);
this folder only stores results.

## Layout

```
characterization/
├── README.md               This file
├── LATEST.md               Current reference values (single source of truth)
├── HISTORY.md              One row per campaign, newest first
├── _template/              Copy this folder to start a new campaign
│   └── README.md
└── YYYY-MM_<description>/  One folder per campaign
    ├── README.md           Conditions, results and notes of the campaign
    ├── tables/             Processed/summary tables (CSV, XLSX)
    └── figures/            Exported figures (PNG/SVG)
```

## Adding a new campaign

1. Copy `_template/` to a new folder named `YYYY-MM_<short-description>`
   (e.g. `2026-11_after-grating-realignment`). Use `YYYY-MM-DD_...` if more
   than one campaign happens in the same month.
2. Fill in its `README.md`: date, operator, system configuration (what
   changed since the previous campaign) and the results table.
3. Put processed tables in `tables/` and exported figures in `figures/`.
   Prefer CSV: the root `.gitignore` excludes `*.mat` and any `data/` or
   `results/` folder. Raw `.tdms` acquisitions stay out of Git; record their
   storage location in the campaign `README.md`.
4. Add a row at the top of [`HISTORY.md`](HISTORY.md).
5. If the campaign supersedes the current reference values, update
   [`LATEST.md`](LATEST.md) and the performance table of the root
   [`README.md`](../README.md). If a calibration constant changed (axial
   slope, spectrometer λ range, galvanometer factors), also review the
   `spectral_domain_1310` profile in
   `OCE_workflow/src/+oce/+config/getOCTSystemOptions.m` (follow
   [AGENTS.md](../OCE_workflow/AGENTS.md): calibration changes are scientific
   changes).

## Conventions

- All values are in air unless stated otherwise.
- Always state the FFT length (4096 or 8192 points), window, number of
  averaged A-lines and ND filter used, because they change the reported
  numbers.
- Report the expected (theoretical or specified) value next to the measured
  one whenever one exists.
- Values derived indirectly (e.g. equivalent sensitivity) must be labelled as
  such.
