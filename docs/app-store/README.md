# App Store decision and readiness

**Decision, November 3, 2026:** preserve all existing desktop functionality and distribute the original ShowMac app through the website first. App Store submission is deferred. Do not replace the original app with a rewritten reduced interface.

The experimental independent Store frontend was reverted in `8a5cf44`. No reduced edition is distributed on the website, and no build was uploaded or submitted to App Review. The installed full app and both website ZIPs are ShowMac 1.18.0 / build 266, preserving the original desktop bundle identity and preferences.

An App Store Connect record was created and retained for future work: [ShowMac, ID 6830209769](https://appstoreconnect.apple.com/apps/6830209769/distribution), Team Jack John (`35PQA6NV57`), registered bundle ID `com.jackjohn.showmac`, SKU `showmac-macos`. No price was saved. The requested one-time price is CNY 5.90 or USD 1.00; the portal offered USD 1.00, while its expanded CNY list did not include 5.90.

## Verified boundary

Using the original CSMC read code on the current ARM macOS 27 host:

- Unsandboxed: SMC connection, sensor-key count and fan count read successfully.
- Standard App Sandbox: SMC connection denied; readings unavailable.
- App Sandbox plus the documented IOKit user-client temporary exception for the observed `AppleSMCClient` class: connection, key count and fan count read successfully again.

These are local read-only probes, not proof of App Review acceptance or validation on every supported OS/model. Temporary exceptions and the original SMC driver protocol need review justification. Do not silently delete sensor features before evaluating this route.

The existing fan-control implementation requests root authorization; Intel turbo and power actions also rely on privileged operations. Apple’s rules prohibit root escalation for Mac App Store apps. Preserving those functions means the original desktop build remains the appropriate distribution path while no compliant equivalent is verified.

## Current desktop distribution

The full app is available from <https://101.37.211.18/showmac/> for Intel and Apple Silicon. It is the existing ad-hoc-signed developer preview and is **not notarized**. Apple Distribution signing is not Developer ID signing. A future notarized desktop release needs a usable Developer ID Application identity, hardened-runtime packaging, notarization and stapling; do not advertise those as complete.

Keep review-contact phone details and signing secrets out of this repository. User-provided review contact information was not published on the website.

## Primary references

- [App Review Guidelines 2.4.5 and 2.5.1](https://developer.apple.com/app-store/review/guidelines/)
- [App Sandbox temporary exception entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)
- [Preparing an app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
