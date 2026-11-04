> Distribution decision (2026-11-04): ShowMac is now free and MIT licensed. App Store submission and paid distribution are canceled; the configurations below are retained as development reference only.

# App Store readiness

## Current decision — November 4, 2026

App Store submission is paused at the user's request. The priority is direct sales of the complete desktop app at <https://show-mac.cc/>. No Store upload or submission is planned. The Store archive workflow is now manual-only; its source and earlier verification are retained for possible future work.

The earlier Store scope retained the original UI, menu bar customization, readable sensors, recent history and dashboard, with privileged fan/turbo/system-power modifications disabled only in the Store channel. Website builds retain those controls. The previously rejected independent simplified frontend remains reverted.

`AppStore/project.yml` builds the original sources with the compile-time `APP_STORE` flag. It uses the separate registered bundle ID `com.jackjohn.showmac`, Team Jack John (`35PQA6NV57`), the shared group `group.com.jackjohn.showmac`, and `showmac-store` widget links. Desktop identity, controls and existing preferences remain unchanged. The Store bundle excludes the root helper; C-level fan writes and authorization launches are blocked, not hidden by a runtime/reviewer switch.

The App Store Connect record is [ID 6830209769](https://appstoreconnect.apple.com/apps/6830209769/distribution), SKU `showmac-macos`. The requested price is CNY 5.90 or USD 1.00; a supported price point and paid-app agreement status must be verified in the portal. Do not publish private review-contact phone details in source.

## Build and verification

Run `xcodegen generate --spec AppStore/project.yml --project AppStore`, then archive the `showmac` scheme with full Xcode 26.6. The `App Store Archive` workflow produces an unsigned universal archive for macOS 11+, checks both executable deployment targets and architectures, and rejects privileged authorization imports or a bundled helper. `Tests/AppStore/hardware-policy.c` verifies that fan writes and privileged session creation fail in the Store build.

Xcode 27 refuses macOS 11 targets. The local Xcode 27 preview is built for macOS 12 only for UI/sandbox checks and must not be used as the macOS 11 release archive. Distribution archives use the supported Xcode 26.6/macOS 26.5 SDK in CI. The desktop CI uses Intel macOS 26 runners after repeated ARM capacity failures; cross-compilation status remains explicit in manifests.

## Verified and remaining

The original read-only CSMC probes on ARM macOS 27 establish:

- Unsandboxed AppleSMC connection, key count and fan count succeed.
- Standard App Sandbox denies the AppleSMC connection.
- App Sandbox with the observed `AppleSMCClient` IOKit temporary exception allows those reads locally.

The Store host requests that documented exception and user-selected file access for CSV exports and custom icons. Temporary exceptions and the SMC driver protocol still require App Review justification; local success is not Apple approval or a guarantee across all Macs. Missing readings remain unavailable rather than invented.

Before submission, register/assign the widget App ID and shared App Group, create matching distribution profiles, sign/export the universal archive, verify the signed app in its sandbox, upload the build, complete accurate metadata/privacy/review details, and submit. No upload or approval is claimed until the corresponding portal state confirms it. The existing Apple Distribution identity is available; an installer distribution identity/profile may still be needed for Mac App Store export. Do not place signing credentials in Git or CI logs.

Website and downloads: <https://show-mac.cc/>; the root and `www` are attached to Cloudflare Pages with working HTTPS. The website full build remains an ad-hoc signed developer preview, not notarized. Apple Distribution signing for the Store does not replace Developer ID notarization for website packages.

## Primary references

- [App Review Guidelines 2.4.5 and 2.5.1](https://developer.apple.com/app-store/review/guidelines/)
- [Temporary exception entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)
- [Preparing an app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
