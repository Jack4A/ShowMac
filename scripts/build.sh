#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${THERMALSCOPE_ARCH:-$(uname -m)}"
case "$ARCH" in x86_64|arm64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
DEFAULT_BUILD_DIR="$ROOT/.build"
if [[ "$ARCH" != "$(uname -m)" ]]; then DEFAULT_BUILD_DIR="$ROOT/.build/cross/$ARCH"; fi
BUILD_DIR="${THERMALSCOPE_BUILD_DIR:-$DEFAULT_BUILD_DIR}"
BUILD_ARGS=(--package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --jobs 2)
if [[ "$ARCH" != "$(uname -m)" ]]; then
    BUILD_ARGS+=(--triple "$ARCH-apple-macosx13.0" --sdk "$(xcrun --sdk macosx --show-sdk-path)")
fi
APP="${1:-$(dirname "$ROOT")/ThermalScope.app}"
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/ThermalScope" "$APP/Contents/MacOS/ThermalScope"
cp "$BIN/ThermalScopeHelper" "$APP/Contents/Helpers/ThermalScopeHelper"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Localization.json" "$APP/Contents/Resources/Localization.json"
cp "$ROOT/Resources/SMCKit-LICENSE.txt" "$APP/Contents/Resources/SMCKit-LICENSE.txt"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
for localization in "$ROOT"/Resources/*.lproj; do
    if [ -d "$localization" ]; then cp -R "$localization" "$APP/Contents/Resources/"; fi
done
THERMALSCOPE_ARCH="$ARCH" bash "$ROOT/scripts/build-widget.sh" "$APP" "$BIN"
IDENTITY="${THERMALSCOPE_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" "$APP/Contents/Helpers/ThermalScopeHelper"
codesign --force --sign "$IDENTITY" --entitlements "$BIN/Host.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
