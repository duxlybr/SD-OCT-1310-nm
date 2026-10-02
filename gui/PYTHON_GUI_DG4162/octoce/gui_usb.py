from __future__ import annotations

import tkinter as tk
from dataclasses import replace
from datetime import datetime
from pathlib import Path
from tkinter import messagebox, ttk
from typing import Any, Callable

import numpy as np
from PIL import Image, ImageTk

from .engine import EngineEvent, EngineState
from .gui import OCTOCEApp
from .usb_camera import USBCameraStream
from .camera_roi import CameraROI, DEFAULT_ROI_PATH, render_pattern
from .camera_roi_setup import CameraROISetup
from .paths import ACQUISITIONS_DIR


BRIGHTNESS_MIN, BRIGHTNESS_MAX = 0, 255
CAPTURE_AREAS = ("FOV completo", "Solo ROI")


def oriented_view(frame: np.ndarray, roi: CameraROI, *, crop: bool) -> tuple[np.ndarray, CameraROI]:
    """Crop to the ROI (optional) and mirror per flip_x/flip_y.

    After mirroring, +X/+Y of the galvos run right/down in the image, so the
    returned ROI (for drawing the pattern) has no flips left.
    """
    left, top, right, bottom = roi.bounds(frame.shape[1], frame.shape[0])
    if crop:
        frame = frame[top:bottom, left:right]
    if roi.flip_x:
        frame = frame[:, ::-1]
    if roi.flip_y:
        frame = frame[::-1]
    drawn = replace(
        roi, flip_x=False, flip_y=False,
        center_x=roi.frame_width - 1 - roi.center_x if roi.flip_x and not crop else roi.center_x,
        center_y=roi.frame_height - 1 - roi.center_y if roi.flip_y and not crop else roi.center_y,
    )
    return np.ascontiguousarray(frame), drawn


class _CameraSetupDialog:
    """Large live USB preview; acceptance is required before an OCT start."""

    def __init__(self, parent: tk.Tk, stream: USBCameraStream, *, acquisition: bool) -> None:
        self.stream = stream
        self.acquisition = acquisition
        self.accepted = False
        self._photo: ImageTk.PhotoImage | None = None
        self._frame: np.ndarray | None = None
        self._loaded = False
        self._after_id: str | None = None
        self.window = tk.Toplevel(parent)
        self.window.title("Preparación de cámara USB · foco y brillo")
        self.window.transient(parent)
        width = max(800, min(1500, parent.winfo_screenwidth() - 60))
        height = max(600, min(980, parent.winfo_screenheight() - 70))
        self.window.geometry(f"{width}x{height}")
        self.window.minsize(800, 600)
        self.window.protocol("WM_DELETE_WINDOW", self._cancel)
        self.window.bind("<F11>", self._toggle_fullscreen)
        self.window.bind("<Escape>", lambda _event: self._cancel())

        layout = ttk.Frame(self.window, padding=14)
        layout.pack(fill="both", expand=True)
        layout.columnconfigure(0, weight=1)
        layout.rowconfigure(1, weight=1)
        ttk.Label(
            layout,
            text="Ajuste la cámara USB · F11: pantalla completa",
            font=("Segoe UI", 13),
        ).grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 10))
        self.canvas = tk.Canvas(layout, bg="#07111f", highlightthickness=0)
        self.canvas.grid(row=1, column=0, sticky="nsew")
        self.canvas.bind("<Configure>", lambda _event: self._render())
        side = ttk.Frame(layout, padding=(16, 0, 0, 0))
        side.grid(row=1, column=1, sticky="ns")
        self.focus_var = tk.StringVar(value="0")
        self.brightness_var = tk.StringVar(value="0")
        self.focus_scale = self._control_row(side, "Foco manual", self.focus_var, 0, 255)
        # Measured on the USB camera (DirectShow): brightness outside 0–255 is rejected.
        self.brightness_scale = self._control_row(
            side, "Brillo (0–255)", self.brightness_var, BRIGHTNESS_MIN, BRIGHTNESS_MAX
        )
        ttk.Button(side, text="Aplicar foco y brillo", command=self._apply).pack(
            fill="x", pady=(16, 8)
        )
        self.readback_var = tk.StringVar(value="Esperando imagen de la cámara…")
        ttk.Label(side, textvariable=self.readback_var, wraplength=230).pack(
            fill="x", pady=(0, 12)
        )
        ttk.Label(
            side,
            text="Si el controlador no admite un ajuste, se indicará aquí. "
                 "El valor leído puede diferir del solicitado.",
            wraplength=230,
        ).pack(fill="x")
        self.status_var = tk.StringVar(value="Abriendo cámara USB…")
        ttk.Label(layout, textvariable=self.status_var).grid(
            row=2, column=0, sticky="w", pady=(8, 0)
        )
        buttons = ttk.Frame(layout)
        buttons.grid(row=2, column=1, sticky="e", pady=(8, 0))
        cancel_label = "Cancelar adquisición" if acquisition else "Cerrar"
        ttk.Button(buttons, text=cancel_label, command=self._cancel).pack(
            side="left", padx=4
        )
        label = "Iniciar adquisición" if acquisition else "Guardar y cerrar"
        ttk.Button(buttons, text=label, command=self._accept).pack(side="left", padx=4)
        self.window.grab_set()
        self._after_id = self.window.after(80, self._poll)

    def _control_row(
        self, parent: ttk.Frame, label: str, variable: tk.StringVar, low: int, high: int,
    ) -> tk.Scale:
        ttk.Label(parent, text=label).pack(anchor="w", pady=(10, 0))
        row = ttk.Frame(parent)
        row.pack(fill="x")
        scale = tk.Scale(
            row, from_=low, to=high, orient="horizontal", resolution=1,
            showvalue=False, length=190,
        )
        scale.pack(side="left")
        scale.bind(
            "<ButtonRelease-1>",
            lambda _event: (variable.set(str(scale.get())), self._apply()),
        )
        ttk.Entry(row, textvariable=variable, width=7).pack(side="left", padx=(5, 0))
        return scale

    def _toggle_fullscreen(self, _event: tk.Event) -> None:
        self.window.attributes(
            "-fullscreen", not bool(self.window.attributes("-fullscreen"))
        )

    def _poll(self) -> None:
        if not self.window.winfo_exists():
            return
        frame, status = self.stream.peek_frame()
        self.status_var.set(status)
        if frame is not None:
            self._frame = frame
            self._render()
            if not self._loaded:
                self._loaded = True
                try:
                    self._show_controls(self.stream.camera_controls())
                except Exception as exc:
                    self.readback_var.set(f"Controles no disponibles: {exc}")
        self._after_id = self.window.after(80, self._poll)

    def _show_controls(self, controls: dict[str, float | bool | None]) -> None:
        focus = controls["focus"]
        brightness = controls["brightness"]
        if focus is not None and brightness is not None:
            self.focus_var.set(f"{focus:g}")
            self.brightness_var.set(f"{brightness:g}")
            self.focus_scale.set(max(0, min(255, float(focus))))
            self.brightness_scale.set(max(BRIGHTNESS_MIN, min(BRIGHTNESS_MAX, float(brightness))))
        parts = [
            f"Foco leído: {focus:g}" if focus is not None else "Foco: no disponible",
            f"Brillo leído: {brightness:g}" if brightness is not None else "Brillo: no disponible",
            "Enfoque manual confirmado" if controls.get("manual_focus") else
            f"Modo manual no confirmado (driver: {controls['autofocus']})",
        ]
        if controls["focus_set"] is False:
            parts.append("Foco manual rechazado por controlador")
        if controls["brightness_set"] is False:
            parts.append("Brillo rechazado por controlador")
        if controls.get("focus_verified") is False:
            parts.append("Foco solicitado distinto del leído: use el valor leído o reintente")
        if controls.get("brightness_verified") is False:
            parts.append("Brillo solicitado distinto del leído: use el valor leído o reintente")
        self.readback_var.set("\n".join(parts))

    def _apply(self) -> bool:
        if not self.stream.running:
            self.readback_var.set("Cámara USB desconectada.")
            return False
        try:
            focus = float(self.focus_var.get().replace(",", "."))
            brightness = float(self.brightness_var.get().replace(",", "."))
            if not BRIGHTNESS_MIN <= brightness <= BRIGHTNESS_MAX:
                raise ValueError(
                    f"la cámara solo acepta brillo entre {BRIGHTNESS_MIN} y {BRIGHTNESS_MAX} "
                    f"({BRIGHTNESS_MIN} = más oscuro)."
                )
            controls = self.stream.camera_controls(focus=focus, brightness=brightness)
            self._show_controls(controls)
            return (
                controls["focus_set"] is not False
                and controls["brightness_set"] is not False
                and controls.get("manual_focus", True)
                and controls.get("focus_verified") is not False
                and controls.get("brightness_verified") is not False
            )
        except (ValueError, RuntimeError, TimeoutError) as exc:
            self.readback_var.set(f"No se pudo ajustar la cámara: {exc}")
            return False

    def _accept(self) -> None:
        if not self._loaded and not messagebox.askyesno(
            "Cámara USB sin imagen",
            "Aún no hay imagen de la cámara USB para ajustar foco y brillo. "
            "¿Continuar sin esos ajustes?",
            parent=self.window,
        ):
            return
        if self._loaded and not self._apply():
            if not messagebox.askyesno(
                "Controles USB",
                "El controlador no confirmó todos los ajustes manuales. "
                "¿Continuar con los valores actuales?",
                parent=self.window,
            ):
                return
        self.accepted = True
        self._close()

    def _cancel(self) -> None:
        self._close()

    def _close(self) -> None:
        if self._after_id is not None:
            self.window.after_cancel(self._after_id)
            self._after_id = None
        self.window.destroy()

    def _render(self) -> None:
        if self._frame is None:
            return
        canvas_width = max(1, self.canvas.winfo_width())
        canvas_height = max(1, self.canvas.winfo_height())
        height, width = self._frame.shape[:2]
        scale = min(canvas_width / width, canvas_height / height)
        pil = Image.fromarray(self._frame, mode="RGB")
        pil = pil.resize(
            (max(1, int(width * scale)), max(1, int(height * scale))),
            Image.Resampling.BILINEAR,
        )
        self._photo = ImageTk.PhotoImage(pil)
        self.canvas.delete("all")
        self.canvas.create_image(
            canvas_width / 2, canvas_height / 2, image=self._photo, anchor="center"
        )


class OCTOCEUSBApp(OCTOCEApp):
    """Separate GUI variant: live USB view, retaining the OCT alignment zoom."""

    USB_REFRESH_MS = 66
    USB_VIEW_SIDE = round(250 * np.sqrt(5))

    def __init__(
        self, root: tk.Tk, *, usb_stream: USBCameraStream | None = None,
        show_setup_on_start: bool = False,
    ) -> None:
        self._usb_stream = usb_stream or USBCameraStream()
        self._usb_last_frame: np.ndarray | None = None
        self._usb_photo: ImageTk.PhotoImage | None = None
        self._usb_after: str | None = None
        self._video_active_path: Path | None = None
        self._setup_after: str | None = None
        self._camera_roi = None
        self._roi_load_error = ""
        try:
            self._camera_roi = CameraROI.load()
        except (OSError, ValueError, TypeError, KeyError) as exc:
            self._roi_load_error = f"ROI no cargada: {exc}"
        super().__init__(root)
        if self._roi_load_error:
            self._append_log(self._roi_load_error)
        for variable in (self.pattern_var, self.orientation_var, self.x_length_var, self.y_length_var):
            variable.trace_add("write", lambda *_args: self._render_usb())
        self.root.title("OCT / OCE Acquisition · USB · Optimizada")
        self._connect_usb()
        self._poll_usb()
        if show_setup_on_start:
            self._setup_after = self.root.after(350, self._initial_usb_setup)

    def _build_diagnostic_content(self, diagnostic_card: ttk.Frame) -> None:
        diagnostic_card.columnconfigure(0, weight=1)
        diagnostic_card.rowconfigure(0, weight=1)
        self.lower_pane.pane(diagnostic_card, weight=4)
        self.usb_panel = ttk.Frame(
            diagnostic_card, style="Card.TFrame", width=self.USB_VIEW_SIDE,
        )
        self.usb_panel.grid(row=0, column=0, sticky="nsew")
        self.usb_panel.columnconfigure(0, weight=1)
        self.usb_panel.rowconfigure(1, weight=1)
        camera_header = ttk.Frame(self.usb_panel, style="Card.TFrame")
        camera_header.grid(row=0, column=0, sticky="ew", pady=(0, 5))
        ttk.Label(camera_header, text="Cámara USB", style="CardTitle.TLabel").pack(side="left")
        self.usb_settings_button = ttk.Button(
            camera_header, text="⚙", width=2, style="Settings.TButton", command=self._open_usb_settings,
        )
        self.usb_settings_button.pack(side="right")
        self.usb_settings_window = tk.Toplevel(self.root)
        self.usb_settings_window.withdraw()
        self.usb_settings_window.title("Configuración de cámara USB")
        self.usb_settings_window.transient(self.root)
        self.usb_settings_window.resizable(False, False)
        self.usb_settings_window.protocol("WM_DELETE_WINDOW", self.usb_settings_window.withdraw)
        self.usb_settings_window.bind("<Escape>", lambda _event: self.usb_settings_window.withdraw())
        self.usb_settings = ttk.Frame(self.usb_settings_window, style="Card.TFrame", padding=14)
        self.usb_settings.pack(fill="both", expand=True)

        controls = ttk.Frame(self.usb_settings, style="Card.TFrame")
        controls.grid(row=0, column=0, sticky="ew", pady=(0, 5))
        ttk.Label(controls, text="Cámara USB", style="Card.TLabel").pack(side="left")
        self.usb_index_var = tk.StringVar(value=str(self._camera_roi.camera_index if self._camera_roi else 0))
        selector = ttk.Combobox(
            controls,
            textvariable=self.usb_index_var,
            values=tuple(str(index) for index in range(6)),
            state="readonly",
            width=3,
        )
        selector.pack(side="left", padx=(7, 4))
        self.usb_selector = selector
        selector.bind("<<ComboboxSelected>>", lambda _event: self._connect_usb())
        self.usb_connect_button = ttk.Button(controls, text="Conectar", command=self._connect_usb)
        self.usb_connect_button.pack(side="left")

        capture_controls = ttk.Frame(self.usb_settings, style="Card.TFrame")
        capture_controls.grid(row=1, column=0, sticky="ew", pady=(3, 5))
        ttk.Label(
            capture_controls, text="Al adquirir:", style="Card.TLabel"
        ).pack(side="left")
        self.capture_mode_var = tk.StringVar(value="Sin captura")
        self.capture_mode_combo = ttk.Combobox(
            capture_controls, textvariable=self.capture_mode_var,
            values=("Sin captura", "Foto", "Video"), state="readonly", width=12,
        )
        self.capture_mode_combo.pack(side="left", padx=(6, 0))
        area_controls = ttk.Frame(self.usb_settings, style="Card.TFrame")
        area_controls.grid(row=2, column=0, sticky="ew", pady=(3, 5))
        ttk.Label(area_controls, text="Área a guardar:", style="Card.TLabel").pack(side="left")
        self.capture_area_var = tk.StringVar(value=CAPTURE_AREAS[0])
        self.capture_area_combo = ttk.Combobox(
            area_controls, textvariable=self.capture_area_var, values=CAPTURE_AREAS,
            state="readonly", width=14,
        )
        self.capture_area_combo.pack(side="left", padx=(6, 0))
        self.usb_setup_button = ttk.Button(
            self.usb_settings, text="Ajustar foco y brillo · vista grande",
            command=self._open_usb_setup,
        )
        self.usb_setup_button.grid(row=4, column=0, sticky="ew", pady=(7, 0))
        roi_controls = ttk.Frame(self.usb_settings, style="Card.TFrame")
        roi_controls.grid(row=5, column=0, sticky="ew", pady=(5, 0))
        self.roi_enabled_var = tk.BooleanVar(value=True)
        self.pattern_overlay_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(roi_controls, text="Usar ROI guardada", variable=self.roi_enabled_var,
                        command=self._render_usb).pack(anchor="w")
        ttk.Checkbutton(roi_controls, text="Indicador rojo del patrón", variable=self.pattern_overlay_var,
                        command=self._render_usb).pack(anchor="w")
        self.roi_setup_button = ttk.Button(
            roi_controls, text="Setup de cámara · calibrar ROI 15 × 15 mm…", command=self._open_roi_setup,
        )
        self.roi_setup_button.pack(fill="x", pady=(5, 0))
        ttk.Label(
            roi_controls, style="Muted.TLabel", wraplength=260, justify="left",
            text="Los cambios del setup (ROI e inversión X/Y) se guardan al cerrarlo.",
        ).pack(anchor="w", pady=(3, 0))
        ttk.Button(self.usb_settings, text="Cerrar", command=self.usb_settings_window.withdraw).grid(
            row=6, column=0, sticky="e", pady=(12, 0))

        self.usb_canvas = tk.Canvas(
            self.usb_panel,
            width=self.USB_VIEW_SIDE,
            height=420,
            bg="#07111f",
            highlightthickness=1,
            highlightbackground="#d5dde8",
        )
        self.usb_canvas.grid(row=1, column=0, sticky="nsew")
        self.usb_canvas.bind("<Configure>", lambda _event: self._render_usb())
        self.usb_status_var = tk.StringVar(value="USB desconectada")
        ttk.Label(
            self.usb_panel,
            textvariable=self.usb_status_var,
            style="Muted.TLabel",
            wraplength=self.USB_VIEW_SIDE - 16,
        ).grid(row=2, column=0, sticky="w", pady=(5, 0))
        self._render_usb()

    def _open_usb_settings(self) -> None:
        self.usb_settings_window.deiconify()
        self.usb_settings_window.lift()
        self.usb_settings_window.focus_set()

    def _connect_usb(self) -> None:
        if self._alignment_active or self._closing or self._usb_stream.recording:
            return
        try:
            index = int(self.usb_index_var.get())
            self._usb_last_frame = None
            self._usb_photo = None
            self._usb_stream.start(index)
            self.usb_status_var.set(f"Abriendo cámara USB {index}…")
            self._render_usb()
        except (RuntimeError, ValueError) as exc:
            self.usb_status_var.set(str(exc))
            self._render_usb()

    def _media_path(self, output: Path | None, extension: str) -> Path:
        if output is not None:
            candidate = output.with_name(output.stem + "_usb" + extension)
        else:
            folder = Path(self.output_var.get()).parent
            if str(folder) in ("", "."):
                folder = ACQUISITIONS_DIR
            candidate = folder / ("USB_" + datetime.now().strftime("%Y%m%d_%H%M%S") + extension)
        base = candidate.with_suffix("")
        number = 2
        while candidate.exists():
            candidate = base.with_name(base.name + f"_{number}").with_suffix(extension)
            number += 1
        return candidate

    def _show_usb_setup(self, *, acquisition: bool) -> bool:
        index = int(self.usb_index_var.get())
        self._usb_stream.start(index)
        dialog = _CameraSetupDialog(self.root, self._usb_stream, acquisition=acquisition)
        self.root.wait_window(dialog.window)
        return dialog.accepted

    def _initial_usb_setup(self) -> None:
        self._setup_after = None
        if not self._closing and self.root.winfo_exists():
            self._open_usb_setup()

    def _open_usb_setup(self) -> None:
        if self.engine.is_active or self._video_active_path is not None:
            messagebox.showinfo(
                "Cámara USB", "Detenga la adquisición antes de ajustar la cámara.",
                parent=self.root,
            )
            return
        try:
            self._show_usb_setup(acquisition=False)
        except (RuntimeError, ValueError) as exc:
            messagebox.showerror("Cámara USB", str(exc), parent=self.root)

    def _before_oct_start(self, output: Path | None) -> None:
        mode = self.capture_mode_var.get()
        if mode == "Sin captura":
            return
        index = int(self.usb_index_var.get())
        if not self._usb_stream.running:
            self._usb_stream.start(index)
        self._usb_stream.restore_manual_controls()
        transform = self._media_transform()
        area = self.capture_area_var.get().lower()
        if mode == "Foto":
            path = self._media_path(output, ".png")
            self._usb_stream.capture_photo(path, transform=transform)
            self._append_log(f"Foto USB ({area}) capturada antes de OCT: {path}")
            return
        if mode != "Video":
            raise ValueError("Elija Sin captura, Foto o Video para la cámara USB.")
        path = self._media_path(output, ".mp4")
        self._usb_stream.start_recording(path, transform=transform)
        self._video_active_path = path
        self.capture_mode_combo.configure(state="disabled")
        self.capture_area_combo.configure(state="disabled")
        self.usb_selector.configure(state="disabled")
        self.usb_connect_button.configure(state="disabled")
        self.usb_setup_button.configure(state="disabled")
        self._append_log(f"Video USB iniciado antes de OCT: {path}")

    def _usable_roi(self) -> CameraROI | None:
        roi = self._camera_roi
        if roi is None or int(self.usb_index_var.get()) != roi.camera_index:
            return None
        return roi

    def _media_transform(self) -> Callable[[np.ndarray], np.ndarray] | None:
        """Frame transform for photo/video: ROI crop (optional) + X/Y inversion."""
        crop = self.capture_area_var.get() == "Solo ROI"
        roi = self._usable_roi()
        if roi is None:
            if crop:
                raise ValueError(
                    "No hay ROI calibrada para esta cámara: use 'FOV completo' o el setup de cámara."
                )
            return None
        if not crop and not (roi.flip_x or roi.flip_y):
            return None

        def transform(frame: np.ndarray) -> np.ndarray:
            return oriented_view(frame, roi, crop=crop)[0]

        latest, _status = self._usb_stream.peek_frame()
        if latest is not None:
            try:
                transform(latest)  # fail before OCT starts, not inside the video thread
            except ValueError as exc:
                raise ValueError(f"No se puede guardar el área seleccionada: {exc}") from exc
        return transform

    def _stop_usb_video(self) -> None:
        if self._video_active_path is None:
            return
        try:
            path, frames = self._usb_stream.stop_recording()
            self._append_log(f"Video USB finalizado: {path} · {frames} fotogramas.")
            if self._usb_stream.last_record_error:
                self._append_log(f"Advertencia de video USB: {self._usb_stream.last_record_error}")
        except Exception as exc:
            self._append_log(f"Error al finalizar video USB: {exc}")
        finally:
            self._video_active_path = None
            self.capture_mode_combo.configure(state="readonly")
            self.capture_area_combo.configure(state="readonly")
            self.usb_selector.configure(state="readonly")
            self.usb_connect_button.configure(state="normal")
            self.usb_setup_button.configure(state="normal")

    def _on_oct_start_failed(self) -> None:
        self._stop_usb_video()

    def _clear_preview(self, message: str) -> None:
        super()._clear_preview(message)
        self.usb_panel.grid()
        if not self._usb_stream.running and not self._alignment_active:
            self._connect_usb()
        self._render_usb()

    def _start_alignment(self) -> None:
        super()._start_alignment()
        # The base action handles validation/confirmation internally. If it
        # returns without starting, keep the USB view available.
        if not self._alignment_active and not self._closing:
            self.usb_panel.grid()
            self._connect_usb()

    def _handle_event(self, event: EngineEvent) -> None:
        super()._handle_event(event)
        if event.kind == "state" and event.payload.get("state") in {
            EngineState.COMPLETED.value, EngineState.STOPPED.value, EngineState.ERROR.value,
        }:
            self._stop_usb_video()
        if (
            event.kind == "state"
            and self._alignment_active
            and event.payload.get("state") in {
                EngineState.COMPLETED.value,
                EngineState.STOPPED.value,
                EngineState.ERROR.value,
            }
            and not self._closing
        ):
            self._alignment_active = False
            self.alignment_zoom_canvas.grid_remove()
            self.usb_panel.grid()
            self._connect_usb()

    def _poll_usb(self) -> None:
        if self._closing or not self.root.winfo_exists():
            return
        frame, status = self._usb_stream.snapshot()
        self.usb_status_var.set(status)
        if frame is not None:
            self._usb_last_frame = frame
            self._render_usb()
        self._usb_after = self.root.after(self.USB_REFRESH_MS, self._poll_usb)

    def _render_usb(self) -> None:
        canvas = self.usb_canvas
        canvas.delete("all")
        frame = self._usb_last_frame
        if frame is None:
            canvas.create_text(
                14, 18, anchor="nw", fill="#9bb2cf", font=("Segoe UI", 10),
                width=max(100, canvas.winfo_width() - 28),
                text=self.usb_status_var.get(),
            )
            return
        roi = self._camera_roi
        warning = self._roi_load_error
        calibrated = False
        if roi is not None:
            try:
                if int(self.usb_index_var.get()) != roi.camera_index:
                    raise ValueError("Cámara distinta a la calibrada; repita el setup ROI.")
                frame, roi = oriented_view(frame, roi, crop=self.roi_enabled_var.get())
                calibrated = True
            except ValueError as exc:
                warning = str(exc)
        elif self.pattern_overlay_var.get():
            warning = "Calibre la ROI con ⚙ → Setup de cámara para ver el patrón en mm."
        height, width = frame.shape[:2]
        canvas_width = max(1, canvas.winfo_width())
        canvas_height = max(1, canvas.winfo_height())
        scale = min(canvas_width / width, canvas_height / height)
        display_width = max(1, int(width * scale))
        display_height = max(1, int(height * scale))
        pil = Image.fromarray(frame, mode="RGB")
        pil = pil.resize((display_width, display_height), Image.Resampling.BILINEAR)
        if self.pattern_overlay_var.get() and calibrated:
            try:
                scan = self._active_scan if (self.engine.is_active or self._alignment_active) else self._configs()[0]
                if scan is not None:
                    pil = render_pattern(pil, scan, roi, scale, cropped=self.roi_enabled_var.get())
            except (ValueError, KeyError) as exc:
                warning = f"Indicador no disponible: {exc}"
        self._usb_photo = ImageTk.PhotoImage(pil)
        canvas.create_image(canvas_width / 2, canvas_height / 2, image=self._usb_photo, anchor="center")
        if warning:
            canvas.create_text(8, 8, anchor="nw", fill="#ffdf4d", width=max(80, canvas_width - 16), text=warning)

    def _open_roi_setup(self) -> None:
        """Run the camera ROI calibration (run_camera_roi_setup) inside the GUI."""
        if self.engine.is_active or self._video_active_path is not None or self._alignment_active:
            messagebox.showinfo(
                "Setup de cámara", "Detenga la adquisición antes de calibrar la cámara.", parent=self.root,
            )
            return
        self.usb_settings_window.withdraw()
        window = tk.Toplevel(self.root)
        window.transient(self.root)
        try:
            self._roi_setup = CameraROISetup(
                window, self._usb_stream, int(self.usb_index_var.get()), DEFAULT_ROI_PATH, autosave=True,
            )
        except (RuntimeError, ValueError) as exc:
            window.destroy()
            messagebox.showerror("Setup de cámara", str(exc), parent=self.root)
            self._connect_usb()
            return
        window.grab_set()
        window.bind("<Destroy>", lambda event: event.widget is window and self._roi_setup_closed())

    def _roi_setup_closed(self) -> None:
        # The setup stops the shared USB stream when it closes: reload and reconnect.
        try:
            self.root.after_idle(self._resume_after_roi_setup)
        except tk.TclError:
            pass  # main window already closing

    def _resume_after_roi_setup(self) -> None:
        if self._closing or not self.root.winfo_exists():
            return
        setup, self._roi_setup = getattr(self, "_roi_setup", None), None
        message = getattr(setup, "result_message", "")
        self._reload_camera_roi()
        self._append_log(self._roi_load_error or message or "Setup de cámara cerrado sin cambios.")
        self._connect_usb()

    def _reload_camera_roi(self) -> None:
        try:
            self._camera_roi = CameraROI.load(DEFAULT_ROI_PATH)
            self._roi_load_error = "" if self._camera_roi else "No existe camera_roi.json; ejecute el setup ROI."
        except (OSError, ValueError, TypeError, KeyError) as exc:
            self._camera_roi = None
            self._roi_load_error = f"ROI no cargada: {exc}"
        self._render_usb()

    def _on_close(self) -> None:
        super()._on_close()

    def _before_root_destroy(self) -> None:
        self._stop_usb_video()
        self._usb_stream.stop()
        super()._before_root_destroy()
        if self._usb_after is not None:
            self.root.after_cancel(self._usb_after)
            self._usb_after = None
        if self._setup_after is not None:
            self.root.after_cancel(self._setup_after)
            self._setup_after = None


def main() -> None:
    root = tk.Tk()
    OCTOCEUSBApp(root)
    root.mainloop()
