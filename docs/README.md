# Documentation

## System (hardware and measurement)

These documents describe **how** the SD-OCT 1310 nm system is built,
calibrated, characterized and operated. Measured results are kept in
[`../characterization/`](../characterization/).

| # | Document | Content |
|---|---|---|
| 1 | [System architecture](01_system_architecture.md) | Design requirements, subsystems, signal chain |
| 2 | [Assembly guide](02_assembly_guide.md) | Mechanical assembly and optical alignment |
| 3 | [Calibration](03_calibration.md) | Spectral, axial and lateral (galvanometer) calibration |
| 4 | [Characterization methods](04_characterization_methods.md) | Resolution, sensitivity, roll-off, phase stability |
| 5 | [Operation and acquisition](05_operation_and_acquisition.md) | Timing, acquisition parameters, data rates |

## Processing (MATLAB workflow)

These documents live with the code in [`../OCE_workflow/docs/`](../OCE_workflow/docs/).

| Document | Content |
|---|---|
| [Processing workflow](../OCE_workflow/docs/processing_workflow.md) | Entrypoints, execution controls, previews and outputs |
| [Experimental metadata](../OCE_workflow/docs/experimental_metadata.md) | Experimental log and acquisition metadata contract |
| [Reconstruction contract](../OCE_workflow/docs/reconstruction_result_contract.md) | OCT profiles (incl. `spectral_domain_1310`), spectral preparation, depth axes |
| [Dispersion windows](../OCE_workflow/docs/dispersion_window_options.md) | Window geometry, sampling and temporal alignment |
| [Dispersion analysis](../OCE_workflow/docs/dispersion_analysis_options.md) | k-f, phase-gradient and diagnostics |
| [Scientific result schema](../OCE_workflow/docs/scientific_result_schema.md) | Persisted data and provenance |
| [Summary statistics](../OCE_workflow/docs/results_summary_statistics.md) | Reductions and uncertainty |
| [Architecture](../OCE_workflow/docs/repository/final_architecture.md) | Domains and product ownership |
| [Validation](../OCE_workflow/docs/repository/validation_status.md) | Regression runner and baseline |
| [Third-party dependencies](../OCE_workflow/docs/repository/third_party_dependencies.md) | Runtime path and provenance |
| [Scientific audit](../OCE_workflow/docs/project/scientific_audit.md) | Open scientific questions |

Figures used by the system documents go in [`img/`](img/).
