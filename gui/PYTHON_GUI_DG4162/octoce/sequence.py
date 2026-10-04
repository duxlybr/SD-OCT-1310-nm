"""Programmed acquisition series from an Excel sheet (one row per acquisition)."""
from __future__ import annotations

from dataclasses import dataclass
from math import isfinite
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence

from .config import AcquisitionMode, Orientation, ScanPattern
from .dg4162 import CH2_WAVEFORMS, Excitation, GeneratorSettings, waveform_scpi
from .naming import clean_stem

SHEET_NAME = "Secuencia"

# (column key, description, allowed values / unit, example rows)
COLUMNS: tuple[tuple[str, str, str], ...] = (
    ("modo", "OCE = MB-mode (B→A→M) · OCT = BM-mode (B→M→A)", "OCE, OCT (también MB, BM)"),
    ("patron", "Patrón de barrido", "Raster, Crosshair, Meridianos, Lineal, Anillos, Espiral"),
    ("orientacion", "Solo para patrón Lineal", "Horizontal, Vertical"),
    ("a_lines", "Cantidad de A-lines", "entero ≥ 1"),
    ("b_scans", "Cantidad de B-scans", "entero ≥ 1"),
    ("m_reps", "M repeticiones", "entero ≥ 1"),
    ("sync_samples", "Puntos sync (SyncSamples)", "entero ≥ 0"),
    ("longitud_x_mm", "Longitud X", "mm"),
    ("longitud_y_mm", "Longitud Y", "mm"),
    ("bframes_delay_us", "BFramesDelay", "µs"),
    ("excitacion", "Sin contacto: CH1 ≤ 1 Vpp · Con contacto: CH1 ≤ 5 Vpp", "Sin contacto, Con contacto"),
    ("ch1_mVpp", "Amplitud de CH1 (portadora)", "mVpp; >1000 pide confirmación"),
    ("ch2_frecuencia_Hz", "Frecuencia de la moduladora (CH2)", "Hz"),
    ("ch2_forma_onda", "Forma de onda de la moduladora (CH2)", ", ".join(CH2_WAVEFORMS)),
    ("ch2_retardo_ms", "Retardo del burst de CH2 tras el trigger", "ms (por defecto 2)"),
    ("ch2_ciclos", "Ciclos por burst de CH2", "entero ≥ 1 (por defecto 1)"),
    ("repeticiones", "Veces que se repite esta fila", "entero ≥ 1 (vacío = 1)"),
    ("espera_s", "Espera después de cada adquisición de la fila", "s (vacío = 0)"),
    ("nombre_archivo", "Vacío = nombre por defecto; si existe se añade _1, _2…", "texto sin extensión"),
    ("carpeta", "Vacío = carpeta elegida en la GUI", "ruta"),
    ("notas", "Libre; no se usa", ""),
)
COLUMN_KEYS = tuple(key for key, _desc, _allowed in COLUMNS)
# Columns whose blank cells take the value currently shown in the GUI.
GUI_DEFAULT_KEYS = COLUMN_KEYS[:16]

EXAMPLE_ROWS: tuple[tuple[Any, ...], ...] = (
    ("OCE", "Lineal", "Horizontal", 100, 1, 400, 200, 5.0, 0.0, 0.0,
     "Sin contacto", 300, 1000, "Pulso", 2, 1, 3, 10, "", "", "Ejemplo: 3 repeticiones"),
    ("OCE", "Lineal", "Horizontal", 100, 1, 400, 200, 5.0, 0.0, 0.0,
     "Sin contacto", 500, 2000, "Pulso", 2, 3, 1, 10, "", "", "Otra frecuencia y 3 ciclos"),
    ("OCT", "Raster", "Horizontal", 512, 64, 1, 50, 5.0, 5.0, 0.0,
     "Sin contacto", 500, 1000, "Pulso", 2, 1, 1, 0, "referencia_OCT", "", "Nombre propio"),
)

_PATTERNS = {
    "raster": ScanPattern.RASTER,
    "crosshair": ScanPattern.CROSSHAIR,
    "meridianos": ScanPattern.MERIDIANS,
    "meridianos (polar)": ScanPattern.MERIDIANS,
    "polar": ScanPattern.MERIDIANS,
    "lineal": ScanPattern.LINEAR,
    "linear": ScanPattern.LINEAR,
    "anillos": ScanPattern.RINGS,
    "anillos concéntricos": ScanPattern.RINGS,
    "anillos concentricos": ScanPattern.RINGS,
    "rings": ScanPattern.RINGS,
    "espiral": ScanPattern.SPIRAL,
    "spiral": ScanPattern.SPIRAL,
}
_MODES = {
    "oce": AcquisitionMode.MB, "mb": AcquisitionMode.MB, "mb_mode": AcquisitionMode.MB,
    "oct": AcquisitionMode.BM, "bm": AcquisitionMode.BM, "bm_mode": AcquisitionMode.BM,
}
_ORIENTATIONS = {"horizontal": Orientation.HORIZONTAL, "vertical": Orientation.VERTICAL}


@dataclass(frozen=True, slots=True)
class SequenceJob:
    """One acquisition of the series (a row expanded by its repetitions)."""

    row: int
    repetition: int
    repetitions: int
    mode: AcquisitionMode
    pattern: ScanPattern
    orientation: Orientation
    alines: int
    bscans: int
    m_repetitions: int
    sync_points: int
    x_length_mm: float
    y_length_mm: float
    bframes_delay_us: float
    generator: GeneratorSettings
    wait_s: float
    name: str
    folder: str


# Preparation per acquisition (generator programming, NI arming, file header
# and closing) assumed until real acquisitions of this session are measured.
DEFAULT_OVERHEAD_S = 3.0


@dataclass(frozen=True, slots=True)
class DurationModel:
    """Real duration ≈ scale × minimum duration + overhead per acquisition."""

    scale: float = 1.0
    overhead_s: float = DEFAULT_OVERHEAD_S

    def predict(self, minimum_s: float) -> float:
        return self.scale * minimum_s + self.overhead_s

    @classmethod
    def fit(cls, samples: Sequence[tuple[float, float]], recent: int = 20) -> "DurationModel":
        """Fit (minimum, real) seconds of completed acquisitions; newest ``recent`` only.

        With acquisitions of clearly different length both terms are fitted by
        least squares; otherwise the extra time is all overhead (scale 1).
        """
        samples = list(samples)[-recent:]
        if not samples:
            return cls()
        xs = [float(x) for x, _y in samples]
        ys = [float(y) for _x, y in samples]
        mean_x, mean_y = sum(xs) / len(xs), sum(ys) / len(ys)
        spread = max(xs) - min(xs)
        if len(xs) >= 2 and spread >= max(1.0, 0.2 * mean_x):
            sxx = sum((x - mean_x) ** 2 for x in xs)
            sxy = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
            scale = min(5.0, max(1.0, sxy / sxx))
        else:
            scale = 1.0
        return cls(scale, max(0.0, mean_y - scale * mean_x))


def sequence_remaining_s(
    minimums: Sequence[float],
    waits: Sequence[float],
    index: int,
    model: DurationModel,
    *,
    job_elapsed_s: float | None = None,
    wait_left_s: float = 0.0,
) -> float:
    """Estimated time left; jobs before ``index`` are done.

    ``job_elapsed_s`` is set while job ``index`` runs; otherwise the series is
    waiting ``wait_left_s`` before starting it. ``waits[j]`` follows job j.
    """
    if index >= len(minimums):
        return 0.0
    current = model.predict(minimums[index])
    if job_elapsed_s is not None:
        total = max(0.0, current - job_elapsed_s)
    else:
        total = current + max(0.0, wait_left_s)
    for j in range(index + 1, len(minimums)):
        total += waits[j - 1] + model.predict(minimums[j])
    return total


def _blank(value: Any) -> bool:
    return value is None or (isinstance(value, str) and not value.strip())


def _text(value: Any) -> str:
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return str(value).strip()


def _float(value: Any, label: str) -> float:
    try:
        number = float(value) if isinstance(value, (int, float)) else float(_text(value).replace(",", "."))
    except ValueError as exc:
        raise ValueError(f"{label}: '{value}' no es un número") from exc
    if not isfinite(number):
        raise ValueError(f"{label} debe ser finito")
    return number


def _int(value: Any, label: str, minimum: int) -> int:
    number = _float(value, label)
    if not number.is_integer():
        raise ValueError(f"{label} debe ser entero")
    if number < minimum:
        raise ValueError(f"{label} debe ser ≥ {minimum}")
    return int(number)


def _choice(value: Any, options: Mapping[str, Any], label: str) -> Any:
    key = _text(value).lower().replace("-", "_").replace(" mode", "_mode")
    if key in options:
        return options[key]
    raise ValueError(f"{label}: '{value}' no es válido")


def read_rows(path: str | Path) -> list[tuple[int, dict[str, Any]]]:
    """Return ``(excel_row_number, {column: value})`` for each non-empty row."""
    from openpyxl import load_workbook

    workbook = load_workbook(Path(path), data_only=True, read_only=True)
    try:
        sheet = workbook[SHEET_NAME] if SHEET_NAME in workbook.sheetnames else workbook.worksheets[0]
        rows = sheet.iter_rows(values_only=True)
        header = next(rows, None)
        if header is None:
            raise ValueError("El Excel está vacío.")
        lookup = {key.lower(): key for key in COLUMN_KEYS}
        columns: list[str | None] = []
        unknown: list[str] = []
        for cell in header:
            if _blank(cell):
                columns.append(None)
                continue
            key = lookup.get(_text(cell).lower())
            if key is None:
                unknown.append(_text(cell))
            columns.append(key)
        if unknown:
            raise ValueError(f"Columnas desconocidas en el Excel: {', '.join(unknown)}")
        if not any(columns):
            raise ValueError("La primera fila del Excel debe tener los nombres de columna de la plantilla.")
        result = []
        for number, values in enumerate(rows, start=2):
            record = {
                key: value for key, value in zip(columns, values)
                if key is not None and not _blank(value)
            }
            record.pop("notas", None)
            if record:
                result.append((number, record))
        return result
    finally:
        workbook.close()


def build_jobs(
    rows: list[tuple[int, dict[str, Any]]],
    defaults: Mapping[str, Any],
    *,
    validate_scan: Callable[[SequenceJob], None] | None = None,
) -> tuple[list[SequenceJob], list[str]]:
    """Expand rows into jobs; blank cells use ``defaults`` (current GUI values).

    Every row is checked before anything runs; all errors are returned together.
    """
    jobs: list[SequenceJob] = []
    errors: list[str] = []
    if not rows:
        errors.append("El Excel no tiene filas de adquisición.")
    for number, record in rows:
        values = {key: defaults.get(key) for key in GUI_DEFAULT_KEYS}
        values.update(record)
        problems: list[str] = []

        def get(key: str, parse: Callable[[Any], Any]) -> Any:
            raw = values.get(key)
            if _blank(raw):
                problems.append(f"falta {key}")
                return None
            try:
                return parse(raw)
            except ValueError as exc:
                problems.append(str(exc))
                return None

        mode = get("modo", lambda v: _choice(v, _MODES, "modo"))
        pattern = get("patron", lambda v: _choice(v, _PATTERNS, "patron"))
        orientation = get("orientacion", lambda v: _choice(v, _ORIENTATIONS, "orientacion"))
        alines = get("a_lines", lambda v: _int(v, "a_lines", 1))
        bscans = get("b_scans", lambda v: _int(v, "b_scans", 1))
        m_reps = get("m_reps", lambda v: _int(v, "m_reps", 1))
        sync = get("sync_samples", lambda v: _int(v, "sync_samples", 0))
        x_mm = get("longitud_x_mm", lambda v: _float(v, "longitud_x_mm"))
        y_mm = get("longitud_y_mm", lambda v: _float(v, "longitud_y_mm"))
        bframes = get("bframes_delay_us", lambda v: _float(v, "bframes_delay_us"))
        excitation = get("excitacion", Excitation.parse)
        ch1_mvpp = get("ch1_mVpp", lambda v: _float(v, "ch1_mVpp"))
        ch2_hz = get("ch2_frecuencia_Hz", lambda v: _float(v, "ch2_frecuencia_Hz"))
        waveform = get("ch2_forma_onda", waveform_scpi)
        delay_ms = get("ch2_retardo_ms", lambda v: _float(v, "ch2_retardo_ms"))
        cycles = get("ch2_ciclos", lambda v: _int(v, "ch2_ciclos", 1))
        repetitions = 1 if _blank(values.get("repeticiones")) else get(
            "repeticiones", lambda v: _int(v, "repeticiones", 1))
        wait_s = 0.0 if _blank(values.get("espera_s")) else get(
            "espera_s", lambda v: _float(v, "espera_s"))
        if wait_s is not None and wait_s < 0:
            problems.append("espera_s no puede ser negativa")
        name = "" if _blank(values.get("nombre_archivo")) else get("nombre_archivo", lambda v: clean_stem(_text(v)))
        folder = "" if _blank(values.get("carpeta")) else _text(values["carpeta"])

        generator = None
        if None not in (excitation, ch1_mvpp, ch2_hz, waveform, delay_ms, cycles):
            generator = GeneratorSettings(
                ch1_vpp=ch1_mvpp / 1000.0,
                ch2_frequency_hz=ch2_hz,
                ch2_waveform=waveform,
                ch2_delay_ms=delay_ms,
                excitation=excitation,
                ch2_burst_cycles=cycles,
            )
            try:
                generator.validate()
            except ValueError as exc:
                problems.append(str(exc))
        if problems:
            errors.append(f"Fila {number}: " + "; ".join(problems))
            continue
        for repetition in range(1, repetitions + 1):
            job = SequenceJob(
                row=number, repetition=repetition, repetitions=repetitions,
                mode=mode, pattern=pattern, orientation=orientation,
                alines=alines, bscans=bscans, m_repetitions=m_reps, sync_points=sync,
                x_length_mm=x_mm, y_length_mm=y_mm, bframes_delay_us=bframes,
                generator=generator, wait_s=wait_s, name=name or "", folder=folder,
            )
            if repetition == 1 and validate_scan is not None:
                try:
                    validate_scan(job)
                except Exception as exc:
                    errors.append(f"Fila {number}: {exc}")
                    break
            jobs.append(job)
    return jobs, errors


def write_template(path: str | Path) -> Path:
    """Create the Excel template with examples, dropdowns and instructions."""
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    from openpyxl.worksheet.datavalidation import DataValidation

    path = Path(path)
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = SHEET_NAME
    sheet.append(list(COLUMN_KEYS))
    header_fill = PatternFill("solid", fgColor="10233F")
    generator_fill = PatternFill("solid", fgColor="7A3E00")
    series_fill = PatternFill("solid", fgColor="1D6B46")
    for index, cell in enumerate(sheet[1]):
        key = COLUMN_KEYS[index]
        cell.font = Font(bold=True, color="FFFFFF")
        cell.alignment = Alignment(horizontal="center")
        if key.startswith(("excitacion", "ch1_", "ch2_")):
            cell.fill = generator_fill
        elif key in ("repeticiones", "espera_s", "nombre_archivo", "carpeta", "notas"):
            cell.fill = series_fill
        else:
            cell.fill = header_fill
        sheet.column_dimensions[cell.column_letter].width = max(12, len(key) + 3)
    sheet.column_dimensions["T"].width = 28
    for row in EXAMPLE_ROWS:
        sheet.append(list(row))
    sheet.freeze_panes = "A2"

    def dropdown(column_key: str, options: list[str]) -> None:
        letter = sheet.cell(row=1, column=COLUMN_KEYS.index(column_key) + 1).column_letter
        validation = DataValidation(
            type="list", formula1='"' + ",".join(options) + '"', allow_blank=True,
        )
        validation.error = "Valor no permitido"
        sheet.add_data_validation(validation)
        validation.add(f"{letter}2:{letter}1000")

    dropdown("modo", ["OCE", "OCT"])
    dropdown("patron", ["Raster", "Crosshair", "Meridianos", "Lineal", "Anillos", "Espiral"])
    dropdown("orientacion", ["Horizontal", "Vertical"])
    dropdown("excitacion", [Excitation.NON_CONTACT.value, Excitation.CONTACT.value])
    dropdown("ch2_forma_onda", list(CH2_WAVEFORMS))

    info = workbook.create_sheet("Instrucciones")
    info.append(["Columna", "Descripción", "Valores / unidad"])
    for cell in info[1]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = header_fill
    for row in COLUMNS:
        info.append(list(row))
    info.append([])
    for line in (
        "Cada fila es una adquisición; 'repeticiones' la repite N veces con el mismo nombre (_1, _2…).",
        "Celdas vacías en las columnas modo … ch2_ciclos toman el valor actual de la GUI.",
        "La GUI valida todas las filas (incluido el límite de voltaje) antes de empezar.",
        "OUTPUT1 se enciende al iniciar cada adquisición y se apaga al terminar; OUTPUT2 queda encendido.",
        "La espera se cuenta desde el final de una adquisición hasta el inicio de la siguiente.",
    ):
        info.append([line])
    info.column_dimensions["A"].width = 20
    info.column_dimensions["B"].width = 62
    info.column_dimensions["C"].width = 36
    path.parent.mkdir(parents=True, exist_ok=True)
    workbook.save(path)
    return path
