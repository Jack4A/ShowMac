#!/usr/bin/env python3
"""Build the static site and copy only verified app release downloads."""
import argparse,hashlib,json,plistlib,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SITE=ROOT/'website'
p=argparse.ArgumentParser();p.add_argument('--releases',type=Path,required=True);args=p.parse_args()
release=args.releases.resolve()
arm=json.loads((release/'release-manifest-arm64.json').read_text())
intel=json.loads((release/'release-manifest.json').read_text())
assert arm['source_commit']==intel['source_commit']
assert arm['version']==intel['version']
subprocess.run(['python3',str(ROOT/'scripts/verify-release-assets.py'),str(release),'--version',arm['version'],'--commit',arm['source_commit']],check=True)
dist=SITE/'dist'
if dist.exists():shutil.rmtree(dist)
dist.mkdir()
for file in ['index.html','style.css','app.js']:
 if file=="index.html":
  text=(SITE/file).read_text()
  for manifest in [arm,intel]:
   text=text.replace(f"ShowMac-1.18.0-macOS-{manifest['architecture']}.zip",manifest['archive'])
  text=text.replace("1.18.0",arm['version']).replace("Build 266","Build "+arm['build']).replace("build 266","build "+arm['build'])
  (dist/file).write_text(text)
 else:shutil.copy2(SITE/file,dist/file)
for directory in ['support','privacy']:
 shutil.copytree(SITE/directory,dist/directory)
assets=dist/'assets';assets.mkdir()
shutil.copy2(ROOT/'Resources/AppIcon.png',assets/'app-icon.png')
for name in ['overview-dark','overview-light','thermal-control','sensors','status-panel']:
 shutil.copy2(ROOT/f'docs/screenshots/v1.18.0/en/{name}.png',assets/f'{name}.png')
downloads=dist/'downloads';downloads.mkdir()
for file in release.iterdir():
 if file.is_file():shutil.copy2(file,downloads/file.name)
(downloads/'SHA256SUMS-all.txt').write_text((release/'SHA256SUMS.txt').read_text().rstrip()+'\n'+(release/'SHA256SUMS-arm64.txt').read_text())
builds={}
for manifest in [arm,intel]:
 archive=downloads/manifest['archive']
 builds[manifest['architecture']]={'file':archive.name,'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
metadata={'version':arm['version'],'build':arm['build'],'minimumMacOS':arm['minimum_macos'],'sourceCommit':arm['source_commit'],'siteCommit':subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip(),'signing':arm['signing'],'notarized':arm['notarized'],'builds':builds}
(dist/'release.json').write_text(json.dumps(metadata,indent=2)+'\n')
(dist/'robots.txt').write_text('User-agent: *\nAllow: /showmac/\n')
print('Built static site:',dist)
