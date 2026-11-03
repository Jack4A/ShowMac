#!/bin/bash
# Independent, sandboxed Mac App Store edition. Never links the desktop helper.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${SHOWMAC_ARCH:-$(uname -m)}"
SDK="${SHOWMAC_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
MINIMUM=11.0
APP="${1:-$ROOT/build/store/ShowMac.app}"
IDENTITY="${SHOWMAC_SIGN_IDENTITY:--}"
BUILD_DIR="${SHOWMAC_BUILD_DIR:-$ROOT/.build/store-$ARCH}"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
python3 - "$SDK" "$MINIMUM" <<'PY'
import json,sys
from pathlib import Path
settings=json.loads((Path(sys.argv[1])/'SDKSettings.json').read_text())
minimum=settings['SupportedTargets']['macosx']['MinimumDeploymentTarget']
if tuple(map(int,minimum.split('.')))>tuple(map(int,sys.argv[2].split('.'))):
 raise SystemExit('Use full Xcode 26.6 / macOS 26.5 SDK to preserve macOS 11 support.')
PY
ARGS=(--build-system native --package-path "$ROOT" --scratch-path "$BUILD_DIR" -c release --jobs 2 --product ShowMacStore --sdk "$SDK" --triple "$ARCH-apple-macosx$MINIMUM" -Xlinker -rpath -Xlinker '@executable_path/../Frameworks')
xcrun swift build "${ARGS[@]}"
BIN="$(xcrun swift build "${ARGS[@]}" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ShowMacStore" "$APP/Contents/MacOS/ShowMacStore"
cp "$ROOT/StoreResources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/StoreResources/PrivacyInfo.xcprivacy" "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
python3 "$ROOT/scripts/bundle-swift-runtime.py" "$APP/Contents/Frameworks" --arch "$ARCH" --identity "$IDENTITY" "$APP/Contents/MacOS/ShowMacStore"
python3 - "$ROOT" "$APP/Contents/MacOS/ShowMacStore" <<'PYCODE'
import subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1])/'scripts'))
from macos_compatibility import macho_metadata
exe=Path(sys.argv[2])
for path in macho_metadata(exe.read_bytes())['rpaths']:
 if '/Toolchains/' in path:subprocess.run(['install_name_tool','-delete_rpath',path,str(exe)],check=True)
PYCODE
if [[ "$IDENTITY" != - ]]; then
    test -f "${SHOWMAC_PROFILE:?Set SHOWMAC_PROFILE to an App Store distribution provisioning profile}"
    cp "$SHOWMAC_PROFILE" "$APP/Contents/embedded.provisionprofile"
    # Add the profile's application identity, without temporary exceptions.
    security cms -D -i "$SHOWMAC_PROFILE" > "$BIN/StoreProfile.plist"
    python3 - "$ROOT/StoreResources/ShowMac.entitlements" "$BIN/StoreProfile.plist" "$BIN/Store.entitlements" <<'PY'
import plistlib,sys
from pathlib import Path
ent=plistlib.loads(Path(sys.argv[1]).read_bytes());profile=plistlib.loads(Path(sys.argv[2]).read_bytes())
p=profile['Entitlements'];identifier='35PQA6NV57.com.jackjohn.showmac'
assert profile['TeamIdentifier']==['35PQA6NV57'] and p.get('com.apple.application-identifier')==identifier
assert not p.get('get-task-allow',False)
ent.update({'com.apple.application-identifier':identifier,'com.apple.developer.team-identifier':'35PQA6NV57'})
Path(sys.argv[3]).write_bytes(plistlib.dumps(ent))
PY
    ENTITLEMENTS="$BIN/Store.entitlements"
else ENTITLEMENTS="$ROOT/StoreResources/ShowMac.entitlements"; fi
codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
python3 "$ROOT/scripts/verify-store.py" "$APP" --arch "$ARCH"
echo "Built sandboxed Store edition: $APP"
