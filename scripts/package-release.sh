#!/bin/bash
# Build a fresh Intel macOS app, verify the ZIP round trip, and emit release assets.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
OUT="${1:-$ROOT/build/releases/v$VERSION}"
if [[ "$(uname -m)" != "x86_64" ]]; then
    echo 'This release pipeline currently requires an Intel x86_64 Mac.' >&2
    exit 1
fi
if [[ -e "$OUT" ]]; then
    echo "Refusing to overwrite release evidence: $OUT" >&2
    exit 1
fi
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo 'Commit source changes before packaging a release.' >&2
    exit 1
fi
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
mkdir -p "$(dirname "$OUT")"
mkdir "$OUT"
OUT="$(cd "$OUT" && pwd)"
APP="$OUT/staging/ThermalScope.app"
THERMALSCOPE_SIGN_IDENTITY=- THERMALSCOPE_APP_GROUP= bash "$ROOT/scripts/build.sh" "$APP"
codesign --verify --deep --strict "$APP"
for executable in "$APP/Contents/MacOS/ThermalScope" "$APP/Contents/Helpers/ThermalScopeHelper" "$APP/Contents/PlugIns/ThermalScopeWidget.appex/Contents/MacOS/ThermalScopeWidget"; do
    test -x "$executable"
    lipo "$executable" -verify_arch x86_64
done
"$APP/Contents/MacOS/ThermalScope" --hidden-view-update-check > "$OUT/hidden-view-check.log"
"$APP/Contents/MacOS/ThermalScope" --localization-check > "$OUT/localization-check.log"
ARCHIVE="$OUT/ThermalScope-$VERSION-macOS-x86_64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
cp "$ROOT/docs/INSTALL.txt" "$OUT/INSTALL.txt"
python3 - "$ROOT" "$OUT" "$ARCHIVE" "$COMMIT" <<'PY'
import hashlib,json,os,plistlib,subprocess,sys,tempfile
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
root,out,archive,commit=Path(sys.argv[1]),Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4]
source=plistlib.loads((root/'Resources/Info.plist').read_bytes())
with tempfile.TemporaryDirectory(prefix='thermalscope-release-verify-') as temporary:
    restored=Path(temporary)/'ThermalScope.app'
    subprocess.run(['ditto','-x','-k',str(archive),temporary],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(restored)],check=True)
    installed=plistlib.loads((restored/'Contents/Info.plist').read_bytes())
    assert installed['CFBundleShortVersionString']==source['CFBundleShortVersionString']
    assert installed['CFBundleVersion']==source['CFBundleVersion']
    for path in ['Contents/MacOS/ThermalScope','Contents/Helpers/ThermalScopeHelper','Contents/PlugIns/ThermalScopeWidget.appex/Contents/MacOS/ThermalScopeWidget']:
        assert os.access(restored/path,os.X_OK),path
    subprocess.run([str(restored/'Contents/MacOS/ThermalScope'),'--hidden-view-update-check'],check=True)
    subprocess.run([str(restored/'Contents/MacOS/ThermalScope'),'--localization-check'],check=True)
manifest={'schema':1,'product':'ThermalScope','version':source['CFBundleShortVersionString'],
          'build':source['CFBundleVersion'],'source_commit':commit,'architecture':'x86_64',
          'minimum_macos':source['LSMinimumSystemVersion'],'signing':'ad-hoc','notarized':False,
          'built_local':datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),
          'archive':archive.name,'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
          'bundled_components':['ThermalScope.app','ThermalScopeHelper','ThermalScopeWidget.appex'],
          'checks':['deep_strict_signature','intel_architecture_all_executables','executable_permissions',
                    'zip_extract_signature','hidden_view_update','localization']}
(out/'release-manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
files=[archive,out/'INSTALL.txt',out/'release-manifest.json']
(out/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in files))
assert subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()==commit
assert not subprocess.check_output(['git','-C',str(root),'status','--porcelain'],text=True).strip()
print('Release assets verified: '+str(out))
PY
