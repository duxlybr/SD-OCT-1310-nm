"""Render only scientific speed/Young maps to the requested PNG gallery.

The image panels use raw accepted estimates, with no smoothing or gap filling.
The reproducibility code, source fields, and regional scores remain outside
the images-only gallery. Truth is the scalar SH material coefficient, not an
experimental or full 3-D elastodynamic ground truth.
"""
from pathlib import Path
import csv
import json
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.io import loadmat
from matplotlib.patches import Circle


def main():
    root = Path(__file__).resolve().parent
    gallery = root.parents[1] / "Speed_Young_Maps"
    gallery.mkdir(parents=True, exist_ok=True)
    fields = loadmat(root / "scalar_helmholtz_fields.mat", simplify_cells=True)["cases"]
    maps = loadmat(root / "scalar_helmholtz_maps.mat", simplify_cells=True)["maps"]
    with (root / "scalar_helmholtz_metrics.csv").open(encoding="utf-8-sig", newline="") as stream:
        metrics = list(csv.DictReader(stream))
    names = {"homogeneous": "Control homogéneo: 12 kPa",
             "stiff_inclusion": "Inclusión rígida: 24 kPa; fondo: 12 kPa",
             "soft_inclusion": "Inclusión blanda: 6 kPa; fondo: 12 kPa"}
    outputs = []
    plt.rcParams.update({"font.size": 11, "axes.titlesize": 12, "axes.labelsize": 11})
    for c, m in zip(fields, maps):
        label = c["label"]
        support = np.asarray(c["farfield_mask"], dtype=bool)
        accepted = support & np.asarray(m["speed"]["valid_mask"], dtype=bool)
        x = np.asarray(c["data"]["x_m"])*1e3
        y = np.asarray(c["data"]["row_m"])*1e3
        truth_speed = np.where(support, c["truth_speed"], np.nan)
        speed = np.where(accepted, m["speed"]["speed_m_s"], np.nan)
        truth_young = np.where(support, c["truth_young"]/1000, np.nan)
        young = np.where(accepted, m["young"]["young_pa"]/1000, np.nan)
        row = next(r for r in metrics if r["case_name"] == label and r["region"] == "farfield")
        fig, axes = plt.subplots(2, 2, figsize=(11.4, 10.6), layout="constrained")
        main_title = fig.suptitle("Simulación escalar 2D · " + names[label],
                                  fontsize=17, fontweight="bold", y=.975)
        main_title.set_in_layout(False)
        config = [(truth_speed, "Velocidad de corte de referencia", "viridis", .9, 3.1, "m/s"),
                  (speed, "Velocidad estimada · AIA escalar 2D", "viridis", .9, 3.1, "m/s"),
                  (truth_young, "Young de referencia", "magma", 2.5, 29, "kPa"),
                  (young, "Young estimado · modelo de corte", "magma", 2.5, 29, "kPa")]
        for ax, (image, title, cm, lower, upper, unit) in zip(axes.flat, config):
            cmap = plt.get_cmap(cm).copy(); cmap.set_bad("#e7e7e7")
            plot = ax.pcolormesh(x, y, image, shading="nearest", cmap=cmap, vmin=lower, vmax=upper,
                                 rasterized=True)
            ax.set(title=title, xlabel="x (mm)", ylabel="y (mm)",
                   xlim=(-4.6, 4.6), ylim=(-4.6, 4.6), aspect="equal")
            ax.set_xticks([-4, -2, 0, 2, 4]); ax.set_yticks([-4, -2, 0, 2, 4])
            if label != "homogeneous":
                ax.add_patch(Circle((0, 0), c["inclusion_radius_m"]*1000,
                                    fill=False, edgecolor="white", linewidth=1.35, linestyle="--"))
            cb = fig.colorbar(plot, ax=ax, shrink=.84, extend="both", pad=.02)
            cb.set_label(unit)
        caption = ("Young condicional: onda escalar de corte; ρ = 1000 kg/m³, ν = 0.495. "
                   "f = 1800 Hz; ventana = 2.4 mm.\n"
                   f"Campo útil: cobertura {float(row['coverage_pct']):.2f}%; "
                   f"error absoluto mediano de velocidad {float(row['speed_median_abs_error_pct']):.2f}%; "
                   f"Young {float(row['young_median_abs_error_pct']):.2f}%. "
                   "Gris: fuera del campo útil o rechazado.\n"
                   "Solución de Helmholtz con μ variable, 24 fuentes periféricas y borde absorbente. "
                   "Sin suavizado ni relleno de huecos.")
        # Constrained-layout rect is x0,y0,width,height rather than x0,y0,x1,y1.
        fig.get_layout_engine().set(rect=(0, .115, 1, .80))
        fig.text(.5, .015, caption, ha="center", va="bottom", fontsize=10, linespacing=1.45)
        output = gallery / f"reverberant_scalar2d_{label}_speed_young.png"
        fig.savefig(output, dpi=180, facecolor="white")
        plt.close(fig)
        outputs.append(str(output))
        print(output)
    (root / "rendered_gallery_files.json").write_text(json.dumps(outputs, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
