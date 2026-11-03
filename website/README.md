# showmac website

A static product site in the full desktop app’s purple/gray palette. The menu bar and its live card panel lead the page; the dashboard, sensors and fan curves follow. App screenshots are actual captures, separately photographed in Chinese and English.

Public site: <https://show-mac.cc/> · [English](https://show-mac.cc/en/) · [中文](https://show-mac.cc/zh/)

## Build and preview

```sh
python3 website/scripts/build.py --releases build/releases/v1.18.1-published
python3 -m http.server 8714 --bind 127.0.0.1 --directory website/dist
```

The build verifies the original architecture pair, source commit, bundle versions, binary deployment targets and checksums. Downloads are copied unchanged. `release.json` records the app source commit and website source commit separately. `website/dist/` is ignored by Git. The build renders localized HTML, canonical/hreflang links and a sitemap. Every language uses its own screenshot directory; dashboard/popover appearance switches with the site theme. The small menu bar strip is explicitly labeled an illustrative layout; panel and full-app images are unmodified captures.

There are no external fonts, analytics, account system, payment flow or server-side support form. The interactive fan curve uses example data and never controls hardware. Language/appearance preferences are stored locally; the manual language selection also sets a first-party cookie for root redirects.

## Location and language

The domain’s root redirects to `/zh/` for CN/HK/MO/TW, `/en/` for other known countries, and the first browser language for unknown IPs. A valid `showmac_language` cookie overrides automatic selection. Explicit `/en/` and `/zh/` URLs always work regardless of location or saved preference. Manual switching preserves the current page, query and anchor.

`deploy/nginx-showmac-locale.conf` uses the already installed GeoIP2 module and a local DB-IP Country Lite MMDB at `/srv/showmac/geoip/country.mmdb`. It uses the actual TCP peer; untrusted public headers cannot spoof the region. Visitor IPs are not sent to a third-party lookup API. DB-IP Lite is approximate, monthly data, licensed CC BY 4.0; every localized page includes the required [DB-IP attribution](https://db-ip.com). Refresh with the current monthly Country Lite download from <https://db-ip.com/db/download/ip-to-country-lite>, verify its published hash, decompress to a temporary file, then atomically replace `country.mmdb`. Nginx checks for changes hourly. The installed initial database is November 2026.

## Hosting and deployment

Nginx serves `/srv/showmac/current`, an atomic symlink to an immutable release under `/srv/showmac/releases/`. The dedicated `show-mac.cc` virtual host is defined by `deploy/nginx-showmac-domain.conf`; HTTP and `www` redirect to the canonical HTTPS domain. The existing IP `/showmac/` endpoint and unrelated root/API/proxy routes remain available.

Build from committed source, transfer the static output, verify both ZIP hashes and local links, then switch `current`. Check both languages, support/privacy, location response, HTTPS, `www` redirect and both public downloads. Keep the prior target for rollback. `deploy/logrotate-showmac` keeps the current log and 13 daily rotations with a 14-day maximum age.

Trusted Let’s Encrypt certificates for the domain and the legacy IP are isolated under `/srv/showmac/acme-config`; the existing account is reused. A dedicated systemd timer checks both certificates twice daily and reloads Nginx on renewal. The other system Certbot installation and existing named-host certificates are untouched. Deploy configs do not contain keys or account credentials.

Downloads remain the complete ad-hoc signed developer preview, without notarization. App Store submission is deferred at the user’s request; no reduced edition is distributed.
