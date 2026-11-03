#!/usr/bin/env python3
"""Verify both architectures before publishing or installing release assets."""
import argparse
import hashlib
import json
import plistlib
import re
import zipfile
from pathlib import Path
from macos_compatibility import MINIMUM_MACOS, verify_app, version_tuple


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(folder, version, commit):
    folder = Path(folder)
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected a three-part release version")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Expected a full source commit SHA")
    expected = set()
    builds = set()
    for arch, suffix in [("arm64", "-arm64"), ("x86_64", "")]:
        archive = f"ThermalScope-{version}-macOS-{arch}.zip"
        manifest = f"release-manifest{suffix}.json"
        install = f"INSTALL{suffix}.txt"
        sums = f"SHA256SUMS{suffix}.txt"
        expected.update([archive, manifest, install, sums])
        for name in [archive, manifest, install, sums]:
            if not (folder / name).is_file():
                raise ValueError(f"Missing release asset: {name}")
        rows = (folder / sums).read_text().splitlines()
        checksums = {}
        for row in rows:
            match = re.fullmatch(r"([0-9a-f]{64})  ([^/\\]+)", row)
            if not match or match[2] in checksums:
                raise ValueError(f"Invalid or duplicate checksum in {sums}")
            checksums[match[2]] = match[1]
        if set(checksums) != {archive, manifest, install}:
            raise ValueError(f"Checksum inventory differs for {arch}")
        for name, digest in checksums.items():
            if sha256(folder / name) != digest:
                raise ValueError(f"Checksum mismatch: {name}")
        data = json.loads((folder / manifest).read_text())
        if (data.get("version"), data.get("architecture"), data.get("source_commit"), data.get("archive")) != (version, arch, commit, archive):
            raise ValueError(f"Release identity mismatch: {manifest}")
        if data.get("archive_sha256") != sha256(folder / archive):
            raise ValueError(f"Archive digest mismatch: {archive}")
        if version_tuple(data.get("minimum_macos", "0")) != version_tuple(MINIMUM_MACOS):
            raise ValueError(f"Manifest minimum macOS mismatch: {manifest}")
        required = {"deep_strict_signature", "target_architecture_all_executables", "executable_permissions", "zip_extract_signature", "static_english_localization", "system_only_dynamic_dependencies", "minimum_macos_all_executables", "weak_linked_new_frameworks", "back_deployed_swift_runtime"}
        if not required.issubset(data.get("checks", [])):
            raise ValueError(f"Required package checks missing: {manifest}")
        builds.add(data.get("build"))
        with zipfile.ZipFile(folder / archive) as zipped:
            for info in ["Contents/Info.plist", "Contents/PlugIns/ThermalScopeWidget.appex/Contents/Info.plist"]:
                metadata = plistlib.loads(zipped.read("ThermalScope.app/" + info))
                if metadata.get("CFBundleShortVersionString") != version or metadata.get("CFBundleVersion") != data.get("build"):
                    raise ValueError(f"Bundle version mismatch: {archive}/{info}")
            verify_app(lambda name: zipped.read("ThermalScope.app/" + name), arch)
    if len(builds) != 1 or not all(isinstance(build, str) and build.isdigit() for build in builds):
        raise ValueError("Architectures must share one numeric build number")
    if {p.name for p in folder.iterdir()} != expected:
        raise ValueError("Release directory must contain exactly the eight release assets")
    return sorted(expected)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()
    assets = verify(args.directory, args.version, args.commit)
    print(f"Verified {len(assets)} release assets: {args.version} at {args.commit}")
