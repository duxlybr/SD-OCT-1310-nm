# Legacy processing pipelines

This folder is reserved for historical or experiment-specific processing pipelines.

The goal is to keep `Codes/` focused on reusable functions and move complete processing workflows here when they are not general-purpose utilities.

Initial legacy candidates identified in `Codes/`:

- `Automatic_OCE_Analysis_New.m`
- `Automatic_OCE_Analysis_CorneasDepth.m`
- `Automatic_OCE_Analysis_CorneasDepth_mod.m`
- `Automatic_OCE_Analysis_CorneasDepth_new.m`
- `Automatic_OCE_Analysis_CorneasLateral.m`
- `Automatic_OCE_Analysis_CorneasLateral_mod.m`
- `Automatic_OCE_Analysis_CorneasLateral_new.m`
- `Automatic_OCE_Analysis_CorneasLateral_CLK.m`

These files should be migrated here in a follow-up cleanup commit after verifying any path dependencies in active scripts.
