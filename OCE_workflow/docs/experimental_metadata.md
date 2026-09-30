# Experimental metadata contract

The Experimental Log and persisted `acquisition_table` keep experimental design, excitation, acquisition organization, and OCT hardware as separate concepts.

## Canonical taxonomy

```text
experiment_type
excitation_type
acquisition_mode
scan_geometry
oct_system_profile
```

Responsibilities:

- `experiment_type`: experiment-design semantics, e.g. `uniaxial_prestrain`;
- `excitation_type`: excitation family, e.g. `quasi_harmonic` or `pulse`;
- `acquisition_mode`: temporal acquisition mode;
- `scan_geometry`: spatial scan organization;
- `oct_system_profile`: OCT hardware/reconstruction profile.

`experiment_type` and `excitation_type` are lower-snake-case identifiers rather than closed enumerations.

For `quasi_harmonic`, `frequency_Hz` is the positive physical excitation frequency and is used by the automatic temporal-filter policy. A `pulse` excitation has no single target frequency, so `frequency_Hz=NaN` is valid and explicitly represents that the scalar excitation frequency is unavailable. The manually selected pulse filter passband is processing configuration and must not be written back as a physical excitation frequency.

Maintained temporal mode:

```text
mb_mode
```

Maintained executable scan geometries:

```text
angular_bmodes
raster
```

`raster` is executable through reconstruction, borders, surface phase and
temporal filtering, and feeds the en-face motion video. k-f dispersion windows
and the persisted scientific result remain `angular_bmodes` products.

Maintained OCT profiles include:

```text
swept_source_1300
spectral_domain_1040
spectral_domain_1310
```

## Experimental Log organization

The workbook uses visual section headers in row 1 and canonical variable names in row 2.

| Section | Recommended columns |
| --- | --- |
| Experiment | `experiment_id`, `sub_experiment`, `experiment_type`, `status` |
| Sample | `sample_type`, `sample_id`, `shape`, `material`, `proportion` |
| Excitation | `excitation_type`, `frequency_Hz`, `period_us`, `lead_train`, `voltage_mVpp`, `puff_delay_ms`, `puff_on_ms`, `puff_frequency_Hz` |
| Acquisition | `run_id`, `filename`, `rep_id`, `acquisition_mode`, `scan_geometry`, `oct_system_profile`, `scan_size_x_mm`, `scan_size_y_mm`, `alines_per_bscan`, `m_repetitions`, `bscan_count` |

The optional acquisition-dimension fields are ordering-neutral metadata and can describe both MB- and BM-style acquisition plans:

```text
alines_per_bscan  = lateral A-line positions in each B-scan
m_repetitions     = temporal repetitions on the M axis
bscan_count       = independent B-scans stored in the acquisition
```

They document the intended acquisition but do not own raw storage interpretation. When present, maintained preparation compares them with the normalized binary header. A mismatch produces a warning and processing continues using the raw-header dimensions.

Additional design variables such as `strain_percent` or `pressure_mmHg` may remain columns and can become summary group keys.

## Required acquisition-table fields

Every canonical persisted `acquisition_table` requires `experiment_id`,
`sub_experiment`, `run_id`, `filename`, `sample_type`, `experiment_type`,
`excitation_type`, `acquisition_mode`, `scan_geometry`, `oct_system_profile`,
`frequency_Hz`, and `rep_id`.

Within a subexperiment, `acquisition_mode`, `scan_geometry`, and `oct_system_profile` are invariant.

## Geometry semantics

`angular_bmodes` means independent stored B-mode segments acquired at defined
scan orientations. Use the [architecture terminology](repository/final_architecture.md#geometry-and-physical-ownership)
for B-mode, scan axis and propagation direction; generic segments are not called meridians.

`raster` means consecutive B-scans along x stepped along y, each position
acquired in `mb_mode` with its own excitation trigger. One B-mode is one B-scan.
Bidirectional (serpentine) rasters are rejected rather than silently reordered.

The OCTOCE reader records the physical length of every stored B-scan in
`bscan_length_mm`, following the acquisition scan planner: raster lines span
`x_length_mm`; linear lines span `x_length_mm` (horizontal) or `y_length_mm`
(vertical); meridian `b` spans the ellipse diameter at `theta = pi*b/bscans`.
Geometry uses that length for the local lateral axis and rejects B-scans of
unequal length (elliptical meridians with more than one scan axis). Historical
headers without this field keep `Ver_scan_length_mm` as the B-mode length.
Positions start at 0 mm on the first acquired A-line and B-scan.

## Acquisition-parameter relationship

`oce.acquisition.prepareAcquisitionParameters` persists schema version 4 and stores canonical `scan_geometry` directly.

Preparation validates canonical metadata directly; it does not translate retired identifiers.

## Result-summary relationship

Summary design remains generic:

```text
experiment.data(d1, d2, ..., dn, repetition)
```

For `uniaxial_prestrain`, a common quasi-harmonic design is:

```text
strain_percent x frequency_Hz x rep_id
```

For pulse experiments, `frequency_Hz` should not be used as a design dimension when it is unavailable; use the actual experimental condition columns instead.

Scan-axis identity remains within-acquisition scientific-result identity rather than an experiment-design dimension.

## Input boundary

Historical workbooks and parameter files are not silently translated. Regenerate
canonical metadata from the original experimental/source information when preparing
an acquisition for maintained processing. Field names from a binary header remain
raw provenance rather than alternate canonical metadata names.
