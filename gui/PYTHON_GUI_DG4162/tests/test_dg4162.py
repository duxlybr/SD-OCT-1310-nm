from __future__ import annotations

import json
import os
import re
import tempfile
import time
import tkinter as tk
import unittest
from pathlib import Path
from unittest.mock import patch

from octoce.config import AcquisitionMode, ScanPattern
from octoce.engine import EngineEvent, EngineState
from octoce.dg4162 import (
    DG4162Controller,
    DG4162Error,
    Excitation,
    GeneratorSettings,
    check_ch1_vpp,
)
from octoce.naming import clean_stem, default_stem, unique_path
from octoce.sequence import build_jobs, read_rows, write_template


# Instrument registers for the default base configuration (BaseSetup()).
BASE_REGISTERS: dict[str, object] = {
    ":OUTP1": "OFF", ":OUTP2": "OFF", ":OUTP1:IMP": "50", ":OUTP2:IMP": "INFINITY",
    ":SOUR1:FUNC": "SIN", ":SOUR1:FREQ": 954900.0, ":SOUR1:VOLT": 0.5,
    ":SOUR1:VOLT:UNIT": "VPP", ":SOUR1:VOLT:OFFS": -0.0007, ":SOUR1:MOD": "ON",
    ":SOUR1:MOD:TYP": "AM", ":SOUR1:MOD:AM:SOUR": "EXT", ":SOUR1:MOD:AM:DEPT": 100.0,
    ":SOUR1:BURS": "OFF",
    ":SOUR2:FUNC": "PULSE", ":SOUR2:FREQ": 1000.0, ":SOUR2:VOLT": 1.0,
    ":SOUR2:VOLT:OFFS": 0.452, ":SOUR2:MOD": "OFF", ":SOUR2:PULS:DCYC": 50.0,
    ":SOUR2:BURS": "ON", ":SOUR2:BURS:MODE": "TRIG",
    ":SOUR2:BURS:NCYC": 1.0, ":SOUR2:BURS:TRIG:SOUR": "EXT", ":SOUR2:BURS:TRIG:SLOP": "POS",
    ":SOUR2:BURS:TDEL": 0.002,
}
# Power-on (factory) configuration observed on the instrument.
FACTORY = {
    **BASE_REGISTERS, ":OUTP1:IMP": "INFINITY", ":SOUR1:FREQ": 1000.0, ":SOUR1:VOLT": 5.0,
    ":SOUR1:VOLT:OFFS": 0.0, ":SOUR1:MOD": "OFF", ":SOUR1:MOD:AM:SOUR": "INT",
    ":SOUR2:FUNC": "SIN",
    ":SOUR2:FREQ": 1000.0, ":SOUR2:VOLT": 5.0, ":SOUR2:VOLT:OFFS": 0.0, ":SOUR2:BURS": "OFF",
    ":SOUR2:BURS:TRIG:SOUR": "INT", ":SOUR2:BURS:TDEL": 0.0,
}


class FakeDG4162:
    """PyVISA-like resource with the default configuration and the :OUTPn? blank line."""

    def __init__(self) -> None:
        self.timeout = 0
        self.read_termination = None
        self.write_termination = None
        self.pending: list[str] = []
        self.errors: list[str] = []
        self.writes: list[str] = []
        self.closed = False
        self.alive = True  # False = generator switched off (every I/O times out)
        self.output1_stuck = False  # True = ":OUTP1 OFF" has no effect (fault injection)
        self.state: dict[str, object] = dict(BASE_REGISTERS)

    def write(self, command: str) -> None:
        if not self.alive:
            raise OSError("VI_ERROR_TMO (-1073807339): Timeout expired before operation completed.")
        self.writes.append(command)
        if command.endswith("?"):
            self._answer(command)
            return
        header, _, value = command.partition(" ")
        if header == ":OUTP1" and value == "OFF" and self.output1_stuck:
            return
        if header not in self.state:
            self.errors.append('-113,"Undefined header; keyword cannot be found"')
            return
        if header == ":SOUR2:FUNC":
            value = {"PULS": "PULSE"}.get(value, value)
        if header.endswith(":IMP") and value == "INF":
            value = "INFINITY"
        self.state[header] = float(value) if isinstance(self.state[header], float) else value

    def _answer(self, command: str) -> None:
        if command == "*IDN?":
            self.pending.append("Rigol Technologies,DG4162,DG4E253001553,00.01.14")
        elif command == ":SYST:ERR?":
            self.pending.append(self.errors.pop(0) if self.errors else '0,"No error"')
        else:
            key = command[:-1]
            value = self.state[key]
            self.pending.append(f"{value:.6E}" if isinstance(value, float) else str(value))
            if re.fullmatch(r":OUTP\d", key):
                self.pending.append("")  # firmware 00.01.14 sends an extra blank line

    def read(self) -> str:
        if not self.pending:
            raise TimeoutError("VI_ERROR_TMO")
        return self.pending.pop(0)

    def read_raw(self) -> bytes:
        return (self.read() + "\n").encode()

    def query(self, command: str) -> str:
        self.write(command)
        return self.read()

    def clear(self) -> None:
        self.pending.clear()

    def close(self) -> None:
        self.closed = True

    @property
    def setting_writes(self) -> list[str]:
        return [w for w in self.writes if not w.endswith("?")]


class FakeResourceManager:
    RESOURCE = "USB0::0x1AB1::0x0641::DG4E253001553::INSTR"

    def __init__(self, instrument: FakeDG4162) -> None:
        self.instrument = instrument
        self.present = True  # False = USB device not enumerated (powered off)

    def list_resources(self) -> tuple[str, ...]:
        return (self.RESOURCE,) if self.present else ()

    def open_resource(self, _resource: str) -> FakeDG4162:
        if not self.present:
            raise OSError("VI_ERROR_RSRC_NFOUND: Insufficient location information.")
        self.instrument.closed = False
        self.instrument.pending.clear()
        return self.instrument


def fake_controller() -> tuple[DG4162Controller, FakeDG4162]:
    instrument = FakeDG4162()
    return DG4162Controller(resource_manager=FakeResourceManager(instrument)), instrument


class ControllerTests(unittest.TestCase):
    def test_reads_state_without_writing_and_survives_blank_line_quirk(self) -> None:
        controller, instrument = fake_controller()
        self.assertIn("DG4162", controller.connect())
        state = controller.read_state()
        self.assertEqual(instrument.setting_writes, [])
        self.assertFalse(state.output1)
        self.assertFalse(state.output2)
        self.assertEqual(state.ch1_function, "SIN")
        self.assertAlmostEqual(state.ch1_vpp, 0.5)
        self.assertEqual(state.ch1_am_source, "EXT")
        self.assertEqual(state.ch2_function, "PULS")
        self.assertAlmostEqual(state.ch2_frequency_hz, 1000.0)
        self.assertAlmostEqual(state.ch2_delay_ms, 2.0)
        self.assertEqual(state.ch2_burst_cycles, 1)
        self.assertTrue(state.ch2_burst)

    def test_apply_programs_verifies_and_keeps_output1_off(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        state = controller.apply(GeneratorSettings(0.3, 1500.0, "Cuadrada", 3.0))
        self.assertFalse(state.output1)
        self.assertAlmostEqual(state.ch1_vpp, 0.3)
        self.assertEqual(state.ch2_function, "SQU")
        self.assertAlmostEqual(state.ch2_frequency_hz, 1500.0)
        self.assertAlmostEqual(state.ch2_delay_ms, 3.0)
        self.assertEqual(instrument.setting_writes[0], ":OUTP1 OFF")
        self.assertIn(":SOUR2:BURS:TDEL 0.003", instrument.setting_writes)

    def test_excitation_toggles_output1_and_keeps_output2_on(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        controller.start_excitation()
        self.assertEqual((instrument.state[":OUTP1"], instrument.state[":OUTP2"]), ("ON", "ON"))
        controller.stop_excitation()
        self.assertEqual((instrument.state[":OUTP1"], instrument.state[":OUTP2"]), ("OFF", "ON"))

    def test_voltage_above_limit_is_refused_before_any_write(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        with self.assertRaises(ValueError):
            controller.apply(GeneratorSettings(1.2, 2000.0))
        with self.assertRaises(ValueError):
            controller.set_ch1_vpp(5.5, limit_vpp=5.0)
        self.assertEqual(instrument.setting_writes, [])
        self.assertAlmostEqual(instrument.state[":SOUR1:VOLT"], 0.5)

    def test_instrument_error_is_raised(self) -> None:
        controller, _instrument = fake_controller()
        controller.connect()
        with self.assertRaisesRegex(DG4162Error, "Undefined header"):
            controller.write(":SOUR2:INVALID 1")

    def test_close_turns_outputs_off_and_leaves_base_configuration(self) -> None:
        from octoce.dg4162 import BaseSetup

        controller, instrument = fake_controller()
        controller.connect()
        controller.apply(GeneratorSettings(0.3, 1500.0, "Gaussiana", 2.0))
        controller.start_excitation()
        self.assertEqual(controller.close(base=BaseSetup()), [])
        self.assertEqual(instrument.state, {**BASE_REGISTERS, ":OUTP2": "ON"})  # base configuration, OUTPUT2 kept on
        self.assertFalse(controller.connected)
        self.assertTrue(instrument.closed)
        self.assertFalse(controller.connected)

    def test_disconnect_sends_nothing(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        controller.disconnect()
        self.assertEqual(instrument.setting_writes, [])
        self.assertTrue(instrument.closed)

    def test_ensure_base_corrects_factory_state_to_defaults(self) -> None:
        from octoce.dg4162 import BaseSetup

        controller, instrument = fake_controller()
        instrument.state = dict(FACTORY)
        controller.connect()
        corrections = controller.ensure_base(BaseSetup())
        labels = " | ".join(corrections)
        for expected in ("CH1 carga", "CH1 frecuencia", "CH1 offset", "CH1 fuente AM", "CH1 AM activa",
                         "CH2 amplitud", "CH2 offset", "CH2 disparo burst", "CH2 burst activo"):
            self.assertIn(expected, labels)
        controller.apply(BaseSetup().default_settings())
        self.assertEqual(instrument.state, BASE_REGISTERS)
        self.assertEqual(controller.ensure_base(BaseSetup()), [])  # nothing left to correct

    def test_ch1_am_is_always_on_with_external_source(self) -> None:
        from octoce.dg4162 import BaseSetup

        controller, instrument = fake_controller()
        instrument.state[":SOUR1:MOD"] = "OFF"  # e.g. modulation switched off on the panel
        instrument.state[":SOUR1:MOD:AM:SOUR"] = "INT"
        controller.connect()
        corrections = controller.ensure_base(BaseSetup())
        self.assertIn("CH1 fuente AM: INT → EXT", corrections)
        self.assertIn("CH1 AM activa: OFF → ON", corrections)
        self.assertEqual((instrument.state[":SOUR1:MOD"], instrument.state[":SOUR1:MOD:AM:SOUR"]), ("ON", "EXT"))

    def test_ch2_burst_cycles_are_set_per_acquisition(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        state = controller.apply(GeneratorSettings(0.5, 1000.0, "Pulso", 2.0, ch2_burst_cycles=5))
        self.assertEqual(state.ch2_burst_cycles, 5)
        self.assertAlmostEqual(instrument.state[":SOUR2:BURS:NCYC"], 5.0)
        with self.assertRaises(ValueError):
            GeneratorSettings(0.5, 1000.0, ch2_burst_cycles=0).validate()

    def test_read_base_of_default_configuration(self) -> None:
        from octoce.dg4162 import BaseSetup

        controller, _instrument = fake_controller()
        controller.connect()
        self.assertEqual(controller.read_base(), BaseSetup())
        self.assertEqual(controller.ensure_base(BaseSetup()), [])  # a matching instrument is left untouched

    def test_infinite_load_is_not_taken_as_50_ohm(self) -> None:
        from octoce.dg4162 import BaseSetup

        controller, instrument = fake_controller()
        instrument.state[":OUTP1:IMP"] = "INFINITY"
        controller.connect()
        self.assertIn("CH1 carga: INFINITY → 50", controller.ensure_base(BaseSetup()))

    def test_base_setup_defaults_save_and_validation(self) -> None:
        from octoce.dg4162 import BaseSetup

        base = BaseSetup()
        self.assertEqual((base.ch1_frequency_hz, base.ch1_offset_v, base.am_depth_percent, base.ch2_vpp,
                          base.ch2_offset_v, base.burst_cycles, base.ch1_vpp, base.ch2_waveform,
                          base.ch2_frequency_hz, base.ch2_delay_ms),
                         (954900.0, -0.0007, 100.0, 1.0, 0.452, 1, 0.5, "PULS", 1000.0, 2.0))
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "dg4162_base.json"
            self.assertEqual(BaseSetup.load(path), base)  # no file: defaults
            custom = BaseSetup(ch1_frequency_hz=1_000_000.0, ch2_vpp=2.0)
            custom.save(path)
            self.assertEqual(BaseSetup.load(path), custom)
        from dataclasses import replace
        for bad in (dict(ch2_vpp=2.0, ch2_offset_v=9.5), dict(ch1_vpp=1.5), dict(burst_cycles=0),
                    dict(ch1_frequency_hz=0.0), dict(ch1_offset_v=2.0), dict(am_depth_percent=150.0)):
            with self.assertRaises(ValueError):
                replace(base, **bad).validate()

    def test_unchanged_values_are_not_rewritten(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        controller.apply(GeneratorSettings(0.5, 1000.0, "Pulso", 2.0))
        self.assertEqual(instrument.setting_writes, [":OUTP1 OFF"])

    def test_waveform_list_starts_with_pulse_and_gaussian(self) -> None:
        from octoce.dg4162 import CH2_WAVEFORMS, waveform_label, waveform_scpi

        self.assertEqual(list(CH2_WAVEFORMS)[:2], ["Pulso", "Gaussiana"])
        self.assertEqual(waveform_scpi("Gaussiana"), "GAUSS")
        self.assertEqual(waveform_label("GAUSSPULSE"), "Pulso gaussiano")
        self.assertEqual(waveform_label("PULSE"), "Pulso")

    def test_lost_session_is_closed_and_probe_reconnects(self) -> None:
        controller, instrument = fake_controller()
        manager = controller._rm
        self.assertTrue(controller.probe())  # first probe connects
        instrument.alive = False  # generator switched off with the session open
        started = time.monotonic()
        with self.assertRaisesRegex(DG4162Error, "Comunicación perdida"):
            controller.read_state()
        self.assertFalse(controller.connected)  # dead session released, no retries
        with self.assertRaisesRegex(DG4162Error, "no conectado"):
            controller.set_output(1, False)  # fails at once instead of timing out
        self.assertLess(time.monotonic() - started, 1.0)
        manager.present = False
        self.assertFalse(controller.probe())
        manager.present = True
        instrument.alive = True  # switched back on
        self.assertTrue(controller.probe())
        self.assertTrue(controller.connected)

    def test_parameters_only_change_with_output1_off(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        events = []
        controller.on_safety = events.append
        controller.set_output(1, True)
        instrument.writes.clear()
        controller.set_ch2_frequency(1500.0)  # any parameter write, called directly
        self.assertEqual(instrument.setting_writes, [":OUTP1 OFF", ":SOUR2:FREQ 1500"])
        self.assertEqual(instrument.state[":OUTP1"], "OFF")
        self.assertEqual(len(events), 1)
        self.assertIn("OUTPUT1", events[0])
        controller.set_output(1, True)  # switching outputs is not a parameter change
        self.assertEqual(instrument.state[":OUTP1"], "ON")
        self.assertEqual(len(events), 1)

    def test_parameter_write_refused_if_output1_does_not_switch_off(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        controller.set_output(1, True)
        instrument.output1_stuck = True
        with self.assertRaisesRegex(DG4162Error, "OUTPUT1 no se apagó"):
            controller.write(":SOUR1:VOLT 0.8")
        self.assertAlmostEqual(instrument.state[":SOUR1:VOLT"], 0.5)  # not changed

    def test_output1_refuses_amplitude_above_limit(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        instrument.state[":SOUR1:VOLT"] = 5.0  # power-on default of the instrument
        with self.assertRaisesRegex(DG4162Error, "OUTPUT1 no se enciende"):
            controller.start_excitation()
        self.assertEqual(instrument.state[":OUTP1"], "OFF")
        controller.output1_limit_vpp = 5.0  # contact mode, confirmed by the user
        controller.start_excitation()
        self.assertEqual(instrument.state[":OUTP1"], "ON")

    def test_output2_is_switched_back_on(self) -> None:
        controller, instrument = fake_controller()
        controller.connect()
        events = []
        controller.on_safety = events.append
        self.assertTrue(controller.ensure_output2_on())
        self.assertEqual(instrument.state[":OUTP2"], "ON")
        self.assertFalse(controller.ensure_output2_on())
        self.assertEqual(len(events), 1)

    def test_voltage_policy(self) -> None:
        self.assertFalse(check_ch1_vpp(1.0, Excitation.NON_CONTACT))
        with self.assertRaises(ValueError):
            check_ch1_vpp(1.001, Excitation.NON_CONTACT)
        self.assertFalse(check_ch1_vpp(0.8, Excitation.CONTACT))
        self.assertTrue(check_ch1_vpp(2.0, Excitation.CONTACT))
        self.assertTrue(check_ch1_vpp(5.0, Excitation.CONTACT))
        with self.assertRaises(ValueError):
            check_ch1_vpp(5.01, Excitation.CONTACT)
        with self.assertRaises(ValueError):
            check_ch1_vpp(0.0, Excitation.CONTACT)


class NamingTests(unittest.TestCase):
    def test_default_name_format(self) -> None:
        self.assertEqual(
            default_stem(AcquisitionMode.MB, 100, 100, 400, 200, ch1_vpp=0.3, ch2_frequency_hz=2000),
            "OCE_100A_100B_400M_200SS_300mVpp_2000Hz",
        )
        self.assertEqual(default_stem(AcquisitionMode.BM, 512, 64, 1, 50), "OCT_512A_64B_1M_50SS")
        self.assertEqual(
            default_stem(AcquisitionMode.MB, 1, 1, 1, 0, ch1_vpp=0.3505, ch2_frequency_hz=2.5),
            "OCE_1A_1B_1M_0SS_350p5mVpp_2p5Hz",
        )

    def test_unique_suffixes_never_overwrite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.assertEqual(unique_path(folder, "x").name, "x.bin")
            (folder / "x.bin").touch()
            self.assertEqual(unique_path(folder, "x").name, "x_1.bin")
            (folder / "x_1.bin").touch()
            self.assertEqual(unique_path(folder, "x").name, "x_2.bin")
            self.assertEqual(unique_path(folder, "x", taken={folder / "x_2.bin"}).name, "x_3.bin")

    def test_clean_stem(self) -> None:
        self.assertEqual(clean_stem("  muestra.bin "), "muestra")
        self.assertEqual(clean_stem(""), "")
        for bad in ("a/b", "a:b", "CON", "fin."):
            with self.assertRaises(ValueError):
                clean_stem(bad)


DEFAULTS = {
    "modo": "OCT", "patron": "Raster", "orientacion": "Horizontal", "a_lines": "512",
    "b_scans": "64", "m_reps": "1", "sync_samples": "50", "longitud_x_mm": "5",
    "longitud_y_mm": "5", "bframes_delay_us": "0", "excitacion": "Sin contacto",
    "ch1_mVpp": "500", "ch2_frecuencia_Hz": "2000", "ch2_forma_onda": "Pulso", "ch2_retardo_ms": "2",
    "ch2_ciclos": "1",
}


class SequenceTests(unittest.TestCase):
    def test_template_round_trip_expands_repetitions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = write_template(Path(directory) / "plantilla.xlsx")
            jobs, errors = build_jobs(read_rows(path), DEFAULTS)
        self.assertEqual(errors, [])
        self.assertEqual(len(jobs), 5)  # 3 + 1 + 1
        first = jobs[0]
        self.assertEqual((first.row, first.repetition, first.repetitions), (2, 1, 3))
        self.assertIs(first.mode, AcquisitionMode.MB)
        self.assertIs(first.pattern, ScanPattern.LINEAR)
        self.assertAlmostEqual(first.generator.ch1_vpp, 0.3)
        self.assertEqual(first.generator.ch2_waveform, "PULS")
        self.assertEqual(first.wait_s, 10.0)
        self.assertEqual(jobs[-1].name, "referencia_OCT")

    def test_blank_cells_use_gui_values_and_all_errors_are_reported(self) -> None:
        rows = [
            (2, {"modo": "OCE", "a_lines": 10}),
            (3, {"ch1_mVpp": 1500}),
            (4, {"excitacion": "Con contacto", "ch1_mVpp": 6000, "repeticiones": 0}),
            (5, {"excitacion": "Con contacto", "ch1_mVpp": 2500, "ch2_forma_onda": "Diente de sierra"}),
        ]
        jobs, errors = build_jobs(rows, DEFAULTS)
        self.assertEqual(len(jobs), 1)
        self.assertEqual((jobs[0].alines, jobs[0].bscans, jobs[0].mode), (10, 64, AcquisitionMode.MB))
        self.assertEqual(len(errors), 3)
        self.assertTrue(errors[0].startswith("Fila 3") and "1 Vpp" in errors[0])
        self.assertIn("5 Vpp", errors[1])
        self.assertIn("repeticiones", errors[1])
        self.assertIn("Diente de sierra", errors[2])

    def test_unknown_column_is_rejected(self) -> None:
        from openpyxl import Workbook

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "s.xlsx"
            workbook = Workbook()
            workbook.active.append(["modo", "voltaje"])
            workbook.active.append(["OCE", 1])
            workbook.save(path)
            with self.assertRaisesRegex(ValueError, "voltaje"):
                read_rows(path)


@unittest.skipUnless(os.name == "nt", "Smoke visual de Tkinter para Windows")
class DG4162GuiTests(unittest.TestCase):
    def setUp(self) -> None:
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
        self.controller.connect()
        app._link_changed(True)

    def tearDown(self) -> None:
        if self.root.winfo_exists():
            self.app._on_close()
        self.tmp.cleanup()

    def pump(self, condition, timeout: float = 20.0) -> None:
        deadline = time.monotonic() + timeout
        while not condition() and time.monotonic() < deadline:
            self.root.update()
            time.sleep(0.01)
        self.assertTrue(condition(), "timeout esperando a la GUI")

    def test_default_name_suffix_sidecar_and_output1_cycle(self) -> None:
        app = self.app
        self.root.update()
        self.assertIn("OCE_4A_1B_3M_2SS_300mVpp_2000Hz.bin", app.target_var.get())
        seen_on = []
        original = self.controller.start_excitation
        self.controller.start_excitation = lambda: (original(), seen_on.append(
            (self.instrument.state[":OUTP1"], self.instrument.state[":OUTP2"])))
        with patch("octoce.gui.messagebox.showerror") as error:
            self.assertTrue(app._start())
            error.assert_not_called()
        self.pump(lambda: not app.engine.is_active and self.instrument.state[":OUTP1"] == "OFF")
        self.assertTrue(seen_on)
        self.assertTrue(all(pair == ("ON", "ON") for pair in seen_on))
        stem = "OCE_4A_1B_3M_2SS_300mVpp_2000Hz"
        self.assertTrue((self.folder / f"{stem}.bin").exists())
        sidecar = json.loads((self.folder / f"{stem}_dg4162.json").read_text(encoding="utf-8"))
        self.assertAlmostEqual(sidecar["generator_settings"]["ch1_vpp"], 0.3)
        self.assertEqual(self.instrument.state[":OUTP2"], "ON")
        self.assertIn(f"{stem}_1.bin", app.target_var.get())

        app.name_var.set("muestra")
        with patch("octoce.gui.messagebox.showerror") as error:
            self.assertTrue(app._start())
            error.assert_not_called()
        self.pump(lambda: not app.engine.is_active and self.instrument.state[":OUTP1"] == "OFF")
        self.assertTrue((self.folder / "muestra.bin").exists())

    def test_non_contact_blocks_above_1vpp_and_contact_asks(self) -> None:
        app = self.app
        writes_before = list(self.instrument.setting_writes)  # connection setup in setUp
        app.ch1_mvpp_var.set("1500")
        self.assertIn("⛔", app.gen_warning_var.get())
        with patch("octoce.gui_dg4162.messagebox.showerror") as error, patch.object(app.engine, "start") as start:
            self.assertFalse(app._start())
        error.assert_called_once()
        start.assert_not_called()
        app.excitation_var.set("Con contacto")
        self.assertIn("⚠", app.gen_warning_var.get())
        with patch("octoce.gui_dg4162.messagebox.askyesno", return_value=False) as ask, \
                patch.object(app.engine, "start") as start:
            self.assertFalse(app._start())
        ask.assert_called_once()
        start.assert_not_called()
        self.assertEqual(self.instrument.setting_writes, writes_before)  # nothing written

    def fake_engine(self, outcomes: list[str]):
        """engine.start replacement: writes the file and reports the next outcome."""
        calls: list[Path] = []

        def start(scan, hardware, *, output_path=None, backend=None, continuous=False):
            calls.append(Path(output_path))
            hook, self.app.engine.before_acquire = self.app.engine.before_acquire, None
            if hook is not None:
                hook()
            Path(output_path).write_bytes(b"x")
            state = outcomes[min(len(calls) - 1, len(outcomes) - 1)]
            self.app.event_queue.put(EngineEvent("state", {"state": state, "reason": "fallo simulado"}))

        return start, calls

    def test_failed_acquisition_is_deleted_and_retried(self) -> None:
        app = self.app
        start, calls = self.fake_engine(["error", "error", "completed"])
        with patch("octoce.gui_dg4162.RETRY_DELAY_MS", 10), patch.object(app.engine, "start", side_effect=start),                 patch("octoce.gui.messagebox.showerror") as error,                 patch("octoce.gui_dg4162.messagebox.showerror") as error2:
            self.assertTrue(app._start())
            self.pump(lambda: len(calls) == 3 and app._retry_after is None and app.event_queue.empty())
            self.root.update()
        error.assert_not_called()
        error2.assert_not_called()
        self.assertEqual(len(set(calls)), 1)  # same name each time: the failed file was deleted
        self.assertEqual(sorted(p.name for p in self.folder.iterdir()),
                         [calls[0].name, calls[0].stem + "_dg4162.json"])
        self.assertEqual(self.instrument.state[":OUTP1"], "OFF")

    def test_retries_stop_after_three(self) -> None:
        app = self.app
        start, calls = self.fake_engine(["error"])
        with patch("octoce.gui_dg4162.RETRY_DELAY_MS", 10), patch.object(app.engine, "start", side_effect=start),                 patch("octoce.gui.messagebox.showerror"),                 patch("octoce.gui_dg4162.messagebox.showerror") as error:
            app._start()
            self.pump(lambda: error.called)
            self.root.update()
        self.assertEqual(len(calls), 4)  # first attempt + 3 retries
        self.assertEqual(list(self.folder.glob("*.bin")), [])
        self.assertEqual(self.instrument.state[":OUTP1"], "OFF")

    def test_alignment_turns_output1_on_and_off(self) -> None:
        app = self.app
        with patch.object(app.engine, "start") as start:
            app._start_alignment()
        start.assert_called_once()
        self.assertEqual(self.instrument.state[":OUTP1"], "ON")  # on while arming
        self.instrument.state[":OUTP1"] = "OFF"  # e.g. switched off on the front panel
        app.engine.before_acquire()  # the engine verifies it once the hardware is armed
        self.assertEqual(self.instrument.state[":OUTP1"], "ON")
        app._handle_event(EngineEvent("state", {"state": EngineState.STOPPED.value}))
        self.assertEqual(self.instrument.state[":OUTP1"], "OFF")

    def test_camera_view_starts_square(self) -> None:
        app = self.app
        self.pump(lambda: app._square_after is None)
        self.root.update()
        self.assertLessEqual(abs(app.usb_canvas.winfo_width() - app.usb_canvas.winfo_height()), 6)
        app._toggle_fullscreen()  # F11: the camera view is squared again
        self.pump(lambda: app._square_after is None)
        self.root.update()
        self.assertLessEqual(abs(app.usb_canvas.winfo_width() - app.usb_canvas.winfo_height()), 6)
        app._toggle_fullscreen()

    def test_sections_start_expanded_and_collapse(self) -> None:
        app = self.app
        self.root.update()
        for section in (app.plan_section, app.generator_section):
            self.assertTrue(section.expanded)
            self.assertTrue(section.body.winfo_ismapped())
            section.header.invoke()
            self.root.update()
            self.assertFalse(section.body.winfo_ismapped())
            section.header.invoke()
            self.root.update()
            self.assertTrue(section.body.winfo_ismapped())

    def test_lambda_and_dispersion_moved_to_hardware_dialog(self) -> None:
        from tkinter import ttk

        app = self.app

        def entries(widget):
            for child in widget.winfo_children():
                if isinstance(child, ttk.Entry):
                    yield child
                yield from entries(child)

        plan_vars = {str(e.cget("textvariable")) for e in entries(app.plan_section.body)}
        for variable in (app.k_start_var, app.k_end_var, app.d2_var, app.d3_var):
            self.assertNotIn(str(variable), plan_vars)
        app._open_hardware_dialog()
        dialog = next(w for w in self.root.winfo_children()
                      if isinstance(w, tk.Toplevel) and w.title() == "Configuración de hardware")
        first = next(entries(dialog))  # "Inicio λ para k (nm)"
        first.delete(0, "end")
        first.insert(0, "1470.5")
        apply = next(b for b in dialog.winfo_children()[-1].winfo_children() if b.cget("text") == "Aplicar")
        apply.invoke()
        self.assertEqual(app.k_start_var.get(), "1470.5")

    def test_roi_setup_button_opens_setup_and_reconnects_camera(self) -> None:
        app = self.app
        opened = []

        class FakeSetup:
            def __init__(self, window, stream, index, path, *, autosave=False):
                self.result_message = "ROI guardada automáticamente"
                opened.append((window, stream, index, path))
                self.assertTrue(autosave)

            assertTrue = staticmethod(self.assertTrue)

        with patch("octoce.gui_usb.CameraROISetup", FakeSetup):
            app.roi_setup_button.invoke()
        self.assertEqual(len(opened), 1)
        window, stream, index, _path = opened[0]
        self.assertIs(stream, app._usb_stream)
        self.assertEqual(index, int(app.usb_index_var.get()))
        starts = len(stream.started)
        window.destroy()
        self.pump(lambda: len(stream.started) > starts)

    def test_buttons_live_inside_their_sections(self) -> None:
        app = self.app

        def texts(widget):
            for child in widget.winfo_children():
                try:
                    yield child.cget("text")
                except tk.TclError:
                    pass
                yield from texts(child)

        self.assertIn("Configuración de hardware…", list(texts(app.plan_section.body)))
        self.assertIn("Secuencia desde Excel…", list(texts(app.generator_section.body)))
        self.assertNotIn("Recargar calibración ROI", list(texts(app.usb_settings)))

    def test_brightness_range_matches_camera(self) -> None:
        from octoce.gui_usb import _CameraSetupDialog

        stream = self.app._usb_stream
        stream.running = True
        dialog = _CameraSetupDialog(self.root, stream, acquisition=False)
        try:
            self.assertEqual((dialog.brightness_scale.cget("from"), dialog.brightness_scale.cget("to")), (0.0, 255.0))
            dialog.brightness_var.set("-20")
            self.assertFalse(dialog._apply())
            self.assertIn("0 y 255", dialog.readback_var.get())
            dialog.brightness_var.set("40")
            self.assertTrue(dialog._apply())
        finally:
            dialog._close()

    def test_capture_area_full_fov_or_roi(self) -> None:
        import numpy as np
        from octoce.camera_roi import CameraROI

        app = self.app
        app._camera_roi = None
        app.capture_area_var.set("Solo ROI")
        with self.assertRaisesRegex(ValueError, "ROI"):
            app._media_transform()
        app.capture_area_var.set("FOV completo")
        self.assertIsNone(app._media_transform())
        app._camera_roi = CameraROI(0, 640, 480, 20, 320, 240, flip_x=True)
        app.usb_index_var.set("0")
        frame = np.zeros((480, 640, 3), dtype=np.uint8)
        frame[:, :10] = 255  # bright strip on the left edge of the sensor
        full = app._media_transform()(frame)
        self.assertEqual(full.shape, (480, 640, 3))
        self.assertTrue(full[:, -1].all() and not full[:, 0].any())  # mirrored in X
        app.capture_area_var.set("Solo ROI")
        self.assertEqual(app._media_transform()(frame).shape, (300, 300, 3))

    def test_roi_setup_autosaves_flip_and_new_geometry(self) -> None:
        import numpy as np
        from types import SimpleNamespace
        from octoce.camera_roi import CameraROI
        from octoce.camera_roi_setup import CameraROISetup

        path = self.folder / "camera_roi.json"
        CameraROI(0, 640, 480, 20, 320, 240).save(path)
        stream = self.app._usb_stream
        stream.frame = np.zeros((480, 640, 3), dtype=np.uint8)
        window = tk.Toplevel(self.root)
        setup = CameraROISetup(window, stream, 0, path, autosave=True)
        self.root.update()
        setup.flip_y.set(True)
        setup.close()
        saved = CameraROI.load(path)
        self.assertEqual((saved.flip_x, saved.flip_y, saved.center_x), (False, True, 320))
        self.assertIn("Inversión", setup.result_message)

        stream.frame = np.zeros((480, 640, 3), dtype=np.uint8)  # the main view consumed the last one
        window = tk.Toplevel(self.root)
        setup = CameraROISetup(window, stream, 0, path, autosave=True)
        self.assertTrue(setup.flip_y.get())  # starts from the saved ROI
        self.root.update()
        setup.freeze()
        self.root.update()
        ox, oy, scale = setup.transform
        for x, y in ((100, 200), (300, 200)):
            setup.click(SimpleNamespace(x=ox + x * scale, y=oy + y * scale))
        setup.approve_geometry()
        setup.close()
        saved = CameraROI.load(path)
        self.assertAlmostEqual(saved.center_x, 200)
        self.assertAlmostEqual(saved.center_y, 200)
        self.assertTrue(saved.flip_y)
        self.assertIn("automáticamente", setup.result_message)

    def test_without_link_light_is_off_and_generator_actions_are_blocked(self) -> None:
        from octoce.gui_dg4162 import LINK_OFF_COLOR, LINK_ON_COLOR

        app = self.app
        self.assertEqual(app.link_light.itemcget(app.link_light_id, "fill"), LINK_ON_COLOR)
        self.instrument.alive = False
        with patch("octoce.gui_dg4162.messagebox.showerror"):
            app.gen_connect_button.invoke()  # the read fails: the GUI must not hang or crash
        self.assertFalse(self.controller.connected)
        self.assertEqual(app.link_light.itemcget(app.link_light_id, "fill"), LINK_OFF_COLOR)
        for button in (app.gen_connect_button, app.gen_load_button, app.gen_apply_button):
            self.assertEqual(str(button.cget("state")), "disabled")
        with patch("octoce.gui_dg4162.messagebox.showerror") as error, patch.object(app.engine, "start") as start:
            self.assertFalse(app._start())
        start.assert_not_called()
        self.assertIn("Sin comunicación", error.call_args.args[1])
        app.gen_enabled_var.set(False)  # acquisitions without the generator still work
        with patch.object(app.engine, "start") as start:
            self.assertTrue(app._start())
        start.assert_called_once()

    def test_connection_corrects_generator_to_base_configuration(self) -> None:
        app = self.app
        self.controller.disconnect()
        app._link_changed(False)
        self.instrument.state = dict(FACTORY)  # switched on: power-on defaults
        logs = []
        with patch.object(app, "_append_log", side_effect=logs.append):
            self.controller.connect()
            app._link_changed(True)
        self.assertTrue(any("configuración base corregida" in line for line in logs))
        state = self.instrument.state
        self.assertEqual((state[":SOUR1:MOD"], state[":SOUR1:MOD:AM:SOUR"], state[":OUTP1:IMP"]),
                         ("ON", "EXT", "50"))  # CH1: sine with external AM
        self.assertAlmostEqual(state[":SOUR1:FREQ"], 954900.0)
        self.assertAlmostEqual(state[":SOUR1:VOLT:OFFS"], -0.0007)
        self.assertEqual((state[":SOUR2:BURS"], state[":SOUR2:BURS:TRIG:SOUR"]), ("ON", "EXT"))
        self.assertAlmostEqual(state[":SOUR1:VOLT"], 0.3)  # panel value, not the 5 Vpp power-on default
        self.assertEqual((state[":OUTP1"], state[":OUTP2"]), ("OFF", "ON"))

    def test_base_config_dialog_saves_and_reprograms(self) -> None:
        from octoce.gui_dg4162 import _BaseConfigDialog

        app = self.app
        dialog = _BaseConfigDialog(app)
        self.assertEqual(dialog.vars["ch1_frequency_hz"].get(), "954.9")
        self.assertEqual(dialog.vars["ch1_offset_v"].get(), "-0.7")
        self.assertEqual(dialog.vars["ch2_delay_ms"].get(), "2")
        dialog.vars["ch1_frequency_hz"].set("1000")  # kHz
        dialog.vars["ch2_vpp"].set("2")
        dialog.vars["ch2_delay_ms"].set("3")
        dialog.save()
        self.assertTrue((self.folder / "dg4162_base.json").exists())
        self.assertAlmostEqual(app.base_setup.ch1_frequency_hz, 1_000_000.0)
        self.assertAlmostEqual(self.instrument.state[":SOUR1:FREQ"], 1_000_000.0)
        self.assertAlmostEqual(self.instrument.state[":SOUR2:VOLT"], 2.0)
        self.assertEqual(app.ch2_delay_var.get(), "3")
        self.instrument.state[":SOUR1:FREQ"] = 950_000.0  # e.g. another state recalled on the panel
        dialog = _BaseConfigDialog(app)
        dialog.read_button.invoke()
        self.assertEqual(dialog.vars["ch1_frequency_hz"].get(), "950")
        dialog.vars["ch2_offset_v"].set("9.9")  # |offset| + Vpp/2 > 10 V
        with patch("octoce.gui_dg4162.messagebox.showerror") as error:
            dialog.save()
        error.assert_called_once()
        dialog.window.destroy()

    def test_watcher_keeps_output2_on(self) -> None:
        import threading

        app = self.app
        self.assertEqual(self.instrument.state[":OUTP2"], "ON")  # set on connection
        self.instrument.state[":OUTP2"] = "OFF"  # switched off on the front panel
        logs = []
        with patch("octoce.gui_dg4162.LINK_CHECK_PERIOD_S", 0.05),                 patch.object(app, "_append_log", side_effect=logs.append):
            app._link_thread = threading.Thread(target=app._watch_generator, daemon=True)
            app._link_thread.start()
            self.pump(lambda: self.instrument.state[":OUTP2"] == "ON" and any("OUTPUT2" in l for l in logs))
        self.assertEqual(self.instrument.state[":OUTP1"], "OFF")

    def test_watcher_reconnects_after_generator_power_cycle(self) -> None:
        import threading
        from octoce.gui_dg4162 import LINK_ON_COLOR

        app = self.app
        manager = self.controller._rm
        self.controller.disconnect()
        app._link_changed(False)
        manager.present = False  # generator off
        with patch("octoce.gui_dg4162.LINK_CHECK_PERIOD_S", 0.05):
            app._link_thread = threading.Thread(target=app._watch_generator, daemon=True)
            app._link_thread.start()
            end = time.monotonic() + 0.3
            while time.monotonic() < end:  # several probes with the generator off
                self.root.update()
                time.sleep(0.01)
            self.assertFalse(app._link_ok)
            manager.present = True  # switched on: connects by itself
            self.pump(lambda: app._link_ok)
            self.assertEqual(app.link_light.itemcget(app.link_light_id, "fill"), LINK_ON_COLOR)
            self.assertEqual(str(app.gen_apply_button.cget("state")), "normal")
            self.instrument.alive = False  # switched off again
            manager.present = False
            self.pump(lambda: not app._link_ok)
            self.assertEqual(str(app.gen_apply_button.cget("state")), "disabled")
            self.instrument.alive = True
            manager.present = True
            self.pump(lambda: app._link_ok)

    def test_excel_sequence_runs_all_jobs(self) -> None:
        from openpyxl import Workbook
        from octoce.sequence import COLUMN_KEYS

        app = self.app
        path = self.folder / "serie.xlsx"
        workbook = Workbook()
        sheet = workbook.active
        sheet.append(list(COLUMN_KEYS))
        blank = {key: None for key in COLUMN_KEYS}
        sheet.append(list({**blank, "ch1_mVpp": 200, "ch2_frecuencia_Hz": 1000,
                           "repeticiones": 2, "espera_s": 0.2}.values()))
        sheet.append(list({**blank, "ch1_mVpp": 400, "ch2_forma_onda": "Senoidal",
                           "nombre_archivo": "final"}.values()))
        workbook.save(path)

        app._open_sequence()
        window = app._sequence_window
        window.path_var.set(str(path))
        window.load()
        self.assertEqual(len(app._sequence_jobs), 3)
        with patch("octoce.gui_dg4162.messagebox.askyesno", return_value=True), \
                patch("octoce.gui.messagebox.showerror") as error:
            app._start_sequence()
            self.pump(lambda: not app._sequence_active, timeout=40.0)
            error.assert_not_called()
        names = sorted(p.name for p in self.folder.glob("*.bin"))
        self.assertEqual(names, [
            "OCE_4A_1B_3M_2SS_200mVpp_1000Hz.bin",
            "OCE_4A_1B_3M_2SS_200mVpp_1000Hz_1.bin",
            "final.bin",
        ])
        self.assertEqual(self.instrument.state[":OUTP1"], "OFF")
        self.assertEqual(self.instrument.state[":SOUR2:FUNC"], "SIN")
        self.assertIn("completa", window.status_var.get())



class USBTransformTests(unittest.TestCase):
    def test_photo_and_video_apply_the_frame_transform(self) -> None:
        import cv2
        from PIL import Image
        from octoce.usb_camera import USBCameraStream
        from test_gui_usb import _FakeCapture

        stream = USBCameraStream(capture_factory=lambda _index: _FakeCapture())
        crop = lambda frame: frame[1:3, 2:6]  # noqa: E731 - 4 × 2 px region
        with tempfile.TemporaryDirectory() as directory:
            stream.start(0)
            try:
                photo = stream.capture_photo(Path(directory) / "roi.png", transform=crop)
                with Image.open(photo) as saved:
                    self.assertEqual(saved.size, (4, 2))
                video = Path(directory) / "roi.mp4"
                stream.start_recording(video, transform=crop)
                time.sleep(0.2)
                stream.stop_recording()
            finally:
                self.assertTrue(stream.stop())
            reader = cv2.VideoCapture(str(video))
            size = (reader.get(cv2.CAP_PROP_FRAME_WIDTH), reader.get(cv2.CAP_PROP_FRAME_HEIGHT))
            reader.release()
            self.assertEqual(size, (4.0, 2.0))


if __name__ == "__main__":
    unittest.main()
