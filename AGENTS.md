# Repository operating rules

## Scope and ownership

- Production lives under `src/+oce/`; dependencies point toward scientific/domain owners.
- Production must not depend on workflows, tests, docs, or `inherited/`.
- One responsibility has one obvious owner. Extend an existing owner before adding an API.
- Keep science, interaction, plotting, persistence, and video output separate.
- `plot*` renders existing products; `save*` reuses the corresponding renderer.
- Binary/header interpretation, OCT hardware, sample optics, and acquisition geometry remain separate domains.
- Separate B-modes never acquire scientific continuity across storage seams.
- Domain ownership and the product chain are defined in [architecture](docs/repository/final_architecture.md).

## Implementation discipline

Before structural or scientific edits:

1. Audit the affected owners, consumers, tests, and specialized contract.
2. Summarize the current behavior and define the exact authorized change.
3. Reuse existing behavior; introduce a new owner only for an independently meaningful responsibility.
4. Implement that scope without opportunistic cleanup.
5. Review the diff for numerical changes, duplicate ownership, naming drift, and unnecessary APIs.
6. Run affected tests, then the canonical gate; review the result and Git state before delivery.

Keep orchestration at one abstraction level. Domain code implements domain tasks.
Human workflows, especially `run_acquisition_stepwise.m` and `run_experiment_batch.m`,
are sequential documents: preserve meaningful, directly executable MATLAB `%%`
stages and an obvious debugging boundary for each scientific product.

Prefer fewer conceptual layers and helper jumps. Keep `private/` small and intentional;
a local one-use helper is preferable to a wrapper that only renames another call.
Do not introduce manager/service layers, generic shared/common dumping grounds,
stage engines, callback registries, speculative frameworks, compatibility wrappers,
alternate pipelines, duplicate defaults, forwarding aliases, or parallel schemas.

Use lowercase MATLAB packages and domain-specific `lowerCamelCase` public functions,
with matching filenames. `resolve*` validates/normalizes an explicit contract; it
must not hide a scientific algorithm. Comments explain physical intent, provenance,
and non-obvious invariants; public headers state inputs, outputs and side effects.

Extend new OCT profiles or raw formats through their existing owning contracts.
Downstream science must not branch on binary family or OCT identity. Do not expose
extra manual controls when an owning configuration already expresses the intent.

## Scientific preservation

Preserve scientific defaults, tolerances, snapshots, schemas, stage ordering,
geometry, optical ownership, experimental data and persisted results unless the
user explicitly authorizes the corresponding scientific change.
Never change a golden, tolerance or snapshot merely to obtain a passing gate.
`UpdateBaseline=true` requires explicit authorization and independent scientific justification.

Validate external metadata/raw data, editable configuration, newly created scientific
products and persisted results at their trust boundaries. Retain checks for invalid
physics, dimensions, geometry and method choices. Do not repeatedly re-audit a
validated upstream product downstream without a new trust boundary or important invariant.

Use existing tests for bounded changes. Do not add runners or redundant defensive
batteries. Every maintained `test_*.m` belongs to exactly one catalog entry.

## Git and validation

`origin/main` is authoritative. Start from current main on a review branch unless
the user specifies another base. Never modify or merge main without explicit authorization.
Keep commit, push and PR actions within the user's requested delivery scope.

Run from the repository root:

```matlab
clear functions;
startup;
addpath(fullfile(pwd, "tests", "runners"), "-end");
summary = run_regression_tests( ...
    "UpdateBaseline", false, ...
    "ThrowOnFailure", true);
```

Use `UpdateBaseline=false` for normal maintenance and run `git diff --check`.
See [validation](docs/repository/validation_status.md) for the controlled baseline
and the boundary between permanent tests and observational real-data validation.

## Documentation and navigation

- [Workflow](docs/processing_workflow.md): entrypoints, execution controls, previews and outputs.
- [Architecture](docs/repository/final_architecture.md): domains, product ownership and contract links.
- [Scientific result](docs/scientific_result_schema.md): persisted meaning and provenance.
- [Summary statistics](docs/results_summary_statistics.md): reductions and uncertainty interpretation.

Read only the specialized contracts relevant to the task. Consult
[scientific_audit.md](docs/project/scientific_audit.md) when the task touches an open scientific audit item.
Do not recreate temporary handoff/context documents. Git and merged PRs own history;
issues own pending work. Maintained docs describe current contracts, not gate counts,
merge SHAs or implementation chronology. Add local AGENTS files only for non-obvious
local invariants that do not belong in this root file.
