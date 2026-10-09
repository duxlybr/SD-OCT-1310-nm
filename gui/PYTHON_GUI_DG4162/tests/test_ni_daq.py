from __future__ import annotations

import sys
import types
import unittest
from threading import Event
from unittest.mock import patch

import numpy as np

from octoce.backends.ni_daq import NIDaqGalvoController
from octoce.config import AcquisitionMode, HardwareConfig, ScanParameters, ScanPattern
from octoce.scan import ScanPlanner


class _Channel:
    def __init__(self, **settings: object):
        self.settings = settings
        self.co_pulse_term = ""


class _AOChannels:
    def __init__(self, task: "_Task"):
        self.task = task

    def add_ao_voltage_chan(self, channel: str, **settings: object) -> _Channel:
        self.task.channel = channel
        return _Channel(**settings)


class _COChannels:
    def __init__(self, task: "_Task"):
        self.task = task

    def add_co_pulse_chan_time(self, counter: str, **settings: object) -> _Channel:
        self.task.counter = counter
        self.task.pulse_settings = settings
        self.task.channel_object = _Channel(**settings)
        return self.task.channel_object


class _Timing:
    def __init__(self, task: "_Task"):
        self.task = task
        self.samp_clk_rate = 0.0

    def cfg_samp_clk_timing(self, *, rate: float, **settings: object) -> None:
        self.samp_clk_rate = rate
        self.task.sample_settings = {"rate": rate, **settings}

    def cfg_implicit_timing(self, **settings: object) -> None:
        self.task.sample_settings = settings


class _StartTrigger:
    def __init__(self, task: "_Task"):
        self.task = task

    def cfg_dig_edge_start_trig(self, source: str, **settings: object) -> None:
        self.task.trigger_settings = {"source": source, **settings}


class _Task:
    registry: list["_Task"] = []
    start_log: list[str] = []

    def __init__(self, name: str):
        self.name = name
        self.ao_channels = _AOChannels(self)
        self.co_channels = _COChannels(self)
        self.timing = _Timing(self)
        self.triggers = types.SimpleNamespace(start_trigger=_StartTrigger(self))
        self.out_stream = self
        self.closed = False
        self.done_checks = 0
        self.done_after_checks = 1
        self.written: np.ndarray | None = None
        self.__class__.registry.append(self)

    def control(self, mode: object) -> None:
        self.control_mode = mode

    def start(self) -> None:
        self.__class__.start_log.append(self.name)

    def is_task_done(self) -> bool:
        self.done_checks += 1
        return self.done_checks >= self.done_after_checks

    def wait_until_done(self, timeout: float) -> None:
        self.wait_timeout = timeout

    def stop(self) -> None:
        return None

    def close(self) -> None:
        self.closed = True


class _Writer:
    def __init__(self, out_stream: _Task, auto_start: bool):
        self.task = out_stream
        self.auto_start = auto_start

    def write_many_sample(self, data: np.ndarray, timeout: float) -> int:
        self.task.written = np.array(data, copy=True)
        return int(data.shape[1])


def _fake_modules() -> dict[str, types.ModuleType]:
    nidaqmx = types.ModuleType("nidaqmx")
    nidaqmx.Task = _Task  # type: ignore[attr-defined]
    constants = types.ModuleType("nidaqmx.constants")
    constants.AcquisitionType = types.SimpleNamespace(FINITE="finite", CONTINUOUS="continuous")
    constants.Edge = types.SimpleNamespace(RISING="rising")
    constants.Level = types.SimpleNamespace(LOW="low")
    constants.TaskMode = types.SimpleNamespace(TASK_COMMIT="commit")
    writers = types.ModuleType("nidaqmx.stream_writers")
    writers.AnalogMultiChannelWriter = _Writer  # type: ignore[attr-defined]
    return {
        "nidaqmx": nidaqmx,
        "nidaqmx.constants": constants,
        "nidaqmx.stream_writers": writers,
    }


class NIDaqSynchronizationTests(unittest.TestCase):
    def setUp(self) -> None:
        _Task.registry.clear()
        _Task.start_log.clear()

    def test_consumers_are_armed_before_ao_master(self) -> None:
        scan = ScanParameters(
            alines=3,
            bscans=1,
            m_repetitions=1,
            sync_points=2,
            bframes_delay_us=1.5,
        )
        hardware = HardwareConfig(line_rate_hz=100_000.0)
        segment = next(ScanPlanner(scan, hardware).iter_segments())
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(hardware)
            controller.start_segment(segment)
            self.assertEqual(
                _Task.start_log,
                ["octoce_camera_trigger", "octoce_oce_trigger", "octoce_ao"],
            )
            tasks = {task.name: task for task in _Task.registry}
            camera = tasks["octoce_camera_trigger"]
            oce = tasks["octoce_oce_trigger"]
            ao = tasks["octoce_ao"]
            self.assertAlmostEqual(camera.pulse_settings["initial_delay"], 20e-6)
            self.assertEqual(camera.sample_settings["samps_per_chan"], 1)
            self.assertEqual(camera.channel_object.co_pulse_term, "/Dev1/PFI12")
            self.assertEqual(oce.sample_settings["samps_per_chan"], 1)
            self.assertEqual(oce.channel_object.co_pulse_term, "/Dev1/PFI13")
            self.assertAlmostEqual(oce.pulse_settings["initial_delay"], 21.5e-6)
            self.assertAlmostEqual(oce.pulse_settings["high_time"], 10e-6)
            self.assertAlmostEqual(oce.pulse_settings["low_time"], 90e-6)
            self.assertEqual(ao.written.shape, (2, segment.ticks))
            oce.done_after_checks = 3
            controller.wait_segment(Event(), timeout_s=1.0)
            self.assertGreaterEqual(oce.done_checks, 3)
            self.assertTrue(all(task.closed for task in (camera, oce, ao)))

    def test_park_does_not_energize_ao_before_first_segment(self) -> None:
        hardware = HardwareConfig()
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(hardware)
            controller.park()
        self.assertEqual(_Task.registry, [])
        self.assertEqual(_Task.start_log, [])

    def test_continuous_alignment_uses_persistent_synchronized_counters(self) -> None:
        hardware = HardwareConfig(line_rate_hz=52_500.0)
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(hardware)
            controller.start_continuous_alignment(alines_per_block=1000, block_rate_hz=50.0)
            self.assertEqual(
                _Task.start_log,
                ["octoce_alignment_camera_50hz", "octoce_alignment_oce_50hz", "octoce_alignment_ao_hold"],
            )
            tasks = {task.name: task for task in _Task.registry}
            camera = tasks["octoce_alignment_camera_50hz"]
            oce = tasks["octoce_alignment_oce_50hz"]
            ao = tasks["octoce_alignment_ao_hold"]
            self.assertEqual(camera.sample_settings["sample_mode"], "continuous")
            self.assertEqual(oce.sample_settings["sample_mode"], "continuous")
            self.assertEqual(camera.trigger_settings["source"], "/Dev1/ao/StartTrigger")
            self.assertEqual(oce.trigger_settings["source"], "/Dev1/ao/StartTrigger")
            self.assertAlmostEqual(camera.pulse_settings["initial_delay"], 0.02)
            self.assertAlmostEqual(oce.pulse_settings["initial_delay"], 0.02)
            self.assertAlmostEqual(oce.pulse_settings["high_time"], 0.002)
            self.assertAlmostEqual(oce.pulse_settings["low_time"], 0.018)
            np.testing.assert_array_equal(ao.written, np.zeros((2, 2)))
            controller.abort_segment()
            self.assertTrue(all(task.closed for task in (camera, oce, ao)))

    def test_continuous_alignment_ramps_and_holds_offset_before_triggers(self) -> None:
        hardware = HardwareConfig(line_rate_hz=52_500.0, park_ramp_points=2000)
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(hardware)
            controller.start_continuous_alignment(alines_per_block=1000, block_rate_hz=50,
                                                   center_xy_mm=(3.0, 2.0))
            tasks = {task.name: task for task in _Task.registry}
            waveform = tasks["octoce_alignment_ao_hold"].written
            expected = np.asarray([3 * hardware.x_v_per_mm, 2 * hardware.y_v_per_mm])
            np.testing.assert_allclose(waveform[:, 0], 0)
            np.testing.assert_allclose(waveform[:, -1], expected)
            np.testing.assert_allclose(controller._last_volts, expected)
            self.assertTrue(np.all(np.diff(waveform, axis=1) >= -1e-12))
            for name in ("octoce_alignment_camera_50hz", "octoce_alignment_oce_50hz"):
                self.assertGreater(tasks[name].pulse_settings["initial_delay"], 2000 / hardware.effective_line_rate_hz)
            controller.abort_segment()
            controller.park()
            np.testing.assert_allclose(_Task.registry[-1].written[:, 0], expected)
            np.testing.assert_allclose(_Task.registry[-1].written[:, -1], hardware.park_volts)

    def test_continuous_alignment_invalid_offset_creates_no_tasks(self) -> None:
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(HardwareConfig(line_rate_hz=52_500))
            with self.assertRaisesRegex(ValueError, "FOV LSM04"):
                controller.start_continuous_alignment(alines_per_block=1000, block_rate_hz=50,
                                                       center_xy_mm=(8, 0))
        self.assertEqual(_Task.registry, [])

    def test_mb_chunk_arms_many_positions_with_one_task_group(self) -> None:
        scan = ScanParameters(
            alines=3, bscans=1, m_repetitions=4, sync_points=2,
            mode=AcquisitionMode.MB,
        )
        hardware = HardwareConfig(line_rate_hz=10_000.0)
        segments = list(ScanPlanner(scan, hardware).iter_segments())
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(hardware)
            ticks = controller.start_mb_chunk(segments)
            self.assertEqual(ticks, 6)
            self.assertEqual(
                _Task.start_log,
                ["octoce_mb_chunk_camera", "octoce_mb_chunk_oce", "octoce_mb_chunk_ao"],
            )
            tasks = {task.name: task for task in _Task.registry}
            camera = tasks["octoce_mb_chunk_camera"]
            oce = tasks["octoce_mb_chunk_oce"]
            ao = tasks["octoce_mb_chunk_ao"]
            self.assertEqual(camera.sample_settings["samps_per_chan"], 3)
            self.assertEqual(oce.sample_settings["samps_per_chan"], 3)
            self.assertAlmostEqual(camera.pulse_settings["initial_delay"], 2 / 10_000)
            self.assertAlmostEqual(camera.pulse_settings["low_time"] + camera.pulse_settings["high_time"], 6 / 10_000)
            self.assertAlmostEqual(oce.pulse_settings["high_time"], 0.1 * 6 / 10_000)
            self.assertEqual(ao.written.shape, (2, 18))
            expected = np.concatenate([segment.xy_volts for segment in segments], axis=0)
            np.testing.assert_allclose(ao.written.T, expected)
            controller.wait_segment(Event(), timeout_s=1.0)
            self.assertTrue(all(task.closed for task in (camera, oce, ao)))

    def test_mb_chunk_extends_hold_for_oce_duty_at_small_m(self) -> None:
        scan = ScanParameters(
            alines=2, bscans=1, m_repetitions=1, sync_points=50,
            mode=AcquisitionMode.MB,
        )
        hardware = HardwareConfig(line_rate_hz=50_000.0)
        segments = list(ScanPlanner(scan, hardware).iter_segments())
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(hardware)
            ticks = controller.start_mb_chunk(segments)
            self.assertGreater(ticks, segments[0].ticks)
            tasks = {task.name: task for task in _Task.registry}
            oce = tasks["octoce_mb_chunk_oce"]
            period = ticks / hardware.effective_line_rate_hz
            self.assertLessEqual(
                oce.pulse_settings["initial_delay"] + oce.pulse_settings["high_time"],
                period,
            )
            controller.abort_segment()

    def test_bm_crosshair_chunk_triggers_oce_only_on_x(self) -> None:
        scan = ScanParameters(
            alines=8, bscans=1, m_repetitions=2, sync_points=3,
            mode=AcquisitionMode.BM, pattern=ScanPattern.CROSSHAIR,
            x_length_mm=4.0, y_length_mm=6.0,
        )
        hardware = HardwareConfig(line_rate_hz=50_000.0)
        segments = list(ScanPlanner(scan, hardware).iter_segments())
        self.assertEqual([s.oce_trigger_count for s in segments], [1, 0, 1, 0])
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(hardware)
            ticks = controller.start_mb_chunk(segments)
            tasks = {task.name: task for task in _Task.registry}
            camera = tasks["octoce_mb_chunk_camera"]
            oce = tasks["octoce_mb_chunk_oce"]
            ao = tasks["octoce_mb_chunk_ao"]
            self.assertEqual(camera.sample_settings["samps_per_chan"], 4)
            self.assertEqual(oce.sample_settings["samps_per_chan"], 2)
            self.assertAlmostEqual(
                oce.pulse_settings["low_time"] + oce.pulse_settings["high_time"],
                2 * ticks / hardware.effective_line_rate_hz,
            )
            self.assertAlmostEqual(oce.pulse_settings["high_time"],
                                   0.2 * ticks / hardware.effective_line_rate_hz)
            self.assertEqual(ao.written.shape, (2, 4 * ticks))
            # The optimized chunk must retain X on AO0 and Y on AO1,
            # including the order of the X/Y camera frames.
            x_active = ao.written[:, scan.sync_points:scan.sync_points + scan.alines]
            y_start = ticks + scan.sync_points
            y_active = ao.written[:, y_start:y_start + scan.alines]
            np.testing.assert_allclose(x_active[0], segments[0].active_xy_volts[:, 0])
            np.testing.assert_allclose(x_active[1], 0.0)
            np.testing.assert_allclose(y_active[0], 0.0)
            np.testing.assert_allclose(y_active[1], segments[1].active_xy_volts[:, 1])
            self.assertAlmostEqual(float(np.ptp(x_active[0])), 4.0 * hardware.x_v_per_mm)
            self.assertAlmostEqual(float(np.ptp(y_active[1])), 6.0 * hardware.y_v_per_mm)
            controller.abort_segment()

    def test_stationary_mb_sync_zero_adds_unacquired_rearm_hold(self) -> None:
        scan = ScanParameters(
            alines=2, bscans=1, m_repetitions=1000, sync_points=0,
            x_length_mm=0, y_length_mm=0, mode=AcquisitionMode.MB,
        )
        hardware = HardwareConfig(line_rate_hz=50_000.0)
        segments = list(ScanPlanner(scan, hardware).iter_segments())
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(hardware)
            ticks = controller.start_mb_chunk(segments)
            self.assertEqual(ticks, 1050)
            tasks = {task.name: task for task in _Task.registry}
            self.assertEqual(tasks["octoce_mb_chunk_camera"].sample_settings["samps_per_chan"], 2)
            self.assertTrue(np.all(tasks["octoce_mb_chunk_ao"].written == 0))
            controller.abort_segment()

    def test_crosshair_y_segment_does_not_repeat_bm_oce_trigger(self) -> None:
        from octoce.config import ScanPattern

        scan = ScanParameters(
            alines=3,
            bscans=1,
            m_repetitions=1,
            sync_points=2,
            pattern=ScanPattern.CROSSHAIR,
        )
        hardware = HardwareConfig(line_rate_hz=100_000.0)
        y_segment = list(ScanPlanner(scan, hardware).iter_segments())[1]
        self.assertEqual(y_segment.oce_trigger_count, 0)
        with patch.dict(sys.modules, _fake_modules()):
            controller = NIDaqGalvoController(hardware)
            controller.start_segment(y_segment)
            self.assertEqual(_Task.start_log, ["octoce_camera_trigger", "octoce_ao"])
            self.assertNotIn("octoce_oce_trigger", {task.name for task in _Task.registry})
            controller.wait_segment(Event(), timeout_s=1.0)


if __name__ == "__main__":
    unittest.main()
