# Third-party dependencies

## MIMT

The vendored MIMT tree is at `third_party/MIMT/`. The maintained interactive
acquisition route estimates B-mode preview limits in `oce.acquisition` and does
not use `immodify1` or its `akzoom` GUI dependency. Startup adds only the MIMT
root; `FEX_dependencies` remains off-path.
Dependency-specific license files exist below `FEX_dependencies/LICENSE_FILES`,
but no global MIMT license file was found, so no global license is inferred.

## fireice

- final path: `third_party/fireice/fireice.m`
- primary function: `fireice`
- author named in the header: Joseph Kirk
- current use: filtering and dispersion-window preview colormaps
- explicit license text found in the file: none

The file was relocated byte-for-byte and is resolved once. It is not copied
into `src/+oce` or `inherited`. Absence of an explicit license grant remains a
redistribution/provenance risk; no license coverage is asserted.

## Runtime path policy

`startup.m` adds only the roots `third_party/MIMT` and
`third_party/fireice`. It does not add the whole `third_party` tree, MIMT demos
or FEX folders, and it does not use `genpath`.
