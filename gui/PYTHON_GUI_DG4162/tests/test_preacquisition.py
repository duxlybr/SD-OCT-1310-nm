from __future__ import annotations

import tempfile
import time
import tkinter as tk
import unittest
from dataclasses import replace
from pathlib import Path
from tkinter import ttk
from unittest.mock import patch

from octoce.config import AcquisitionMode, ConfigurationError, HardwareConfig, ScanPattern
from octoce.engine import EngineEvent
from octoce.preacquisition import SYNC_POINTS, alines_for_window, plan_preacquisition
from octoce.storage import read_info
from octoce.widgets import disable_combobox_wheel

from test_dg4162 import fake_controller


class PlanTests(unittest.TestCase):
    def test_alines_are_window_over_lateral_resolution(self) -> None:
        self.assertEqual(alines_for_window(15.0), 750)
        self.assertEqual(alines_for_window(10.0), 500)
        self.assertEqual(alines_for_window(0.1), 5)
        self.assertEqual(alines_for_window(14.1), 705)

    def test_window_inside_limits_is_kept_and_isotropic(self) -> None:
        plan = plan_preacquisition(10.0, 8.0, 0.0, 0.0, HardwareConfig())
        scan = plan.scan
        self.assertFalse(plan.reduced)
        self.assertEqual((scan.alines, scan.bscans, scan.m_repetitions), (500, 400, 1))
        self.assertEqual((scan.x_length_mm, scan.y_length_mm), (10.0, 8.0))
        self.assertIs(scan.mode, AcquisitionMode.BM)
        self.assertIs(scan.pattern, ScanPattern.RASTER)
        self.assertEqual(scan.sync_points, SYNC_POINTS)
        self.assertFalse(plan.hardware.oce_enabled)  # no PFI13: the DG4162 never fires

    def test_default_15_mm_is_reduced_to_the_largest_valid_window(self) -> None:
        hardware = HardwareConfig()
        plan = plan_preacquisition(15.0, 15.0, 0.0, 0.0, hardware)
        scan = plan.scan
        self.assertTrue(plan.reduced)
        # LSM04 FOV (14.1 mm) in X; GVS002 −3° row (beam diameter unknown) in Y.
        self.assertEqual((scan.x_length_mm, scan.alines), (14.1, 705))
        self.assertEqual((scan.y_length_mm, scan.bscans), (11.8, 590))
        plan.hardware.validate(scan)
        # One more 20 µm step on either axis would not be valid.
        for x, y in ((14.12, 11.8), (14.1, 11.82)):
            with self.assertRaises(ConfigurationError):
                plan.hardware.validate(replace(scan, x_length_mm=x, y_length_mm=y))
        self.assertIn("reducido", plan.describe())
        self.assertEqual(plan.header()["requested_window_mm"], [15.0, 15.0])
        self.assertEqual(plan.header()["window_mm"], [14.1, 11.8])

    def test_offset_reduces_the_window_around_the_center(self) -> None:
        plan = plan_preacquisition(15.0, 15.0, 1.0, 0.5, HardwareConfig())
        self.assertEqual((plan.scan.center_x_mm, plan.scan.center_y_mm), (1.0, 0.5))
        self.assertEqual(plan.scan.x_length_mm, 12.1)  # 7.05 − 1 on each side
        plan.hardware.validate(plan.scan)

    def test_invalid_window_is_rejected(self) -> None:
        for value in (0.0, -1.0, float("nan")):
            with self.assertRaises(ConfigurationError):
                plan_preacquisition(value, 10.0, 0.0, 0.0, HardwareConfig())


class ComboboxWheelTests(unittest.TestCase):
    def test_wheel_does_not_change_a_combobox(self) -> None:
        root = tk.Tk()
        self.addCleanup(root.destroy)
        variable = tk.StringVar(value="B")
        combo = ttk.Combobox(root, textvariable=variable, values=["A", "B", "C"], state="readonly")
        combo.pack()
        root.update()
        combo.event_generate("<MouseWheel>", delta=-120)  # Tk default: next value
        root.update()
        self.assertEqual(variable.get(), "C")
        disable_combobox_wheel(root)
        for delta in (-120, 120, -360):
            combo.event_generate("<MouseWheel>", delta=delta)
            root.update()
        self.assertEqual(variable.get(), "C")
        self.assertEqual(root.bind_class("TCombobox", "<MouseWheel>"), "")


class PreacquisitionGuiTests(unittest.TestCase):
    def setUp(self) -> None:
        warning = patch("octoce.gui.messagebox.askyesno", return_value=True)
        warning.start()
        self.addCleanup(warning.stop)
        from octoce.gui_dg4162 import OCTOCEDG4162App
        from test_gui_usb import _FakeStream

        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name)
        self.root = tk.Tk()
        self.controller, self.instrument = fake_controller()
        self.app = OCTOCEDG4162App(
            self.root, usb_stream=_FakeStream(), generator=self.controller, auto_connect=False,
            base_path=self.folder / "dg4162_base.json",
        )
        app = self.app
        app.backend_var.set("Simulación")
        app.save_var.set(True)
        app.folder_var.set(str(self.folder))
        app.mode_var.set("MB-mode  (B → A → M)")
        app.pattern_var.set("Lineal")
        app.alines_var.set("4")
        app.bscans_var.set("1")
        app.repetitions_var.set("3")
        app.sync_var.set("2")
        app.ch1_mvpp_var.set("300")
        app.ch2_freq_var.set("2000")
        app.preacq_x_var.set("0.1")  # 5 A-lines × 5 B-scans keeps the simulation fast
        app.preacq_y_var.set("0.1")
        self.controller.connect()
        app._link_changed(True)

    def tearDown(self) -> None:
        try:
            alive = bool(self.root.winfo_exists())
        except tk.TclError:
            alive = False
        if alive:
            self.app._on_close()
        self.tmp.cleanup()

    def pump(self, condition, timeout: float = 30.0) -> None:
        deadline = time.monotonic() + timeout
        while not condition() and time.monotonic() < deadline:
            self.root.update()
            time.sleep(0.01)
        self.assertTrue(condition(), "timeout esperando a la GUI")

    def idle(self) -> bool:
        app = self.app
        return (not app.engine.is_active and app._preacq_after is None and app._run_kind is None
                and app.event_queue.empty())

    def test_enabled_by_default_with_15_mm_window(self) -> None:
        from octoce.preacquisition import DEFAULT_WINDOW_MM

        app = self.app
        self.assertTrue(app.preacq_enabled_var.get())
        self.assertEqual(DEFAULT_WINDOW_MM, 15.0)
        app.preacq_x_var.set("15")
        app.preacq_y_var.set("15")
        self.assertIn("705 A-lines × 590 B-scans", app.preacq_info_var.get())
        self.assertIn("Reducida", app.preacq_info_var.get())
        app.preacq_enabled_var.set(False)
        self.assertIn("Desactivada", app.preacq_info_var.get())
        # The wheel never changes the drop-down lists of the panel.
        self.assertEqual(self.root.bind_class("TCombobox", "<MouseWheel>"), "")

    def test_mb_acquisition_saves_raster_first_without_excitation(self) -> None:
        app = self.app
        excitations = []
        original = self.controller.start_excitation
        self.controller.start_excitation = lambda: (excitations.append(app._preacq_active), original())[1]
        with patch("octoce.gui.messagebox.showerror") as error, \
                patch("octoce.gui_dg4162.messagebox.showerror") as error2:
            self.assertTrue(app._start())
            self.pump(lambda: (self.folder / "OCE_4A_1B_3M_2SS_300mVpp_2000Hz.bin").exists() and self.idle())
            error.assert_not_called()
            error2.assert_not_called()
        stem = "OCE_4A_1B_3M_2SS_300mVpp_2000Hz"
        self.assertEqual(sorted(p.name for p in self.folder.glob("*.bin")),
                         [f"{stem}.bin", f"{stem}_preraster.bin"])
        pre = read_info(self.folder / f"{stem}_preraster.bin").header
        self.assertEqual((pre["scan"]["mode"], pre["scan"]["pattern"]), ("BM", "raster"))
        self.assertEqual((pre["scan"]["alines"], pre["scan"]["bscans"], pre["scan"]["m_repetitions"]),
                         (5, 5, 1))
        self.assertIn("preacquisition", pre)
        self.assertNotIn("generator", pre)
        self.assertFalse(pre["hardware"]["oce_enabled"])
        real = read_info(self.folder / f"{stem}.bin").header
        self.assertEqual(real["scan"]["mode"], "MB")
        self.assertIn("generator", real)
        self.assertTrue(excitations)
        self.assertFalse(any(excitations))  # OUTPUT1 only for the MB acquisition
        self.assertEqual(self.instrument.state[":OUTP1"], "OFF")

    def test_bm_or_disabled_skips_the_preacquisition(self) -> None:
        app = self.app
        for setup in ({"mode": "BM-mode  (B → M → A)"}, {"enabled": False}):
            app.mode_var.set(setup.get("mode", "MB-mode  (B → A → M)"))
            app.preacq_enabled_var.set(setup.get("enabled", True))
            with patch.object(app.engine, "start") as start:
                self.assertTrue(app._start())
            start.assert_called_once()
            self.assertNotIn("preraster", start.call_args.kwargs["output_path"].name)
            self.assertEqual(start.call_args.args[0].mode.name, app.mode_var.get()[:2])
            app._handle_event(EngineEvent("state", {"state": "completed"}))
            app._run_kind = None

    def fake_engine(self, outcomes: list[str]):
        calls: list[tuple[str, Path]] = []

        def start(scan, hardware, *, output_path=None, backend=None, continuous=False):
            calls.append((scan.mode.value, Path(output_path)))
            self.app.engine.header_metadata = None
            hook, self.app.engine.before_acquire = self.app.engine.before_acquire, None
            if hook is not None:
                hook()
            Path(output_path).write_bytes(b"x")
            state = outcomes[min(len(calls) - 1, len(outcomes) - 1)]
            self.app.event_queue.put(EngineEvent("state", {"state": state, "reason": "simulado"}))

        return start, calls

    def test_stopped_preacquisition_does_not_start_the_mb_acquisition(self) -> None:
        app = self.app
        start, calls = self.fake_engine(["stopped"])
        with patch.object(app.engine, "start", side_effect=start):
            self.assertTrue(app._start())
            self.pump(self.idle)
            for _ in range(30):
                self.root.update()
                time.sleep(0.01)
        self.assertEqual([mode for mode, _path in calls], ["BM"])
        self.assertEqual(self.instrument.state[":OUTP1"], "OFF")

    def test_failed_preacquisition_is_retried_then_mb_runs_once(self) -> None:
        app = self.app
        start, calls = self.fake_engine(["error", "completed", "completed"])
        with patch("octoce.gui_dg4162.RETRY_DELAY_MS", 10), \
                patch.object(app.engine, "start", side_effect=start):
            self.assertTrue(app._start())
            self.pump(lambda: len(calls) == 3 and self.idle())
        self.assertEqual([mode for mode, _path in calls], ["BM", "BM", "MB"])
        self.assertEqual(calls[0][1], calls[1][1])  # the failed raster was deleted and redone
        self.assertEqual(sorted(p.name for p in self.folder.glob("*.bin")),
                         sorted({calls[0][1].name, calls[2][1].name}))

    def test_stop_between_raster_and_mb_cancels_the_mb_acquisition(self) -> None:
        app = self.app
        start, calls = self.fake_engine(["completed"])
        with patch("octoce.gui_dg4162.PREACQ_CHAIN_DELAY_MS", 5000), \
                patch.object(app.engine, "start", side_effect=start):
            self.assertTrue(app._start())
            self.pump(lambda: app._preacq_after is not None)
            app._stop()
            self.root.update()
        self.assertIsNone(app._preacq_after)
        self.assertEqual([mode for mode, _path in calls], ["BM"])

    def test_high_voltage_is_confirmed_once_before_the_raster(self) -> None:
        app = self.app
        app.excitation_var.set("Con contacto")
        app.ch1_mvpp_var.set("1500")
        start, calls = self.fake_engine(["completed"])
        with patch("octoce.gui_dg4162.messagebox.askyesno", return_value=True) as ask, \
                patch.object(app.engine, "start", side_effect=start):
            self.assertTrue(app._start())
            self.assertEqual(len(calls), 1)  # the raster runs after the confirmation
            self.pump(lambda: len(calls) == 2 and self.idle())
        titles = [call.args[0] for call in ask.call_args_list]
        self.assertEqual(sum("CH1" in title for title in titles), 1)
        self.assertEqual(sum("simulación" in title.lower() for title in titles), 1)
        self.assertEqual([mode for mode, _path in calls], ["BM", "MB"])

    def test_excel_sequence_saves_one_raster_at_the_start(self) -> None:
        from openpyxl import Workbook
        from octoce.sequence import COLUMN_KEYS

        app = self.app
        path = self.folder / "serie.xlsx"
        workbook = Workbook()
        sheet = workbook.active
        sheet.append(list(COLUMN_KEYS))
        blank = {key: None for key in COLUMN_KEYS}
        sheet.append(list({**blank, "ch1_mVpp": 200, "ch2_frecuencia_Hz": 1000,
                           "repeticiones": 2, "espera_s": 0.1}.values()))
        sheet.append(list({**blank, "ch1_mVpp": 400, "nombre_archivo": "final"}.values()))
        workbook.save(path)
        app._open_sequence()
        window = app._sequence_window
        window.path_var.set(str(path))
        window.load()
        self.assertEqual(len(app._sequence_jobs), 3)
        with patch("octoce.gui_dg4162.messagebox.askyesno", return_value=True), \
                patch("octoce.gui.messagebox.showerror") as error:
            app._start_sequence()
            self.pump(lambda: not app._sequence_active, timeout=60.0)
            error.assert_not_called()
        names = sorted(p.name for p in self.folder.glob("*.bin"))
        self.assertEqual(names, [
            "OCE_4A_1B_3M_2SS_200mVpp_1000Hz.bin",
            "OCE_4A_1B_3M_2SS_200mVpp_1000Hz_1.bin",
            "OCE_4A_1B_3M_2SS_200mVpp_1000Hz_preraster.bin",
            "final.bin",
        ])
        self.assertIn("completa", window.status_var.get())
        self.assertEqual(self.instrument.state[":OUTP1"], "OFF")

        # A new series saves its own raster again.
        app._start_sequence()
        self.pump(lambda: not app._sequence_active, timeout=60.0)
        self.assertEqual(len(list(self.folder.glob("*_preraster*.bin"))), 2)


if __name__ == "__main__":
    unittest.main()
