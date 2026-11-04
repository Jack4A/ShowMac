# ShowMac website

Free, MIT-licensed native Mac monitoring, with a menu bar first product page. The website provides the full desktop download and invites visitors to [Star or contribute on GitHub](https://github.com/Jackkakaya/ThermalScope). No payment, license activation, external fonts or analytics scripts are used.

Production: https://show-mac.cc/ · English `/en/` · Chinese `/zh/`.

## Build and preview

```sh
python3 website/scripts/build.py --releases build/releases/v1.18.2-published
python3 -m http.server 8714 --bind 127.0.0.1 --directory website/dist
```

The build verifies paired release archives, source commit, minimum macOS versions and checksums before copying downloads unchanged. `release.json` records app and site revisions separately. Screenshots use actual app captures in each language. The curve demonstration is labeled example data and does not control hardware.

## Cloudflare Pages

Upload a ZIP containing the contents of `website/dist/` to the existing `showmac` Pages project's production deployment. Root and www are bound to show-mac.cc; www redirects to the root. The worker uses Cloudflare location (CN/HK/MO/TW → Chinese, other known locations → English), with browser language fallback. An explicit language URL or manual language cookie takes priority. Preferences are stored locally.

Old purchase/checkout URLs redirect to the open-source section, and the former billing API returns 410. No payment configuration is required. Run `node --test website/tests/routing.test.mjs` before deploying.

Legacy Nginx configurations remain under `website/deploy/` for the previous hosting setup. Production uses Cloudflare and does not fetch the former origin.
