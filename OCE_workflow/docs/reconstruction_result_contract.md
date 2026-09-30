# Reconstruction result contract

`oce.acquisition.reconstructComplexVolume` returns one validated scalar struct. It does not plot, persist, create directories, or interpret experimental scan organization.

```text
reconstruction_result
  complex_volume
  amplitude
  log_amplitude
  axes
  crop
  geometry
  provenance
```

## Quantities

| Field | Quantity | Units | Layout |
|---|---|---|---|
| `complex_volume.values` | `complex_oct_amplitude` | `arbitrary_complex_amplitude` | `lateral_depth_time` |
| `amplitude.values` | `mean_temporal_oct_amplitude` | `arbitrary_amplitude` | `depth_lateral` |
| `log_amplitude.values` | `log_oct_amplitude` | `dB_relative` | `depth_lateral` |

Amplitude is exactly `mean(abs(complex_volume),3)'`. Log amplitude is `real(20*log10(amplitude))`. It is not squared intensity.

## Axes and geometry ownership

Reconstruction axes are limited to quantities owned by reconstruction:

```text
axes.lateral -> monotonic storage index [samples]
axes.depth   -> refractive-corrected depth [mm]
axes.time    -> acquisition time [s]
```

`reconstruction_result.geometry` contains only generic storage/depth/time information:

```text
spectral_sample_count
prepared_spectral_sample_count
fft_sample_count
temporal_repetition_count
available_depth_sample_count
lateral_sample_count
depth_sample_count
time_sample_count
depth_sample_interval_mm
time_sample_interval_s
```

It does not contain acquisition-specific B-mode fields:

```text
bmode_count
samples_per_bmode
bmode_scan_width_mm
bmode_lateral_axis_mm
```

Those belong to `acquisition_state.geometry` because they depend on canonical experimental `scan_geometry`, not the OCT FFT reconstruction.

For `scan_geometry="angular_bmodes"`, `oce.acquisition.buildAcquisitionGeometry` builds the local physical B-mode axis once from the neutral raw descriptor. It is not inferred a second time inside reconstruction.

Raw I/O returns `measurement.raw_descriptor` and `rawdata` with layout
`spectral_time_lateral`, holding native `uint16` digitizer counts; spectral
preparation converts them to double exactly. `buildAcquisitionState` combines reconstruction with
acquisition geometry; downstream domains use that geometry for B-mode spatial
information. See [architecture](repository/final_architecture.md) for the ownership map.

## OCT-system boundary

Binary storage/header family is independent from OCT hardware profile.

Maintained OCT profiles include:

| Profile | System | Spectral preparation |
| --- | --- | --- |
| `swept_source_1300` | swept-source OCT | FFT-ready/uniform-k input, no scientific background subtraction, no resampling |
| `spectral_domain_1040` | spectral-domain OCT | sample-derived global-median background subtraction + inverse-wavelength PCHIP resampling |
| `spectral_domain_1310` | spectral-domain OCT | sample-derived global-median background subtraction + inverse-wavelength PCHIP resampling |

`oce.acquisition.prepareSpectralSamples` owns system-specific preparation. Background handling and spectral resampling are independent preprocessing stages selected by `OCTSystemOptions.spectral_preprocessing`; sampling semantics remain in `OCTSystemOptions.spectral_sampling`. `reconstructComplexVolume` owns the common Hann/FFT/crop/packing/axes operations.

The spectral-domain background method is `sample_derived_global_median`: one spectrum is estimated from the same acquisition by taking the temporal median independently at every lateral position and then the median across lateral positions. That spectrum is subtracted before inverse-wavelength resampling. The swept-source profile uses `background_method="none"`.

The SD-1040 estimator is retained as an explicit system-specific tradeoff because representative real-data reconstruction without it showed strong depth-stationary background bands that substantially degraded interface visibility. Synthetic audit evidence also shows that this estimator can suppress sufficiently laterally coherent real structure; that limitation must be considered when interpreting coherent sample structure.

The SD-1310 system configuration uses detector-pixel wavelength endpoints
`1261.36 -> 1472.76 nm`, nominal center wavelength `1.310 um`, and a 50 kHz
A-scan rate. The endpoints define spectral resampling, not depth sampling.
Depth calibration is experimental: `1.48 um/bin` in air at reference FFT 8192
for 2048 spectral samples. Reconstruction retains FFT 2048 and derives
`1.48 * 8192 / 2048 = 5.92 um/bin` in air. The reference FFT is calibration
provenance, not an editable reconstruction FFT size.

A future independent-background method may extend the same background stage once its real input contract is defined, without coupling that policy to raw file parsing.

Preview-only swept-source baseline removal remains separate from scientific reconstruction and does not define the profile background method.

Downstream scientific domains do not branch on binary family or OCT profile.

## Provenance and physical sampling

`OCTSystemOptions.depth_sampling_calibration` records calibration evidence in
air with explicit `method`, `interval_um`, and `source`:

| Profile | Method | Calibration interval | Source |
| --- | --- | --- | --- |
| SS1300 | `native_fft_interval` | 7.1 um/bin for unpadded reconstruction | `profile_supplied` |
| SD1040 | `native_fft_interval` | 3.57 um/bin for unpadded reconstruction | `experimentally_characterized` |
| SD1310 | `reference_fft_interval` | 1.48 um/bin at FFT8192 | `experimentally_characterized` |

The reference method additionally requires `spectral_sample_count` and
`reference_fft_sample_count`. Reconstruction rejects acquisitions whose spectral
count differs from that calibration. The native method preserves existing
unpadded calibration without inventing reference FFT sizes for SS1300 or SD1040.
Changing the physical spectral sampling requires appropriate calibration evidence.
Neither method represents optical axial resolution; no PSF/FWHM value is assumed.

Reconstruction provenance retains the calibration evidence and effective sample
index with their sources, spectral preparation, OCT profile, center wavelength,
and reconstruction method. Geometry records raw, prepared, and FFT counts from
the acquisition/actual arrays. All three must agree; available depth count is
`floor(fft_sample_count/2)`. There is no OCT padding setting.

Physical depth is:

```text
(crop_local_index - 1) * interval_in_air_um * 1e-3 / refractive_index
```

in mm.

The effective sample index comes from explicit `SampleOpticalOptions` and is
applied exactly once by reconstruction. The depth axis intentionally starts at
zero inside the crop, including crops whose raw start index is greater than one.
`geometry.depth_sample_interval_mm` agrees with that axis (NaN for a singleton
axis, preserving the existing contract).

Border methods consume `reconstruction.axes.depth.values` and interpolate it for
fractional fitted indices. Index 1 maps to its first value; no extrapolation is
performed outside the axis. In-vivo thickness priors use the already resolved
physical interval in acquisition geometry. Border code does not receive OCT or
sample-optics configuration. `findSurface` returns indices and intensity only.
Final `anteriorSurface` and `posteriorSurface` share the reconstruction coordinate system.

`oce.results.validateReconstructionResult` is the strict validator and rejects acquisition-specific B-mode geometry inside `reconstruction_result.geometry`.

## Configuration boundary and historical results

`axial_pixel_res` and `axial_pixel_res_source` are retired. The existing OCT
resolver rejects old or mixed old/new configurations with
`OCE:Config:RetiredAxialSampling`; it does not silently reinterpret historical
calibration or retain competing aliases.

Before reprocessing, rebuild the selected `OCTSystemOptions` with
`oce.config.getOCTSystemOptions(profile)`. Explicitly reapply reviewed custom
center wavelength, A-scan rate, spectral preparation, and calibration evidence;
review per-acquisition OCT overrides as well. For a custom native air interval,
set `depth_sampling_calibration.interval_um` and `.source`. For a reference-FFT
calibration, also supply the measured spectral and reference FFT counts.
Validate and save through the existing ProcessingConfig boundary.

Saved results retain their recorded calibration; they are never silently recalibrated.
The [scientific-result contract](scientific_result_schema.md) owns supported persistence schemas.
