#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?app bundle path required}"
BIN="${2:?Swift build output required}"
IDENTITY="${THERMALSCOPE_SIGN_IDENTITY:--}"
GROUP="${THERMALSCOPE_APP_GROUP:-}"
ARCH="${THERMALSCOPE_ARCH:-$(uname -m)}"
case "$ARCH" in x86_64|arm64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
if [[ -n "$GROUP" && "$IDENTITY" == "-" ]]; then
    echo 'App Groups require a real signing identity; no Team ID is invented.' >&2
    exit 1
fi
EXT="$APP/Contents/PlugIns/ThermalScopeWidget.appex"
mkdir -p "$EXT/Contents/MacOS" "$EXT/Contents/Resources"
SDK="${THERMALSCOPE_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
xcrun swiftc -parse-as-library -application-extension -O -target "$ARCH-apple-macosx13.0" -sdk "$SDK" -I "$BIN/Modules" -I "$BIN" -L "$BIN" -lWidgetUI -lWidgetShared -framework SwiftUI -framework WidgetKit -Xlinker -e -Xlinker _NSExtensionMain "$ROOT/Widgets/ThermalScopeWidget.swift" -o "$EXT/Contents/MacOS/ThermalScopeWidget"
python3 - "$APP" "$EXT" "$GROUP" "$BIN" <<'PY'
import plistlib,sys
from pathlib import Path
app,ext,group,metadata=Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3],Path(sys.argv[4])
host=plistlib.loads((app/'Contents/Info.plist').read_bytes())
p={'CFBundleInfoDictionaryVersion':'6.0','CFBundleDevelopmentRegion':'en','CFBundleIdentifier':host['CFBundleIdentifier']+'.Widget','CFBundleExecutable':'ThermalScopeWidget','CFBundleName':'温控台','CFBundleDisplayName':'温控台','CFBundlePackageType':'XPC!','CFBundleShortVersionString':host['CFBundleShortVersionString'],'CFBundleVersion':host['CFBundleVersion'],'CFBundleSupportedPlatforms':['MacOSX'],'LSMinimumSystemVersion':'13.0','NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}}
e={'com.apple.security.app-sandbox':True}
h={}
if group:
 p['ThermalScopeAppGroup']=group;host['ThermalScopeAppGroup']=group
 e['com.apple.security.application-groups']=[group];h['com.apple.security.application-groups']=[group]
else:
 e['com.apple.security.temporary-exception.files.home-relative-path.read-only']=['/Library/Application Support/ThermalScope/WidgetSnapshots/']
(ext/'Contents/Info.plist').write_bytes(plistlib.dumps(p))
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(host))
(metadata/'Widget.entitlements').write_bytes(plistlib.dumps(e))
(metadata/'Host.entitlements').write_bytes(plistlib.dumps(h))
for name in ['Widget.entitlements','Host.entitlements']:
 (app/'Contents'/name).unlink(missing_ok=True)
PY
cp "$ROOT/Resources/Localization.json" "$EXT/Contents/Resources/Localization.json"
for localization in "$ROOT"/Resources/*.lproj; do
    if [ -d "$localization" ]; then cp -R "$localization" "$EXT/Contents/Resources/"; fi
done
codesign --force --sign "$IDENTITY" --entitlements "$BIN/Widget.entitlements" "$EXT"
