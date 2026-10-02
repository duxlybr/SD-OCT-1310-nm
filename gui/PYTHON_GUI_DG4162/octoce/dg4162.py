"""SCPI control of the RIGOL DG4162 generator used for OCE excitation.

Reference setup (front-panel state ``C:\\STATE 4:1040octoacus1000.RSF``):

* CH1: 948.07 kHz sine carrier, AM 100 % from the EXT input, 50 Ω load. Its
  amplitude (Vpp) sets the excitation; OUTPUT1 is only on during acquisitions.
* CH2: modulating pulse (2 kHz, 1 Vpp, offset 0.452 V, High-Z) in burst mode,
  1 cycle per external trigger (PFI13) with a trigger delay. OUTPUT2 stays on.

All SCPI traffic goes through :class:`DG4162Controller`, which checks
``:SYST:ERR?`` after each write and verifies the written values by reading them
back. ``:OUTPn?`` and ``:OUTPn:POL?`` answer with an extra blank line on
firmware 00.01.14; the controller reads it right away to keep queries aligned
(waiting for it with a timeout costs ~2 s per query with NI-VISA).
"""
from __future__ import annotations

import re
import threading
from dataclasses import asdict, dataclass
from enum import Enum
from math import isfinite
from typing import Any

DEFAULT_RESOURCE = "USB0::0x1AB1::0x0641::DG4E253001553::INSTR"
DEFAULT_TIMEOUT_MS = 3000

WARNING_CH1_VPP = 1.0

# All verified on the DG4162 (fw 00.01.14): burst, amplitude and offset are kept.
CH2_WAVEFORMS = {
    "Pulso": "PULS",
    "Gaussiana": "GAUSS",
    "Pulso gaussiano": "GAUSSPULSE",
    "Cuadrada": "SQU",
    "Senoidal": "SIN",
    "Semiseno": "ABSSINEHALF",
    "Haversine": "HAVERSINE",
    "Hanning": "HANNING",
    "Blackman": "BLACKMAN",
    "Triangular": "TRIANG",
    "Trapecio": "TRAPEZIA",
    "Rampa": "RAMP",
    "Rampa negativa": "NEGRAMP",
    "Exp. creciente": "EXPRISE",
    "Exp. decreciente": "EXPFALL",
    "Sinc": "SINC",
    "Lorentz": "LORENTZ",
}
_WAVEFORM_LABELS = {scpi: label for label, scpi in CH2_WAVEFORMS.items()}

_EXTRA_BLANK_LINE = re.compile(r"^:OUTP(?:UT)?\d(?::POL(?:ARITY)?)?\?$", re.IGNORECASE)


class DG4162Error(RuntimeError):
    """Communication, instrument or verification error."""


class Excitation(str, Enum):
    NON_CONTACT = "Sin contacto"
    CONTACT = "Con contacto"

    @property
    def limit_vpp(self) -> float:
        # Without contact the amplifier accepts at most 1 Vpp at its input.
        return 1.0 if self is Excitation.NON_CONTACT else 5.0

    @classmethod
    def parse(cls, text: str) -> "Excitation":
        key = str(text).strip().lower().replace("_", " ")
        if key in ("sin contacto", "sincontacto", "no contacto", "non contact", "noncontact"):
            return cls.NON_CONTACT
        if key in ("con contacto", "contacto", "contact"):
            return cls.CONTACT
        raise ValueError(f"Excitación desconocida: {text!r} (use 'Con contacto' o 'Sin contacto').")


def check_ch1_vpp(vpp: float, excitation: Excitation) -> bool:
    """Validate CH1 amplitude; return True when it needs explicit confirmation."""
    if not isfinite(vpp) or vpp <= 0:
        raise ValueError("La amplitud de CH1 debe ser un número mayor que 0 Vpp.")
    if vpp > excitation.limit_vpp + 1e-12:
        raise ValueError(
            f"CH1 = {vpp * 1000:g} mVpp supera el límite de {excitation.limit_vpp:g} Vpp "
            f"para excitación {excitation.value.lower()}."
        )
    return vpp > WARNING_CH1_VPP + 1e-12


def waveform_scpi(label_or_scpi: str) -> str:
    text = str(label_or_scpi).strip()
    for label, scpi in CH2_WAVEFORMS.items():
        if text.lower() in (label.lower(), scpi.lower()):
            return scpi
    normalized = _normalize_function(text)
    if normalized in _WAVEFORM_LABELS:
        return normalized
    raise ValueError(
        f"Forma de onda de CH2 no admitida: {label_or_scpi!r} "
        f"(opciones: {', '.join(CH2_WAVEFORMS)})."
    )


def waveform_label(scpi: str) -> str:
    return _WAVEFORM_LABELS.get(_normalize_function(scpi), scpi)


_FUNCTION_ALIASES = {"PULSE": "PULS", "SQUARE": "SQU", "SINUSOID": "SIN", "SINE": "SIN"}


def _normalize_function(answer: str) -> str:
    text = answer.strip().strip('"').upper()
    return _FUNCTION_ALIASES.get(text, text)


@dataclass(frozen=True, slots=True)
class GeneratorSettings:
    """Values the GUI controls for one acquisition."""

    ch1_vpp: float
    ch2_frequency_hz: float
    ch2_waveform: str = "PULS"
    ch2_delay_ms: float = 2.0
    excitation: Excitation = Excitation.NON_CONTACT

    def validate(self) -> bool:
        """Raise on invalid values; return True when CH1 needs confirmation."""
        needs_confirmation = check_ch1_vpp(self.ch1_vpp, self.excitation)
        if not isfinite(self.ch2_frequency_hz) or self.ch2_frequency_hz <= 0:
            raise ValueError("La frecuencia de CH2 debe ser mayor que 0 Hz.")
        if not isfinite(self.ch2_delay_ms) or self.ch2_delay_ms < 0:
            raise ValueError("El retardo de CH2 no puede ser negativo.")
        waveform_scpi(self.ch2_waveform)
        return needs_confirmation

    def as_dict(self) -> dict[str, Any]:
        data = asdict(self)
        data["excitation"] = self.excitation.value
        data["ch2_waveform"] = waveform_label(self.ch2_waveform)
        return data


@dataclass(frozen=True, slots=True)
class GeneratorState:
    """Snapshot of the generator, read with queries only."""

    identity: str
    output1: bool
    output2: bool
    ch1_function: str
    ch1_frequency_hz: float
    ch1_vpp: float
    ch1_offset_v: float
    ch1_modulation: bool
    ch1_modulation_type: str
    ch1_am_source: str
    ch2_function: str
    ch2_frequency_hz: float
    ch2_vpp: float
    ch2_offset_v: float
    ch2_burst: bool
    ch2_burst_trigger: str
    ch2_delay_ms: float

    def summary(self) -> str:
        return (
            f"CH1 {self.ch1_function} {self.ch1_frequency_hz / 1000:g} kHz · "
            f"{self.ch1_vpp * 1000:g} mVpp · "
            f"{'AM ' + self.ch1_am_source if self.ch1_modulation else 'sin modulación'} · "
            f"OUT1 {'ON' if self.output1 else 'OFF'}\n"
            f"CH2 {waveform_label(self.ch2_function)} {self.ch2_frequency_hz:g} Hz · "
            f"{self.ch2_vpp:g} Vpp · offset {self.ch2_offset_v:g} V · "
            f"burst {'ON' if self.ch2_burst else 'OFF'} ({self.ch2_burst_trigger}) · "
            f"retardo {self.ch2_delay_ms:g} ms · OUT2 {'ON' if self.output2 else 'OFF'}"
        )

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def _approx(a: float, b: float, rel: float = 1e-4, abs_tol: float = 1e-9) -> bool:
    return abs(a - b) <= max(abs_tol, rel * max(abs(a), abs(b)))


class DG4162Controller:
    """Thread-safe SCPI wrapper over PyVISA for the DG4162."""

    def __init__(
        self,
        resource: str = DEFAULT_RESOURCE,
        *,
        timeout_ms: int = DEFAULT_TIMEOUT_MS,
        visa_backend: str = "@ivi",
        resource_manager: Any | None = None,
    ) -> None:
        self.resource = resource
        self.timeout_ms = timeout_ms
        self.visa_backend = visa_backend
        self._rm = resource_manager
        self._inst: Any | None = None
        self._lock = threading.RLock()
        self._extra_blank_line = True
        self.identity = ""
        # State read on the first connection; restored when the GUI closes.
        self.baseline: GeneratorState | None = None

    # -- connection ---------------------------------------------------------
    @property
    def connected(self) -> bool:
        return self._inst is not None

    def probe(self) -> bool:
        """Heartbeat: reconnect when the instrument is present; check it answers.

        Never raises. A failed check closes the session so that the next probe
        opens a fresh one (needed after the generator is switched off and on).
        """
        with self._lock:
            if self._inst is None:
                if not self._resource_present():
                    return False
                try:
                    self.connect()
                except DG4162Error:
                    return False
                return True
            try:
                self._query("*IDN?")
            except DG4162Error:
                return False
            return True

    def _resource_present(self) -> bool:
        """Fast USB enumeration check, so a missing instrument costs no timeout."""
        try:
            if self._rm is None:
                import pyvisa

                self._rm = pyvisa.ResourceManager(self.visa_backend)
            wanted = self.resource.upper()
            return any(str(name).upper() == wanted for name in self._rm.list_resources())
        except Exception:
            return False

    def connect(self) -> str:
        with self._lock:
            if self._inst is not None:
                return self.identity
            try:
                if self._rm is None:
                    import pyvisa

                    self._rm = pyvisa.ResourceManager(self.visa_backend)
                inst = self._rm.open_resource(self.resource)
            except ImportError as exc:
                raise DG4162Error("Falta PyVISA: py -3.11 -m pip install pyvisa") from exc
            except Exception as exc:
                raise DG4162Error(
                    f"No se pudo abrir {self.resource}: {exc}. "
                    "Verifique el cable USB y que Ultra Sigma esté cerrado."
                ) from exc
            inst.timeout = self.timeout_ms
            inst.read_termination = "\n"
            inst.write_termination = "\n"
            self._inst = inst
            try:
                self._clear_io()
                identity = self._query("*IDN?")
                if "DG4162" not in identity.upper():
                    raise DG4162Error(f"El equipo no es un DG4162: {identity}")
                self._detect_blank_line()
                self._clear_errors()
                self.identity = identity
                if self.baseline is None:
                    self.baseline = self.read_state()
            except BaseException:
                self._release()
                raise
            return identity

    def close(self, *, restore: bool = True) -> list[str]:
        """Leave the generator in its base state and close the session.

        Both outputs are switched off and, with ``restore``, CH1/CH2 return to
        the values read on the first connection. Returns warnings (empty = OK).
        """
        with self._lock:
            if self._inst is None:
                return []
            warnings: list[str] = []
            for channel in (1, 2):
                try:
                    self.set_output(channel, False)
                except Exception as exc:
                    warnings.append(f"No se pudo apagar OUTPUT{channel}: {exc}")
            if restore and self.baseline is not None and not warnings:
                try:
                    self.restore_baseline()
                except Exception as exc:
                    warnings.append(f"No se pudo restaurar la configuración inicial: {exc}")
            self._release()
            return warnings

    def disconnect(self) -> None:
        """Close the session without sending anything (read-only use)."""
        with self._lock:
            self._release()

    def restore_baseline(self) -> None:
        base = self.baseline
        if base is None:
            return
        with self._lock:
            if base.ch2_function in _WAVEFORM_LABELS:
                self.set_ch2_waveform(base.ch2_function)
            self.set_ch2_frequency(base.ch2_frequency_hz)
            self.set_ch2_delay_ms(base.ch2_delay_ms)
            self.set_ch1_vpp(base.ch1_vpp, limit_vpp=base.ch1_vpp)

    def _release(self) -> None:
        inst, self._inst = self._inst, None
        if inst is not None:
            try:
                inst.close()
            except Exception:
                pass

    def _require(self) -> Any:
        if self._inst is None:
            raise DG4162Error("DG4162 no conectado.")
        return self._inst

    # -- low level ------------------------------------------------------------
    def _clear_io(self) -> None:
        """USBTMC device clear: discards pending responses (~10 ms)."""
        try:
            self._require().clear()
        except DG4162Error:
            raise
        except Exception as exc:
            raise DG4162Error(f"No se pudo limpiar la comunicación USB: {exc}") from exc

    def _detect_blank_line(self) -> None:
        """Check once whether :OUTPn? sends the extra blank line (fw 00.01.14)."""
        inst = self._require()
        inst.query(":OUTP1?")
        try:
            self._extra_blank_line = inst.read().strip() == ""
        except Exception:
            self._extra_blank_line = False
            self._clear_io()

    def _lost(self, command: str, exc: Exception) -> DG4162Error:
        """Close a session that stopped answering (e.g. generator switched off).

        Reusing it, or sending a device clear to it, can block the GUI for many
        timeouts; the next probe() opens a fresh session instead.
        """
        self._release()
        return DG4162Error(f"Comunicación perdida con el DG4162 ({command}): {exc}")

    def _query(self, command: str) -> str:
        inst = self._require()
        try:
            answer = inst.query(command).strip()
            if self._extra_blank_line and _EXTRA_BLANK_LINE.match(command):
                inst.read()  # already in the output buffer: no wait
        except Exception as exc:
            raise self._lost(command, exc) from exc
        return answer

    def _query_float(self, command: str) -> float:
        answer = self._query(command)
        try:
            return float(answer.strip('"'))
        except ValueError as exc:
            raise DG4162Error(f"Respuesta no numérica a {command}: {answer!r}") from exc

    def _query_bool(self, command: str) -> bool:
        return self._query(command).upper() in ("ON", "1")

    def _error(self) -> tuple[int, str]:
        answer = self._query(":SYST:ERR?")
        code, _, message = answer.partition(",")
        try:
            return int(code), message.strip().strip('"')
        except ValueError as exc:
            raise DG4162Error(f"Respuesta inesperada a :SYST:ERR?: {answer!r}") from exc

    def _clear_errors(self) -> list[str]:
        stale: list[str] = []
        for _ in range(20):
            code, message = self._error()
            if code == 0:
                break
            stale.append(f"{code}: {message}")
        return stale

    def write(self, command: str) -> None:
        """Send one SCPI command and fail if the instrument reports an error."""
        with self._lock:
            inst = self._require()
            try:
                inst.write(command)
            except Exception as exc:
                raise self._lost(command, exc) from exc
            errors = self._clear_errors()
            if errors:
                raise DG4162Error(f"{command} → {'; '.join(errors)}")

    def query(self, command: str) -> str:
        with self._lock:
            return self._query(command)

    # -- reading --------------------------------------------------------------
    def read_state(self) -> GeneratorState:
        with self._lock:
            return GeneratorState(
                identity=self.identity or self._query("*IDN?"),
                output1=self._query_bool(":OUTP1?"),
                output2=self._query_bool(":OUTP2?"),
                ch1_function=_normalize_function(self._query(":SOUR1:FUNC?")),
                ch1_frequency_hz=self._query_float(":SOUR1:FREQ?"),
                ch1_vpp=self._ch1_vpp(),
                ch1_offset_v=self._query_float(":SOUR1:VOLT:OFFS?"),
                ch1_modulation=self._query_bool(":SOUR1:MOD?"),
                ch1_modulation_type=self._query(":SOUR1:MOD:TYP?"),
                ch1_am_source=self._query(":SOUR1:MOD:AM:SOUR?"),
                ch2_function=_normalize_function(self._query(":SOUR2:FUNC?")),
                ch2_frequency_hz=self._query_float(":SOUR2:FREQ?"),
                ch2_vpp=self._query_float(":SOUR2:VOLT?"),
                ch2_offset_v=self._query_float(":SOUR2:VOLT:OFFS?"),
                ch2_burst=self._query_bool(":SOUR2:BURS?"),
                ch2_burst_trigger=self._query(":SOUR2:BURS:TRIG:SOUR?"),
                ch2_delay_ms=self._query_float(":SOUR2:BURS:TDEL?") * 1000.0,
            )

    def _ch1_vpp(self) -> float:
        unit = self._query(":SOUR1:VOLT:UNIT?").upper()
        if unit != "VPP":
            raise DG4162Error(f"CH1 usa la unidad {unit}; configure VPP en el panel.")
        return self._query_float(":SOUR1:VOLT?")

    def output(self, channel: int) -> bool:
        with self._lock:
            return self._query_bool(f":OUTP{int(channel)}?")

    # -- writing --------------------------------------------------------------
    def set_output(self, channel: int, enabled: bool) -> None:
        channel = int(channel)
        if channel not in (1, 2):
            raise ValueError("Canal inválido.")
        with self._lock:
            self.write(f":OUTP{channel} {'ON' if enabled else 'OFF'}")
            if self._query_bool(f":OUTP{channel}?") != enabled:
                raise DG4162Error(f"OUTPUT{channel} no quedó {'ON' if enabled else 'OFF'}.")

    def set_ch1_vpp(self, vpp: float, *, limit_vpp: float) -> None:
        if not isfinite(vpp) or vpp <= 0 or vpp > limit_vpp + 1e-12:
            raise ValueError(f"CH1 {vpp:g} Vpp fuera del rango permitido (0, {limit_vpp:g}] Vpp.")
        with self._lock:
            if _approx(self._ch1_vpp(), vpp, rel=1e-6):  # also refuses a unit other than VPP
                return
            self.write(f":SOUR1:VOLT {vpp:.6g}")
            readback = self._query_float(":SOUR1:VOLT?")
            if not _approx(readback, vpp, rel=1e-3):
                raise DG4162Error(f"CH1 quedó en {readback:g} Vpp (solicitado {vpp:g}).")

    def set_ch2_waveform(self, waveform: str) -> None:
        scpi = waveform_scpi(waveform)
        with self._lock:
            if _normalize_function(self._query(":SOUR2:FUNC?")) == scpi:
                return
            self.write(f":SOUR2:FUNC {scpi}")
            readback = _normalize_function(self._query(":SOUR2:FUNC?"))
            if readback != scpi:
                raise DG4162Error(f"CH2 quedó en {readback} (solicitado {scpi}).")

    def set_ch2_frequency(self, frequency_hz: float) -> None:
        if not isfinite(frequency_hz) or frequency_hz <= 0:
            raise ValueError("La frecuencia de CH2 debe ser mayor que 0 Hz.")
        with self._lock:
            if _approx(self._query_float(":SOUR2:FREQ?"), frequency_hz, rel=1e-9):
                return
            self.write(f":SOUR2:FREQ {frequency_hz:.9g}")
            readback = self._query_float(":SOUR2:FREQ?")
            if not _approx(readback, frequency_hz):
                raise DG4162Error(f"CH2 quedó en {readback:g} Hz (solicitado {frequency_hz:g}).")

    def set_ch2_delay_ms(self, delay_ms: float) -> None:
        if not isfinite(delay_ms) or delay_ms < 0:
            raise ValueError("El retardo de CH2 no puede ser negativo.")
        with self._lock:
            current = self._query_float(":SOUR2:BURS:TDEL?") * 1000.0
            if _approx(current, delay_ms, rel=1e-9, abs_tol=1e-9):
                return
            self.write(f":SOUR2:BURS:TDEL {delay_ms / 1000.0:.9g}")
            readback = self._query_float(":SOUR2:BURS:TDEL?") * 1000.0
            if not _approx(readback, delay_ms, rel=1e-3, abs_tol=1e-6):
                raise DG4162Error(f"Retardo CH2 quedó en {readback:g} ms (solicitado {delay_ms:g}).")

    def apply(self, settings: GeneratorSettings) -> GeneratorState:
        """Program CH1/CH2 with OUTPUT1 off and return the verified state."""
        settings.validate()
        with self._lock:
            self.set_output(1, False)
            self.set_ch2_waveform(settings.ch2_waveform)
            self.set_ch2_frequency(settings.ch2_frequency_hz)
            self.set_ch2_delay_ms(settings.ch2_delay_ms)
            self.set_ch1_vpp(settings.ch1_vpp, limit_vpp=settings.excitation.limit_vpp)
            return self.read_state()

    def start_excitation(self) -> bool:
        """OUTPUT2 on (kept on) and OUTPUT1 on; only writes what is off.

        Returns True when an output had to be switched on.
        """
        changed = False
        with self._lock:
            for channel in (2, 1):
                if not self._query_bool(f":OUTP{channel}?"):
                    self.set_output(channel, True)
                    changed = True
        return changed

    def stop_excitation(self) -> None:
        self.set_output(1, False)
