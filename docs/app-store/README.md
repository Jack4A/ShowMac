# ShowMac — Mac App Store edition

A separate sandboxed monitoring app. The full desktop edition remains the website download.

- Team: **Jack John — 35PQA6NV57**
- Registered explicit bundle ID: `com.jackjohn.showmac`
- App Store Connect record: [ShowMac — 6830209769](https://appstoreconnect.apple.com/apps/6830209769/distribution)
- Initial Store version: **1.0.0 / build 1**, macOS 11+
- Pricing request: one-time purchase, **CNY 5.90 or USD 1.00**, subject to Apple’s actual selectable price points. Do not advertise an unconfigured price.
- Support: `920491071@qq.com`

## Edition boundary

The Store target depends only on public Apple frameworks. It does not link ThermalCore, CSMC, the privileged helper, kernel-extension loading, global process inspection or system-setting writes. It shows CPU utilization, an estimate of used memory (active + wired + compressed pages), the macOS thermal-state classification, and available power/battery information. Thermal state is not a temperature reading. Missing battery/CPU data remains absent.

Recent CPU and memory samples stay in memory for 30 minutes. Users can export CSV with a sandboxed save panel. The app has English/Chinese, appearance settings, configurable menu readings and a small menu panel. There is no account, telemetry upload, advertising SDK or in-app purchase.

## Build and validation

Use full Xcode 26.6 / macOS 26.5 SDK for the macOS 11 deployment target:

```sh
DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer bash scripts/build-store.sh
build/store/ShowMac.app/Contents/MacOS/ShowMacStore --self-check
```

CI builds both architectures and checks the binary boundary, actual minimum OS, sandbox entitlements and privacy manifest. Native validation tests real public CPU/memory readings, CPU counter rollover and missing first samples. CI artifacts are ad-hoc signed **validation builds**, not submission packages.

Distribution signing requires this Team’s App Store provisioning profile and existing Apple Distribution identity. Packaging for upload also requires a Mac Installer Distribution signing identity. Never check profiles, private keys, API tokens or installer credentials into Git. An App Store Connect session alone does not authorize exporting credentials.

## Submission status

The App Store record exists. Distribution signing, valid submission package, screenshots, pricing, availability, age rating, privacy disclosure, review contact and final App Review submission must be verified in App Store Connect. A created record or locally running sandbox build is not a published app.

## Official references

- [Mac App Store rules, including sandbox and privilege restrictions](https://developer.apple.com/app-store/review/guidelines/)
- [Create an App Store provisioning profile](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile/)
- [Packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
