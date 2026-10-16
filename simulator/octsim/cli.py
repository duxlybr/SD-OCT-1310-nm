"""Línea de comandos: ejecutar presets o configuraciones JSON sin la GUI.

    python -m octsim                      # abre la GUI
    python -m octsim --list               # lista los presets
    python -m octsim --preset 1           # ejecuta un preset (número o nombre)
    python -m octsim --config sim.json    # ejecuta una configuración guardada
"""
from __future__ import annotations

import argparse
import sys
import time

from .config import SimulationConfig
from .presets import PRESETS


def _progress(frac: float, msg: str) -> None:
    sys.stdout.write(f"\r[{frac * 100:5.1f} %] {msg[:110]:<110}")
    sys.stdout.flush()


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="octsim", description="Simulador OCE/OCT SD-OCT 1310 nm")
    p.add_argument("--list", action="store_true", help="lista los presets")
    p.add_argument("--preset", help="número (1..N) o nombre del preset a ejecutar")
    p.add_argument("--config", help="archivo JSON de configuración")
    p.add_argument("--out", help="carpeta de resultados (por defecto results/<nombre>)")
    p.add_argument("--backend", choices=("auto", "gpu", "cpu"), help="fuerza el backend del FDTD")
    args = p.parse_args(argv)
    names = list(PRESETS)
    if args.list:
        for i, n in enumerate(names, 1):
            print(f"{i}. {n}")
        return 0
    if not args.preset and not args.config:
        from .gui import main as gui_main  # noqa: PLC0415
        gui_main()
        return 0
    if args.config:
        cfg = SimulationConfig.load_json(args.config)
    else:
        key = names[int(args.preset) - 1] if args.preset.isdigit() else args.preset
        cfg = PRESETS[key]()
    if args.backend:
        cfg.fdtd.backend = args.backend
    from .pipeline import run_simulation  # noqa: PLC0415
    t0 = time.perf_counter()
    res = run_simulation(cfg, _progress, outdir=args.out)
    print()
    v = res.validation
    print(f"Resultados en: {res.outdir}  ({time.perf_counter() - t0:.0f} s)")
    print(f"Validación ({v.get('modelo')}, f = {v.get('frecuencia_hz', 0):.0f} Hz): "
          f"{'APROBADA' if v.get('aprobado') else 'CON FALLAS'}")
    for c in v.get("checks", []):
        print(f"  [{'OK ' if c.get('ok') else 'X  '}] {c['nombre']}: medido {c.get('valor', float('nan')):.3f}, "
              f"esperado {c.get('esperado', float('nan')):.3f}, error {c.get('error_pct', float('nan')):+.1f} % "
              f"(tol {c.get('tol_pct', float('nan')):.0f} %) - {c.get('detalle', '')}")
    for w in res.warnings:
        print(f"  ADVERTENCIA: {w}")
    return 0 if v.get("aprobado", True) else 2
