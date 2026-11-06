#!/usr/bin/env python3
"""Bundle upstream and registry license texts alongside the native statistics engine."""
from pathlib import Path
import json,subprocess,sys
root=Path(__file__).resolve().parents[1]
metadata=json.loads(subprocess.check_output(['cargo','metadata','--manifest-path',str(root/'UsageEngine/Cargo.toml'),'--locked','--format-version=1'],text=True))
parts=['ShowMac Agent Usage Engine\nTokscale upstream commit: 82613d2f5e96654ce3729892afbb0025979f1c75\nSource: https://github.com/junhoyeo/tokscale\n\n'+(root/'Vendor/tokscale/LICENSE').read_text()]
for package in sorted(metadata['packages'],key=lambda p:(p['name'],p['version'])):
 if not package.get('source',''):continue
 folder=Path(package['manifest_path']).parent
 texts=[]
 for pattern in ['LICENSE*','LICENCE*','COPYING*','NOTICE*']:
  for file in sorted(folder.glob(pattern)):
   if file.is_file():texts.append(file.name+'\n'+file.read_text(errors='replace'))
 parts.append('\n\n'+'='*60+'\n'+package['name']+' '+package['version']+'\nLicense: '+str(package.get('license') or 'See package source')+'\n'+str(package.get('repository') or package.get('homepage') or '')+'\n\n'+'\n\n'.join(texts))
Path(sys.argv[1]).write_text('\n'.join(parts))
