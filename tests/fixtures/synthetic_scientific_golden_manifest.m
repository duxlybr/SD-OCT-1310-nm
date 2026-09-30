function manifest = synthetic_scientific_golden_manifest(repoRoot)
%SYNTHETIC_SCIENTIFIC_GOLDEN_MANIFEST Canonical synthetic golden contract.

    if nargin < 1 || strlength(string(repoRoot)) == 0
        error('repoRoot is required.');
    end

    manifest = struct();
    manifest.version = 4;
    manifest.goldenFile = fullfile(string(repoRoot), "tests", "fixtures", ...
        "synthetic_scientific_baseline.mat");
    manifest.tolerances = struct( ...
        'floatingAbsolute', 1e-12, ...
        'floatingRelative', 1e-10, ...
        'justification', ...
        "Tight tolerance for deterministic processing and floating-point noise only.");
end
