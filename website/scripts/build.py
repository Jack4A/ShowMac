#!/usr/bin/env python3
"""Build localized pages and copy only verified, paired desktop releases."""
import argparse,hashlib,html,json,re,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];SITE=ROOT/'website'
p=argparse.ArgumentParser();p.add_argument('--releases',type=Path,required=True);p.add_argument('--screenshots',type=Path,default=ROOT/'docs/screenshots/v1.18.1');args=p.parse_args()
release=args.releases.resolve()
arm=json.loads((release/'release-manifest-arm64.json').read_text());intel=json.loads((release/'release-manifest.json').read_text())
assert arm['source_commit']==intel['source_commit'] and arm['version']==intel['version']
subprocess.run(['python3',str(ROOT/'scripts/verify-release-assets.py'),str(release),'--version',arm['version'],'--commit',arm['source_commit']],check=True)
dist=SITE/'dist'
if dist.exists():shutil.rmtree(dist)
dist.mkdir()
for name in ['style.css','app.js']:shutil.copy2(SITE/name,dist/name)
credit='<p class="geo-credit"><a href="https://db-ip.com">IP Geolocation by DB-IP</a></p>'
translation=re.compile(r'<([a-z0-9]+)([^>]*\bdata-en="([^"]*)"[^>]*\bdata-zh="([^"]*)"[^>]*)>.*?</\1>',re.S)
for lang in ['en','zh']:
 for page in ['', 'support', 'privacy']:
  source=SITE/(page+'/index.html' if page else 'index.html');text=source.read_text()
  text=translation.sub(lambda m:'<'+m[1]+m[2]+'>'+html.unescape(m[3 if lang=='en' else 4])+'</'+m[1]+'>',text)
  text=text.replace('lang="en"',f'lang="{"zh-CN" if lang=="zh" else "en"}"',1)
  for manifest in [arm,intel]:text=text.replace(f"showmac-1.18.0-macOS-{manifest['architecture']}.zip",manifest['archive'])
  text=text.replace('1.18.0',arm['version']).replace('Build 266','Build '+arm['build']).replace('build 266','build '+arm['build'])
  # Resolve every local file from the localized page, including support/privacy.
  depth=2 if page else 1;prefix='../'*depth
  def url(m):
   attr,value=m[1],m[2]
   if value.startswith(('#','http:','https:','mailto:','data:')):return m[0]
   while value.startswith('../'):value=value[3:]
   if value.startswith('./'):value=value[2:]
   if value=='' or value.startswith('#'):value=f'{lang}/'+value
   elif value.startswith(('support/','privacy/')):value=f'{lang}/'+value
   return f'{attr}="{prefix}{value}"'
  text=re.sub(r'(href|src)="([^"]*)"',url,text)
  text=text.replace('assets/en/','assets/'+lang+'/')
  if lang=='zh':
   text=text.replace('Skip to content','跳至正文').replace('showmac — A clearer view of your Mac','showmac — 你的 Mac，就在状态栏').replace('Support — showmac','支持 — showmac').replace('Privacy policy — showmac','隐私政策 — showmac')
  canonical='https://show-mac.cc/'+lang+'/'+(page+'/' if page else '')
  seo=f'<link rel="canonical" href="{canonical}"><link rel="alternate" hreflang="en" href="https://show-mac.cc/en/{page+"/" if page else ""}"><link rel="alternate" hreflang="zh-CN" href="https://show-mac.cc/zh/{page+"/" if page else ""}">'
  text=text.replace('</head>',seo+'</head>').replace('</body>',credit+'</body>')
  target=dist/lang/page;target.mkdir(parents=True,exist_ok=True);(target/'index.html').write_text(text)
# Static previews have the same default-location mechanism as production, with browser language fallback.
(dist/'index.html').write_text('<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>showmac</title><script src="app.js" defer></script></head><body><p><a href="en/">English</a> · <a href="zh/">中文</a></p></body></html>')
for page in ['support','privacy']:
 target=dist/page;target.mkdir();(target/'index.html').write_text('<!doctype html><html lang="en"><head><meta charset="utf-8"><script src="../app.js" defer></script><title>showmac</title></head><body><a href="../en/'+page+'/">English</a> · <a href="../zh/'+page+'/">中文</a></body></html>')
assets=dist/'assets';assets.mkdir();shutil.copy2(ROOT/'Resources/AppIcon.png',assets/'app-icon.png')
for lang in ['en','zh']:
 target=assets/lang;target.mkdir()
 for name in ['overview-dark','overview-light','thermal-control','sensors','status-panel-dark','status-panel-light']:
  shutil.copy2(args.screenshots/lang/(name+'.png'),target/(name+'.png'))
downloads=dist/'downloads';downloads.mkdir()
for file in release.iterdir():
 if file.is_file():shutil.copy2(file,downloads/file.name)
(downloads/'SHA256SUMS-all.txt').write_text((release/'SHA256SUMS.txt').read_text().rstrip()+'\n'+(release/'SHA256SUMS-arm64.txt').read_text())
builds={}
for manifest in [arm,intel]:
 archive=downloads/manifest['archive'];builds[manifest['architecture']]={'file':archive.name,'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest()}
metadata={'version':arm['version'],'build':arm['build'],'minimumMacOS':arm['minimum_macos'],'sourceCommit':arm['source_commit'],'siteCommit':subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD'],text=True).strip(),'signing':arm['signing'],'notarized':arm['notarized'],'builds':builds}
(dist/'release.json').write_text(json.dumps(metadata,indent=2)+'\n')
(dist/'robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: https://show-mac.cc/sitemap.xml\n')
urls=[f'https://show-mac.cc/{lang}/{page}' for lang in ['en','zh'] for page in ['','support/','privacy/']]
(dist/'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'+''.join('<url><loc>'+u+'</loc></url>' for u in urls)+'</urlset>')
print('Built static site:',dist)
