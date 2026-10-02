"""Stable local project paths, independent of the shell working directory."""
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = APP_ROOT.parent
DATA_ROOT = PROJECT_ROOT / "data"
ACQUISITIONS_DIR = DATA_ROOT / "acquisitions"
CONFIG_DIR = PROJECT_ROOT / "config"
