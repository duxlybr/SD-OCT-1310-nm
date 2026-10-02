from __future__ import annotations

import os
import tempfile
import threading
import time
import tkinter as tk
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image, ImageTk

from octoce.engine import EngineEvent, EngineState
from octoce.gui_usb import OCTOCEUSBApp, _CameraSetupDialog
from octoce.usb_camera import USBCameraStream
from octoce.camera_roi import CameraROI
from octoce.camera_roi_setup import CameraROISetup
from octoce.camera_roi import DEFAULT_ROI_PATH
from octoce.paths import ACQUISITIONS_DIR, PROJECT_ROOT


class _FakeStream:
    def __init__(self) -> None:
        self.running = False
        self.started: list[int] = []
        self.stops = 0
        self.frame: np.ndarray | None = None
        self.recording = False
        self.recorded_paths: list[str] = []
        self.photo_paths: list[str] = []
        self.last_record_error = None
        self.focus = 20.0
        self.brightness = 90.0

    def start(self, index: int) -> None:
        self.started.append(index)
        self.running = True

    def stop(self) -> bool:
        self.stops += 1
        self.running = False
        return True

    def snapshot(self) -> tuple[np.ndarray | None, str]:
        frame, self.frame = self.frame, None
        return frame, "USB de prueba"

    def peek_frame(self) -> tuple[np.ndarray | None, str]:
        return self.frame, "USB de prueba"

    def camera_controls(self, *, focus=None, brightness=None):
        if focus is not None:
            self.focus = focus
        if brightness is not None:
            self.brightness = brightness
        return {
            "autofocus": 0.0, "focus": self.focus, "brightness": self.brightness,
            "manual_focus": True,
            "focus_set": True if focus is not None else None,
            "brightness_set": True if brightness is not None else None,
            "focus_verified": True if focus is not None else None,
            "brightness_verified": True if brightness is not None else None,
        }

    def start_recording(self, path) -> None:
        self.recorded_paths.append(str(path))
        self.recording = True

    def restore_manual_controls(self):
        return self.camera_controls(focus=self.focus, brightness=self.brightness)

    def capture_photo(self, path):
        self.photo_paths.append(str(path))
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(
            np.zeros((4, 6, 3), dtype=np.uint8), mode="RGB"
        ).save(path)
        return Path(path)

    def stop_recording(self):
        self.recording = False
        return self.recorded_paths[-1] if self.recorded_paths else None, 3


@unittest.skipUnless(os.name == "nt", "Smoke visual de Tkinter para Windows")
class USBGuiTests(unittest.TestCase):
    def test_default_data_and_calibration_paths_ignore_working_directory(self) -> None:
        root = tk.Tk()
        original_cwd = Path.cwd()
        app = None
        try:
            with tempfile.TemporaryDirectory() as directory:
                try:
                    os.chdir(directory)
                    app = OCTOCEUSBApp(root, usb_stream=_FakeStream(), show_setup_on_start=False)
                    self.assertEqual(Path(app.output_var.get()).parent, ACQUISITIONS_DIR)
                    self.assertEqual(DEFAULT_ROI_PATH, PROJECT_ROOT / "config/camera_roi.json")
                    app.output_var.set("sample.bin")
                    self.assertEqual(app._media_path(None, ".png").parent, ACQUISITIONS_DIR)
                finally:
                    os.chdir(original_cwd)  # Windows cannot remove its current directory.
                    if app is not None:
                        app._on_close()
        finally:
            os.chdir(original_cwd)
            if app is None:
                root.destroy()

    def test_saved_roi_crop_optional_overlay_and_invalid_resolution(self) -> None:
        root = tk.Tk()
        roi = CameraROI(0, 640, 480, 20, 320, 240)
        with patch.object(CameraROI, "load", return_value=roi):
            app = OCTOCEUSBApp(root, usb_stream=_FakeStream(), show_setup_on_start=False)
        try:
            root.update_idletasks()
            app._usb_last_frame = np.zeros((480, 640, 3), dtype=np.uint8)
            app._render_usb()
            self.assertEqual(app._usb_photo.width(), app._usb_photo.height())
            app.pattern_overlay_var.set(True)
            app._render_usb()
            rgb = np.asarray(ImageTk.getimage(app._usb_photo))[:, :, :3]
            self.assertTrue(np.any(np.all(rgb == (255, 0, 0), axis=2)))
            app.pattern_overlay_var.set(False)
            app._render_usb()
            self.assertFalse(np.any(np.asarray(ImageTk.getimage(app._usb_photo))[:, :, :3]))
            app._usb_last_frame = np.zeros((240, 320, 3), dtype=np.uint8)
            app._render_usb()
            messages = [app.usb_canvas.itemcget(item, "text") for item in app.usb_canvas.find_all() if app.usb_canvas.type(item) == "text"]
            self.assertTrue(any("Resolución distinta" in message for message in messages))
        finally:
            app._on_close()

    def test_standalone_setup_converts_display_clicks_and_saves_roi(self) -> None:
        from types import SimpleNamespace

        root = tk.Tk()
        stream = _FakeStream()
        stream.frame = np.zeros((480, 640, 3), dtype=np.uint8)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "camera_roi.json"
            setup = CameraROISetup(root, stream, path=path)
            try:
                root.update_idletasks()
                setup.freeze()
                root.update_idletasks()
                ox, oy, scale = setup.transform
                for x, y in ((100, 200), (300, 200)):
                    setup.click(SimpleNamespace(x=ox + x * scale, y=oy + y * scale))
                with self.assertRaises(ValueError):
                    setup.roi()
                with patch("octoce.camera_roi_setup.messagebox.showerror") as error:
                    setup.save()
                    error.assert_called_once()
                self.assertFalse(path.exists())
                setup.approve_button.invoke()
                setup.click(SimpleNamespace(x=ox + 320 * scale, y=oy + 240 * scale))
                self.assertAlmostEqual(setup.roi().pixels_per_mm, 20)
                with patch("octoce.camera_roi_setup.messagebox.showinfo"):
                    setup.save()
                self.assertEqual(CameraROI.load(path).bounds(640, 480), (170, 90, 470, 390))
                self.assertFalse(stream.running)
            finally:
                try:
                    if root.winfo_exists():
                        setup.close()
                except tk.TclError:
                    pass  # Successful save already destroyed the standalone root.

    def test_setup_shapes_can_move_resize_and_require_reapproval(self) -> None:
        from types import SimpleNamespace

        root = tk.Tk()
        stream = _FakeStream()
        stream.frame = np.zeros((480, 640, 3), dtype=np.uint8)
        setup = CameraROISetup(root, stream)
        try:
            root.update_idletasks()
            setup.freeze()

            def event(x, y):
                ox, oy, scale = setup.transform
                return SimpleNamespace(x=ox + x * scale, y=oy + y * scale)

            for kind in ("Cuadrado", "Elipse / círculo"):
                with self.subTest(kind=kind):
                    setup.geometry.set(kind)
                    root.update_idletasks()
                    setup.click(event(100, 100))
                    setup.drag(event(300, 250))
                    setup._end_drag()
                    np.testing.assert_allclose(setup.points[1], (300, 300) if kind == "Cuadrado" else (300, 250))
                    setup.click(event(200, 200))
                    setup.drag(event(220, 210))
                    setup._end_drag()
                    np.testing.assert_allclose(setup.points[0], (120, 110))
                    setup.click(event(*setup.points[1]))
                    setup.drag(event(320, 310))
                    setup._end_drag()
                    np.testing.assert_allclose(setup.points[1], (320, 310))
                    setup.approve_button.invoke()
                    self.assertTrue(setup.approved)
                    setup.click(event(320, 240))
                    self.assertAlmostEqual(setup.roi().pixels_per_mm, 20)
                    setup.distance.set("20")
                    self.assertFalse(setup.approved)
                    self.assertIsNone(setup.center)
                    with self.assertRaises(ValueError):
                        setup.roi()
                    setup.distance.set("10")
            setup.approve_geometry()
            setup.axis.set("Vertical")
            self.assertFalse(setup.approved)
            setup.approve_geometry()
            setup.edit_button.invoke()
            self.assertFalse(setup.approved)
        finally:
            setup.close()

    def test_startup_is_fullscreen_without_automatic_camera_setup(self) -> None:
        root = tk.Tk()
        stream = _FakeStream()
        with patch.object(OCTOCEUSBApp, "_open_usb_setup") as setup:
            app = OCTOCEUSBApp(root, usb_stream=stream)
            try:
                root.after(500, root.quit)
                root.mainloop()
                setup.assert_not_called()
                self.assertTrue(root.attributes("-fullscreen"))
                app.backend_var.set("Simulación")
                app.save_var.set(False)
                with patch.object(app.engine, "start"):
                    app._start()
                setup.assert_not_called()
            finally:
                if root.winfo_exists():
                    app._on_close()

    def test_photo_is_saved_once_before_oct(self) -> None:
        root = tk.Tk()
        stream = _FakeStream()
        app = OCTOCEUSBApp(root, usb_stream=stream, show_setup_on_start=False)
        try:
            with tempfile.TemporaryDirectory() as directory:
                app.backend_var.set("Simulación")
                app.save_var.set(False)
                app.output_var.set(str(Path(directory) / "sample.bin"))
                app.capture_mode_var.set("Foto")
                observed = []
                with patch.object(
                    app.engine, "start",
                    side_effect=lambda *args, **kwargs: observed.append(
                        Path(stream.photo_paths[-1]).exists()
                    ),
                ):
                    app._start()
                self.assertEqual(observed, [True])
                self.assertEqual(len(stream.photo_paths), 1)
                self.assertEqual(Path(stream.photo_paths[0]).suffix, ".png")
                self.assertFalse(stream.recording)
        finally:
            if root.winfo_exists():
                app._on_close()

    def test_video_is_armed_before_oct_and_closed_on_terminal_state(self) -> None:
        root = tk.Tk()
        stream = _FakeStream()
        app = OCTOCEUSBApp(root, usb_stream=stream, show_setup_on_start=False)
        try:
            app.backend_var.set("Simulación")
            app.save_var.set(False)
            app.capture_mode_var.set("Video")
            observed = []
            with patch.object(app, "_show_usb_setup") as setup, patch.object(app.engine, "start", side_effect=lambda *args, **kwargs: observed.append(stream.recording)):
                app._start()
            setup.assert_not_called()
            self.assertEqual(observed, [True])
            self.assertTrue(stream.recording)
            self.assertEqual(len(stream.recorded_paths), 1)
            self.assertTrue(stream.recorded_paths[0].endswith(".mp4"))
            app._handle_event(EngineEvent("state", {"state": EngineState.COMPLETED.value}))
            self.assertFalse(stream.recording)
        finally:
            if root.winfo_exists():
                app._on_close()

    def test_usb_view_and_alignment_zoom_are_visible_together(self) -> None:
        root = tk.Tk()
        stream = _FakeStream()
        try:
            app = OCTOCEUSBApp(root, usb_stream=stream, show_setup_on_start=False)
            app.backend_var.set("Simulación")
            root.update_idletasks()
            self.assertEqual(stream.started, [0])
            self.assertTrue(app.usb_panel.grid_info())
            self.assertFalse(app.alignment_zoom_canvas.grid_info())
            self.assertTrue(app.crosshair_loop_button.winfo_exists())
            self.assertIs(app.usb_panel.master, app.diagnostic_card)
            self.assertIs(app.acquisition_status.master, app.header)
            self.assertFalse(any(isinstance(child, tk.Toplevel) and child.winfo_ismapped() for child in root.winfo_children()))
            self.assertIs(app.usb_canvas.winfo_toplevel(), root)
            app.usb_settings_button.invoke()
            root.update_idletasks()
            self.assertTrue(app.usb_settings_window.winfo_ismapped())
            self.assertIs(app.usb_settings.master, app.usb_settings_window)
            app.usb_settings_window.withdraw()
            self.assertFalse(hasattr(app, "log"))
            self.assertEqual(app.engine.preview_depth_range, (1, 2048))

            with patch.object(app, "_show_usb_setup") as setup, patch.object(app.engine, "start") as start:
                app._start_crosshair_loop()
            setup.assert_not_called()
            self.assertTrue(start.call_args.kwargs["continuous"])
            self.assertTrue(app.usb_panel.grid_info())
            self.assertTrue(stream.running)

            stream.frame = np.zeros((48, 64, 3), dtype=np.uint8)
            app._poll_usb()
            self.assertTrue(any(app.usb_canvas.type(item) == "image" for item in app.usb_canvas.find_all()))

            with patch.object(app.engine, "start") as start:
                app._start_alignment()
            self.assertTrue(start.call_args.kwargs["continuous"])
            self.assertTrue(app.usb_panel.grid_info())
            self.assertTrue(app.alignment_zoom_canvas.grid_info())
            self.assertTrue(stream.running)
            self.assertNotEqual(app.usb_panel.grid_info()["column"], app.alignment_zoom_canvas.grid_info()["column"])
            app._preview_db = np.arange(64 * 1000, dtype=np.float32).reshape(64, 1000)
            app._preview_depth_indexes = np.arange(64)
            app.z_cursor_var.set(32)
            root.update_idletasks()
            app._render_alignment_zoom()
            self.assertIsNotNone(app._alignment_zoom_photo)
            self.assertTrue(any(app.alignment_zoom_canvas.type(item) == "image" for item in app.alignment_zoom_canvas.find_all()))

            app._handle_event(EngineEvent("state", {"state": EngineState.STOPPED.value, "reason": "prueba"}))
            self.assertTrue(app.usb_panel.grid_info())
            self.assertFalse(app.alignment_zoom_canvas.grid_info())
            self.assertEqual(stream.started, [0, 0])
        finally:
            if root.winfo_exists():
                app._on_close()

    def test_large_setup_applies_focus_and_brightness_before_accepting(self) -> None:
        root = tk.Tk()
        stream = _FakeStream()
        stream.start(0)
        stream.frame = np.zeros((48, 64, 3), dtype=np.uint8)
        try:
            dialog = _CameraSetupDialog(root, stream, acquisition=True)
            def complete() -> None:
                dialog.focus_var.set("37")
                dialog.brightness_var.set("112")
                dialog._accept()
            root.after(250, complete)
            root.wait_window(dialog.window)
            self.assertTrue(dialog.accepted)
            self.assertEqual((stream.focus, stream.brightness), (37.0, 112.0))
        finally:
            root.destroy()

    def test_acquisition_does_not_repeat_camera_setup(self) -> None:
        root = tk.Tk()
        app = OCTOCEUSBApp(root, usb_stream=_FakeStream(), show_setup_on_start=False)
        try:
            app.backend_var.set("Simulación")
            app.save_var.set(False)
            with patch.object(app, "_show_usb_setup") as setup, patch.object(
                app.engine, "start"
            ) as start:
                app._start()
            setup.assert_not_called()
            start.assert_called_once()
        finally:
            if root.winfo_exists():
                app._on_close()


class _FakeCapture:
    def __init__(self) -> None:
        self.released = threading.Event()
        self.properties: dict[int, float] = {}
        self.set_calls: list[tuple[int, float]] = []

    def isOpened(self) -> bool:
        return True

    def read(self) -> tuple[bool, np.ndarray]:
        time.sleep(0.01)
        frame = np.zeros((4, 6, 3), dtype=np.uint8)
        frame[:, :, 0] = 255  # BGR azul; debe convertirse a RGB.
        return True, frame

    def release(self) -> None:
        self.released.set()

    def get(self, prop_id: int) -> float:
        return self.properties.get(prop_id, 0.0)

    def set(self, prop_id: int, value: float) -> bool:
        self.set_calls.append((prop_id, value))
        self.properties[prop_id] = value
        return True


class USBStreamTests(unittest.TestCase):
    def test_photo_uses_new_frame_and_writes_png(self) -> None:
        capture = _FakeCapture()
        stream = USBCameraStream(capture_factory=lambda _index: capture)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "photo.png"
            stream.start(0)
            try:
                self.assertEqual(stream.capture_photo(path), path)
                with Image.open(path) as saved:
                    self.assertEqual(saved.size, (6, 4))
                with self.assertRaises(FileExistsError):
                    stream.capture_photo(path)
            finally:
                self.assertTrue(stream.stop())

    def test_focus_is_attempted_even_if_autofocus_toggle_is_rejected(self) -> None:
        import cv2

        class RejectAuto(_FakeCapture):
            def set(self, prop_id: int, value: float) -> bool:
                if prop_id == cv2.CAP_PROP_AUTOFOCUS:
                    return False
                return super().set(prop_id, value)

        capture = RejectAuto()
        stream = USBCameraStream(capture_factory=lambda _index: capture)
        stream.start(0)
        try:
            result = stream.camera_controls(focus=45.0)
            self.assertFalse(result["autofocus_set"])
            self.assertTrue(result["focus_set"])
            self.assertTrue(result["focus_verified"])
            self.assertEqual(result["focus"], 45.0)
        finally:
            self.assertTrue(stream.stop())

    def test_manual_controls_are_restored_after_reopen(self) -> None:
        captures: list[_FakeCapture] = []
        def factory(_index: int) -> _FakeCapture:
            capture = _FakeCapture()
            captures.append(capture)
            return capture

        stream = USBCameraStream(capture_factory=factory)
        stream.start(0)
        self.assertTrue(stream.camera_controls(focus=35.0, brightness=98.0)["focus_verified"])
        self.assertTrue(stream.stop())
        stream.start(0)
        try:
            deadline = time.monotonic() + 2.0
            while stream.peek_frame()[0] is None and time.monotonic() < deadline:
                time.sleep(0.01)
            import cv2
            self.assertEqual(captures[-1].get(cv2.CAP_PROP_FOCUS), 35.0)
            self.assertEqual(captures[-1].get(cv2.CAP_PROP_BRIGHTNESS), 98.0)
        finally:
            self.assertTrue(stream.stop())

    def test_manual_controls_are_applied_on_capture_thread(self) -> None:
        import cv2

        capture = _FakeCapture()
        capture.properties[cv2.CAP_PROP_AUTOFOCUS] = 1.0
        stream = USBCameraStream(capture_factory=lambda _index: capture)
        stream.start(0)
        try:
            values = stream.camera_controls(focus=37.0, brightness=112.0)
            self.assertEqual(values["autofocus"], 0.0)
            self.assertEqual(values["focus"], 37.0)
            self.assertEqual(values["brightness"], 112.0)
            self.assertEqual(
                capture.set_calls[:3],
                [
                    (cv2.CAP_PROP_AUTOFOCUS, 0),
                    (cv2.CAP_PROP_FOCUS, 37.0),
                    (cv2.CAP_PROP_BRIGHTNESS, 112.0),
                ],
            )
        finally:
            self.assertTrue(stream.stop())

    def test_recording_waits_for_first_frame_and_finalizes_writer(self) -> None:
        import cv2

        class Writer:
            def __init__(self) -> None:
                self.frames = 0
                self.closed = False

            def isOpened(self) -> bool:
                return True

            def write(self, frame) -> None:
                self.frames += 1

            def release(self) -> None:
                self.closed = True

        capture = _FakeCapture()
        writer = Writer()
        stream = USBCameraStream(capture_factory=lambda _index: capture)
        with tempfile.TemporaryDirectory() as directory, patch.object(
            cv2, "VideoWriter", return_value=writer
        ):
            path = Path(directory) / "test.mp4"
            stream.start(0)
            self.assertEqual(stream.start_recording(path), path)
            self.assertGreaterEqual(writer.frames, 1)
            self.assertTrue(stream.recording)
            result_path, frames = stream.stop_recording()
            self.assertEqual(result_path, path)
            self.assertGreaterEqual(frames, 1)
            self.assertTrue(writer.closed)
            self.assertTrue(stream.stop())

    def test_latest_frame_is_rgb_and_capture_is_released(self) -> None:
        capture = _FakeCapture()
        stream = USBCameraStream(capture_factory=lambda _index: capture)
        stream.start(0)
        frame = None
        deadline = time.monotonic() + 2.0
        while frame is None and time.monotonic() < deadline:
            frame, _status = stream.snapshot()
            time.sleep(0.01)
        self.assertIsNotNone(frame)
        assert frame is not None
        self.assertEqual(frame.shape, (4, 6, 3))
        self.assertEqual(tuple(frame[0, 0]), (0, 0, 255))
        self.assertTrue(stream.stop())
        self.assertTrue(capture.released.is_set())


if __name__ == "__main__":
    unittest.main()
