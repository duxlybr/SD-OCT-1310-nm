"""Small Tk helpers shared by the GUIs."""
from __future__ import annotations

import tkinter as tk

# Wheel events Tk binds on the ttk combobox class (Windows/macOS: MouseWheel;
# X11: buttons 4/5). Without them the wheel only scrolls the panel underneath.
_WHEEL_SEQUENCES = ("<MouseWheel>", "<Shift-MouseWheel>", "<Button-4>", "<Button-5>")


def disable_combobox_wheel(widget: tk.Misc) -> None:
    """Drop-down lists ignore the mouse wheel in the whole Tk application.

    Scrolling the left control panel over a combobox used to change its value
    (mode, pattern, excitation…) by accident. The class binding is removed, so
    the event reaches the panel's ``bind_all`` handler and the panel scrolls
    instead; the value only changes by clicking the list or with the keyboard.
    """
    for sequence in _WHEEL_SEQUENCES:
        widget.unbind_class("TCombobox", sequence)
