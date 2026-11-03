#!/bin/bash
# Native fixture checks only; never request authorization or write real hardware.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
    for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer; do
        if [[ -f "$candidate/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]]; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi
SDK="${THERMALSCOPE_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
BUILD_DIR="${THERMALSCOPE_BUILD_DIR:-$ROOT/.build}"
ARGS=(--build-system native --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --jobs 2 --sdk "$SDK")
APP="$ROOT/build/check/ThermalScope.app"
bash "$ROOT/scripts/build.sh" "$APP"
BIN="$(xcrun swift build "${ARGS[@]}" --show-bin-path)"
"$BIN/ThermalCoreChecks"
python3 -m unittest discover -s Tests/Performance -v
python3 -m unittest discover -s Tests/Release -v
"$APP/Contents/MacOS/ThermalScope" --hidden-view-update-check
"$APP/Contents/MacOS/ThermalScope" --localization-check
for flag in --status-cards-check --curve-warning-check --menu-sensor-check --menu-composition-check --menu-customization-check; do
    "$APP/Contents/MacOS/ThermalScope" "$flag" --ui-check
done
"$APP/Contents/MacOS/ThermalScope" --cpu-warning-check
