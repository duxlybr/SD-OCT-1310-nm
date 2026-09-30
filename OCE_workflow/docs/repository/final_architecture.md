# Architecture and ownership

## Repository domains

| Location | Responsibility |
| --- | --- |
| `src/+oce/` | Maintained production packages |
| `workflows/` | Sequential human-facing coordination |
| `tests/` | Executable contracts and deterministic regressions |
| `docs/` | Current operational and scientific reference |
| `third_party/` | Explicit vendored dependencies |
| `inherited/` | Historical source, outside the runtime path |

Production dependencies point toward package-qualified domain owners, never toward
workflows, tests or documentation. The [workflow guide](../processing_workflow.md)
owns operational instructions; [AGENTS.md](../../AGENTS.md) owns modification rules.

## Fixed scientific product chain

```text
ProcessingConfig
-> prepareAcquisitionRun
-> processing_inputs + config_for_run
-> raw measurement
-> acquisition_state
-> reconstruction_result
-> border_result
-> phase_result
-> filter_result
-> window_result
-> dispersion_analysis_result
-> oce_result
```

`oce.pipeline.processPreparedAcquisition` coordinates automatic execution.
Manual workflows expose the same products as directly executable MATLAB sections.
`buildAcquisitionState` composes metadata, system/sample configuration, raw data,
acquisition geometry and the reconstruction product; it is not another reconstruction algorithm.

| Product | Owner | Main consumer |
| --- | --- | --- |
| Raw measurement/header | `oce.io.readRawAcquisition` / `readAcquisitionHeader` | Acquisition state |
| Acquisition geometry | `oce.acquisition.buildAcquisitionGeometry` | B-mode scientific domains |
| Reconstruction | `oce.acquisition.reconstructComplexVolume` | Borders and phase |
| Borders / thickness | `oce.borders.detectAndMask` | Phase and scientific result |
| Phase | `oce.motion.computeDepthResolvedPhase` / `computeSurfacePhase` | Filtering and phase-gradient |
| Filtered phase | `oce.filtering.filterPhaseResults` | Dispersion windows |
| Windows | `oce.dispersion.buildWindows` | Both dispersion estimators |
| Dispersion analysis | `oce.dispersion.analyzeWindows` | Scientific result and previews |
| Persisted scientific product | `oce.results.buildScientificResult` | I/O, summaries and plots |

## Geometry and physical ownership

A **B-mode** is an independent acquisition/storage/processing segment. A **scan axis**
is its undirected physical axis; **direction** means left/right propagation along it.
Separate B-modes have no scientific continuity across storage seams. `meridian` is
appropriate only for a sample whose physical interpretation is genuinely meridional.

Binary/header storage interpretation belongs to `oce.io`; OCT hardware/spectral
configuration to `OCTSystemOptions`; material optics to `SampleOpticalOptions`.
File format and OCT-system physics are independent. Downstream science does not
branch on binary family or OCT identity.

Acquisition geometry owns B-mode organization and local lateral axes. Reconstruction
owns generic storage, depth and time axes. See [metadata](../experimental_metadata.md)
and [reconstruction](../reconstruction_result_contract.md) for their physical contracts.

## Persistence, summaries and presentation

`oce.results.validateScientificResult` owns the persisted contract;
`oce.io.saveScientificResult` and `loadScientificResult` own its strict I/O boundary.
The [scientific schema](../scientific_result_schema.md) defines saved data and provenance.

`buildSubexperimentResultSet` is the summary-stage load boundary; experiment assembly
uses that owner. Reductions consume assembled `experiment.data`, not reopened files.
[Summary statistics](../results_summary_statistics.md) owns ordering and uncertainty semantics.

`oce.plotting` and `oce.plotting.summary` render existing products. `save*` owners
reuse their corresponding `plot*` owners and persist. `oce.video` owns optional
motion-video output; `oce.interaction` owns desktop tuning around scientific owners.
None of these presentation paths recalculates scientific products.

## Specialized references

- [Dispersion windows](../dispersion_window_options.md): geometry, sampling and temporal alignment.
- [Dispersion analysis](../dispersion_analysis_options.md): k-f, phase-gradient and diagnostics.
- [Validation](validation_status.md): runner, catalog and controlled golden.
- [Dependencies](third_party_dependencies.md): runtime path and provenance.

Consult [scientific_audit.md](../project/scientific_audit.md) when the task touches an open scientific audit item.
