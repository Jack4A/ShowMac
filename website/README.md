# showmac website

A static product site in the full desktop app’s purple/gray palette. The menu bar and its live card panel lead the page; the dashboard, sensors and fan curves follow. App screenshots are actual captures, separately photographed in Chinese and English.

Public site: <https://show-mac.cc/> · [English](https://show-mac.cc/en/) · [中文](https://show-mac.cc/zh/)

## Build and preview

```sh
python3 website/scripts/build.py --releases build/releases/v1.18.1-published
python3 -m http.server 8714 --bind 127.0.0.1 --directory website/dist
```

The build verifies the original architecture pair, source commit, bundle versions, binary deployment targets and checksums. Downloads are copied unchanged. `release.json` records the app source commit and website source commit separately. `website/dist/` is ignored by Git. The build renders localized HTML, canonical/hreflang links and a sitemap. Every language uses its own screenshot directory; dashboard/popover appearance switches with the site theme. The small menu bar strip is explicitly labeled an illustrative layout; panel and full-app images are unmodified captures.

There are no external fonts, analytics, account system or server-side support form. The bilingual purchase page shows the requested one-time price (CNY 5.90 / USD 1.00), but checkout is explicitly closed: no payment provider, order processing or license delivery is connected yet. The current developer preview remains downloadable without payment. The interactive fan curve uses example data and never controls hardware. Language/appearance preferences are stored locally; the manual language selection also sets a first-party cookie for root redirects.

## Location and language

The domain’s root redirects to `/zh/` for CN/HK/MO/TW, `/en/` for other known countries, and the first browser language for unknown IPs. A valid `showmac_language` cookie overrides automatic selection. Explicit `/en/` and `/zh/` URLs always work regardless of location or saved preference. Manual switching preserves the current page, query and anchor.

`deploy/nginx-showmac-locale.conf` uses the already installed GeoIP2 module and a local DB-IP Country Lite MMDB at `/srv/showmac/geoip/country.mmdb`. It uses the actual TCP peer; untrusted public headers cannot spoof the region. Visitor IPs are not sent to a third-party lookup API. DB-IP Lite is approximate, monthly data, licensed CC BY 4.0; every localized page includes the required [DB-IP attribution](https://db-ip.com). Refresh with the current monthly Country Lite download from <https://db-ip.com/db/download/ip-to-country-lite>, verify its published hash, decompress to a temporary file, then atomically replace `country.mmdb`. Nginx checks for changes hourly. The installed initial database is November 2026.

## Hosting and deployment

Nginx serves `/srv/showmac/current`, an atomic symlink to an immutable release under `/srv/showmac/releases/`. The dedicated `show-mac.cc` virtual host is defined by `deploy/nginx-showmac-domain.conf`; HTTP and `www` redirect to the canonical HTTPS domain. The existing IP `/showmac/` endpoint and unrelated root/API/proxy routes remain available.

Build from committed source, transfer the static output, verify both ZIP hashes and local links, then switch `current`. Check both languages, support/privacy, location response, HTTPS, `www` redirect and both public downloads. Keep the prior target for rollback. `deploy/logrotate-showmac` keeps the current log and 13 daily rotations with a 14-day maximum age.

Trusted Let’s Encrypt certificates for the domain and the legacy IP are isolated under `/srv/showmac/acme-config`; the existing account is reused. A dedicated systemd timer checks both certificates twice daily and reloads Nginx on renewal. The other system Certbot installation and existing named-host certificates are untouched. Deploy configs do not contain keys or account credentials.

Downloads remain the complete ad-hoc signed developer preview, without notarization. App Store submission is deferred at the user’s request; no reduced edition is distributed.

## Cloudflare migration — November 4, 2026

The user selected Cloudflare after mainland-origin domain access was blocked pending filing. The Pages project is `showmac`, with the verified live fallback <https://showmac.pages.dev/>. Website assets, localized screenshots and both original ZIPs are uploaded to Pages; they do not proxy or fetch the former mainland origin.

The build now defaults to `--hosting cloudflare`, copying `cloudflare/worker.mjs` as `_worker.js`, plus security headers and routing metadata. The edge Worker selects the initial language from Cloudflare's country metadata, with a first-party manual cookie override and browser-language fallback. Explicit language URLs stay explicit. CDN caching is disabled on user-specific redirects. Cloudflare privacy wording replaces the former origin's log-retention/DB-IP statements. Use `--hosting nginx` only for the retained legacy server deployment.

For a dashboard upload, ZIP the contents of `dist/` (without a parent folder), then create a production deployment of the existing Pages project. `_worker.js` is supported by dashboard uploads. Check `/locale.json`, a manual language override, both localized pages, and the public download hashes. Do not upload source credentials, provisioning profiles, server logs or private build folders.

The custom root and `www` records target `showmac.pages.dev`. The user approved moving authoritative DNS to `chance.ns.cloudflare.com` and `nia.ns.cloudflare.com` on November 4. Both hostnames are now attached to the Pages project: the root serves HTTPS successfully, and `www` redirects to the same path at the root. The dashboard confirms the root is active with SSL enabled; public HTTPS checks verify both hostnames. Existing resolver caches may retain old nameserver answers until their TTL expires. The custom domain remains `show-mac.cc`; the human-facing logo wordmark is `ShowMac` and has been deployed.

## Direct sales — current preparation

App Store work is paused and its archive workflow is manual-only. Direct sales must retain the full desktop app. The owner confirmed the CNY 5.90 / USD 1.00 one-time price, then clarified that they have only personal Alipay/WeChat accounts and payment QR codes, not approved merchant payment products. No merchant API credentials are available. The owner has selected Paddle, starting with sandbox checkout; a connected test account and approved live seller account are still pending. See [the competitor research](../docs/direct-sales-research.md) for the choice and licensing caveats.

The purchase page is a truthful public preparation page, not a completed live checkout integration. It must stay disabled until the payment account is approved, license scope and refund terms are agreed, server-side payment verification and delivery are implemented, and a complete test purchase/refund has passed. Do not add private payment keys to HTML, JavaScript, app bundles, Git or logs; do not issue licenses based on a browser redirect or an uploaded payment screenshot. Signed provider callbacks and/or authenticated server-side order queries must verify the merchant, product, amount, currency and final order status. Retried callbacks must not issue duplicate licenses. USD checkout needs a provider that actually supports that currency; do not silently charge CNY while labeling it USD.

### Paddle sandbox

The owner selected Paddle for test payments. `/en/checkout/` and `/zh/checkout/` are separate, unindexed test pages; they never enable live checkout or issue licenses. The ordinary purchase page stays closed. Create one sandbox product with two **one-time, non-recurring** prices (USD 1.00 and CNY 5.90), and confirm them in the sandbox catalog. The account creation/password/terms step is currently handed to the owner at <https://sandbox-login.paddle.com/>.

In the existing Pages project's **production variables** (the checkout itself always uses the Paddle sandbox), configure only these public client parameters:

- `PADDLE_SANDBOX_CLIENT_TOKEN`: a `test_` client-side token, never a private API key or `live_` token.
- `PADDLE_SANDBOX_PRICE_USD`: the USD 1.00 one-time `pri_` ID.
- `PADDLE_SANDBOX_PRICE_CNY`: the CNY 5.90 one-time `pri_` ID.

Missing or invalid configuration keeps checkout disabled. `/api/billing/sandbox-config` is GET-only and no-store. Only the test checkout page permits Paddle frames; other pages retain their original CSP. The build emits a single `_worker.js`, so direct dashboard uploads do not depend on bundling imported modules. `node --test website/tests/billing.test.mjs` checks the sandbox boundary and routing. Test checkout completion is explicitly unverified UI feedback: confirm the transaction in Paddle's sandbox dashboard. Server-side order verification, license issuance, email delivery, refunds and app activation remain required before real sales.
