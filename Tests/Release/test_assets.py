import importlib.util
import json
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_assets", ROOT / "scripts/verify-release-assets.py")
assets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(assets)


class ReleaseAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.version = "1.17.0"
        self.commit = "a" * 40
        for arch, suffix in [("arm64", "-arm64"), ("x86_64", "")]:
            name = f"ThermalScope-{self.version}-macOS-{arch}.zip"
            metadata = plistlib.dumps({"CFBundleShortVersionString": self.version, "CFBundleVersion": "261"})
            with zipfile.ZipFile(self.folder / name, "w") as zipped:
                for path in ["Contents/Info.plist", "Contents/PlugIns/ThermalScopeWidget.appex/Contents/Info.plist"]:
                    zipped.writestr("ThermalScope.app/" + path, metadata)
            (self.folder / f"INSTALL{suffix}.txt").write_text("Fixture installation instructions")
            manifest = {"version": self.version, "build": "261", "source_commit": self.commit, "architecture": arch, "archive": name, "archive_sha256": assets.sha256(self.folder / name), "checks": ["deep_strict_signature", "target_architecture_all_executables", "executable_permissions", "zip_extract_signature", "static_english_localization", "system_only_dynamic_dependencies"]}
            (self.folder / f"release-manifest{suffix}.json").write_text(json.dumps(manifest))
            self.refresh(suffix)

    def refresh(self, suffix):
        arch = "arm64" if suffix else "x86_64"
        names = [f"ThermalScope-{self.version}-macOS-{arch}.zip", f"INSTALL{suffix}.txt", f"release-manifest{suffix}.json"]
        (self.folder / f"SHA256SUMS{suffix}.txt").write_text("".join(assets.sha256(self.folder / name) + "  " + name + "\n" for name in names))

    def test_complete_pair(self):
        self.assertEqual(len(assets.verify(self.folder, self.version, self.commit)), 8)

    def test_tampered_asset(self):
        (self.folder / "INSTALL.txt").write_text("changed")
        with self.assertRaisesRegex(ValueError, "Checksum mismatch"):
            assets.verify(self.folder, self.version, self.commit)

    def test_wrong_source_commit(self):
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            assets.verify(self.folder, self.version, "b" * 40)

    def test_missing_architecture(self):
        (self.folder / "release-manifest-arm64.json").unlink()
        with self.assertRaisesRegex(ValueError, "Missing release asset"):
            assets.verify(self.folder, self.version, self.commit)

    def test_bundle_version_mismatch(self):
        path = self.folder / "ThermalScope-1.17.0-macOS-arm64.zip"
        with zipfile.ZipFile(path, "w") as zipped:
            zipped.writestr("ThermalScope.app/Contents/Info.plist", plistlib.dumps({"CFBundleShortVersionString": "1.16.0", "CFBundleVersion": "260"}))
        manifest_path = self.folder / "release-manifest-arm64.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["archive_sha256"] = assets.sha256(path)
        manifest_path.write_text(json.dumps(manifest))
        self.refresh("-arm64")
        with self.assertRaisesRegex(ValueError, "Bundle version mismatch"):
            assets.verify(self.folder, self.version, self.commit)

    def test_unexpected_asset(self):
        (self.folder / "local-debug.log").write_text("not a release asset")
        with self.assertRaisesRegex(ValueError, "exactly the eight"):
            assets.verify(self.folder, self.version, self.commit)

    def test_missing_package_verification(self):
        path = self.folder / "release-manifest.json"
        manifest = json.loads(path.read_text())
        manifest["checks"] = []
        path.write_text(json.dumps(manifest))
        self.refresh("")
        with self.assertRaisesRegex(ValueError, "Required package checks"):
            assets.verify(self.folder, self.version, self.commit)


if __name__ == "__main__":
    unittest.main()
