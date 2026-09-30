# Validation

Run the canonical, self-contained synthetic suite from the repository root:

```matlab
clear functions;
startup;
addpath(fullfile(pwd, "tests", "runners"), "-end");
summary = run_regression_tests( ...
    "UpdateBaseline", false, ...
    "ThrowOnFailure", true);
```

The sole runner is `tests/runners/run_regression_tests.m`. Its private catalog,
`tests/runners/private/repository_test_catalog.m`, assigns every maintained
`test_*.m` exactly once; uncatalogued or duplicated entries fail validation.

The controlled golden is `tests/fixtures/synthetic_scientific_baseline.mat`.
Its identity and tolerances are owned by `tests/fixtures/synthetic_scientific_golden_manifest.m`.
Normal maintenance uses `UpdateBaseline=false`. A baseline update requires explicit
user authorization and independent scientific justification, never just a failing gate.

Real acquisitions may support targeted observational validation. They are not normal
gate dependencies and do not become heavyweight permanent fixtures without a separate decision.
Run affected tests before the full gate, then `git diff --check`. Record results in
the delivery report; implementation checkpoints and historical totals belong in Git/PR history.
