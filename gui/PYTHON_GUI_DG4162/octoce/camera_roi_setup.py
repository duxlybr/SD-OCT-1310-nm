"""Optional standalone interactive USB calibration, independent of OCT/NI."""
from __future__ import annotations

import argparse
import math
import tkinter as tk
from dataclasses import replace
from pathlib import Path
from tkinter import messagebox, ttk

from PIL import Image, ImageTk

from .camera_roi import CameraROI, DEFAULT_ROI_PATH
from .usb_camera import USBCameraStream


def geometry_scale(kind, points, real_mm, axis="Horizontal"):
    """Measure a line length, square side or ellipse diameter in sensor pixels."""
    if len(points) != 2 or not math.isfinite(real_mm) or real_mm <= 0:
        raise ValueError("Dibuje una figura e introduzca una medida real positiva.")
    (x0, y0), (x1, y1) = points
    if not all(math.isfinite(v) for v in (x0, y0, x1, y1)):
        raise ValueError("Coordenadas de geometría inválidas.")
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    if kind == "Línea":
        pixels = math.dist(*points)
    elif kind == "Cuadrado":
        if not math.isclose(dx, dy, abs_tol=1e-8):
            raise ValueError("La figura debe tener lados iguales.")
        pixels = dx
    elif kind == "Elipse / círculo":
        if axis not in ("Horizontal", "Vertical"):
            raise ValueError("Seleccione el diámetro horizontal o vertical.")
        if min(dx, dy) < 2:
            raise ValueError("La elipse debe tener dos diámetros de al menos dos píxeles.")
        pixels = dx if axis == "Horizontal" else dy
    else:
        raise ValueError("Figura de calibración desconocida.")
    if pixels < 2:
        raise ValueError("La medida debe ocupar al menos dos píxeles.")
    return pixels / real_mm


def geometry_center(points):
    """Center of the line, square or ellipse defined by its two points."""
    (x0, y0), (x1, y1) = points
    return (x0 + x1) / 2, (y0 + y1) / 2


class CameraROISetup:
    """Calibrate the 15 × 15 mm ROI. With ``autosave`` (GUI use) closing saves the changes."""

    def __init__(self, root, stream, camera_index=0, path=DEFAULT_ROI_PATH, *, autosave=False):
        self.root, self.stream, self.index, self.path = root, stream, camera_index, path
        self.autosave = autosave
        self.result_message = ""
        self._saved = False
        try:
            self.existing = CameraROI.load(path)
        except (OSError, ValueError, TypeError, KeyError):
            self.existing = None
        self.frame = None
        self.points = []
        self.center = None
        self.frozen = False
        self.approved = False
        self._approved_scale = None
        self._drag_mode = None
        self.transform = None
        self.after_id = None
        root.title("Setup USB · calibración y ROI 15 × 15 mm")
        root.geometry("1100x800")
        root.protocol("WM_DELETE_WINDOW", self.close)
        controls = ttk.Frame(root, padding=8)
        controls.pack(fill="x")
        ttk.Label(controls, text="Figura:").pack(side="left")
        self.geometry = tk.StringVar(value="Línea")
        ttk.Combobox(controls, textvariable=self.geometry,
                     values=("Línea", "Cuadrado", "Elipse / círculo"), state="readonly", width=17).pack(side="left", padx=6)
        self.axis = tk.StringVar(value="Horizontal")
        self.axis_selector = ttk.Combobox(controls, textvariable=self.axis,
                                         values=("Horizontal", "Vertical"), state="disabled", width=12)
        self.axis_selector.pack(side="left", padx=6)
        self.measure_label = tk.StringVar(value="Longitud real (mm):")
        ttk.Label(controls, textvariable=self.measure_label).pack(side="left")
        self.distance = tk.StringVar(value="10")
        ttk.Entry(controls, textvariable=self.distance, width=8).pack(side="left", padx=6)
        actions = ttk.Frame(root, padding=(8, 0, 8, 8))
        actions.pack(fill="x")
        ttk.Button(actions, text="Congelar / reiniciar", command=self.freeze).pack(side="left", padx=4)
        self.approve_button = ttk.Button(actions, text="Aprobar geometría", command=self.approve_geometry, state="disabled")
        self.approve_button.pack(side="left", padx=4)
        self.edit_button = ttk.Button(actions, text="Editar geometría", command=self.edit_geometry, state="disabled")
        self.edit_button.pack(side="left", padx=4)
        ttk.Button(actions, text="Guardar ROI", command=self.save).pack(side="left", padx=4)
        axes = ttk.Frame(root, padding=(8, 0, 8, 8))
        axes.pack(fill="x")
        self.flip_x = tk.BooleanVar(value=bool(self.existing and self.existing.flip_x))
        self.flip_y = tk.BooleanVar(value=bool(self.existing and self.existing.flip_y))
        ttk.Checkbutton(axes, text="Invertir X del patrón", variable=self.flip_x,
                        command=self.render).pack(side="left")
        ttk.Checkbutton(axes, text="Invertir Y del patrón", variable=self.flip_y,
                        command=self.render).pack(side="left", padx=12)
        ttk.Label(axes, text="Flechas: sentido +X/+Y de los galvos en la imagen; "
                             "la vista de la GUI se voltea para mostrarlos a la derecha/abajo.").pack(
            side="left", padx=12)
        self.status = tk.StringVar(value="Coloque una referencia en el plano de adquisición y congele la imagen.")
        ttk.Label(root, textvariable=self.status, padding=8, wraplength=1000).pack(fill="x")
        self.canvas = tk.Canvas(root, bg="#07111f", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<Button-1>", self.click)
        self.canvas.bind("<B1-Motion>", self.drag)
        self.canvas.bind("<ButtonRelease-1>", lambda event: self._end_drag())
        self.canvas.bind("<Configure>", lambda event: self.render())
        self.distance.trace_add("write", self._measurement_changed)
        self.axis.trace_add("write", self._measurement_changed)
        self.geometry.trace_add("write", self._geometry_changed)
        stream.start(camera_index)
        self.poll()

    def poll(self):
        if not self.frozen:
            frame, status = self.stream.peek_frame()
            if frame is not None:
                self.frame = frame.copy()
                self.render()
            else:
                self.status.set(status)
        self.after_id = self.root.after(80, self.poll)

    def _measurement_changed(self, *_args):
        self.edit_geometry()

    def _geometry_changed(self, *_args):
        self.points = []
        self._drag_mode = None
        self.edit_geometry()

    def edit_geometry(self):
        self.approved = False
        self._approved_scale = None
        self.center = None
        self.render()

    def freeze(self):
        if self.frame is None:
            return
        self.frozen = not self.frozen
        self.points = []
        self._drag_mode = None
        self.edit_geometry()

    def calibration(self):
        return geometry_scale(self.geometry.get(), self.points,
                              float(self.distance.get().replace(",", ".")), self.axis.get())

    def approve_geometry(self):
        if not self.frozen:
            self.status.set("Congele la imagen antes de aprobar la geometría.")
            return
        try:
            self._approved_scale = self.calibration()
        except ValueError as exc:
            self.status.set(str(exc))
            return
        self.approved = True
        self._drag_mode = None
        self.center = geometry_center(self.points)
        self.render()

    def roi(self):
        if not self.approved:
            raise ValueError("Primero ajuste la figura y pulse Aprobar geometría.")
        height, width = self.frame.shape[:2]
        roi = CameraROI(self.index, width, height, self._approved_scale, *self.center,
                        self.flip_x.get(), self.flip_y.get())
        roi.bounds(width, height)
        return roi

    def _sensor_point(self, event, clamp=False):
        if self.transform is None or self.frame is None:
            return None
        ox, oy, scale = self.transform
        x, y = (event.x - ox) / scale, (event.y - oy) / scale
        height, width = self.frame.shape[:2]
        if clamp:
            return max(0, min(width - 1, x)), max(0, min(height - 1, y))
        return (x, y) if 0 <= x < width and 0 <= y < height else None

    def _endpoint(self, anchor, point):
        if self.geometry.get() != "Cuadrado":
            return point
        dx, dy = point[0] - anchor[0], point[1] - anchor[1]
        sx, sy = (1 if dx >= 0 else -1), (1 if dy >= 0 else -1)
        h, w = self.frame.shape[:2]
        side = min(max(abs(dx), abs(dy)),
                   w - 1 - anchor[0] if sx > 0 else anchor[0],
                   h - 1 - anchor[1] if sy > 0 else anchor[1])
        return anchor[0] + sx * side, anchor[1] + sy * side

    def click(self, event):
        if not self.frozen or self.approved:
            return
        point = self._sensor_point(event)
        if point is None:
            return
        if len(self.points) < 2:
            if not self.points:
                self.points.append(point)
                self._drag_mode = ("draw",)
            else:
                self.points.append(self._endpoint(self.points[0], point))
                self._drag_mode = None
        else:
            tolerance = 10 / self.transform[2]
            for index, handle in enumerate(self.points):
                if math.dist(point, handle) <= tolerance:
                    self._drag_mode = ("handle", index)
                    break
            else:
                a, b = self.points
                inside = min(a[0], b[0]) - tolerance <= point[0] <= max(a[0], b[0]) + tolerance and min(a[1], b[1]) - tolerance <= point[1] <= max(a[1], b[1]) + tolerance
                self._drag_mode = ("move", point, list(self.points)) if inside else None
        self.render()

    def drag(self, event):
        if not self.frozen or self.approved or self._drag_mode is None:
            return
        point = self._sensor_point(event, clamp=True)
        mode = self._drag_mode[0]
        if mode == "draw":
            endpoint = self._endpoint(self.points[0], point)
            self.points = [self.points[0], endpoint]
        elif mode == "handle":
            index = self._drag_mode[1]
            self.points[index] = self._endpoint(self.points[1 - index], point)
        else:
            _mode, origin, original = self._drag_mode
            h, w = self.frame.shape[:2]
            dx = max(-min(p[0] for p in original), min(point[0] - origin[0], w - 1 - max(p[0] for p in original)))
            dy = max(-min(p[1] for p in original), min(point[1] - origin[1], h - 1 - max(p[1] for p in original)))
            self.points = [(x + dx, y + dy) for x, y in original]
        self.render()

    def _end_drag(self):
        self._drag_mode = None

    def render(self):
        if self.frame is None:
            return
        kind = self.geometry.get()
        self.axis_selector.configure(state="readonly" if kind == "Elipse / círculo" else "disabled")
        self.measure_label.set("Longitud real (mm):" if kind == "Línea" else "Lado real (mm):" if kind == "Cuadrado" else f"Diámetro {self.axis.get().lower()} real (mm):")
        self.approve_button.configure(state="normal" if self.frozen and len(self.points) == 2 and not self.approved else "disabled")
        self.edit_button.configure(state="normal" if self.approved else "disabled")
        height, width = self.frame.shape[:2]
        cw, ch = max(1, self.canvas.winfo_width()), max(1, self.canvas.winfo_height())
        scale = min(cw / width, ch / height)
        dw, dh = max(1, round(width * scale)), max(1, round(height * scale))
        ox, oy = (cw - dw) / 2, (ch - dh) / 2
        self.transform = ox, oy, scale
        self.photo = ImageTk.PhotoImage(Image.fromarray(self.frame).resize((dw, dh)))
        self.canvas.delete("all")
        self.canvas.create_image(ox, oy, image=self.photo, anchor="nw")
        color = "#39e68c" if self.approved else "yellow"
        if len(self.points) == 2:
            a, b = self.points
            coords = (ox + a[0]*scale, oy + a[1]*scale, ox + b[0]*scale, oy + b[1]*scale)
            if kind == "Línea":
                self.canvas.create_line(*coords, fill=color, width=2)
            else:
                bounds = (min(coords[0], coords[2]), min(coords[1], coords[3]), max(coords[0], coords[2]), max(coords[1], coords[3]))
                renderer = self.canvas.create_rectangle if kind == "Cuadrado" else self.canvas.create_oval
                renderer(*bounds, outline=color, width=2)
        for x, y in self.points:
            x, y = ox + x * scale, oy + y * scale
            self.canvas.create_oval(x - 5, y - 5, x + 5, y + 5, fill=color)
        if not self.frozen:
            self.status.set("Vista en vivo: coloque la referencia y congele para calibrar.")
        elif not self.approved:
            self.status.set("Dibuje con dos clics o arrastre. Ajuste los extremos arrastrando los puntos; arrastre el interior para mover. Luego pulse Aprobar geometría.")
        else:
            self.status.set(f"Geometría aprobada · {self._approved_scale:.3f} px/mm. Centro de la ROI = centro de la geometría.")
        shown = None
        if self.center is not None:
            try:
                shown = self.roi()
                left, top, right, bottom = shown.bounds(width, height)
                self.canvas.create_rectangle(ox + left*scale, oy + top*scale, ox + right*scale, oy + bottom*scale, outline="red", width=2)
                self.status.set(f"ROI válida: 15 × 15 mm · {shown.pixels_per_mm:.3f} px/mm. Centrada en la geometría aprobada; puede guardar o editar la geometría.")
            except ValueError as exc:
                shown = None
                self.status.set(str(exc))
        elif self.existing is not None and self.existing.camera_index == self.index and not self.points:
            try:
                left, top, right, bottom = self.existing.bounds(width, height)
                shown = self.existing
                self.canvas.create_rectangle(ox + left*scale, oy + top*scale, ox + right*scale, oy + bottom*scale,
                                             outline="red", width=2, dash=(6, 4))
                if not self.frozen:
                    self.status.set("ROI guardada (rojo discontinuo). Cambie la inversión X/Y o congele para recalibrar."
                                    + (" Los cambios se guardan al cerrar." if self.autosave else ""))
            except ValueError:
                shown = None
        if shown is not None:
            self._draw_axes(shown, ox, oy, scale)

    def _draw_axes(self, roi, ox, oy, scale):
        """Arrows for the galvo +X/+Y directions in the camera image (per flips)."""
        length = 15 * roi.pixels_per_mm * 0.3 * scale
        cx, cy = ox + roi.center_x * scale, oy + roi.center_y * scale
        sx = -1 if self.flip_x.get() else 1
        sy = -1 if self.flip_y.get() else 1
        for dx, dy, label in ((sx * length, 0, "+X"), (0, sy * length, "+Y")):
            self.canvas.create_line(cx, cy, cx + dx, cy + dy, fill="#ff5a5a", width=3, arrow="last",
                                    arrowshape=(12, 14, 5))
            self.canvas.create_text(cx + dx * 1.18, cy + dy * 1.18, text=label, fill="#ff5a5a",
                                    font=("Segoe UI", 11, "bold"))

    def save(self):
        try:
            roi = self.roi()
            roi.save(self.path)
        except (ValueError, OSError) as exc:
            messagebox.showerror("ROI", str(exc), parent=self.root)
            return
        self._saved = True
        self.result_message = f"ROI guardada: {roi.pixels_per_mm:.3f} px/mm en {self.path.name}."
        messagebox.showinfo("ROI guardada", f"Configuración guardada en {self.path}", parent=self.root)
        self.close()

    def autosave_changes(self):
        """Save a newly approved ROI, or only the X/Y inversion of the saved one."""
        try:
            if self.approved and self.center is not None:
                roi = self.roi()
                roi.save(self.path)
                self.result_message = f"ROI guardada automáticamente: {roi.pixels_per_mm:.3f} px/mm."
            elif self.existing is not None and (self.flip_x.get(), self.flip_y.get()) != (
                self.existing.flip_x, self.existing.flip_y
            ):
                replace(self.existing, flip_x=self.flip_x.get(), flip_y=self.flip_y.get()).save(self.path)
                self.result_message = (
                    f"Inversión guardada automáticamente: X {'invertido' if self.flip_x.get() else 'normal'}, "
                    f"Y {'invertido' if self.flip_y.get() else 'normal'}."
                )
            elif self.points and not self.approved:
                self.result_message = "Setup cerrado con una geometría sin aprobar: se mantiene la ROI anterior."
        except (ValueError, OSError) as exc:
            self.result_message = f"No se guardó la ROI: {exc}"
        self._saved = True

    def close(self):
        if self.autosave and not self._saved:
            self.autosave_changes()
        if self.after_id is not None:
            self.root.after_cancel(self.after_id)
        self.stream.stop()
        self.root.destroy()


def main():
    parser = argparse.ArgumentParser(description="Calibrar USB y guardar una ROI de 15 × 15 mm")
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--output", type=Path, default=DEFAULT_ROI_PATH)
    args = parser.parse_args()
    root = tk.Tk()
    CameraROISetup(root, USBCameraStream(), args.camera, args.output)
    root.mainloop()
