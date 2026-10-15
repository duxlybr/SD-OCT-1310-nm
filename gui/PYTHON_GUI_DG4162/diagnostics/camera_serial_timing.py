"""Camera Link serial timing of the GL2048R against the NI-IMAQ camera file (ICD).

``imgRingSetup`` replays every serial command of the camera file and waits for
each exact reply within that action's ``Timeout``. With the installed ICD
(GL2048R-10A_icd0173rev3) every action allows 3000 ms, but ``OPR 2`` takes
~3.06 s and ``RESET`` ~2.7 s on this camera (measured 2026-10-15), so
acquisitions fail with NI-IMAQ error -1074397037 ("The serial read did not
complete within the specified timeout period").

    py -3.11 -m diagnostics.camera_serial_timing            # measure, read-only ICD
    py -3.11 -m diagnostics.camera_serial_timing --fix      # also raise ICD timeouts (backup kept)

Only run with the GUI and NI MAX closed. The commands sent are the ones
NI-IMAQ itself sends at every acquisition with this application's settings
(``RESET`` reinitializes the sensor readout and keeps the settings); no DAQ
task, galvo motion or PFI12/PFI13 pulse is generated.
"""
from __future__ import annotations

import argparse
import ctypes
import time
from ctypes import byref, c_char_p, c_int32, c_uint32, create_string_buffer

from octoce.camera_icd import SAFE_TIMEOUT_MS, camera_file, raise_timeouts, serial_timeouts
from octoce.config import HardwareConfig

CR = "\r"


def sequence(hardware: HardwareConfig) -> list[str]:
    """Serial commands NI-IMAQ sends for this application's settings, in ICD order."""
    on = {True: "ON", False: "OFF"}
    return [
        "*", "RESPONSE BRIEF", "FPA:FBCAP 3", f"OPR {hardware.camera_operational_setting.split()[1]}",
        "FRAME:PERIOD:MAXEXP 1000",
        f"CORR:OFFSET {on[hardware.camera_offset_correction]}",
        f"CORR:GAIN {on[hardware.camera_uniformity_correction]}",
        f"CORR:PIXEL {on[hardware.camera_pixel_replace]}",
        f"CORR:OFFSET:GLOBAL {hardware.camera_dark_level}",
        "GAIN:DIGITAL 32", "TESTPAT:CAM OFF", "FRAME:STAMP OFF", "TRIG:MODE 1", "TRIG:POL HIGH", "RESET",
    ]


def measure(interface: str, commands: list[str]) -> list[tuple[str, float, bool]]:
    """Send each command on the raw Camera Link serial port; (command, seconds, reply ok)."""
    dll = ctypes.WinDLL("imaq.dll")
    for name, args in (("imgInterfaceOpen", [c_char_p, ctypes.POINTER(c_uint32)]),
                       ("imgSessionOpen", [c_uint32, ctypes.POINTER(c_uint32)]),
                       ("imgSessionSerialWrite", [c_uint32, c_char_p, ctypes.POINTER(c_uint32), c_uint32]),
                       ("imgSessionSerialRead", [c_uint32, c_char_p, ctypes.POINTER(c_uint32), c_uint32]),
                       ("imgSessionSerialFlush", [c_uint32]),
                       ("imgClose", [c_uint32, c_uint32])):
        getattr(dll, name).argtypes = args
        getattr(dll, name).restype = c_int32
    interface_id, session_id = c_uint32(), c_uint32()
    if dll.imgInterfaceOpen(interface.encode("ascii"), byref(interface_id)) != 0:
        raise RuntimeError(f"No se pudo abrir {interface} (¿GUI o NI MAX abiertos?).")
    results = []
    try:
        if dll.imgSessionOpen(interface_id, byref(session_id)) != 0:
            raise RuntimeError("No se pudo abrir la sesión NI-IMAQ.")
        for command in commands:
            dll.imgSessionSerialFlush(session_id)
            payload = (command + CR).encode()
            size = c_uint32(len(payload))
            started = time.perf_counter()
            dll.imgSessionSerialWrite(session_id, payload, byref(size), 1000)
            reply = b""
            while time.perf_counter() - started < 15.0:
                buffer = create_string_buffer(512)
                count = c_uint32(511)
                dll.imgSessionSerialRead(session_id, buffer, byref(count), 200)
                reply += buffer.raw[: count.value]
                if reply.endswith(b">") and (b"OK" in reply or command == "*"):
                    break
            ok = reply.endswith(b">") and (command == "*" or b"OK" in reply)
            results.append((command, time.perf_counter() - started, ok))
    finally:
        dll.imgClose(session_id, 1)
        dll.imgClose(interface_id, 1)
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--interface", default="img0")
    parser.add_argument("--fix", action="store_true",
                        help=f"raise ICD serial timeouts below {SAFE_TIMEOUT_MS} ms (backup kept)")
    args = parser.parse_args()
    hardware = HardwareConfig()
    icd = camera_file(args.interface)
    timeouts = serial_timeouts(icd)
    limit_s = min(timeouts) / 1000.0
    print(f"ICD: {icd}")
    print(f"Timeouts serie en el ICD: mínimo {min(timeouts)} ms, máximo {max(timeouts)} ms ({len(timeouts)} acciones)")
    slowest = 0.0
    for command, seconds, ok in measure(args.interface, sequence(hardware)):
        slowest = max(slowest, seconds)
        flag = "  <-- supera el timeout del ICD" if seconds > limit_s else ""
        print(f"{'OK ' if ok else 'ERR'} {seconds:6.3f} s  {command}{flag}")
    margin = limit_s - slowest
    print(f"Comando más lento: {slowest:.3f} s · margen frente al ICD: {margin:+.3f} s")
    if args.fix:
        changed, backup = raise_timeouts(icd)
        if changed:
            print(f"ICD actualizado: {changed} timeouts serie elevados a {SAFE_TIMEOUT_MS} ms. Respaldo: {backup}")
        else:
            print(f"ICD sin cambios: todos los timeouts serie ya son ≥ {SAFE_TIMEOUT_MS} ms.")
    elif margin < 1.0:
        print("Margen insuficiente: ejecute con --fix para elevar los timeouts serie del ICD.")


if __name__ == "__main__":
    main()
