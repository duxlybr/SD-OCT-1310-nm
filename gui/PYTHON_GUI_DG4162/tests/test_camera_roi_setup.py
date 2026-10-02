import unittest

from octoce.camera_roi_setup import geometry_scale


class GeometryCalibrationTests(unittest.TestCase):
    def test_line_uses_euclidean_length(self):
        self.assertEqual(geometry_scale("Línea", [(0, 0), (300, 400)], 25), 20)

    def test_square_uses_side_instead_of_diagonal(self):
        self.assertEqual(geometry_scale("Cuadrado", [(300, 300), (100, 100)], 10), 20)

    def test_ellipse_uses_selected_diameter_and_circle_accepts_either(self):
        points = [(100, 100), (420, 260)]
        self.assertEqual(geometry_scale("Elipse / círculo", points, 20), 16)
        self.assertEqual(geometry_scale("Elipse / círculo", points, 20, "Vertical"), 8)
        for axis in ("Horizontal", "Vertical"):
            self.assertEqual(geometry_scale("Elipse / círculo", [(0, 0), (200, 200)], 10, axis), 20)

    def test_rejects_invalid_measurements_and_shapes(self):
        for kind, points, mm, axis in (
            ("Línea", [], 10, "Horizontal"),
            ("Línea", [(0, 0), (1, 0)], 10, "Horizontal"),
            ("Línea", [(0, 0), (200, 0)], 0, "Horizontal"),
            ("Línea", [(0, 0), (200, 0)], float("nan"), "Horizontal"),
            ("Línea", [(0, 0), (float("inf"), 0)], 10, "Horizontal"),
            ("Cuadrado", [(0, 0), (200, 100)], 10, "Horizontal"),
            ("Elipse / círculo", [(0, 0), (200, 0)], 10, "Horizontal"),
            ("Elipse / círculo", [(0, 0), (200, 100)], 10, "Diagonal"),
        ):
            with self.subTest(kind=kind, points=points, mm=mm, axis=axis):
                with self.assertRaises(ValueError):
                    geometry_scale(kind, points, mm, axis)
