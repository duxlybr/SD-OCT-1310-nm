from __future__ import annotations

import os
import math
import queue
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Protocol

import numpy as np
from numpy.typing import NDArray


class _Capture(Protocol):
    def isOpened(self) -> bool: ...
    def read(self) -> tuple[bool, NDArray[np.uint8] | None]: ...
    def release(self) -> None: ...
    def get(self, prop_id: int) -> float: ...
    def set(self, prop_id: int, value: float) -> bool: ...


@dataclass
class _ControlRequest:
    focus: float | None = None
    brightness: float | None = None
    done: threading.Event = field(default_factory=threading.Event)
    cancelled: threading.Event = field(default_factory=threading.Event)
    result: dict[str, float | bool | None] | None = None
    error: Exception | None = None


class USBCameraStream:
    """Best-effort USB video on its own thread; never blocks the NI acquisition."""

    def __init__(self, capture_factory: Callable[[int], _Capture] | None = None) -> None:
        self._capture_factory = capture_factory
        self._lock = threading.Lock()
        self._frame_ready = threading.Condition(self._lock)
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._frame: NDArray[np.uint8] | None = None
        self._latest_frame: NDArray[np.uint8] | None = None
        self._frame_serial = 0
        self._desired_controls: dict[int, tuple[float | None, float | None]] = {}
        self._control_requests: queue.Queue[_ControlRequest] = queue.Queue()
        self._status = "USB desconectada"
        self._index: int | None = None
        self._record_path: Path | None = None
        self._record_writer: object | None = None
        self._record_transform: Callable[[NDArray[np.uint8]], NDArray[np.uint8]] | None = None
        self._record_ready: threading.Event | None = None
        self._record_done = threading.Event()
        self._record_error: str | None = None
        self._record_stop_requested = False
        self._record_frames = 0
        self._last_record_path: Path | None = None
        self._last_record_frames = 0

    @property
    def running(self) -> bool:
        thread = self._thread
        return thread is not None and thread.is_alive()

    @property
    def recording(self) -> bool:
        with self._lock:
            return self._record_path is not None

    @property
    def last_record_error(self) -> str | None:
        with self._lock:
            return self._record_error

    def start_recording(
        self, path: str | os.PathLike[str], timeout_s: float = 8.0, *,
        transform: Callable[[NDArray[np.uint8]], NDArray[np.uint8]] | None = None,
    ) -> Path:
        """Arm MP4 in the capture thread and wait until its first frame is written.

        ``transform`` (e.g. ROI crop / mirror) is applied to every frame written.
        """
        destination = Path(path)
        if destination.suffix.lower() != ".mp4":
            raise ValueError("El video USB debe tener extensión .mp4.")
        if destination.exists():
            raise FileExistsError(f"El video ya existe: {destination}")
        if not self.running:
            raise RuntimeError("La cámara USB no está recibiendo fotogramas.")
        destination.parent.mkdir(parents=True, exist_ok=True)
        ready = threading.Event()
        with self._lock:
            if self._record_path is not None:
                raise RuntimeError("Ya hay una grabación USB activa.")
            self._record_path = destination
            self._record_writer = None
            self._record_transform = transform
            self._record_ready = ready
            self._record_done.clear()
            self._record_error = None
            self._record_stop_requested = False
            self._record_frames = 0
        if not ready.wait(timeout_s):
            self.stop_recording()
            raise TimeoutError("La cámara USB no escribió un fotograma antes del inicio OCT.")
        with self._lock:
            error = self._record_error
        if error is not None:
            raise RuntimeError(error)
        return destination

    def stop_recording(self, timeout_s: float = 8.0) -> tuple[Path | None, int]:
        with self._lock:
            if self._record_path is None:
                return self._last_record_path, self._last_record_frames
            self._record_stop_requested = True
            done = self._record_done
        if not done.wait(timeout_s):
            raise TimeoutError("No se pudo finalizar el archivo de video USB a tiempo.")
        with self._lock:
            return self._last_record_path, self._last_record_frames

    def _finish_recording(self, error: str | None = None) -> None:
        with self._lock:
            writer = self._record_writer
            path = self._record_path
            frames = self._record_frames
            ready = self._record_ready
            self._record_writer = None
            self._record_path = None
            self._record_transform = None
            self._record_ready = None
            self._record_stop_requested = False
            self._record_error = error
            self._last_record_path = path
            self._last_record_frames = frames
        try:
            if writer is not None:
                writer.release()
        except Exception as exc:
            with self._lock:
                self._record_error = f"No se pudo cerrar el video USB: {exc}"
        finally:
            if ready is not None:
                ready.set()
            self._record_done.set()

    def start(self, index: int) -> None:
        if not 0 <= index <= 15:
            raise ValueError("El índice USB debe estar entre 0 y 15.")
        if self.running and self._index == index:
            return
        if not self.stop():
            raise RuntimeError("La cámara USB anterior aún no se ha liberado.")
        self._index = index
        self._stop_event = threading.Event()
        with self._lock:
            self._frame = None
            self._latest_frame = None
            self._frame_serial = 0
            self._status = f"Abriendo cámara USB {index}…"
        self._thread = threading.Thread(
            target=self._capture_loop,
            args=(index, self._stop_event),
            name="octoce-usb-camera",
            daemon=True,
        )
        self._thread.start()

    def stop(self, timeout_s: float = 2.0) -> bool:
        thread = self._thread
        if thread is None:
            return True
        self._stop_event.set()
        thread.join(timeout_s)
        if thread.is_alive():
            with self._lock:
                self._status = "Esperando liberación de la cámara USB…"
            return False
        self._thread = None
        self._index = None
        with self._lock:
            self._frame = None
            self._latest_frame = None
            self._status = "USB desconectada"
            self._frame_ready.notify_all()
        return True

    def snapshot(self) -> tuple[NDArray[np.uint8] | None, str]:
        with self._lock:
            frame = self._frame
            self._frame = None
            return frame, self._status

    def peek_frame(self) -> tuple[NDArray[np.uint8] | None, str]:
        """Read the latest image without consuming the regular preview frame."""
        with self._lock:
            return self._latest_frame, self._status

    def capture_photo(
        self, path: str | os.PathLike[str], timeout_s: float = 4.0, *,
        transform: Callable[[NDArray[np.uint8]], NDArray[np.uint8]] | None = None,
    ) -> Path:
        """Save the next camera frame as PNG, before the OCT acquisition starts."""
        from PIL import Image

        destination = Path(path)
        if destination.suffix.lower() != ".png":
            raise ValueError("La foto USB debe tener extensión .png.")
        if not self.running:
            raise RuntimeError("La cámara USB no está recibiendo fotogramas.")
        deadline = time.monotonic() + timeout_s
        with self._frame_ready:
            previous = self._frame_serial
            while self._frame_serial == previous and self.running:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("No llegó una imagen nueva de la cámara USB.")
                self._frame_ready.wait(remaining)
            if self._latest_frame is None or self._frame_serial == previous:
                raise RuntimeError("La cámara USB dejó de entregar imágenes.")
            frame = self._latest_frame.copy()
        if transform is not None:
            frame = np.ascontiguousarray(transform(frame))
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("xb") as handle:
            Image.fromarray(frame, mode="RGB").save(handle, format="PNG")
        return destination

    def restore_manual_controls(self) -> dict[str, float | bool | None] | None:
        """Reapply accepted values after camera reopen or before media capture."""
        index = self._index
        desired = self._desired_controls.get(index) if index is not None else None
        if desired is None:
            return None
        return self.camera_controls(focus=desired[0], brightness=desired[1])

    def camera_controls(
        self, *, focus: float | None = None, brightness: float | None = None,
        timeout_s: float = 3.0,
    ) -> dict[str, float | bool | None]:
        """Query or change USB controls on the capture thread (not during read)."""
        if not self.running:
            raise RuntimeError("La cámara USB no está conectada.")
        for name, value in (("foco", focus), ("brillo", brightness)):
            if value is not None and not math.isfinite(value):
                raise ValueError(f"El {name} debe ser un número finito.")
        request = _ControlRequest(focus=focus, brightness=brightness)
        self._control_requests.put(request)
        if not request.done.wait(timeout_s):
            request.cancelled.set()
            raise TimeoutError("La cámara USB no respondió al ajuste de foco/brillo.")
        if request.error is not None:
            raise request.error
        assert request.result is not None
        if self._index is not None and (focus is not None or brightness is not None):
            previous = self._desired_controls.get(self._index, (None, None))
            self._desired_controls[self._index] = (
                float(request.result["focus"])
                if focus is not None and request.result["focus_set"] and request.result["focus_verified"]
                else previous[0],
                float(request.result["brightness"])
                if brightness is not None and request.result["brightness_set"] and request.result["brightness_verified"]
                else previous[1],
            )
        return request.result

    @staticmethod
    def _apply_controls(
        capture: _Capture, request: _ControlRequest, cv2: object,
    ) -> dict[str, float | bool | None]:
        if not hasattr(capture, "get") or not hasattr(capture, "set"):
            raise RuntimeError("El controlador de la cámara no ofrece controles manuales.")
        focus_set = None
        brightness_set = None
        autofocus_set = None
        if request.focus is not None:
            autofocus_set = bool(capture.set(cv2.CAP_PROP_AUTOFOCUS, 0))
            # Some drivers reject AUTOFOCUS=0 but still accept manual FOCUS.
            # Always try the actual focus command, then inspect the readback.
            focus_set = bool(capture.set(cv2.CAP_PROP_FOCUS, request.focus))
        if request.brightness is not None:
            brightness_set = bool(capture.set(cv2.CAP_PROP_BRIGHTNESS, request.brightness))
        if request.focus is not None or request.brightness is not None:
            time.sleep(0.08)
        autofocus = float(capture.get(cv2.CAP_PROP_AUTOFOCUS))
        focus = float(capture.get(cv2.CAP_PROP_FOCUS))
        brightness = float(capture.get(cv2.CAP_PROP_BRIGHTNESS))
        backend_name = capture.getBackendName() if hasattr(capture, "getBackendName") else ""
        manual_focus = (
            abs(autofocus - 2.0) < 0.1
            if str(backend_name).upper() == "DSHOW"
            else abs(autofocus) < 0.1
        )
        return {
            "autofocus": autofocus,
            "manual_focus": manual_focus,
            "autofocus_set": autofocus_set,
            "focus": focus,
            "brightness": brightness,
            "focus_set": focus_set,
            "brightness_set": brightness_set,
            "focus_verified": None if request.focus is None else abs(focus - request.focus) <= 0.5,
            "brightness_verified": None if request.brightness is None else abs(brightness - request.brightness) <= 0.5,
        }

    def _service_control_requests(self, capture: _Capture, cv2: object) -> None:
        while True:
            try:
                request = self._control_requests.get_nowait()
            except queue.Empty:
                return
            if request.cancelled.is_set():
                request.done.set()
                continue
            try:
                request.result = self._apply_controls(capture, request, cv2)
            except Exception as exc:
                request.error = exc
            finally:
                request.done.set()

    def _fail_control_requests(self) -> None:
        while True:
            try:
                request = self._control_requests.get_nowait()
            except queue.Empty:
                return
            request.error = RuntimeError("La cámara USB se desconectó durante el ajuste.")
            request.done.set()

    def _set_status(self, status: str) -> None:
        with self._lock:
            self._status = status

    def _capture_loop(self, index: int, stop_event: threading.Event) -> None:
        capture: _Capture | None = None
        try:
            import cv2

            if self._capture_factory is not None:
                capture = self._capture_factory(index)
            else:
                backends = (
                    (cv2.CAP_DSHOW, cv2.CAP_MSMF, cv2.CAP_ANY)
                    if os.name == "nt" else (cv2.CAP_ANY,)
                )
                for backend in backends:
                    candidate = cv2.VideoCapture(index, backend)
                    if candidate.isOpened():
                        capture = candidate
                        break
                    candidate.release()
            if capture is None or not capture.isOpened():
                self._set_status(f"No se pudo abrir USB {index}. Pruebe otro índice.")
                return
            desired = self._desired_controls.get(index)
            if desired is not None:
                try:
                    self._apply_controls(
                        capture, _ControlRequest(focus=desired[0], brightness=desired[1]), cv2
                    )
                except Exception as exc:
                    self._set_status(f"No se pudieron restaurar los ajustes USB: {exc}")
            failures = 0
            while not stop_event.is_set():
                self._service_control_requests(capture, cv2)
                with self._lock:
                    stop_recording = self._record_stop_requested
                if stop_recording:
                    self._finish_recording()
                ok, frame = capture.read()
                if not ok or frame is None:
                    failures += 1
                    if failures >= 20:
                        self._set_status(f"Sin fotogramas de USB {index}. Reintente conectar.")
                        return
                    stop_event.wait(0.05)
                    continue
                failures = 0
                with self._lock:
                    record_path = self._record_path
                    writer = self._record_writer
                    transform = self._record_transform
                if record_path is not None:
                    try:
                        recorded = frame if transform is None else np.ascontiguousarray(transform(frame))
                    except Exception as exc:
                        self._finish_recording(f"No se pudo recortar el video USB: {exc}")
                        record_path = None
                if record_path is not None:
                    if writer is None:
                        try:
                            fps = float(capture.get(cv2.CAP_PROP_FPS)) if hasattr(capture, "get") else 0.0
                            if not 1.0 <= fps <= 240.0:
                                fps = 30.0
                            writer = cv2.VideoWriter(
                                str(record_path), cv2.VideoWriter_fourcc(*"mp4v"),
                                fps, (int(recorded.shape[1]), int(recorded.shape[0])),
                            )
                            if not writer.isOpened():
                                raise RuntimeError("OpenCV no pudo abrir el codificador MP4.")
                            with self._lock:
                                self._record_writer = writer
                        except Exception as exc:
                            self._finish_recording(f"No se pudo iniciar el video USB: {exc}")
                            writer = None
                    if writer is not None:
                        try:
                            writer.write(recorded)
                            with self._lock:
                                self._record_frames += 1
                                ready = self._record_ready
                            if ready is not None:
                                ready.set()
                        except Exception as exc:
                            self._finish_recording(f"Fallo escribiendo el video USB: {exc}")
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                with self._lock:
                    self._frame = rgb
                    self._latest_frame = rgb
                    self._frame_serial += 1
                    self._status = f"USB {index} · {rgb.shape[1]}×{rgb.shape[0]}"
                    self._frame_ready.notify_all()
        except ImportError:
            self._set_status("Falta OpenCV: instale requirements-usb.txt")
        except Exception as exc:
            self._set_status(f"Error de cámara USB: {exc}")
        finally:
            with self._frame_ready:
                self._frame_ready.notify_all()
            self._fail_control_requests()
            if self.recording:
                self._finish_recording("La cámara USB dejó de entregar fotogramas.")
            if capture is not None:
                capture.release()
