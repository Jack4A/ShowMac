# ShowMac website

Free, MIT-licensed native Mac monitoring, with a menu bar first product page. The website provides the full desktop download and invites visitors to [Star or contribute on GitHub](https://github.com/Jackkakaya/ThermalScope). No payment, license activation, external fonts or analytics scripts are used.

Production: https://show-mac.cc/ · English `/en/` · Chinese `/zh/`.

## Build and preview

```sh
python3 website/scripts/build.py --releases build/releases/v1.18.2-published
python3 -m http.server 8714 --bind 127.0.0.1 --directory website/dist
```

The build verifies paired release archives, source commit, minimum macOS versions and checksums before copying downloads unchanged. `release.json` records app and site revisions separately. Screenshots use actual app captures in each language. Version-specific captures override the documented 1.18.1 baseline when available; 1.18.2 refreshes the menu bar panel in both themes. The curve demonstration is labeled example data and does not control hardware.

## Cloudflare Pages

The tested command-line deployment uses Cloudflare's official Wrangler (Node.js 22):

```sh
npm exec --yes --package=wrangler@4.157.0 -- wrangler login --scopes account:read pages:write
CLOUDFLARE_ACCOUNT_ID=9f875f08a4d5c8cf10a7b4da593e7710 npm exec --yes --package=wrangler@4.157.0 -- wrangler pages deploy website/dist --project-name showmac --branch main --no-bundle
npm exec --yes --package=wrangler@4.157.0 -- wrangler logout
```

The production branch is `main`. OAuth requires account consent and includes background access; use only the account and Pages permissions above. Keep credentials outside Git. Wrangler's local `.wrangler/` cache and the generated site are ignored. Verify the custom domain's `release.json`, both download checksums, language selection and legacy purchase redirects after deployment. The command-line flow is an alternative when the dashboard's asset uploader returns 403.

Upload a ZIP containing the contents of `website/dist/` to the existing `showmac` Pages project's production deployment. Root and www are bound to show-mac.cc; www redirects to the root. The worker uses Cloudflare location (CN/HK/MO/TW → Chinese, other known locations → English), with browser language fallback. An explicit language URL or manual language cookie takes priority. Preferences are stored locally.

Old purchase/checkout URLs redirect to the open-source section, and the former billing API returns 410. No payment configuration is required. Run `node --test website/tests/routing.test.mjs` before deploying.

Legacy Nginx configurations remain under `website/deploy/` for the previous hosting setup. Production uses Cloudflare and does not fetch the former origin.
