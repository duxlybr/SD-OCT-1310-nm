"""DG4162 check. Read-only by default.

    py -3.11 diagnostics\\dg4162_check.py                 # read only
    py -3.11 diagnostics\\dg4162_check.py --write-test    # program CH2/CH1, OUTPUT1 stays OFF
    py -3.11 diagnostics\\dg4162_check.py --write-test --pulse-output1   # + OUTPUT1 ON 1 s

--write-test rewrites the STATE 4 values with CH2 delay = 2 ms, checks that a
CH2 waveform change keeps amplitude/offset, and turns OUTPUT2 on. It never
saves a state to the instrument memory. Close Ultra Sigma first.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from octoce.dg4162 import DG4162Controller, GeneratorSettings  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-test", action="store_true")
    parser.add_argument("--pulse-output1", action="store_true")
    args = parser.parse_args()

    controller = DG4162Controller()
    print(controller.connect())
    before = controller.read_state()
    print("Estado inicial:\n" + before.summary())
    if not args.write_test:
        controller.disconnect()
        return 0
    try:
        settings = GeneratorSettings(
            ch1_vpp=before.ch1_vpp, ch2_frequency_hz=before.ch2_frequency_hz,
            ch2_waveform=before.ch2_function, ch2_delay_ms=2.0,
        )
        state = controller.apply(settings)
        print("\nTras aplicar (retardo 2 ms):\n" + state.summary())

        controller.set_ch2_waveform("SQU")
        square = controller.read_state()
        controller.set_ch2_waveform(before.ch2_function)
        restored = controller.read_state()
        print(f"\nCH2 cuadrada: {square.ch2_vpp:g} Vpp, offset {square.ch2_offset_v:g} V, "
              f"burst {'ON' if square.ch2_burst else 'OFF'}")
        print(f"CH2 de vuelta a {restored.ch2_function}: {restored.ch2_vpp:g} Vpp, "
              f"offset {restored.ch2_offset_v:g} V, {restored.ch2_frequency_hz:g} Hz, "
              f"burst {'ON' if restored.ch2_burst else 'OFF'}, retardo {restored.ch2_delay_ms:g} ms")

        controller.set_output(2, True)
        print("\nOUTPUT2 ON")
        if args.pulse_output1:
            controller.start_excitation()
            print("OUTPUT1 ON (1 s)…")
            time.sleep(1.0)
            controller.stop_excitation()
            print("OUTPUT1 OFF")
        print("\nEstado final:\n" + controller.read_state().summary())
    finally:
        warnings = controller.close()
        for warning in warnings:
            print("ATENCIÓN:", warning)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
