#!/bin/bash
# Build a fresh macOS app, verify archive contents, and record native vs cross validation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ARCH="${THERMALSCOPE_ARCH:-$(uname -m)}"
case "$ARCH" in x86_64|arm64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
SUFFIX=""
if [[ "$ARCH" == "arm64" ]]; then SUFFIX="-arm64"; fi
OUT="${1:-$ROOT/build/releases/v$VERSION-$ARCH}"
if [[ -e "$OUT" ]]; then echo "Refusing to overwrite release evidence: $OUT" >&2; exit 1; fi
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then echo 'Commit source changes before packaging a release.' >&2; exit 1; fi
COMMIT="$(git -C "$ROOT" rev-parse HEAD)"
mkdir -p "$(dirname "$OUT")"
mkdir "$OUT"
OUT="$(cd "$OUT" && pwd)"
APP="$OUT/staging/ThermalScope.app"
THERMALSCOPE_ARCH="$ARCH" THERMALSCOPE_SIGN_IDENTITY=- THERMALSCOPE_APP_GROUP= bash "$ROOT/scripts/build.sh" "$APP"
codesign --verify --deep --strict "$APP"
for executable in "$APP/Contents/MacOS/ThermalScope" "$APP/Contents/Helpers/ThermalScopeHelper" "$APP/Contents/PlugIns/ThermalScopeWidget.appex/Contents/MacOS/ThermalScopeWidget"; do
    test -x "$executable"
    lipo "$executable" -verify_arch "$ARCH"
done
ARCHIVE="$OUT/ThermalScope-$VERSION-macOS-$ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
cp "$ROOT/docs/INSTALL$SUFFIX.txt" "$OUT/INSTALL$SUFFIX.txt"
python3 - "$ROOT" "$OUT" "$ARCHIVE" "$COMMIT" "$ARCH" "$SUFFIX" <<'PY'
import hashlib,json,os,platform,plistlib,subprocess,sys,tempfile
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo
root,out,archive,commit,arch,suffix=Path(sys.argv[1]),Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4],sys.argv[5],sys.argv[6]
source=plistlib.loads((root/'Resources/Info.plist').read_bytes())
native=platform.machine()==arch
checks=['deep_strict_signature','target_architecture_all_executables','executable_permissions','zip_extract_signature','static_english_localization','system_only_dynamic_dependencies']
with tempfile.TemporaryDirectory(prefix='thermalscope-release-verify-') as temporary:
    restored=Path(temporary)/'ThermalScope.app'
    subprocess.run(['ditto','-x','-k',str(archive),temporary],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(restored)],check=True)
    installed=plistlib.loads((restored/'Contents/Info.plist').read_bytes())
    assert installed['CFBundleShortVersionString']==source['CFBundleShortVersionString']
    assert installed['CFBundleVersion']==source['CFBundleVersion']
    for path in ['Contents/MacOS/ThermalScope','Contents/Helpers/ThermalScopeHelper','Contents/PlugIns/ThermalScopeWidget.appex/Contents/MacOS/ThermalScopeWidget']:
        executable=restored/path
        assert os.access(executable,os.X_OK),path
        assert subprocess.check_output(['lipo',str(executable),'-archs'],text=True).strip()==arch,path
        for line in subprocess.check_output(['otool','-L',str(executable)],text=True).splitlines()[1:]:
            library=line.strip().split(' (')[0]
            assert library.startswith(('/System/Library/','/usr/lib/','@rpath/libswift')),library
    table=json.loads((restored/'Contents/Resources/Localization.json').read_text())
    assert table and all(key and row.get('en') for key,row in table.items())
    if native:
        for flag,name in [('--hidden-view-update-check','hidden-view-check.log'),('--localization-check','localization-check.log')]:
            result=subprocess.run([str(restored/'Contents/MacOS/ThermalScope'),flag],check=True,capture_output=True,text=True)
            (out/name).write_text(result.stdout+result.stderr)
        checks+=['hidden_view_update','localization_runtime']
manifest={'schema':2,'product':'ThermalScope','version':source['CFBundleShortVersionString'],
          'build':source['CFBundleVersion'],'source_commit':commit,'architecture':arch,
          'minimum_macos':source['LSMinimumSystemVersion'],'signing':'ad-hoc','notarized':False,
          'built_local':datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),'build_host_architecture':platform.machine(),
          'runtime_validation':'fixture_checks_only' if native else 'not_run_cross_compiled',
          'apple_silicon_hardware_validation':False,'hardware_control_available':True,'fan_control_requires_capability_probe':True,'turbo_control_available':arch=='x86_64','power_control_available':arch=='x86_64',
          'experimental':arch=='arm64',
          'archive':archive.name,'archive_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
          'bundled_components':['ThermalScope.app','ThermalScopeHelper','ThermalScopeWidget.appex'],'checks':checks}
manifest_path=out/('release-manifest'+suffix+'.json')
manifest_path.write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
files=[archive,out/('INSTALL'+suffix+'.txt'),manifest_path]
(out/('SHA256SUMS'+suffix+'.txt')).write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in files))
assert subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip()==commit
assert not subprocess.check_output(['git','-C',str(root),'status','--porcelain'],text=True).strip()
print('Release assets verified: '+str(out))
print('Runtime validation: '+manifest['runtime_validation'])
PY
