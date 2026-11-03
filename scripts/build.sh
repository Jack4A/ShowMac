#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# CLI-only toolchains omit SwiftUI's platform macros. Select an installed full
# Xcode for this process, without changing the user's global developer directory.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
    for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer; do
        if [[ -f "$candidate/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib" ]]; then
            export DEVELOPER_DIR="$candidate"
            break
        fi
    done
fi
SDK="${THERMALSCOPE_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
ARCH="${THERMALSCOPE_ARCH:-$(uname -m)}"
MINIMUM_OS="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$ROOT/Resources/Info.plist")"
# SwiftPM in Xcode 27 silently raises a macOS 11 package to macOS 12. Fail
# clearly instead of shipping an Info.plist that disagrees with its executables.
python3 - "$SDK" "$MINIMUM_OS" <<'PY'
import json,sys
from pathlib import Path
sdk=Path(sys.argv[1]);target=tuple(map(int,sys.argv[2].split('.')))
minimum=json.loads((sdk/'SDKSettings.json').read_text())['SupportedTargets']['macosx']['MinimumDeploymentTarget']
if tuple(map(int,minimum.split('.')))>target:
    raise SystemExit(f'This SDK requires macOS {minimum}; select full Xcode 26.5/26.6 with DEVELOPER_DIR to build for macOS {sys.argv[2]}.')
PY
case "$ARCH" in x86_64|arm64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
DEFAULT_BUILD_DIR="$ROOT/.build"
if [[ "$ARCH" != "$(uname -m)" ]]; then DEFAULT_BUILD_DIR="$ROOT/.build/cross/$ARCH"; fi
BUILD_DIR="${THERMALSCOPE_BUILD_DIR:-$DEFAULT_BUILD_DIR}"
BUILD_ARGS=(--build-system native --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --jobs 2 --sdk "$SDK"
    --triple "$ARCH-apple-macosx$MINIMUM_OS" -Xlinker -rpath -Xlinker '@executable_path/../Frameworks')
APP="${1:-$(dirname "$ROOT")/showmac.app}"
xcrun swift build "${BUILD_ARGS[@]}"
BIN="$(xcrun swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/ThermalScope" "$APP/Contents/MacOS/ThermalScope"
cp "$BIN/ThermalScopeHelper" "$APP/Contents/Helpers/ThermalScopeHelper"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Localization.json" "$APP/Contents/Resources/Localization.json"
cp "$ROOT/Resources/SMCKit-LICENSE.txt" "$APP/Contents/Resources/SMCKit-LICENSE.txt"
# actool ships only with full Xcode; without it the appearance assets are skipped and
# Color.accentColor falls back to the system accent color at runtime.
if xcrun --find actool >/dev/null 2>&1; then
    xcrun actool "$ROOT/Resources/Appearance.xcassets" --compile "$APP/Contents/Resources" \
        --platform macosx --minimum-deployment-target "$MINIMUM_OS" --target-device mac \
        --accent-color AccentColor --output-partial-info-plist "$BIN/Appearance-Info.plist" >/dev/null
else
    echo "warning: actool not found; skipping appearance assets, accent color falls back to system" >&2
fi
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
for localization in "$ROOT"/Resources/*.lproj; do
    if [ -d "$localization" ]; then cp -R "$localization" "$APP/Contents/Resources/"; fi
done
THERMALSCOPE_SDK="$SDK" THERMALSCOPE_ARCH="$ARCH" bash "$ROOT/scripts/build-widget.sh" "$APP" "$BIN"
python3 "$ROOT/scripts/bundle-swift-runtime.py" "$APP/Contents/Frameworks" \
    --arch "$ARCH" --identity "${THERMALSCOPE_SIGN_IDENTITY:--}" \
    "$APP/Contents/MacOS/ThermalScope" "$APP/Contents/Helpers/ThermalScopeHelper"
# The SDK in Mach-O controls compatibility appearance; don't ship a build whose
# SDK stamp silently fell back to the deployment target.
python3 - "$APP" "$SDK" "$MINIMUM_OS" <<'PY'
import json,re,subprocess,sys
from pathlib import Path
app,sdk=map(Path,sys.argv[1:3]);minimum=sys.argv[3]
expected=json.loads((sdk/'SDKSettings.json').read_text())['Version']
def version(text):return tuple((list(map(int,text.split('.')))+[0,0])[:3])
for relative in ['Contents/MacOS/ThermalScope','Contents/Helpers/ThermalScopeHelper','Contents/PlugIns/ThermalScopeWidget.appex/Contents/MacOS/ThermalScopeWidget']:
    output=subprocess.check_output(['xcrun','vtool','-show-build',str(app/relative)],text=True)
    found=re.findall(r'^\s*sdk\s+(\d+(?:\.\d+)*)\s*$',output,re.M)
    if not found or any(version(value)!=version(expected) for value in found):
        raise SystemExit(f'SDK stamp mismatch for {relative}: expected {expected}, got {found}')
    minos=re.findall(r'^\s*minos\s+(\d+(?:\.\d+)*)\s*$',output,re.M)
    if not minos or any(version(value)!=version(minimum) for value in minos):
        raise SystemExit(f'Deployment target mismatch for {relative}: expected {minimum}, got {minos}')
print(f'Verified SDK {expected} and minimum macOS {minimum} in app, helper and widget.')
PY
python3 "$ROOT/scripts/macos_compatibility.py" "$APP" --arch "$ARCH" --strip-toolchain-rpaths
IDENTITY="${THERMALSCOPE_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --entitlements "$BIN/Widget.entitlements" "$APP/Contents/PlugIns/ThermalScopeWidget.appex"
codesign --force --sign "$IDENTITY" "$APP/Contents/Helpers/ThermalScopeHelper"
codesign --force --sign "$IDENTITY" --entitlements "$BIN/Host.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"
