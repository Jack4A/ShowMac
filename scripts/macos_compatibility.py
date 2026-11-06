"""Inspect Mach-O deployment commands without requiring macOS or Xcode."""
import plistlib
import struct
from pathlib import Path

EXECUTABLES = [
    "Contents/MacOS/ThermalScope",
    "Contents/Helpers/ThermalScopeHelper",
    "Contents/Helpers/ShowMacUsageEngine",
    "Contents/PlugIns/ThermalScopeWidget.appex/Contents/MacOS/ThermalScopeWidget",
]
MINIMUM_MACOS = "11.0"


def version_tuple(value):
    return tuple((list(map(int, value.split("."))) + [0, 0])[:3])


def macho_metadata(data):
    if data[:4] != b"\xcf\xfa\xed\xfe" or len(data) < 32:
        raise ValueError("Expected a thin 64-bit Mach-O executable")
    cpu = struct.unpack_from("<I", data, 4)[0]
    count, length = struct.unpack_from("<II", data, 16)
    end = 32 + length
    if count > 4096 or end > len(data):
        raise ValueError("Invalid Mach-O command table")
    offset, minimum, libraries, rpaths = 32, None, [], []
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("Truncated Mach-O command")
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > end:
            raise ValueError("Invalid Mach-O command size")
        if command in (0x32, 0x24):  # LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX
            position = offset + (12 if command == 0x32 else 8)
            if position + 8 > offset + size:
                raise ValueError("Invalid Mach-O deployment command")
            raw = struct.unpack_from("<I", data, position)[0]
            if command == 0x32 and struct.unpack_from("<I", data, offset + 8)[0] != 1:
                raise ValueError("Expected macOS build platform")
            minimum = (raw >> 16, (raw >> 8) & 255, raw & 255)
        if command in (0xc, 0x80000018, 0x8000001c):  # load / weak load / rpath
            if size < 12:
                raise ValueError("Invalid Mach-O path command")
            start = struct.unpack_from("<I", data, offset + 8)[0]
            if not 12 <= start < size:
                raise ValueError("Invalid Mach-O path offset")
            name = data[offset + start:offset + size].split(b"\0", 1)[0].decode()
            if command == 0x8000001c:
                rpaths.append(name)
            else:
                libraries.append((name, command == 0x80000018))
        offset += size
    if minimum is None:
        raise ValueError("Missing Mach-O deployment version")
    return {"cpu": cpu, "minimum": minimum, "libraries": libraries, "rpaths": rpaths}


def verify_app(read, architecture):
    expected_cpu = {"arm64": 0x100000c, "x86_64": 0x1000007}[architecture]
    for relative in ["Contents/Info.plist", "Contents/PlugIns/ThermalScopeWidget.appex/Contents/Info.plist"]:
        metadata = plistlib.loads(read(relative))
        if version_tuple(metadata.get("LSMinimumSystemVersion", "0")) != version_tuple(MINIMUM_MACOS):
            raise ValueError(f"Bundle minimum macOS mismatch: {relative}")
    host = plistlib.loads(read("Contents/Info.plist"))
    engine_required = version_tuple(host.get("CFBundleShortVersionString", "0")) >= (1,18,15)
    for relative in EXECUTABLES:
        try:
            data = read(relative)
        except (FileNotFoundError, KeyError):
            if relative.endswith("/ShowMacUsageEngine") and not engine_required:
                continue
            raise ValueError("Missing required bundled executable: " + relative)
        metadata = macho_metadata(data)
        if metadata["cpu"] != expected_cpu or metadata["minimum"] != version_tuple(MINIMUM_MACOS):
            raise ValueError(f"Binary minimum macOS/architecture mismatch: {relative}")
        if any(not path.startswith(("@executable_path", "@loader_path", "/usr/lib/swift")) for path in metadata["rpaths"]):
            raise ValueError(f"Non-portable runtime search path: {relative}")
        for library, weak in metadata["libraries"]:
            if any(name in library for name in ["/Charts.framework/", "/SwiftUICore.framework/", "/Symbols.framework/"]) and not weak:
                raise ValueError(f"New framework must be weak linked: {relative}: {library}")
            if library.endswith("/libswift_Concurrency.dylib"):
                root = relative.split("Contents/MacOS/")[0] if ".appex/" in relative else ""
                runtime = root + "Contents/Frameworks/libswift_Concurrency.dylib"
                try:
                    read(runtime)
                except (FileNotFoundError, KeyError) as error:
                    raise ValueError(f"Missing back-deployed Swift runtime: {runtime}") from error
                if "@executable_path/../Frameworks" not in metadata["rpaths"]:
                    raise ValueError(f"Missing Swift runtime search path: {relative}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--arch", choices=["arm64", "x86_64"], required=True)
    parser.add_argument("--strip-toolchain-rpaths", action="store_true")
    args = parser.parse_args()
    if args.strip_toolchain_rpaths:
        import subprocess
        for relative in EXECUTABLES:
            binary = args.app / relative
            for path in macho_metadata(binary.read_bytes())["rpaths"]:
                if "/Toolchains/" in path:
                    subprocess.run(["install_name_tool", "-delete_rpath", path, str(binary)], check=True)
    verify_app(lambda name: (args.app / name).read_bytes(), args.arch)
    print(f"Verified macOS {MINIMUM_MACOS} deployment, weak frameworks and Swift runtime: {args.arch}")
