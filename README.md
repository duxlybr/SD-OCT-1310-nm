# OCE Workflow

MATLAB processing for OCT/OCE acquisitions: reconstruction, phase estimation,
filtering, Lamb-wave phase-speed analysis, and experimental summaries.

## Start

Open MATLAB in the repository root and run:

```matlab
startup
```

Keep raw acquisitions, generated results and experiment-specific parameter files
outside the repository. Choose a workflow below and edit its user configuration.

## Human workflows

| Task | Entrypoint |
| --- | --- |
| Inspect one acquisition section by section | `workflows/run_acquisition_stepwise.m` |
| Prepare interactively, then process a batch | `workflows/run_experiment_batch.m` |
| Process one prepared acquisition | `workflows/process_single_acquisition.m` |
| Process a prepared batch | `workflows/process_acquisition_batch.m` |
| Summarize one subexperiment | `workflows/summarize_subexperiment_results.m` |
| Summarize an experiment | `workflows/summarize_experiment_results.m` |

The [workflow guide](docs/processing_workflow.md) explains preparation, stopping,
runtime previews and persistence. k-f and optional phase-gradient estimates remain
separate; their interpretation is in [dispersion analysis](docs/dispersion_analysis_options.md).

## Find the right reference

- Changing code: read [AGENTS.md](AGENTS.md), then the [architecture map](docs/repository/final_architecture.md).
- Preparing metadata: [experimental metadata](docs/experimental_metadata.md).
- Interpreting saved data: [scientific result](docs/scientific_result_schema.md).
- Interpreting statistics: [summary statistics](docs/results_summary_statistics.md).
- Validating changes: [canonical gate](docs/repository/validation_status.md), using `UpdateBaseline=false`.

## Layout

`src/+oce/` contains production packages; `workflows/` contains human entrypoints;
`tests/` contains executable contracts; `docs/` contains maintained reference.
`third_party/` contains vendored dependencies. `inherited/` is off-path historical
source, not an alternate processing route.
