# ShowMac website

A dependency-free static product website matching the full desktop app’s purple/gray palette. English is the default; visitors can switch to Chinese and choose light/dark appearance. The app screenshots are real, captured from the installed full desktop release.

Public site: <https://101.37.211.18/showmac/>

## Build

Download the eight release assets for both architectures into a local directory, then run:

```sh
python3 website/scripts/build.py --releases build/releases/v1.18.0-published
python3 -m http.server 8714 --bind 127.0.0.1 --directory website/dist
```

The build first verifies the architecture pair, source commit, bundle versions, minimum OS and checksums. It copies the original ZIPs, installation notes and manifests without editing them; `SHA256SUMS-all.txt` combines the two original checksum lists. `release.json` records the app source commit and website source commit separately. Output in `website/dist/` is ignored by Git.

The site has no external fonts, analytics, account system, server-side form or payment flow. Support is a mail link. Local browser storage holds appearance/language only. The interactive fan curve is clearly an example and never connects to hardware.

## Hosting

The current server already hosts other apps. ShowMac occupies `/showmac/` on the IP address; its HTTP location redirects to HTTPS. Its original root and API routes remain in place. Nginx serves `/srv/showmac/current/`, a symlink to an immutable directory in `/srv/showmac/releases/`.

For updates, build from committed source, transfer a tar archive of `dist/`, extract it into a new release directory, verify the ZIP hashes against `release.json`, then atomically switch `current`. Check the homepage, support, privacy and both public ZIP hashes. Keep the previous target for rollback. No reload is needed for a content-only symlink update.

`deploy/nginx-showmac.conf` is the scoped HTTPS static-site location; `nginx-showmac-http.conf` handles the HTTP redirect and ACME challenge. `nginx-showmac-https.conf` preserves the pre-existing default proxy fallback. `deploy/logrotate-showmac` keeps current logs plus 13 daily rotations (maxage 14), separate from other applications’ logs. The live Nginx config was backed up before the include was added. A pre-existing duplicate headscale server-name warning was left unchanged.

The user requested an IP address without a domain. HTTPS uses a publicly trusted Let’s Encrypt IP certificate. No domain was added. The certificate, account symlink, work directory and renewal logs are isolated under `/srv/showmac/`; Certbot 5.9.0 is installed in an isolated module directory without changing the existing Certbot installation. A dedicated systemd timer checks this certificate twice a day and reloads Nginx after renewal. A staging renewal simulation succeeded. The HTTPS virtual host preserves the previous default proxy route for all other paths; existing named-host TLS sites keep their own certificates. The downloadable full app is the existing ad-hoc-signed developer preview, not a notarized Developer ID release. The site states this explicitly. App Store submission has been deferred at the user’s request so all existing functionality remains available through the website. No reduced Store build is distributed.
