"""Prueba de extremo a extremo (pequeña) y prueba de humo de la GUI."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from octsim.acquisition import AcquisitionConfig  # noqa: E402
from octsim.backend import GPU_AVAILABLE  # noqa: E402
from octsim.config import SimulationConfig  # noqa: E402
from octsim.fdtd import FDTDSettings  # noqa: E402
from octsim.presets import PRESETS, rapido  # noqa: E402


def tiny_config() -> SimulationConfig:
    cfg = rapido()
    cfg.name = "prueba_unitaria"
    cfg.geometry.size_x_mm, cfg.geometry.size_y_mm, cfg.geometry.size_z_mm = 5.0, 4.0, 2.0
    cfg.acquisition = AcquisitionConfig(mode="MB", pattern="raster", alines=10, bscans=6, m_reps=150,
                                        sync_points=20, x_length_mm=3.0, y_length_mm=2.0, center_x_mm=0.5)
    cfg.excitation.ch2_delay_ms = 0.5
    cfg.fdtd = FDTDSettings(cell_mm=0.08, record_depth_mm=0.5, backend="auto")
    cfg.output.max_video_frames = 20
    return cfg


class PipelineTests(unittest.TestCase):
    @unittest.skipUnless(GPU_AVAILABLE, "la prueba de extremo a extremo usa la GPU (en CPU es lenta)")
    def test_end_to_end_tiny(self) -> None:
        from octsim.pipeline import run_simulation  # noqa: PLC0415
        with tempfile.TemporaryDirectory() as tmp:
            res = run_simulation(tiny_config(), outdir=Path(tmp) / "out", use_cache=False)
            self.assertIsNotNone(res.enface)
            self.assertTrue(res.bmode)
            self.assertTrue(any(m.plane == "enface" for m in res.speed_maps))
            self.assertGreater(res.truth_check["r"], 0.95)
            for key in ("video_enface", "video_bmode_B3", "fig_geometria", "datos"):
                self.assertIn(key, res.files)
                self.assertTrue(Path(res.files[key]).exists())

    def test_presets_are_valid_and_serializable(self) -> None:
        for name, factory in PRESETS.items():
            cfg = factory()
            self.assertEqual(cfg.validate(), [], msg=name)
            again = SimulationConfig.from_dict(cfg.to_dict())
            self.assertEqual(again.to_dict(), cfg.to_dict(), msg=name)


def _norm(d: dict) -> dict:
    """Normaliza números (int/float) y tuplas para comparar configuraciones."""
    import json  # noqa: PLC0415
    out = json.loads(json.dumps(d, default=list), parse_int=float)
    out["speed"]["methods"] = sorted(out["speed"]["methods"])   # el orden de métodos no importa
    return out


class GuiSmokeTests(unittest.TestCase):
    def test_gui_loads_every_preset(self) -> None:
        try:
            from octsim.gui import SimulatorApp  # noqa: PLC0415
            app = SimulatorApp()
        except Exception as exc:  # noqa: BLE001 - sin pantalla
            self.skipTest(f"Tk no disponible: {exc}")
        try:
            app.update()
            for name in PRESETS:
                app.preset_var.set(name)
                app._load_preset()
                app._preview()
                app.update()
                cfg = app._collect()
                self.assertEqual(_norm(cfg.to_dict()), _norm(PRESETS[name]().to_dict()), msg=name)
        finally:
            app.destroy()


if __name__ == "__main__":
    unittest.main()
