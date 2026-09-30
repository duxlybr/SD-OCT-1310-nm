# Scientific audit log

This document records scientific-processing questions that require quantitative validation before changing maintained calculations. Scientific items must not be resolved by changing a golden baseline merely to make tests pass.

## OCT axial calibration and coordinate ownership

SD1310 air-depth calibration supplied and confirmed by the experiment owner is
1.48 um per FFT bin at FFT8192, using the same 2048 spectral samples and relevant
spectral sampling as the maintained reconstruction. The confirmed difference is
zero-padding by four. Thus the unpadded FFT2048 interval is 5.92 um/bin in air;
physical sample depth divides this by the explicit sample refractive index once.
The measurement is user-supplied experimental evidence, not a new measurement
performed by this repository or a wavelength-endpoint estimate. No optical
PSF/FWHM resolution is inferred. SS1300 and SD1040 retain 7.1 and 3.57 um/bin.

The maintained spectral preparation, FFT input/output sample count, complex
amplitudes, and motion algorithms are unchanged. Revised calibration changes the
physical interpretation of depth samples, including the interpreted support of
sample-count windows. It does not resample those windows. In-vivo posterior
search bounds expressed in mm consequently resolve using the corrected physical
interval; their numerical pixel bounds may change with calibration.

Border surfaces previously used `index * dz` while reconstruction used
`(index - 1) * dz`. Consuming the existing reconstruction axis translates both
surfaces by `-dz` at fixed calibration. For any anterior/posterior pair,
`(z_p - dz) - (z_a - dz) = z_p - z_a`; Euclidean nearest-neighbor distances and
thickness are translation-invariant. The golden's SS1300 fixture therefore has
a predicted translation of `-7.1/1.4 * 1e-3 mm`, unchanged indices, unchanged
thickness and phase speeds, and removal of the unconsumed `DepthPos` diagnostic.
The phantom 2/0 offsets and independent peak targets remain fixed.

The crop-local zero is preserved. Recovering absolute raw-volume depth is a
separate coordinate-contract decision and is deferred.

## Geometry-neutral naming migration — CLOSED validation note

The B-mode/scan-axis naming cut-over was architectural/persistence work, not a scientific algorithm change. Historical R004 schema-v1 to schema-v2 scientific equivalence was validated before retirement of the external real-data harness. That evidence remains in Git history.

The maintained validation strategy is now the deterministic synthetic golden documented in `docs/repository/validation_status.md`.

## Issue #97 — SD-1040 sample-derived background subtraction

**Status:** REOPENED; REAL-DATA REVISION UNDER VALIDATION

### Audited maintained path

The original `spectral_domain_1040` profile estimated one background spectrum from the same acquisition that contained the sample:

```text
temporal median at each lateral position
-> median across lateral positions
-> subtract from every selected spectrum
-> uniform inverse-wavelength resampling with PCHIP
-> Hann
-> FFT
```

The synthetic audit isolated background handling while preserving the SD wavelength-to-uniform-inverse-wavelength resampling. Standalone MATLAB audit scripts and their generated results remained outside the repository. They did not become maintained test dependencies.

### Controlled synthetic evidence

A flat coherent reflector showed a sharp failure near the 50% lateral-median threshold:

```text
49% lateral coverage -> ~98.5% reflector preserved
51% lateral coverage -> ~1.45% preserved
75% lateral coverage -> ~0.33% preserved
100% lateral coverage -> ~0.095% preserved
```

The same estimator strongly suppressed a common spectral artifact, so the problem was not lack of common-mode rejection. It was ambiguity between a common system component and real laterally coherent sample structure.

A second audit varied lateral phase and amplitude at 100% reflector coverage. Phase decorrelation progressively reduced the damage; fully random lateral phase preserved about 98.8% of the reflector. Amplitude variation alone did not remove the ambiguity. This demonstrated that the sample-derived estimator relies on lateral incoherence to avoid absorbing real structure.

A third audit compared three branches with identical downstream PCHIP/Hann/FFT processing:

```text
no subtraction
background estimated from the sample
background estimated from an independent background-only acquisition
```

For a fully coherent flat reflector, the sample-derived estimator preserved only about 0.096% of the reflector while suppressing the common artifact by about 56.9 dB. The independent background preserved about 100.0% of the reflector while providing essentially the same artifact suppression (~56.8 dB).

### First decision and subsequent real-data observation

PR #99 initially changed the maintained SD-1040 default to `background_method="none"` while preserving inverse-wavelength PCHIP resampling. The normal repository gate passed with `UpdateBaseline=false`.

After merge, a representative real SD-1040 acquisition was processed through `workflows/run_acquisition_stepwise.m` using that no-background policy. The reconstruction and crop-selection previews showed strong depth-stationary horizontal bands across most of the reconstructed field. Those bands substantially reduced interface contrast and made the no-background reconstruction unsuitable for the observed SD-1040 data.

The real acquisition is observational evidence only. It is not added to repository tests, fixtures, or a golden baseline.

### Revised maintained decision

For the currently characterized SD-1040 system, the practical reconstruction failure without background subtraction outweighs the synthetic coherent-reflector limitation of the sample-derived estimator. The maintained profile therefore restores the former estimator under the canonical method name:

```text
spectral_domain_1040
background_method = sample_derived_global_median
resampling_method = uniform_inverse_wavelength
interpolation_method = pchip
```

The estimator definition remains exactly:

```text
median over time independently at each lateral position
-> median across lateral positions
-> one global background spectrum
```

`swept_source_1300` remains unchanged:

```text
background_method = none
resampling_method = none
```

Background handling and spectral resampling remain separate preprocessing responsibilities inside `oce.acquisition.prepareSpectralSamples`. The restored estimator is selected by `background_method`; it is not coupled to wavelength sampling, BIN parsing, or future TDMS parsing.

A future independent-background method remains preferable in principle because the synthetic audit showed that it can suppress the common artifact without absorbing a fully coherent reflector. It should only be implemented after its real acquisition/input contract is known.

### Validation rule

Regression coverage must protect the exact `sample_derived_global_median` estimator and its ordering before inverse-wavelength resampling. The synthetic test should verify the estimator against an explicit reference calculation rather than claim that the method preserves all possible static reflectors.

The canonical golden is not regenerated. Final acceptance requires the normal repository gate with `UpdateBaseline=false`.

## SA-001 — Median filtering before dispersion FFT2D

**Status:** OPEN

### Current maintained path

The default surface-phase postprocessing is:

```matlab
FilterOptions.surface_postprocessing.remove_temporal_mean = true;
FilterOptions.surface_postprocessing.median.enabled = true;
FilterOptions.surface_postprocessing.median.window_samples = [3 3];
```

`oce.filtering.postprocessSurfacePhase` performs temporal-mean subtraction followed by:

```matlab
medfilt2(values, [3 3], 'Symmetric')
```

`oce.dispersion.buildWindows` consumes the resulting `filterResult.surface_postprocessed.values`; directional windows then enter the maintained 2-D dispersion spectrum path.

### Scientific concern

The median is a nonlinear rank filter and has no single multiplicative transfer function in the 2-D Fourier domain. It may suppress local outliers, but may also alter ridge shape, amplitudes, fine spatial/temporal structure, selected wavenumber, or phase speed.

### Required audit

Run an A/B comparison with all other processing identical:

1. median enabled `[3 3]`;
2. median disabled before dispersion-window extraction.

At minimum compare surface space-time maps, cropped k-f magnitude maps, detected ridge `k(f)`, selected wavenumber at excitation frequency, phase-speed curves, representative directions/frequencies/repetitions/SNR levels, and controlled synthetic data with known dispersion truth.

### Decision rule

Do not remove, replace, or retune this operation from visual appearance alone. A change requires a separately scoped scientific PR and quantitative evidence. Keep `UpdateBaseline=false` during the audit.

## SA-002 — Phantom border detector after per-B-mode isolation

**Status:** CLOSED

### Architectural conclusion

Each stored B-mode is processed independently. Separate B-modes are not physically continuous lateral neighbors, so lateral filtering, jump rejection, interpolation, fitting, smoothing, and thickness geometry must not cross storage seams.

### Accepted implementation

Owner:

```text
src/+oce/+borders/+methods/findPhantomBorders.m
```

Maintained behavior includes:

```text
- local anterior/posterior excursion rejection using max_lateral_jump + max_jump_gap;
- stable treatment of rejected anterior excursions before LOWESS;
- posterior candidate rejection using the same local semantics;
- background estimation from a low-intensity percentile of the local B-mode;
- lateral_edge_exclusion kept separate from detector logic;
- no canonical phantom min_depth_index floor.
```

Synthetic regression protects shallow valid surfaces and the local jump/background cases that motivated the fix.

### Closure rule

Reopen only for a new reproducible detector failure not explained by acquisition-specific tuning or insufficient signal support.

## SA-003 — Dispersion FFT physical-axis bin spacing

**Status:** CLOSED

### Finding

The maintained dispersion spectrum previously used:

```matlab
linspace(-0.5, 0.5, N) / sample_interval
```

for odd-length FFT axes. This assigns `N` points across both `-Fs/2` and `+Fs/2`, producing spacing `Fs/(N-1)` instead of the DFT spacing `Fs/N`.

The deterministic synthetic case exposed the defect directly:

```text
N_t = 129, intended df = 100 Hz
old axis step = 100.78125 Hz

N_x = 65, intended dk = 50 1/m
old axis step = 50.78125 1/m
```

### Historical convention preserved

The inherited dispersion path explicitly used odd FFT lengths, typically:

```matlab
FFT_Nx = (2^13) + 1;
FFT_Nt = (2^13) + 1;
```

The maintained resolver continues to require odd FFT lengths. PR #84 did not restore inherited code and did not add an even-length compatibility path.

The corrected centered DFT coordinates are:

```matlab
half_span = (N - 1) / 2;
bin_spacing = 1 / (N * sample_interval);
axis = (-half_span:half_span) * bin_spacing;
```

### Scientific consequence

The FFT magnitude itself was unchanged; the physical frequency/wavenumber coordinates were mislabeled. Therefore ridge coordinates, target-frequency metadata, and phase speed `c=f/k` could be biased.

For the historical `N=8193` convention, the scale error was approximately `0.0122%`. When temporal and spatial FFT lengths were equal, much of the common scale factor canceled in `c=f/k`, so a large historical phase-speed change is not expected. The defect becomes more relevant for smaller or unequal temporal/spatial FFT lengths.

### Validation and closure

PR #84 was first validated on the pre-golden suite:

```text
PASS=48 FAIL=0 SKIPPED=11
UpdateBaseline=false
```

After PR #84 was merged into `main` and then integrated into `test/synthetic-scientific-golden`, the old baseline failed only at the expected coordinate transition:

```text
old baseline frequency-axis value: 100.78125 Hz
corrected actual value:            100 Hz
```

Critically, before baseline comparison the synthetic regression independently verified:

```text
target frequency = 1000 Hz for every propagation direction
recovered phase speed = 2 m/s within the reviewed 0.10 m/s tolerance
border indices/thickness within controlled truth tolerances
scientific result schema/validation
```

Only after those truths passed was the explicitly authorized synthetic baseline regenerated.

Final user-executed gates:

```text
UpdateBaseline=true:  PASS=49 FAIL=0 SKIPPED=0
UpdateBaseline=false: PASS=49 FAIL=0 SKIPPED=0
```

SA-003 is therefore closed. Reopen only if a new reproducible FFT-coordinate inconsistency is found.

## Visualization-only median filtering

Median filtering used only for rendered depth-motion video frames is an output concern. It does not modify `filterResult.depth`, `surface_postprocessed`, dispersion windows, FFT2D, or scientific results and therefore does not resolve SA-001.
