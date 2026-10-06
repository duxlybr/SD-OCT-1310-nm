from __future__ import annotations

import tempfile
import time
import unittest
from pathlib import Path

import numpy as np

from octoce.backends.simulated import SimulatedBackend
from octoce.backends.base import AcquisitionResult
from octoce.backends.ni_hardware import NIHardwareBackend
from octoce.backends.base import AcquisitionResult
from octoce.config import AcquisitionMode, HardwareConfig, Orientation, ScanParameters, ScanPattern
from octoce.engine import AcquisitionEngine, EngineEvent, EngineState
from octoce.processing import (
    SPECTRAL_WINDOWS,
    normalize_preview,
    preview_complex,
    reconstruct_oct_complex,
    reconstruct_oct_db,
)
from octoce.storage import build_header, open_memmap, read_info


class ProcessingTests(unittest.TestCase):
    def test_selected_z_bin_is_exact_even_when_preview_is_downsampled(self) -> None:
        raw = (
            1000 + np.arange(12, dtype=np.uint16)[:, None] * 3
            + np.arange(64, dtype=np.uint16)[None, :]
        )
        result = preview_complex(raw, selected_depth_bin=137)
        self.assertEqual(len(result), 5)
        self.assertNotIn(137, result[2])
        narrow = preview_complex(raw, depth_start_bin=137, depth_end_bin=137)
        np.testing.assert_allclose(result[4], narrow[1][0])

    def test_reconstruction_shape_and_normalization(self) -> None:
        pixels = 64
        x = np.arange(pixels, dtype=np.float32)
        rows = np.stack([2000 + 500 * np.cos(2 * np.pi * (8 + i) * x / pixels) for i in range(5)])
        raw = np.clip(rows, 0, 4095).astype(np.uint16)
        db = reconstruct_oct_db(raw)
        self.assertEqual(db.shape, (32, 5))
        image = normalize_preview(db)
        self.assertEqual(image.shape, (32, 5))
        self.assertEqual(image.dtype, np.uint8)
        self.assertGreater(int(image.max()), int(image.min()))

    def test_complex_preview_exposes_phase_and_original_indexes(self) -> None:
        pixels = 64
        x = np.arange(pixels, dtype=np.float32)
        raw = np.stack(
            [2000 + 500 * np.cos(2 * np.pi * 8 * x / pixels + phase) for phase in (0.0, 0.4, 0.8)]
        ).astype(np.uint16)
        complex_oct = reconstruct_oct_complex(raw)
        self.assertEqual(complex_oct.shape, (32, 3))
        self.assertTrue(np.iscomplexobj(complex_oct))
        intensity, phase, depth_indexes, aline_indexes = preview_complex(
            raw, max_width=2, max_height=8
        )
        self.assertEqual(intensity.shape, phase.shape)
        self.assertLessEqual(intensity.shape[0], 8)
        self.assertLessEqual(intensity.shape[1], 2)
        self.assertEqual(depth_indexes.size, intensity.shape[0])
        self.assertEqual(aline_indexes.size, intensity.shape[1])
        self.assertTrue(np.all(phase >= -np.pi))
        self.assertTrue(np.all(phase <= np.pi))

    def test_dc_removal_is_standard_and_can_be_disabled(self) -> None:
        identical = np.tile(np.arange(64, dtype=np.uint16), (6, 1)) + 1000
        with_dc_removed = reconstruct_oct_complex(identical)
        without_dc_removed = reconstruct_oct_complex(identical, remove_dc=False)
        self.assertTrue(np.allclose(with_dc_removed, 0.0))
        self.assertGreater(float(np.abs(without_dc_removed).max()), 0.0)

    def test_k_linearization_and_single_depth_domain(self) -> None:
        pixels = 2048
        wavelength = np.linspace(1470.01, 1262.13, pixels)
        k = 2.0 * np.pi / wavelength
        phases = np.linspace(0.0, 1.5, 10)
        raw = np.stack([
            2000.0 + 420.0 * np.cos(36.0 * (k - k.min()) / np.ptp(k) * 2.0 * np.pi + phase)
            for phase in phases
        ]).astype(np.uint16)
        intensity, phase, depth_indexes, _ = preview_complex(raw)
        self.assertEqual(intensity.shape, phase.shape)
        self.assertLessEqual(int(depth_indexes.max()), 2048)
        self.assertEqual(intensity.shape[1], 10)
        shifted, _, _, _ = preview_complex(raw, wavelength_start_nm=1460.0, wavelength_end_nm=1280.0)
        self.assertFalse(np.allclose(intensity, shifted))

    def test_dispersion_compensation_restores_a_dispersed_psf(self) -> None:
        pixels = 2048
        hardware = HardwareConfig()
        wavelength = np.linspace(hardware.k_start_nm, hardware.k_end_nm, pixels)   # reversed detector
        k = 2.0 * np.pi / wavelength
        q = np.linspace(-1.0, 1.0, pixels)            # uniform-k axis, ascending k
        k_sorted = np.sort(k)
        q_of_k = np.interp(k, np.linspace(k_sorted[0], k_sorted[-1], pixels), q)
        d2, d3 = 8.0, 5.0
        envelope = np.exp(-0.5 * ((np.arange(pixels) - 1024) / 400.0) ** 2)
        phases = np.linspace(0.0, 2.0, 6)
        detector = np.stack([
            2000.0 + 600.0 * envelope * np.cos(2.0 * k * 2.0e6 + d2 * q_of_k ** 2 + d3 * q_of_k ** 3 + p)
            for p in phases
        ])[:, ::-1]                                   # back to camera order
        raw = np.clip(detector, 0, 4095).astype(np.uint16)

        def peak(**kwargs: float) -> float:
            spectrum = reconstruct_oct_complex(raw, fft_size=8192, reverse_spectrum=True,
                                               wavelength_start_nm=hardware.k_start_nm,
                                               wavelength_end_nm=hardware.k_end_nm, **kwargs)
            return float(np.abs(spectrum).mean(axis=1).max())

        dispersed = peak()
        corrected = peak(dispersion_d2_rad=d2, dispersion_d3_rad=d3)
        wrong_sign = peak(dispersion_d2_rad=-d2, dispersion_d3_rad=-d3)
        self.assertGreater(corrected, 1.15 * dispersed)   # max of the D2 scan sits at d2 (checked)
        self.assertLess(wrong_sign, dispersed)
        with self.assertRaisesRegex(ValueError, "linealización"):
            reconstruct_oct_complex(raw, dispersion_d2_rad=1.0)

    def test_spectral_windows_keep_level_and_trade_width_for_sidelobes(self) -> None:
        samples = 2048
        n = np.arange(samples)
        raw = np.stack([2000 + 500 * np.cos(2 * np.pi * 300.3 * n / samples + p)
                        for p in np.linspace(0, 3, 8)]).astype(np.uint16)

        def psf(window: str) -> tuple[float, float]:
            amp = np.abs(reconstruct_oct_complex(raw, fft_size=8192, window=window)).mean(axis=1)
            i = int(np.argmax(amp))
            half = amp[i] / 2
            left = i
            while amp[left] > half:
                left -= 1
            right = i
            while amp[right] > half:
                right += 1
            return float(amp[i]), float(right - left)

        hann_level, hann_width = psf("Hann")
        for name in SPECTRAL_WINDOWS:
            level, _ = psf(name)
            self.assertAlmostEqual(level / hann_level, 1.0, delta=0.08, msg=name)
        self.assertLess(psf("Rectangular")[1], hann_width)
        self.assertGreater(psf("Blackman-Harris")[1], hann_width)
        # Hann reproduces the historical preview exactly
        legacy = np.fft.rfft((raw - raw.mean(axis=0)) * np.hanning(samples), n=8192, axis=1)[:, 1:4097].T
        np.testing.assert_allclose(np.abs(reconstruct_oct_complex(raw, fft_size=8192)),
                                   np.abs(legacy), rtol=1e-4, atol=1e-2)
        with self.assertRaisesRegex(ValueError, "Ventana espectral"):
            reconstruct_oct_complex(raw, window="Triangular")
        engine = AcquisitionEngine()
        engine.set_preview_window("Blackman")
        self.assertEqual(engine.preview_window, "Blackman")
        with self.assertRaises(ValueError):
            engine.set_preview_window("Nope")

    def test_preview_depth_window_can_be_narrow_or_wide(self) -> None:
        raw = np.tile(np.arange(64, dtype=np.uint16), (8, 1)) + 1000
        narrow, _, narrow_bins, _ = preview_complex(
            raw, depth_start_bin=100, depth_end_bin=119, max_height=100
        )
        self.assertEqual(narrow.shape, (20, 8))
        np.testing.assert_array_equal(narrow_bins, np.arange(100, 120))
        wide, _, wide_bins, _ = preview_complex(
            raw, depth_start_bin=3000, depth_end_bin=4096, max_height=2000
        )
        self.assertEqual(wide.shape, (1097, 8))
        self.assertEqual((wide_bins[0], wide_bins[-1]), (3000, 4096))
        with self.assertRaisesRegex(ValueError, "Rango Z inválido"):
            preview_complex(raw, depth_start_bin=200, depth_end_bin=100)


class EngineTests(unittest.TestCase):
    def test_linear_bidirectional_raw_order_preserves_m_samples(self) -> None:
        class CoordinateBackend(SimulatedBackend):
            def acquire_segment(self, segment, destination, stop_event):
                positions = np.rint((segment.active_xy_mm[:, 0] + 10.0) * 100).astype(np.uint16)
                destination[:] = positions[:, None]
                return AcquisitionResult(
                    requested_buffer=segment.sequence_index,
                    copied_buffer=segment.sequence_index,
                    physical_ring_index=segment.sequence_index % 16,
                    lost_buffers_total=0,
                    elapsed_s=0.0,
                )

        hardware = HardwareConfig(
            spectral_samples=16, line_rate_hz=10_000.0, oce_enabled=False,
        )
        with tempfile.TemporaryDirectory() as directory:
            for mode in (AcquisitionMode.BM, AcquisitionMode.MB):
                scan = ScanParameters(
                    alines=3, bscans=2, m_repetitions=2, sync_points=2,
                    x_length_mm=4.0, y_length_mm=0.0,
                    mode=mode, pattern=ScanPattern.LINEAR,
                )
                path = Path(directory) / f"linear_{mode.value}.bin"
                engine = AcquisitionEngine()
                engine.start(scan, hardware, output_path=path, backend=CoordinateBackend())
                engine.join(10.0)
                self.assertEqual(engine.state, EngineState.COMPLETED)
                info = read_info(path)
                self.assertTrue(info.complete)
                self.assertTrue(info.header["scan"]["linear_bidirectional"])
                self.assertIn("M time samples", info.header["raw_storage"]["linear_bidirectional_policy"])
                data = np.asarray(open_memmap(path)[:, 0]).copy()
                if mode is AcquisitionMode.BM:
                    expected = np.tile([800, 1000, 1200], 4)
                else:
                    expected = np.repeat([800, 1000, 1200, 1200, 1000, 800], 2)
                np.testing.assert_array_equal(data, expected)

    def test_bm_crosshair_header_records_two_sweep_oce_period(self) -> None:
        scan = ScanParameters(
            alines=500, bscans=2, m_repetitions=1, sync_points=50,
            mode=AcquisitionMode.BM, pattern=ScanPattern.CROSSHAIR,
        )
        hardware = HardwareConfig(line_rate_hz=50_000.0)
        header = build_header(
            scan, hardware, backend="ni-pcie-6323+1433-optimized", trajectory_sha256="test",
        )
        timing = header["synchronization"]
        self.assertTrue(timing["chunked"])
        self.assertEqual(timing["chunk_mode"], "BM")
        self.assertEqual(timing["oce_trigger_stride_sweeps"], 2)
        self.assertAlmostEqual(timing["oce_pulse_period_us"], 2 * timing["mb_period_us"])
        self.assertAlmostEqual(timing["oce_pulse_width_us"], 0.1 * timing["oce_pulse_period_us"])

    def test_optimized_mb_batches_preserve_raw_order_and_file_integrity(self) -> None:
        scan = ScanParameters(
            alines=5, bscans=2, m_repetitions=3, sync_points=2,
            x_length_mm=2.0, y_length_mm=1.0,
            mode=AcquisitionMode.MB, pattern=ScanPattern.RASTER,
        )
        hardware = HardwareConfig(
            spectral_samples=16, line_rate_hz=10_000.0, oce_enabled=True,
        )

        class RecordingChunkBackend(NIHardwareBackend):
            def __init__(self) -> None:
                super().__init__()
                self.chunks: list[tuple[int, ...]] = []

            def open(self, scan, hardware) -> None:
                return None

            def mb_chunk_size(self, scan, hardware) -> int:
                return 2

            def acquire_segment(self, segment, destination, stop_event):
                raise AssertionError("La ruta MB optimizada no debe rearmar por posición.")

            def acquire_mb_chunk(self, segments, stop_event):
                self.chunks.append(tuple(s.sequence_index for s in segments))
                for segment in segments:
                    data = np.full(
                        (segment.active_count, hardware.spectral_samples),
                        segment.sequence_index + 1,
                        dtype=np.uint16,
                    )
                    yield segment, data, AcquisitionResult(
                        requested_buffer=segment.sequence_index,
                        copied_buffer=segment.sequence_index,
                        physical_ring_index=segment.sequence_index % hardware.imaq_ring_buffers,
                        lost_buffers_total=0,
                        elapsed_s=0.001,
                    )

            def close(self, *, abort=False) -> None:
                return None

        backend = RecordingChunkBackend()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "optimized_mb.bin"
            engine = AcquisitionEngine()
            engine.start(scan, hardware, output_path=path, backend=backend)
            engine.join(10.0)
            self.assertEqual(engine.state, EngineState.COMPLETED)
            self.assertEqual(
                backend.chunks,
                [(0, 1), (2, 3), (4, 5), (6, 7), (8, 9)],
            )
            info = read_info(path)
            self.assertTrue(info.complete)
            self.assertEqual(info.committed_alines, 30)
            timing = info.header["synchronization"]
            self.assertTrue(timing["mb_chunked"])
            self.assertEqual(timing["mb_period_ticks"], 5)
            self.assertAlmostEqual(timing["oce_pulse_width_us"], 50.0)
            raw = open_memmap(path)
            for index in range(10):
                self.assertTrue(np.all(raw[index * 3:(index + 1) * 3] == index + 1))
            del raw

    def test_continuous_bm_crosshair_repeats_both_sweeps_and_reports_time(self) -> None:
        scan = ScanParameters(
            alines=500, bscans=1, m_repetitions=1, sync_points=50,
            x_length_mm=10.0, y_length_mm=10.0,
            mode=AcquisitionMode.BM, pattern=ScanPattern.CROSSHAIR,
        )
        self.assertEqual(scan.expected_alines, 1000)
        hardware = HardwareConfig(
            spectral_samples=64, line_rate_hz=10_000.0,
            preview_rate_hz=100.0, oce_enabled=False,
        )

        class RecordingBackend(SimulatedBackend):
            def __init__(self):
                super().__init__(realtime_factor=20.0)
                self.segments = []

            def acquire_segment(self, segment, destination, stop_event):
                self.segments.append(segment)
                return super().acquire_segment(segment, destination, stop_event)

        backend = RecordingBackend()
        events = []

        def on_event(event):
            events.append(event)
            if event.kind == "progress" and event.payload["acquired_alines"] >= 2000:
                engine.stop()

        engine = AcquisitionEngine(on_event)
        engine.set_preview_depth_range(100, 300)
        engine.start(scan, hardware, output_path=None, backend=backend, continuous=True)
        engine.join(10.0)
        self.assertEqual(engine.state, EngineState.STOPPED)
        self.assertEqual([s.sweep_index for s in backend.segments], [0, 1, 0, 1])
        self.assertEqual([s.bscan_index for s in backend.segments], [0, 0, 1, 1])
        self.assertEqual([s.active_count for s in backend.segments], [500] * 4)
        self.assertLess(
            abs(float(backend.segments[2].xy_mm[0, 1] - backend.segments[1].active_xy_mm[-1, 1])),
            0.1,
        )
        previews = [event.payload for event in events if event.kind == "preview"]
        self.assertTrue(previews)
        self.assertTrue(all(p["crosshair"] for p in previews))
        self.assertTrue(all(p["depth_start_bin"] == 100 and p["depth_end_bin"] == 300 for p in previews))
        terminal = next(event.payload for event in events if event.kind == "state" and event.payload["state"] == "stopped")
        self.assertGreater(terminal["elapsed_s"], 0.0)
        with self.assertRaisesRegex(ValueError, "deshabilite OCE"):
            AcquisitionEngine().start(
                scan, HardwareConfig(spectral_samples=64, oce_enabled=True),
                output_path=None, continuous=True,
            )

    def test_crosshair_preview_contains_both_sweeps_in_one_event(self) -> None:
        scan = ScanParameters(
            alines=12, bscans=1, m_repetitions=1, sync_points=2,
            x_length_mm=2.0, y_length_mm=2.0,
            mode=AcquisitionMode.BM, pattern=ScanPattern.CROSSHAIR,
        )
        hardware = HardwareConfig(spectral_samples=64, line_rate_hz=10_000.0, oce_enabled=False)
        events = []
        engine = AcquisitionEngine(events.append)
        engine.start(scan, hardware, output_path=None, backend=SimulatedBackend(realtime_factor=100.0))
        engine.join(5.0)
        self.assertEqual(engine.state, EngineState.COMPLETED)
        previews = [event.payload for event in events if event.kind == "preview"]
        self.assertEqual(len(previews), 1)
        self.assertTrue(previews[0]["crosshair"])
        self.assertEqual(previews[0]["intensity_db"].shape[1], 12)
        self.assertEqual(previews[0]["secondary_intensity_db"].shape[1], 12)

    def test_continuous_stationary_alignment_stops_without_file(self) -> None:
        scan = ScanParameters(
            alines=1, bscans=1, m_repetitions=1000, sync_points=4,
            x_length_mm=0.0, y_length_mm=0.0,
            mode=AcquisitionMode.MB, pattern=ScanPattern.LINEAR,
        )
        hardware = HardwareConfig(spectral_samples=64, line_rate_hz=10_000.0, oce_enabled=False)
        events = []
        def stop_after_two(event):
            events.append(event)
            if event.kind == "progress" and event.payload["acquired_alines"] >= 2000:
                engine.stop()

        engine = AcquisitionEngine(stop_after_two)
        engine.set_preview_remove_dc(False)
        engine.start(scan, hardware, output_path=None, backend=SimulatedBackend(realtime_factor=100.0), continuous=True)
        engine.join(5.0)
        self.assertEqual(engine.state, EngineState.STOPPED)
        self.assertTrue(any(event.kind == "preview" for event in events))
        self.assertIsNone(next(event.payload["expected_alines"] for event in events if event.kind == "progress"))

    def test_continuous_stationary_alignment_allows_oce_once_per_mb_block(self) -> None:
        scan = ScanParameters(
            alines=1, bscans=1, m_repetitions=1000, sync_points=4,
            x_length_mm=0.0, y_length_mm=0.0,
            mode=AcquisitionMode.MB, pattern=ScanPattern.LINEAR,
        )
        hardware = HardwareConfig(spectral_samples=64, line_rate_hz=10_000.0, oce_enabled=True)
        events = []

        class RecordingBackend(SimulatedBackend):
            def __init__(self):
                super().__init__(realtime_factor=100.0)
                self.triggers = []

            def acquire_segment(self, segment, destination, stop_event):
                self.triggers.append(segment.oce_trigger_count)
                return super().acquire_segment(segment, destination, stop_event)

        backend = RecordingBackend()

        def stop_after_two(event):
            events.append(event)
            if event.kind == "progress" and event.payload["acquired_alines"] >= 2000:
                engine.stop()

        engine = AcquisitionEngine(stop_after_two)
        engine.start(scan, hardware, output_path=None, backend=backend, continuous=True)
        engine.join(5.0)
        self.assertEqual(engine.state, EngineState.STOPPED)
        self.assertEqual(backend.triggers, [1, 1])
        self.assertTrue(any(event.kind == "preview" for event in events))

    def test_simulated_engine_writes_complete_mb_file(self) -> None:
        scan = ScanParameters(
            alines=8,
            bscans=2,
            m_repetitions=3,
            sync_points=2,
            x_length_mm=2.0,
            y_length_mm=1.0,
            mode=AcquisitionMode.MB,
            pattern=ScanPattern.RASTER,
        )
        hardware = HardwareConfig(
            spectral_samples=64,
            sensor_bit_depth=12,
            line_rate_hz=10_000.0,
            preview_rate_hz=100.0,
            oce_enabled=False,
        )
        events = []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "engine.bin"
            engine = AcquisitionEngine(events.append)
            engine.start(
                scan,
                hardware,
                output_path=path,
                backend=SimulatedBackend(realtime_factor=100.0),
            )
            engine.join(10.0)
            self.assertEqual(engine.state, EngineState.COMPLETED)
            info = read_info(path)
            self.assertTrue(info.complete)
            self.assertEqual(info.committed_alines, 48)
            self.assertEqual(open_memmap(path, logical_shape=True).shape, (2, 8, 3, 64))
            self.assertFalse(any(event.kind == "preview" for event in events))
            progress = [event for event in events if event.kind == "progress"]
            self.assertEqual(progress[-1].payload["acquired_alines"], 48)

    def test_all_modes_and_patterns_end_to_end(self) -> None:
        cases = [
            (ScanPattern.RASTER, Orientation.HORIZONTAL),
            (ScanPattern.CROSSHAIR, Orientation.HORIZONTAL),
            (ScanPattern.MERIDIANS, Orientation.HORIZONTAL),
            (ScanPattern.LINEAR, Orientation.HORIZONTAL),
            (ScanPattern.LINEAR, Orientation.VERTICAL),
            (ScanPattern.RINGS, Orientation.HORIZONTAL),
            (ScanPattern.SPIRAL, Orientation.HORIZONTAL),
        ]
        hardware = HardwareConfig(
            spectral_samples=32,
            sensor_bit_depth=12,
            line_rate_hz=10_000.0,
            preview_rate_hz=200.0,
            oce_enabled=False,
        )
        with tempfile.TemporaryDirectory() as directory:
            for mode in AcquisitionMode:
                for pattern, orientation in cases:
                    with self.subTest(mode=mode.value, pattern=pattern.value, orientation=orientation.value):
                        scan = ScanParameters(
                            alines=5,
                            bscans=2,
                            m_repetitions=2,
                            sync_points=2,
                            x_length_mm=2.0,
                            y_length_mm=1.5,
                            mode=mode,
                            pattern=pattern,
                            orientation=orientation,
                        )
                        path = Path(directory) / f"{mode.value}-{pattern.value}-{orientation.value}.bin"
                        engine = AcquisitionEngine()
                        engine.start(
                            scan,
                            hardware,
                            output_path=path,
                            backend=SimulatedBackend(realtime_factor=100.0),
                        )
                        engine.join(5.0)
                        self.assertEqual(engine.state, EngineState.COMPLETED)
                        info = read_info(path)
                        self.assertTrue(info.complete)
                        self.assertEqual(info.committed_alines, scan.expected_alines)
                        mapped = open_memmap(path)
                        self.assertEqual(mapped.shape, (scan.expected_alines, hardware.spectral_samples))
                        del mapped
                        logical = open_memmap(path, logical_shape=True)
                        self.assertEqual(
                            logical.shape,
                            (*scan.logical_shape_without_pixels, hardware.spectral_samples),
                        )
                        del logical

    def test_ring_preview_assembles_the_whole_ring(self) -> None:
        hardware = HardwareConfig(spectral_samples=32, line_rate_hz=10_000.0,
                                  preview_rate_hz=200.0, oce_enabled=False)
        for mode in AcquisitionMode:
            with self.subTest(mode=mode.value):
                events: list[EngineEvent] = []
                scan = ScanParameters(alines=5, bscans=3, m_repetitions=2, sync_points=2,
                                      x_length_mm=2.0, y_length_mm=2.0, mode=mode,
                                      pattern=ScanPattern.RINGS)
                engine = AcquisitionEngine(events.append)
                engine.start(scan, hardware, output_path=None,
                             backend=SimulatedBackend(realtime_factor=100.0))
                engine.join(5.0)
                self.assertEqual(engine.state, EngineState.COMPLETED)
                deadline = time.monotonic() + 5.0
                while time.monotonic() < deadline and not any(e.kind == "preview" for e in events):
                    time.sleep(0.02)
                time.sleep(0.2)
                previews = [e.payload for e in events if e.kind == "preview"]
                self.assertTrue(previews)
                last = previews[-1]
                self.assertEqual(last["bscan_index"], 2)
                self.assertIsNone(last["sweep_index"])  # not a crosshair sweep
                self.assertEqual(int(np.max(last["aline_indexes"])), 14)  # outer ring: 3 arcs x 5


if __name__ == "__main__":
    unittest.main()
