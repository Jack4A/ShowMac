# ShowMac website

Free, MIT-licensed native Mac monitoring, with a menu bar first product page. The website provides the full desktop download and invites visitors to [Star or contribute on GitHub](https://github.com/Jack4A/ShowMac). No payment, license activation, external fonts or third-party analytics scripts are used. A small first-party counter displays cumulative website page views and download starts.

Production: https://show-mac.cc/ · English `/en/` · Chinese `/zh/`.

## Build and preview

```sh
python3 website/scripts/build.py --releases build/releases/v1.18.3-published
python3 -m http.server 8714 --bind 127.0.0.1 --directory website/dist
```

The static preview cannot write statistics. To test the actual Pages worker and a local D1 database, run `wrangler d1 execute STATS_DB --local --file cloudflare/migrations/0001_statistics.sql` and `wrangler pages dev --port 8723 --binding STATS_ENV=local` from `website/`. Localhost uses isolated local storage; only the explicit local flag enables recording. Preview deployment hostnames never write production counters.

The build verifies paired release archives, source commit, minimum macOS versions and checksums before copying downloads unchanged. `release.json` records app and site revisions separately. Screenshots use actual app captures in each language. The builder uses the newest documented capture no later than the downloaded app version, falling back to the 1.18.1 baseline. The 1.18.2 panel captures remain in use until a later capture replaces them. The curve demonstration is labeled example data and does not control hardware.

The landing page and support guide explicitly label the 1.18.4 changes as a developer preview while public downloads remain 1.18.3. Its single-curve demonstration supports CPU/GPU MAX selection, fractional temperature edits and a draggable speed ceiling; all temperatures and fan ranges in the demonstration are illustrative. A site-only deployment must not advertise an unpublished app version in `release.json` or replace the verified release archives with local builds.

## Cloudflare Pages

The tested command-line deployment uses Cloudflare's official Wrangler (Node.js 22):

```sh
npm exec --yes --package=wrangler@4.157.0 -- wrangler login --device --browser=false --scopes account:read pages:write d1:write
CLOUDFLARE_ACCOUNT_ID=9f875f08a4d5c8cf10a7b4da593e7710 npm exec --yes --package=wrangler@4.157.0 -- wrangler d1 execute STATS_DB --remote --file website/cloudflare/migrations/0001_statistics.sql --config website/wrangler.toml
CLOUDFLARE_ACCOUNT_ID=9f875f08a4d5c8cf10a7b4da593e7710 npm exec --yes --package=wrangler@4.157.0 -- wrangler pages deploy --cwd website --project-name showmac --branch main --no-bundle
npm exec --yes --package=wrangler@4.157.0 -- wrangler logout
```

The production branch is `main`. OAuth requires account consent and includes background access; use only the account, Pages and D1 permissions above, then log out. Keep credentials outside Git. Wrangler's local `.wrangler/` cache and the generated site are ignored. The checked-in Wrangler configuration preserves the existing Pages project settings and binds its dedicated statistics database. The schema is idempotent: reapplying it and redeploying never reset counts or their start date. Do not recreate the production database for a normal deployment. Verify the custom domain's statistics API, `release.json`, both download checksums, language selection and legacy purchase redirects after deployment.

Deploy the contents of `website/dist/` with the Wrangler configuration and its D1 binding to the existing `showmac` Pages project. Root and www are bound to show-mac.cc; www redirects to the root. The worker uses Cloudflare location (CN/HK/MO/TW → Chinese, other known locations → English), with browser language fallback. An explicit language URL or manual language cookie takes priority. Preferences are stored locally.

Old purchase/checkout URLs redirect to the open-source section, and the former billing API returns 410. No payment configuration is required. Before deploying, run:

```sh
node --check website/stats.js
node --test website/tests/*.test.mjs
python3 -m unittest discover -s website/tests -p '*_test.py'
```

## Statistics

`GET /api/stats` returns public totals, the counter's `startedAt` date, page counts for each of the six English/Chinese home/support/privacy pages, and downloads by `arm64` / `x86_64`. Refreshes count as new page views; a back-forward cache restoration also counts. Root language redirects, static assets and hash changes do not count. There is no historical backfill or unique-visitor metric.

`stats.js` posts one random event ID and an allowlisted path to `POST /api/stats/pageview` when a localized page becomes visible. `GET /download/arm64` and `/download/x86_64` record a download start and immediately redirect to the existing verified ZIP. Links retain the release filename. HEAD requests, direct `/downloads/` archive links and GitHub downloads do not increment this counter. Statistics failures never block a download.

Known bots, prefetches, DNT and Global Privacy Control are excluded. Counters are anonymous aggregates: no IP, user agent, referrer, query string, visitor identifier or app sensor data is stored in D1. Random per-event IDs are kept for seven days to deduplicate retries, then cleared on later inserts; totals remain. A SQLite trigger increments totals atomically only for new IDs. The API is intended for approximate public usage counts, not billing or fraud-resistant auditing. If D1 is unavailable, the website shows unavailable statistics rather than fabricated zeroes. See the localized privacy policy for provider delivery/security metadata.

Legacy Nginx configurations remain under `website/deploy/` for the previous hosting setup. Production uses Cloudflare and does not fetch the former origin.
