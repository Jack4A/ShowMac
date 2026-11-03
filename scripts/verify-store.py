#!/usr/bin/env python3
"""Check the Store binary boundary, sandbox, privacy and macOS minimum."""
import argparse,plistlib,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from macos_compatibility import macho_metadata,version_tuple
p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('--arch',required=True);args=p.parse_args()
app=args.app
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier']=='com.jackjohn.showmac'
assert info['LSMinimumSystemVersion']=='11.0'
exe=app/'Contents/MacOS/ShowMacStore'
meta=macho_metadata(exe.read_bytes())
assert meta['minimum']==version_tuple('11.0'),meta
assert meta['cpu']=={'arm64':0x100000c,'x86_64':0x1000007}[args.arch],meta
for library,_ in meta['libraries']:
 assert library.startswith(('/System/Library/','/usr/lib/','@rpath/libswift')),library
assert all(path.startswith('@') or path.startswith(('/System/Library/','/usr/lib/')) for path in meta['rpaths']),meta['rpaths']
symbols=subprocess.check_output(['nm','-u',str(exe)],text=True)
for banned in ['AuthorizationExecuteWithPrivileges','IOServiceOpen','IOConnectCallStructMethod','proc_listallpids','SMC','CSMC','kmutil']:
 assert banned not in symbols,banned
assert not (app/'Contents/Helpers').exists()
assert not (app/'Contents/PlugIns').exists()
ent=plistlib.loads(subprocess.run(['codesign','-d','--entitlements',':-',str(app)],check=True,capture_output=True).stdout)
assert ent['com.apple.security.app-sandbox'] is True
allowed={'com.apple.security.app-sandbox','com.apple.security.files.user-selected.read-write','com.apple.application-identifier','com.apple.developer.team-identifier'}
assert set(ent)<=allowed,ent
privacy=plistlib.loads((app/'Contents/Resources/PrivacyInfo.xcprivacy').read_bytes())
assert not privacy['NSPrivacyTracking'] and privacy['NSPrivacyCollectedDataTypes']==[]
print('Verified independent Store binary, macOS 11 minimum, enforced sandbox entitlements and privacy manifest.')
