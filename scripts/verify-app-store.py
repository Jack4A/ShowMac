#!/usr/bin/env python3
"""Verify the unsigned shared-source Store archive before any signing/upload."""
import argparse,plistlib,re,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('app',type=Path);args=p.parse_args();app=args.app
assert not (app/'Contents/Helpers').exists(),'Store bundle must not carry the privileged helper'
host=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert host['CFBundleIdentifier']=='com.jackjohn.showmac'
assert host['CFBundleDisplayName']=='showmac'
assert host['CFBundleShortVersionString']=='1.18.1' and host['CFBundleVersion']=='268'
assert host['LSMinimumSystemVersion']=='11.0'
components=[app,*app.glob('Contents/PlugIns/*.appex')];assert len(components)==2
for bundle in components:
 info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
 assert info['CFBundleShortVersionString']==host['CFBundleShortVersionString'] and info['CFBundleVersion']==host['CFBundleVersion']
 assert info['ThermalScopeAppGroup']=='group.com.jackjohn.showmac'
 executable=bundle/'Contents/MacOS'/info['CFBundleExecutable']
 archs=set(subprocess.check_output(['lipo','-archs',str(executable)],text=True).split());assert archs=={'arm64','x86_64'},archs
 load=subprocess.check_output(['xcrun','vtool','-show-build',str(executable)],text=True)
 assert re.findall(r'^\s*minos\s+(\S+)',load,re.M)==['11.0','11.0'],load
 symbols=subprocess.check_output(['nm','-u',str(executable)],text=True)
 assert 'AuthorizationExecuteWithPrivileges' not in symbols and 'AuthorizationCopyRights' not in symbols
 print('Verified',bundle.name,sorted(archs),'minimum macOS 11, no privilege APIs')
print('Store archive passed distribution checks; signing and App Review remain separate steps.')
