import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ui_appearance", ROOT / "scripts/compare-ui-appearance.py")
appearance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(appearance)


class AppearanceComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data = {}
        for theme in ["light", "dark"]:
            for page in ["metrics", "thermal", "sensors", "optimization", "metric", "settings", "popover"]:
                popup = page == "popover"
                self.data[theme + "-" + page] = {
                    "width": 390 if popup else 1000, "height": 640 if popup else 760,
                    "sidebarWidth": None if popup else 220,
                    "sidebarHeight": None if popup else 748, "sidebarTop": None if popup else 0, "settingsTop": None if popup else 696,
                    "selectedColor": None if popup else ([76, 69, 80, 255] if theme == "dark" else [255] * 4),
                    "sidebarColor": None if popup else [29, 29, 37, 255],
                    "contentTopColor": None if popup else ([35, 33, 44, 255] if theme == "dark" else [244,245,247,255]),
                }
        for version in ["26", "27"]:
            folder = self.root / version
            folder.mkdir()
            (folder / "appearance-metrics.json").write_text(json.dumps(self.data))

    def change(self, name, field, value):
        self.data[name][field] = value
        (self.root / "26/appearance-metrics.json").write_text(json.dumps(self.data))

    def test_same_binary_stable_chrome(self):
        self.assertEqual(appearance.compare(self.root), 14)

    def test_reversed_dark_selection_fails(self):
        self.change("dark-metrics", "selectedColor", [27, 27, 35, 255])
        with self.assertRaisesRegex(ValueError, "Color drift"):
            appearance.compare(self.root)

    def test_default_column_width_drift_fails(self):
        self.change("light-metrics", "sidebarWidth", 280)
        with self.assertRaisesRegex(ValueError, "Layout drift"):
            appearance.compare(self.root)

    def test_content_titlebar_background_drift_fails(self):
        self.change("dark-metrics", "contentTopColor", [48, 44, 49, 255])
        with self.assertRaisesRegex(ValueError, "Color drift"):
            appearance.compare(self.root)

    def test_missing_measurement_cannot_pass(self):
        self.change("dark-metrics", "selectedColor", None)
        with self.assertRaisesRegex(ValueError, "Missing color"):
            appearance.compare(self.root)

    def test_small_raster_rounding_is_allowed(self):
        self.change("dark-metrics", "selectedColor", [78, 70, 81, 255])
        self.assertEqual(appearance.compare(self.root), 14)
