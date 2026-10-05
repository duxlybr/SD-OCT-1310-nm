"""Audit the user's image-only gallery; put inventory in its sibling folder."""
from pathlib import Path
import csv
import hashlib
import json
from PIL import Image

HERE = Path(__file__).resolve().parent
GALLERY = HERE.parent / "Speed_Young_Maps"


def main():
    entries = sorted(GALLERY.iterdir())
    assert entries, "The gallery is empty"
    assert all(p.is_file() and p.suffix.lower() == ".png" for p in entries), \
        "Gallery must contain only PNG images, with no subfolders or metadata"
    records = []
    for path in entries:
        with Image.open(path) as image:
            width, height = image.size
            image.verify()
        assert width >= 1000 and height >= 600, f"Insufficient figure resolution: {path.name}"
        family = ("experimental" if path.name.startswith("experimental_") else
                  "elastodynamic_fdtd" if path.name.startswith("fdtd_") else
                  "scalar_reverberant_helmholtz" if path.name.startswith("reverberant_") else
                  "thin_flexural_lamb_plate" if path.name.startswith("simulation_lamb_plate_") else
                  "bscan_modal_or_elastodynamic" if path.name.startswith("simulation_bscan_") else
                  "eight_independent_scalar_SH" if path.name.startswith("fish_") else
                  "paired_exact_FDTD_XZ" if path.name.startswith("comparison_exact_fdtd_") else
                  "raw_unwrap_PD2D" if path.name.startswith(("comparison_unwrap_pd2d_", "unwrap_interactive_")) else
                  "unclassified")
        assert family != "unclassified", f"Unrecognized gallery provenance: {path.name}"
        records.append(dict(filename=path.name, family=family, width_px=width,
                            height_px=height, bytes=path.stat().st_size,
                            sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    with (HERE / "gallery_image_inventory.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(records[0]))
        writer.writeheader()
        writer.writerows(records)
    manifest = dict(gallery=str(GALLERY), image_count=len(records),
                    only_png=True, image_readability_check=True,
                    images=records,
                    note="Numerical validation lives in sibling subfolders; no metadata written to image gallery.")
    (HERE / "gallery_image_inventory.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(dict(image_count=len(records), only_png=True,
                          families={family: sum(r['family'] == family for r in records)
                                    for family in sorted(set(r['family'] for r in records))}), indent=2))


if __name__ == "__main__":
    main()
