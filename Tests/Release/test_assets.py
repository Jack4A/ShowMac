import importlib.util
import json
import plistlib
import tempfile
import struct
import sys
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from macos_compatibility import EXECUTABLES

SPEC = importlib.util.spec_from_file_location("release_assets", ROOT / "scripts/verify-release-assets.py")
assets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(assets)


class ReleaseAssetsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.version = "1.17.1"
        self.commit = "a" * 40
        for arch, suffix in [("arm64", "-arm64"), ("x86_64", "")]:
            name = f"ThermalScope-{self.version}-macOS-{arch}.zip"
            metadata = plistlib.dumps({"CFBundleShortVersionString": self.version, "CFBundleVersion": "262", "LSMinimumSystemVersion": "11.0"})
            with zipfile.ZipFile(self.folder / name, "w") as zipped:
                for path in ["Contents/Info.plist", "Contents/PlugIns/ThermalScopeWidget.appex/Contents/Info.plist"]:
                    zipped.writestr("ThermalScope.app/" + path, metadata)
                for path in EXECUTABLES:
                    zipped.writestr("ThermalScope.app/" + path, self.binary(arch))
            (self.folder / f"INSTALL{suffix}.txt").write_text("Fixture installation instructions")
            manifest = {"version": self.version, "build": "262", "minimum_macos": "11.0", "source_commit": self.commit, "architecture": arch, "archive": name, "archive_sha256": assets.sha256(self.folder / name), "checks": ["deep_strict_signature", "target_architecture_all_executables", "executable_permissions", "zip_extract_signature", "static_english_localization", "system_only_dynamic_dependencies", "minimum_macos_all_executables", "weak_linked_new_frameworks", "back_deployed_swift_runtime"]}
            (self.folder / f"release-manifest{suffix}.json").write_text(json.dumps(manifest))
            self.refresh(suffix)

    @staticmethod
    def binary(arch, minimum=11, commands=()):
        cpu = {"arm64": 0x100000c, "x86_64": 0x1000007}[arch]
        deployment = struct.pack("<6I", 0x32, 24, 1, minimum << 16, (26 << 16) | (5 << 8), 0)
        extra = b"".join(commands)
        return struct.pack("<8I", 0xfeedfacf, cpu, 0, 2, 1 + len(commands), 24 + len(extra), 0, 0) + deployment + extra

    def rewrite_archive(self, relative, data):
        path = self.folder / f"ThermalScope-{self.version}-macOS-arm64.zip"
        with zipfile.ZipFile(path) as zipped:
            files = {name: zipped.read(name) for name in zipped.namelist()}
        files["ThermalScope.app/" + relative] = data
        with zipfile.ZipFile(path, "w") as zipped:
            for name, value in files.items():
                zipped.writestr(name, value)
        manifest_path = self.folder / "release-manifest-arm64.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["archive_sha256"] = assets.sha256(path)
        manifest_path.write_text(json.dumps(manifest))
        self.refresh("-arm64")

    def test_binary_deployment_is_not_only_plist(self):
        for relative in EXECUTABLES:
            with self.subTest(relative=relative):
                self.rewrite_archive(relative, self.binary("arm64", minimum=13))
                with self.assertRaisesRegex(ValueError, "Binary minimum"):
                    assets.verify(self.folder, self.version, self.commit)
                self.rewrite_archive(relative, self.binary("arm64"))

    def test_widget_minimum_must_match_host(self):
        self.rewrite_archive("Contents/PlugIns/ThermalScopeWidget.appex/Contents/Info.plist", plistlib.dumps({"CFBundleShortVersionString": self.version, "CFBundleVersion": "262", "LSMinimumSystemVersion": "13.0"}))
        with self.assertRaisesRegex(ValueError, "Bundle minimum"):
            assets.verify(self.folder, self.version, self.commit)

    def test_manifest_minimum_must_match_binary(self):
        path = self.folder / "release-manifest.json"
        data = json.loads(path.read_text())
        data["minimum_macos"] = "12.0"
        path.write_text(json.dumps(data))
        self.refresh("")
        with self.assertRaisesRegex(ValueError, "Manifest minimum"):
            assets.verify(self.folder, self.version, self.commit)

    @staticmethod
    def path_command(command, path):
        offset = 12 if command == 0x8000001c else 24
        size = (offset + len(path) + 1 + 7) // 8 * 8
        return (struct.pack("<III", command, size, offset) + bytes(offset - 12) + path.encode() + b"\0").ljust(size, b"\0")

    def test_new_framework_cannot_be_strong_linked(self):
        load = self.path_command(0xc, "/System/Library/Frameworks/Charts.framework/Versions/A/Charts")
        self.rewrite_archive(EXECUTABLES[0], self.binary("arm64", commands=[load]))
        with self.assertRaisesRegex(ValueError, "weak linked"):
            assets.verify(self.folder, self.version, self.commit)

    def test_weak_framework_is_allowed(self):
        load = self.path_command(0x80000018, "/System/Library/Frameworks/Charts.framework/Versions/A/Charts")
        self.rewrite_archive(EXECUTABLES[0], self.binary("arm64", commands=[load]))
        self.assertEqual(len(assets.verify(self.folder, self.version, self.commit)), 8)

    def test_concurrency_runtime_must_be_bundled_and_discoverable(self):
        load = self.path_command(0x80000018, "@rpath/libswift_Concurrency.dylib")
        self.rewrite_archive(EXECUTABLES[0], self.binary("arm64", commands=[load]))
        with self.assertRaisesRegex(ValueError, "Missing back-deployed"):
            assets.verify(self.folder, self.version, self.commit)
        self.rewrite_archive("Contents/Frameworks/libswift_Concurrency.dylib", b"fixture runtime")
        with self.assertRaisesRegex(ValueError, "runtime search path"):
            assets.verify(self.folder, self.version, self.commit)
        rpath = self.path_command(0x8000001c, "@executable_path/../Frameworks")
        self.rewrite_archive(EXECUTABLES[0], self.binary("arm64", commands=[load, rpath]))
        self.assertEqual(len(assets.verify(self.folder, self.version, self.commit)), 8)

    def test_developer_machine_rpath_is_rejected(self):
        path = self.path_command(0x8000001c, "/Applications/Xcode.app/Contents/Developer/Toolchains/default/usr/lib")
        self.rewrite_archive(EXECUTABLES[0], self.binary("arm64", commands=[path]))
        with self.assertRaisesRegex(ValueError, "Non-portable"):
            assets.verify(self.folder, self.version, self.commit)

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
        path = self.folder / "ThermalScope-1.17.1-macOS-arm64.zip"
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
