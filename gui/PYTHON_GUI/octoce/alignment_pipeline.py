"""Guided spectrometer/interferometer alignment pipeline.

The steps follow the usual SD-OCT protocol of covering one arm at a time:

1. Oscuro            both arms covered -> dark level (optional)
2. Referencia        sample covered, reference iris -> Ir at 50-65 % of saturation
3. Forma espectral   camera height/rotation and grating against the reference shape
4. Muestra           reference covered, sample iris -> Is below the anti-saturation limit
5. Interferencia     both arms open, mirror at 150-600 um -> visibility, no saturation
6. Enfoque           mirror at 1.5-2.6 mm -> maximise fringe contrast, even blue/red
7. Verificacion      mirror back near zero delay; shape, PSF, roll-off; report

Covering each arm gives Ir(px) and Is(px).  Their ratio rho = Is/Ir does not
depend on the spectrometer (both arms share it), so the absolute fringe
visibility V = C (1+rho) / (2 sqrt(rho)) stays valid while the spectrometer is
being adjusted, and (sqrt(Ir)+sqrt(Is))^2 predicts saturation before opening
both arms.  Focus is judged at depth because near zero delay the fringes are too
coarse to see it: optimising the FWHM there can silently defocus the
spectrometer and kill the penetration.
"""
from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Sequence

import numpy as np

from .alignment_metrics import AlignmentReference, AlignmentResult, lowpass_envelope

# Fringe contrast vs mirror depth of Penetration_3 (best alignment), measured with
# AlignmentProcessor.fringe_metrics on the exported TDMS series.
P3_CONTRAST_CURVE = (
    (79.0, 0.867), (579.0, 0.815), (1080.0, 0.679), (1580.0, 0.602), (2080.0, 0.497),
    (2580.0, 0.407), (3078.0, 0.322), (3579.0, 0.240), (4079.0, 0.170),
)


@dataclass
class PipelineTargets:
    reference_min_pct: float = 50.0
    reference_max_pct: float = 65.0
    interference_max_pct: float = 90.0
    sample_min_pct: float = 1.0
    dark_max_pct: float = 10.0
    shallow_depth_um: tuple[float, float] = (150.0, 600.0)
    focus_depth_um: tuple[float, float] = (1500.0, 2600.0)
    visibility_good: float = 0.7
    visibility_warn: float = 0.5
    snr_good_db: float = 30.0
    blue_red: tuple[float, float] = (1.0, 1.3)          # P3: 1.08-1.22 at every depth
    blue_red_warn: tuple[float, float] = (0.85, 1.45)
    rolloff_db_mm: float = -1.89                         # P3 fringe-contrast roll-off (10*log10)
    sharpness_drop_warn: float = 0.85
    contrast_curve: tuple[tuple[float, float], ...] = P3_CONTRAST_CURVE

    @classmethod
    def load(cls, path: Path) -> "PipelineTargets":
        targets = cls()
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            for key, value in data.items():
                if hasattr(targets, key) and not key.startswith("_"):
                    current = getattr(targets, key)
                    if isinstance(current, tuple):
                        value = tuple(tuple(v) if isinstance(v, list) else v for v in value)
                    setattr(targets, key, value)
        return targets

    def save(self, path: Path) -> None:
        data = asdict(self)
        data["_descripcion"] = (
            "Objetivos del pipeline de alineación. Porcentajes respecto a la saturación del sensor; "
            "roll-off del contraste de franjas en dB/mm (10*log10, convención de Penetration_Analysis); "
            "contrast_curve = contraste de franjas de Penetration_3 frente a la profundidad (µm).")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")

    def expected_relative_contrast(self, z_shallow_um: float, z_deep_um: float) -> float:
        z = np.array([c[0] for c in self.contrast_curve])
        c = np.log(np.array([c[1] for c in self.contrast_curve]))
        return float(np.exp(np.interp(z_deep_um, z, c) - np.interp(z_shallow_um, z, c)))


@dataclass
class Criterion:
    label: str
    value: str
    target: str
    status: str   # good | warn | bad | neutral


@dataclass
class StepView:
    criteria: list[Criterion]
    hint: str = ""
    ready: bool = False
    can_capture: bool = True


@dataclass(frozen=True)
class StepDef:
    key: str
    title: str
    instructions: str
    capture_label: str | None
    optional: bool = False


STEPS: tuple[StepDef, ...] = (
    StepDef("oscuro", "Nivel oscuro",
            "Cierre los dos diafragmas (o tape la entrada del espectrómetro) y capture el nivel oscuro. "
            "Se restará de los espectros en los pasos siguientes.",
            "Capturar oscuro", optional=True),
    StepDef("referencia", "Potencia del brazo de referencia",
            "Tape por completo el brazo de muestra. Abra el diafragma de referencia hasta que el máximo "
            "del espectro quede en la banda verde: deja margen para las franjas sin saturar.",
            "Capturar referencia (Ir)"),
    StepDef("forma", "Forma espectral sobre la cámara",
            "Con solo la referencia, ajuste altura/rotación de la cámara y la rejilla hasta que la curva "
            "naranja se superponga a la referencia (lado azul y rojo). No toque aún el enfoque.",
            None),
    StepDef("muestra", "Potencia del brazo de muestra",
            "Tape por completo el brazo de referencia y destape la muestra (espejo). Ajuste su diafragma "
            "por debajo del límite calculado con Ir: así las franjas no saturarán al abrir ambos brazos.",
            "Capturar muestra (Is)"),
    StepDef("interferencia", "Interferencia cerca del retardo cero",
            "Destape ambos brazos y coloque el espejo a 150–600 µm. Compruebe que no hay saturación y "
            "que la visibilidad de franjas es alta; después capture este punto superficial.",
            "Capturar punto superficial"),
    StepDef("enfoque", "Enfoque del espectrómetro (espejo a ~2 mm)",
            "Mueva el espejo a 1.5–2.6 mm y NO lo mueva durante el paso. Ajuste el enfoque de la "
            "lente/cámara para MAXIMIZAR el contraste; luego la inclinación de la cámara para que el "
            "contraste azul/rojo quede en la banda verde. Ignore aquí el FWHM.",
            "Capturar punto profundo"),
    StepDef("verificacion", "Verificación final (espejo a 150–600 µm)",
            "Vuelva a acercar el espejo SIN tocar el enfoque. Revise forma, PSF y roll-off; al fijar el "
            "estado final se guarda la nitidez espectral para avisar si después se desenfoca.",
            "Fijar estado final"),
)


FRINGE_PRESENT_CONTRAST = 0.03


def _grade(ok: bool, warn: bool) -> str:
    return "good" if ok else "warn" if warn else "bad"


def _fmt(value: float | None, spec: str = ".2f", suffix: str = "") -> str:
    if value is None or not math.isfinite(value):
        return "—"
    return f"{value:{spec}}{suffix}"


class AlignmentPipeline:
    def __init__(self, targets: PipelineTargets, *, sensor_max: float = 4095.0,
                 envelope_bins: int = 6):
        self.targets = targets
        self.sensor_max = float(sensor_max)
        self.envelope_bins = envelope_bins
        self.index = 0
        self.completed: set[str] = set()
        self.skipped: set[str] = set()
        self.dark: np.ndarray | None = None
        self.ir: np.ndarray | None = None
        self.is_: np.ndarray | None = None
        self.rho: np.ndarray | None = None
        self.shallow: dict[str, float] | None = None
        self.deep: dict[str, float] | None = None
        self.final: dict[str, float] | None = None
        self.best_focus: dict[str, float] | None = None
        self.sharpness_baseline: float | None = None
        self.started = datetime.now()
        self.log: list[str] = []

    # -- navigation -------------------------------------------------------------
    @property
    def step(self) -> StepDef:
        return STEPS[self.index]

    def goto(self, index: int) -> None:
        self.index = max(0, min(len(STEPS) - 1, index))

    def next(self) -> None:
        self.completed.add(self.step.key)
        self.goto(self.index + 1)

    def skip(self) -> None:
        self.skipped.add(self.step.key)
        self.goto(self.index + 1)

    def status_of(self, key: str) -> str:
        if key == self.step.key:
            return "active"
        if key in self.completed:
            return "done"
        if key in self.skipped:
            return "skipped"
        return "pending"

    # -- derived quantities -----------------------------------------------------------
    def _minus_dark(self, spectrum: np.ndarray) -> np.ndarray:
        return spectrum - self.dark if self.dark is not None else spectrum

    def sample_limit_counts(self) -> float | None:
        """Largest Is (above dark) that keeps (sqrt(Ir)+sqrt(Is))^2 under the interference limit."""
        if self.ir is None:
            return None
        ir = np.maximum(lowpass_envelope(self.ir, self.envelope_bins), 0.0)
        dark_level = float(np.median(self.dark)) if self.dark is not None else 0.0
        budget = self.targets.interference_max_pct / 100.0 * self.sensor_max - dark_level
        bright = ir > 0.2 * ir.max()
        headroom = np.sqrt(max(budget, 0.0)) - np.sqrt(ir[bright])
        return float(np.min(np.maximum(headroom, 0.0)) ** 2)

    def contrast_drop_db(self) -> tuple[float | None, float | None]:
        """Fringe-contrast drop between the shallow and deep points and the drop of
        Penetration_3 between the same depths (10*log10, Penetration convention)."""
        if not (self.shallow and self.deep):
            return None, None
        key = "visibility" if math.isfinite(self.shallow.get("visibility", math.nan)) and             math.isfinite(self.deep.get("visibility", math.nan)) else "contrast"
        a, b = self.shallow[key], self.deep[key]
        if not (math.isfinite(a) and math.isfinite(b)) or a <= 0 or b <= 0:
            return None, None
        expected = self.targets.expected_relative_contrast(self.shallow["depth_um"], self.deep["depth_um"])
        return 10.0 * math.log10(b / a), 10.0 * math.log10(expected)

    def rolloff_db_mm(self) -> tuple[float | None, str]:
        if not (self.shallow and self.deep):
            return None, ""
        key = "visibility" if math.isfinite(self.shallow.get("visibility", math.nan)) and \
            math.isfinite(self.deep.get("visibility", math.nan)) else "contrast"
        dz_mm = (self.deep["depth_um"] - self.shallow["depth_um"]) / 1000.0
        if dz_mm <= 0.2 or self.shallow[key] <= 0 or self.deep[key] <= 0:
            return None, key
        return 10.0 * math.log10(self.deep[key] / self.shallow[key]) / dz_mm, key

    # -- live evaluation -----------------------------------------------------------------
    def evaluate(self, r: AlignmentResult, reference: AlignmentReference | None) -> StepView:
        handler: Callable[[AlignmentResult, AlignmentReference | None], StepView] = getattr(
            self, f"_eval_{self.step.key}")
        return handler(r, reference)

    def _power_pct(self, r: AlignmentResult) -> float:
        return 100.0 * r.spectrum.max_counts / self.sensor_max

    def _no_fringes(self, r: AlignmentResult, blocked: str) -> Criterion:
        # Without interference the demodulated fringe contrast is ~0.005 (noise and
        # spectral structure); a mirror gives 0.1-0.9.  The PSF SNR is not usable
        # here: the envelope tail near DC always looks like a "peak".
        f = r.fringe
        contrast = f.contrast if f is not None and f.valid else 0.0
        clean = contrast < FRINGE_PRESENT_CONTRAST
        return Criterion("Interferencia", "ninguna" if clean else f"contraste {contrast:.2f}",
                         f"ninguna (brazo de {blocked} tapado)", "good" if clean else "bad")

    def _eval_oscuro(self, r: AlignmentResult, _ref: AlignmentReference | None) -> StepView:
        pct = self._power_pct(r)
        ok = pct < self.targets.dark_max_pct
        crit = [Criterion("Cuentas máximas", f"{r.spectrum.max_counts:.0f} ({pct:.0f} %)",
                          f"< {self.targets.dark_max_pct:.0f} %", "good" if ok else "bad")]
        return StepView(crit, "" if ok else "Todavía entra luz: tape ambos brazos.", ready=ok, can_capture=ok)

    def _eval_referencia(self, r: AlignmentResult, _ref: AlignmentReference | None) -> StepView:
        t = self.targets
        pct = self._power_pct(r)
        good = t.reference_min_pct <= pct <= t.reference_max_pct
        warn = t.reference_min_pct - 10 <= pct <= t.reference_max_pct + 10
        sat = r.spectrum.saturated_fraction > 0
        crit = [
            Criterion("Máximo del espectro", f"{r.spectrum.max_counts:.0f} ({pct:.0f} %)",
                      f"{t.reference_min_pct:.0f}–{t.reference_max_pct:.0f} % "
                      f"({t.reference_min_pct / 100 * self.sensor_max:.0f}–"
                      f"{t.reference_max_pct / 100 * self.sensor_max:.0f})",
                      "bad" if sat else _grade(good, warn)),
            Criterion("Píxeles saturados", f"{100 * r.spectrum.saturated_fraction:.2f} %", "0 %",
                      "bad" if sat else "good"),
            self._no_fringes(r, "muestra"),
        ]
        hint = ("Abra el diafragma de referencia." if pct < t.reference_min_pct else
                "Cierre un poco el diafragma de referencia." if pct > t.reference_max_pct else "")
        ready = good and not sat and crit[2].status == "good"
        return StepView(crit, hint, ready=ready, can_capture=not sat)

    def _eval_forma(self, r: AlignmentResult, ref: AlignmentReference | None) -> StepView:
        if ref is None:
            return StepView([], "Cargue una referencia espectral.", ready=False, can_capture=False)
        s, rs = r.spectrum, ref.metrics
        rms = r.rms_diff_pct if r.rms_diff_pct is not None else math.nan
        d_ratio = s.ratio - rs.ratio
        rel = s.fwhm_spectrum_um / rs.fwhm_spectrum_um - 1.0
        crit = [
            Criterion("Equilibrio azul/rojo", f"{s.ratio:.3f}", f"{rs.ratio:.3f} ± 0.03",
                      _grade(abs(d_ratio) <= 0.03, abs(d_ratio) <= 0.08)),
            Criterion("Forma (RMS)", _fmt(rms, ".1f", " %"), "< 3 %", _grade(rms <= 3, rms <= 6)),
            Criterion("FWHM que permite el espectro", f"{s.fwhm_spectrum_um:.2f} µm",
                      f"≤ {rs.fwhm_spectrum_um * 1.02:.2f} µm", _grade(rel <= 0.02, rel <= 0.08)),
            Criterion("Bordes al 50 %", f"{s.edges50_px[0]}–{s.edges50_px[1]} px",
                      f"{rs.edges50_px[0]}–{rs.edges50_px[1]} px",
                      _grade(max(abs(s.edges50_px[0] - rs.edges50_px[0]),
                                 abs(s.edges50_px[1] - rs.edges50_px[1])) <= 30, True)),
        ]
        ready = all(c.status == "good" for c in crit[:3])
        return StepView(crit, "Lado azul/rojo: vea los porcentajes sobre la gráfica principal.",
                        ready=ready, can_capture=False)

    def _eval_muestra(self, r: AlignmentResult, _ref: AlignmentReference | None) -> StepView:
        limit = self.sample_limit_counts()
        level = float(np.max(lowpass_envelope(self._minus_dark(r.frame_mean), self.envelope_bins))) \
            if r.frame_mean is not None else r.spectrum.max_counts
        pct = 100.0 * level / self.sensor_max
        crit = []
        if limit is None:
            crit.append(Criterion("Límite anti-saturación", "—", "capture antes Ir (paso 2)", "warn"))
            status = "neutral"
        else:
            status = _grade(level <= limit, level <= 1.3 * limit)
            if pct < self.targets.sample_min_pct:
                status = "warn"
        crit.insert(0, Criterion("Brazo de muestra (máx)", f"{level:.0f} ({pct:.1f} %)",
                                 f"≤ {limit:.0f} ({100 * limit / self.sensor_max:.1f} %)" if limit else "—",
                                 status))
        crit.append(self._no_fringes(r, "referencia"))
        hint = ""
        if limit is not None and level > limit:
            hint = "Cierre el diafragma de muestra: con Ir actual las franjas saturarían."
        elif pct < self.targets.sample_min_pct:
            hint = "Señal de muestra muy débil: abra un poco el diafragma de muestra."
        ready = status == "good" and crit[-1].status == "good"
        return StepView(crit, hint, ready=ready, can_capture=crit[-1].status == "good")

    def _fringe_criteria(self, r: AlignmentResult) -> tuple[float, float]:
        f = r.fringe
        if f is None or not f.valid:
            return math.nan, math.nan
        return f.contrast, f.visibility

    def _eval_interferencia(self, r: AlignmentResult, _ref: AlignmentReference | None) -> StepView:
        t = self.targets
        depth = r.psf.depth_um if r.psf is not None else math.nan
        snr = r.psf.snr_db if r.psf is not None else math.nan
        pct = self._power_pct(r)
        contrast, vis = self._fringe_criteria(r)
        lo, hi = t.shallow_depth_um
        crit = [
            Criterion("Profundidad del espejo", _fmt(depth, ".0f", " µm"), f"{lo:.0f}–{hi:.0f} µm",
                      _grade(lo <= depth <= hi, 100 <= depth <= 900)),
            Criterion("Máximo con franjas", f"{r.spectrum.max_counts:.0f} ({pct:.0f} %)",
                      f"≤ {t.interference_max_pct:.0f} %",
                      "bad" if r.spectrum.saturated_fraction > 0 else
                      _grade(pct <= t.interference_max_pct, pct <= 97)),
            Criterion("SNR del pico", _fmt(snr, ".0f", " dB"), f"≥ {t.snr_good_db:.0f} dB",
                      _grade(snr >= t.snr_good_db, snr >= 20)),
        ]
        if math.isfinite(vis) and vis > 1.15:
            crit.append(Criterion("Visibilidad de franjas", f"{vis:.2f}",
                                  "> 1: Is/Ir ya no corresponde (¿movió un diafragma?) · recapture pasos 2 y 4",
                                  "warn"))
        elif math.isfinite(vis):
            crit.append(Criterion("Visibilidad de franjas", f"{vis:.2f}", f"≥ {t.visibility_good:.2f}",
                                  _grade(vis >= t.visibility_good, vis >= t.visibility_warn)))
        else:
            crit.append(Criterion("Contraste de franjas", _fmt(contrast), "capture Ir e Is para la visibilidad",
                                  "neutral"))
        ready = all(c.status in ("good", "neutral") for c in crit)
        hint = ""
        if r.spectrum.saturated_fraction > 0 or pct > t.interference_max_pct:
            hint = "Hay saturación con franjas: cierre algo el diafragma de muestra (o el de referencia)."
        elif not lo <= depth <= hi:
            hint = f"Coloque el espejo entre {lo:.0f} y {hi:.0f} µm."
        return StepView(crit, hint, ready=ready, can_capture=math.isfinite(contrast))

    def _eval_enfoque(self, r: AlignmentResult, _ref: AlignmentReference | None) -> StepView:
        t = self.targets
        depth = r.psf.depth_um if r.psf is not None else math.nan
        contrast, vis = self._fringe_criteria(r)
        blue_red = r.fringe.blue_red if r.fringe is not None and r.fringe.valid else math.nan
        lo, hi = t.focus_depth_um
        in_range = lo <= depth <= hi
        if in_range and math.isfinite(contrast):
            best = self.best_focus
            # the best value is only comparable at the same mirror depth
            if best is None or abs(depth - best["depth_um"]) > 60 or contrast > best["contrast"]:
                self.best_focus = {"depth_um": depth, "contrast": contrast,
                                   "blue_red": blue_red, "t": datetime.now().timestamp()}
        crit = [Criterion("Profundidad del espejo", _fmt(depth, ".0f", " µm"), f"{lo:.0f}–{hi:.0f} µm",
                          _grade(in_range, False))]
        if self.best_focus is not None and math.isfinite(contrast):
            frac = contrast / self.best_focus["contrast"]
            crit.append(Criterion("Contraste de franjas", f"{contrast:.3f}",
                                  f"máximo de la sesión {self.best_focus['contrast']:.3f}",
                                  _grade(frac >= 0.97, frac >= 0.9)))
        else:
            crit.append(Criterion("Contraste de franjas", _fmt(contrast, ".3f"), "maximizar", "neutral"))
        if self.shallow is not None and math.isfinite(contrast) and math.isfinite(self.shallow["contrast"]):
            rel = contrast / self.shallow["contrast"]
            expected = t.expected_relative_contrast(self.shallow["depth_um"], depth)
            crit.append(Criterion("Contraste relativo al superficial", f"{rel:.2f}",
                                  f"P3 a esta profundidad: {expected:.2f}",
                                  _grade(rel >= 0.95 * expected, rel >= 0.8 * expected)))
        br_lo, br_hi = t.blue_red
        w_lo, w_hi = t.blue_red_warn
        crit.append(Criterion("Contraste azul/rojo", _fmt(blue_red), f"{br_lo:.2f}–{br_hi:.2f} (P3)",
                              _grade(br_lo <= blue_red <= br_hi, w_lo <= blue_red <= w_hi)))
        hint = ""
        if not in_range:
            hint = f"Mueva el espejo a {lo / 1000:.1f}–{hi / 1000:.1f} mm: cerca de 0 el enfoque no se ve."
        elif math.isfinite(blue_red) and blue_red < br_lo:
            hint = "El extremo azul pierde contraste: incline la cámara para enfocar mejor el lado azul."
        elif math.isfinite(blue_red) and blue_red > br_hi:
            hint = "El extremo rojo pierde contraste: incline la cámara para enfocar mejor el lado rojo."
        ready = in_range and all(c.status in ("good", "neutral") for c in crit)
        return StepView(crit, hint, ready=ready, can_capture=in_range and math.isfinite(contrast))

    def _eval_verificacion(self, r: AlignmentResult, ref: AlignmentReference | None) -> StepView:
        t = self.targets
        depth = r.psf.depth_um if r.psf is not None else math.nan
        lo, hi = t.shallow_depth_um
        crit = [Criterion("Profundidad del espejo", _fmt(depth, ".0f", " µm"), f"{lo:.0f}–{hi:.0f} µm",
                          _grade(lo <= depth <= hi, 60 <= depth <= 900))]
        if ref is not None:
            rms = r.rms_diff_pct if r.rms_diff_pct is not None else math.nan
            crit.append(Criterion("Forma (RMS)", _fmt(rms, ".1f", " %"), "< 3 %", _grade(rms <= 3, rms <= 6)))
        if r.psf is not None:
            crit.append(Criterion("FWHM del espejo", f"{r.psf.fwhm_fit_um:.2f} µm",
                                  f"ref. {ref.psf.fwhm_fit_um:.2f} µm" if ref and ref.psf else "—", "neutral"))
        drop, p3_drop = self.contrast_drop_db()
        if drop is not None and p3_drop is not None:
            z1, z2 = self.shallow["depth_um"] / 1000, self.deep["depth_um"] / 1000
            crit.append(Criterion(f"Caída de contraste {z1:.2f}→{z2:.2f} mm", f"{drop:+.1f} dB",
                                  f"P3 entre las mismas profundidades: {p3_drop:+.1f} dB",
                                  _grade(drop >= p3_drop - 0.5, drop >= p3_drop - 1.5)))
        else:
            crit.append(Criterion("Caída de contraste con la profundidad", "—",
                                  "capture los puntos superficial y profundo", "warn"))
        ready = all(c.status in ("good", "neutral") for c in crit)
        return StepView(crit, "", ready=ready, can_capture=r.psf is not None)

    # -- captures ------------------------------------------------------------------------------
    def capture(self, results: Sequence[AlignmentResult]) -> str:
        """Store the averaged state of the current step from several frames."""
        if not results:
            raise ValueError("No hay cuadros para capturar.")
        means = [r.frame_mean for r in results if r.frame_mean is not None]
        mean = np.mean(np.vstack(means), axis=0) if means else results[-1].spectrum.mean_spectrum
        key = self.step.key

        def avg(getter: Callable[[AlignmentResult], float]) -> float:
            vals = [getter(r) for r in results]
            vals = [v for v in vals if v is not None and math.isfinite(v)]
            return float(np.mean(vals)) if vals else math.nan

        if key == "oscuro":
            self.dark = mean
            msg = f"Oscuro capturado (media {mean.mean():.1f} cuentas)."
        elif key == "referencia":
            self.ir = self._minus_dark(mean)
            msg = f"Ir capturado (máximo {self.ir.max():.0f} cuentas)."
            self._update_rho()
        elif key == "muestra":
            self.is_ = self._minus_dark(mean)
            self._update_rho()
            msg = f"Is capturado (máximo {self.is_.max():.0f} cuentas; Is/Ir medio {self.mean_rho():.3f})."
        elif key in ("interferencia", "enfoque", "verificacion"):
            point = {
                "depth_um": avg(lambda r: r.psf.depth_um if r.psf else math.nan),
                "contrast": avg(lambda r: r.fringe.contrast if r.fringe and r.fringe.valid else math.nan),
                "visibility": avg(lambda r: r.fringe.visibility if r.fringe and r.fringe.valid else math.nan),
                "blue_red": avg(lambda r: r.fringe.blue_red if r.fringe and r.fringe.valid else math.nan),
                "fwhm_fit_um": avg(lambda r: r.psf.fwhm_fit_um if r.psf else math.nan),
                "snr_db": avg(lambda r: r.psf.snr_db if r.psf else math.nan),
                "sharpness": avg(lambda r: r.spectrum.sharpness),
                "max_counts": avg(lambda r: r.spectrum.max_counts),
                "fwhm_spectrum_um": avg(lambda r: r.spectrum.fwhm_spectrum_um),
            }
            if key == "interferencia":
                self.shallow = point
                msg = f"Punto superficial a {point['depth_um']:.0f} µm (contraste {point['contrast']:.3f})."
            elif key == "enfoque":
                self.deep = point
                rolloff, _ = self.rolloff_db_mm()
                msg = f"Punto profundo a {point['depth_um']:.0f} µm (contraste {point['contrast']:.3f})" + (
                    f"; roll-off {rolloff:+.2f} dB/mm." if rolloff is not None else ".")
            else:
                self.final = point
                self.sharpness_baseline = point["sharpness"] if math.isfinite(point["sharpness"]) else None
                msg = "Estado final fijado: se vigilará la nitidez espectral para detectar desenfoques."
        else:
            raise ValueError(f"El paso '{key}' no tiene captura.")
        self.log.append(f"{datetime.now():%H:%M:%S} {msg}")
        self.completed.add(key)
        return msg

    def _update_rho(self) -> None:
        if self.ir is None or self.is_ is None:
            self.rho = None
            return
        ir = np.maximum(lowpass_envelope(self.ir, self.envelope_bins), 1e-9)
        is_ = np.maximum(lowpass_envelope(self.is_, self.envelope_bins), 0.0)
        rho = is_ / ir
        bright = ir > 0.1 * ir.max()
        if np.any(bright):   # outside the bright band use the nearest valid value
            idx = np.flatnonzero(bright)
            rho = np.interp(np.arange(rho.size), idx, rho[idx])
        self.rho = np.clip(rho, 1e-6, None)

    def mean_rho(self) -> float:
        if self.rho is None or self.ir is None:
            return math.nan
        ir = lowpass_envelope(self.ir, self.envelope_bins)
        bright = ir > 0.3 * ir.max()
        return float(np.average(self.rho[bright], weights=ir[bright]))

    # -- report -------------------------------------------------------------------------------
    def report(self) -> dict[str, Any]:
        rolloff, basis = self.rolloff_db_mm()
        def arr(a: np.ndarray | None) -> list[float] | None:
            return None if a is None else [round(float(v), 3) for v in a]
        return {
            "creado": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "inicio": self.started.strftime("%Y-%m-%d %H:%M:%S"),
            "pasos_completados": sorted(self.completed),
            "pasos_omitidos": sorted(self.skipped),
            "objetivos": asdict(self.targets),
            "is_ir_medio": self.mean_rho(),
            "limite_muestra_cuentas": self.sample_limit_counts(),
            "punto_superficial": self.shallow,
            "punto_profundo": self.deep,
            "estado_final": self.final,
            "rolloff_dos_puntos_db_mm": rolloff,
            "rolloff_base": basis,
            "caida_contraste_db": self.contrast_drop_db()[0],
            "caida_contraste_P3_mismas_profundidades_db": self.contrast_drop_db()[1],
            "registro": self.log,
            "oscuro": arr(self.dark),
            "ir": arr(self.ir),
            "is": arr(self.is_),
        }

    def save_report(self, folder: Path) -> Path:
        folder.mkdir(parents=True, exist_ok=True)
        path = folder / f"alineacion_{datetime.now():%Y%m%d_%H%M%S}.json"
        path.write_text(json.dumps(self.report(), indent=2, ensure_ascii=False, default=float),
                        encoding="utf-8")
        return path
