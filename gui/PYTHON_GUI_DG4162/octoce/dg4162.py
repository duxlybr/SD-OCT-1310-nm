"""SCPI control of the RIGOL DG4162 generator used for OCE excitation.

OCE setup (defaults in :class:`BaseSetup`):

* CH1: 954.9 kHz sine (transducer resonance), offset -0.7 mV DC, no
  modulation, 50 Ω load. Its amplitude (Vpp) sets the excitation; OUTPUT1 is
  only on during acquisitions.
* CH2: modulating pulse (2 kHz, 1 Vpp, offset 0.452 V, High-Z) in burst mode,
  1 cycle per external trigger (PFI13) with a trigger delay. OUTPUT2 stays on.

All SCPI traffic goes through :class:`DG4162Controller`, which checks
``:SYST:ERR?`` after each write and verifies the written values by reading them
back. ``:OUTPn?`` and ``:OUTPn:POL?`` answer with an extra blank line on
firmware 00.01.14; the controller reads it right away to keep queries aligned
(waiting for it with a timeout costs ~2 s per query with NI-VISA).
"""
from __future__ import annotations

import json
import re
import threading
from dataclasses import asdict, dataclass, fields, replace
from enum import Enum
from math import isfinite
from pathlib import Path
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
# Switching an output on/off; every other write changes a parameter.
_OUTPUT_SWITCH = re.compile(r"^:OUTP(?:UT)?[12]\s+(?:ON|OFF)$", re.IGNORECASE)


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


@dataclass(frozen=True, slots=True)
class BaseSetup:
    """OCE base configuration of the generator.

    Fixed parts: CH1 sine, 50 Ω load, no modulation, no burst; CH2 High-Z,
    no modulation, pulse duty 50 %, burst triggered by EXT (PFI13) on the
    rising edge. The values
    below are editable in the GUI and saved in ``gui/config/dg4162_base.json``.
    ``ch1_vpp`` and the ``ch2_*`` waveform/frequency/delay are the defaults of
    the acquisition panel and the state left when the GUI closes.
    """

    ch1_frequency_hz: float = 954_900.0  # transducer resonance (CH1 carrier)
    ch1_offset_v: float = -0.0007  # -0.7 mV DC
    ch2_vpp: float = 1.0
    ch2_offset_v: float = 0.452
    burst_cycles: int = 1
    ch1_vpp: float = 0.5
    ch2_waveform: str = "PULS"
    ch2_frequency_hz: float = 2000.0
    ch2_delay_ms: float = 6.0

    def validate(self) -> None:
        if not isfinite(self.ch1_frequency_hz) or not 0 < self.ch1_frequency_hz <= 160e6:
            raise ValueError("La frecuencia de resonancia (CH1) debe estar entre 0 y 160 MHz.")
        if not isfinite(self.ch1_offset_v) or abs(self.ch1_offset_v) > 1.0:
            raise ValueError("El offset de CH1 debe estar entre -1 V y 1 V.")
        if not isfinite(self.ch2_vpp) or self.ch2_vpp <= 0:
            raise ValueError("La amplitud de CH2 debe ser mayor que 0 Vpp.")
        if not isfinite(self.ch2_offset_v) or abs(self.ch2_offset_v) + self.ch2_vpp / 2 > 10.0:
            raise ValueError("CH2: |offset| + amplitud/2 no puede superar 10 V (High-Z).")
        if int(self.burst_cycles) != self.burst_cycles or not 1 <= self.burst_cycles <= 1_000_000:
            raise ValueError("Los ciclos por burst deben ser un entero entre 1 y 1 000 000.")
        if check_ch1_vpp(self.ch1_vpp, Excitation.NON_CONTACT):
            raise ValueError("La amplitud por defecto de CH1 no puede superar 1 Vpp.")
        self.default_settings().validate()

    def default_settings(self) -> GeneratorSettings:
        return GeneratorSettings(
            ch1_vpp=self.ch1_vpp, ch2_frequency_hz=self.ch2_frequency_hz,
            ch2_waveform=self.ch2_waveform, ch2_delay_ms=self.ch2_delay_ms,
        )

    @classmethod
    def load(cls, path: Path) -> "BaseSetup":
        """Saved configuration, or the defaults when there is none."""
        if not path.exists():
            return cls()
        data = json.loads(path.read_text(encoding="utf-8"))
        known = {field.name for field in fields(cls)}
        base = replace(cls(), **{key: value for key, value in data.items() if key in known})
        base = replace(base, ch2_waveform=waveform_scpi(base.ch2_waveform), burst_cycles=int(base.burst_cycles))
        base.validate()
        return base

    def save(self, path: Path) -> None:
        self.validate()
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_text(json.dumps({"version": 1, **asdict(self)}, indent=2), encoding="utf-8")
        temporary.replace(path)


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
        # Called (from any thread) when a safety rule acts, e.g. OUTPUT1 forced off.
        self.on_safety: Any | None = None
        # OUTPUT1 is never switched on with CH1 above this amplitude. 1 Vpp is the
        # non-contact limit; the GUI raises it to 5 Vpp only for confirmed contact use.
        self.output1_limit_vpp = Excitation.NON_CONTACT.limit_vpp

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
            except BaseException:
                self._release()
                raise
            return identity

    def close(self, *, base: BaseSetup | None = None) -> list[str]:
        """OUTPUT1 off, optionally leave ``base`` programmed, OUTPUT2 on, close.

        OUTPUT2 stays on even after the GUI closes. Returns warnings (empty = OK).
        """
        with self._lock:
            if self._inst is None:
                return []
            warnings: list[str] = []
            try:
                self.set_output(1, False)
            except Exception as exc:
                warnings.append(f"No se pudo apagar OUTPUT1: {exc}")
            if base is not None and not warnings:
                try:
                    self.ensure_base(base)
                    self.apply(base.default_settings())
                except Exception as exc:
                    warnings.append(f"No se pudo dejar la configuración base: {exc}")
            if self._inst is not None:
                try:
                    if not self._query_bool(":OUTP2?"):
                        self.set_output(2, True)
                except Exception as exc:
                    warnings.append(f"No se pudo dejar OUTPUT2 encendido: {exc}")
            self._release()
            return warnings

    def disconnect(self) -> None:
        """Close the session without sending anything (read-only use)."""
        with self._lock:
            self._release()

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

    def _notify_safety(self, message: str) -> None:
        callback = self.on_safety
        if callback is not None:
            try:
                callback(message)
            except Exception:
                pass

    def write(self, command: str) -> None:
        """Send one SCPI command and fail if the instrument reports an error.

        Safety rule: a parameter may only change with OUTPUT1 off. Every write
        other than switching an output checks OUTPUT1 first and switches it off.
        """
        with self._lock:
            inst = self._require()
            if not _OUTPUT_SWITCH.match(command.strip()) and self._query_bool(":OUTP1?"):
                self.write(":OUTP1 OFF")
                if self._query_bool(":OUTP1?"):
                    raise DG4162Error(f"OUTPUT1 no se apagó; no se envía {command}.")
                self._notify_safety(f"OUTPUT1 estaba encendido antes de cambiar parámetros ({command}): apagado.")
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
            if channel == 1 and enabled:
                vpp = self._ch1_vpp()
                if vpp > self.output1_limit_vpp + 1e-12:
                    raise DG4162Error(
                        f"OUTPUT1 no se enciende: CH1 = {vpp * 1000:g} mVpp supera el límite de "
                        f"{self.output1_limit_vpp:g} Vpp."
                    )
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

    def ensure_base(self, base: BaseSetup) -> list[str]:
        """Check the OCE base configuration and correct what differs.

        OUTPUT1 is switched off first. Returns the corrections made (empty when
        the generator already matched); every write is verified by reading back.
        """
        base.validate()
        corrections: list[str] = []
        with self._lock:
            if self._query_bool(":OUTP1?"):
                self.set_output(1, False)
                corrections.append("OUTPUT1: ON → OFF")

            def check(label: str, query: str, expected: object, command: str) -> None:
                def matches(answer: str) -> bool:
                    if isinstance(expected, (int, float)):
                        try:
                            value = float(answer.strip('"'))
                        except ValueError:
                            return False
                        # "INFINITY" parses as inf, which _approx would accept.
                        return isfinite(value) and _approx(value, float(expected), rel=1e-6, abs_tol=1e-9)
                    return answer.upper().startswith(str(expected).upper())

                current = self._query(query)
                if matches(current):
                    return
                self.write(command)
                after = self._query(query)
                if not matches(after):
                    raise DG4162Error(f"{label}: quedó en {after} (esperado {expected}).")
                corrections.append(f"{label}: {current} → {after}")

            check("CH1 carga", ":OUTP1:IMP?", 50, ":OUTP1:IMP 50")
            check("CH1 forma de onda", ":SOUR1:FUNC?", "SIN", ":SOUR1:FUNC SIN")
            check("CH1 frecuencia (Hz)", ":SOUR1:FREQ?", base.ch1_frequency_hz,
                  f":SOUR1:FREQ {base.ch1_frequency_hz:.9g}")
            check("CH1 offset (V)", ":SOUR1:VOLT:OFFS?", base.ch1_offset_v,
                  f":SOUR1:VOLT:OFFS {base.ch1_offset_v:.6g}")
            check("CH1 modulación", ":SOUR1:MOD?", "OFF", ":SOUR1:MOD OFF")
            check("CH1 burst", ":SOUR1:BURS?", "OFF", ":SOUR1:BURS OFF")
            check("CH2 carga", ":OUTP2:IMP?", "INF", ":OUTP2:IMP INF")
            check("CH2 modulación", ":SOUR2:MOD?", "OFF", ":SOUR2:MOD OFF")
            check("CH2 ciclo de trabajo del pulso (%)", ":SOUR2:PULS:DCYC?", 50.0, ":SOUR2:PULS:DCYC 50")
            check("CH2 amplitud (Vpp)", ":SOUR2:VOLT?", base.ch2_vpp, f":SOUR2:VOLT {base.ch2_vpp:.6g}")
            check("CH2 offset (V)", ":SOUR2:VOLT:OFFS?", base.ch2_offset_v,
                  f":SOUR2:VOLT:OFFS {base.ch2_offset_v:.6g}")
            check("CH2 modo burst", ":SOUR2:BURS:MODE?", "TRIG", ":SOUR2:BURS:MODE TRIG")
            check("CH2 ciclos por burst", ":SOUR2:BURS:NCYC?", base.burst_cycles,
                  f":SOUR2:BURS:NCYC {int(base.burst_cycles)}")
            check("CH2 disparo burst", ":SOUR2:BURS:TRIG:SOUR?", "EXT", ":SOUR2:BURS:TRIG:SOUR EXT")
            check("CH2 flanco de disparo", ":SOUR2:BURS:TRIG:SLOP?", "POS", ":SOUR2:BURS:TRIG:SLOP POS")
            check("CH2 burst activo", ":SOUR2:BURS?", "ON", ":SOUR2:BURS ON")
        return corrections

    def read_base(self) -> BaseSetup:
        """Current instrument values as a BaseSetup (to adopt them as defaults)."""
        with self._lock:
            state = self.read_state()
            return BaseSetup(
                ch1_frequency_hz=state.ch1_frequency_hz,
                ch1_offset_v=state.ch1_offset_v,
                ch2_vpp=state.ch2_vpp,
                ch2_offset_v=state.ch2_offset_v,
                burst_cycles=int(round(self._query_float(":SOUR2:BURS:NCYC?"))),
                ch1_vpp=state.ch1_vpp,
                ch2_waveform=waveform_scpi(state.ch2_function),
                ch2_frequency_hz=state.ch2_frequency_hz,
                ch2_delay_ms=state.ch2_delay_ms,
            )

    def ensure_output2_on(self) -> bool:
        """Safety rule: OUTPUT2 stays on. Returns True when it had to be switched on."""
        with self._lock:
            if self._query_bool(":OUTP2?"):
                return False
            self.set_output(2, True)
        self._notify_safety("OUTPUT2 estaba apagado: encendido (debe permanecer encendido).")
        return True

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
