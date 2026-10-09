from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from octoce.galvo_settings import GalvoOffsets


class GalvoSettingsTests(unittest.TestCase):
    def test_persisted_defaults_and_invalid_value_preserves_previous(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "galvo_offsets.json"
            self.assertEqual(GalvoOffsets.load(path), GalvoOffsets())
            offsets = GalvoOffsets(0.025, -0.042)
            offsets.save(path)
            self.assertEqual(GalvoOffsets.load(path), offsets)
            for invalid in (8, float("nan"), float("inf")):
                with self.assertRaises(ValueError):
                    GalvoOffsets(invalid, 0).save(path)
                self.assertEqual(GalvoOffsets.load(path), offsets)
            self.assertEqual(list(path.parent.glob("*.tmp")), [])

    def test_corrupt_defaults_are_reported(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "galvo_offsets.json"
            path.write_text('{"schema_version": 1, "x_mm": 0, "y_mm": 99}')
            with self.assertRaises(ValueError):
                GalvoOffsets.load(path)
