#!/usr/bin/env python3
"""Bundle Apple's back-deployment runtime, including weak concurrency imports."""
import argparse
import shutil
import subprocess
from pathlib import Path
from macos_compatibility import macho_metadata

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("destination", type=Path)
parser.add_argument("--arch", choices=["arm64", "x86_64"], required=True)
parser.add_argument("--identity", default="-")
parser.add_argument("executables", type=Path, nargs="+")
args = parser.parse_args()
args.destination.mkdir(parents=True, exist_ok=True)
command = ["xcrun", "swift-stdlib-tool", "--copy", "--strip-bitcode", "--platform", "macosx",
           "--destination", str(args.destination), "--sign", args.identity]
for executable in args.executables:
    command += ["--scan-executable", str(executable)]
subprocess.run(command, check=True)

# Some tool/architecture combinations leave only a .original backup for a weak
# concurrency import. Supply that exact Apple runtime before removing backups.
needs_concurrency = any(
    name.endswith("/libswift_Concurrency.dylib")
    for executable in args.executables
    for name, _ in macho_metadata(executable.read_bytes())["libraries"]
)
runtime = args.destination / "libswift_Concurrency.dylib"
if needs_concurrency and not runtime.is_file():
    original = args.destination / "libswift_Concurrency.dylib.original"
    if not original.is_file():
        compiler = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()).resolve()
        original = compiler.parent.parent / "lib/swift-5.5/macosx/libswift_Concurrency.dylib"
    if not original.is_file():
        raise SystemExit("Apple's macOS back-deployment concurrency runtime is missing from the selected Xcode")
    shutil.copy2(original, runtime)
    print(f"Bundled Apple concurrency runtime: {original}")

for library in args.destination.glob("*.dylib"):
    subprocess.run(["lipo", str(library), "-verify_arch", args.arch], check=True)
    subprocess.run(["codesign", "--force", "--sign", args.identity, str(library)], check=True)
for backup in args.destination.glob("*.original"):
    backup.unlink()
