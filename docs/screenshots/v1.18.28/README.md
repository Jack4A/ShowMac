# ShowMac 1.18.28 (295) — development-preview captures

English and Simplified Chinese, light and dark, rendered from the same checked local app. All readings, power history, token events, quota and drag states are isolated examples; no personal usage, account, process or conversation data is included. No hardware controls or saved preferences were changed by capture.

- Overview, sensors, CPU details, thermal controls, electricity, Token usage and compact Settings.
- Menu bar popover with four configured cards, the optional Token summary and the simplified two-row fan controls; CPU processes are hidden for the example.
- Scene manager, card deletion surface, and an Intel Turbo row fixture. The Turbo fixture is rendered explicitly on the ARM host to validate the Intel UI; it does not spoof hardware or invoke controls.
- `capture.json` records the app version, fixture names and exact PNG hashes. Native source: `Sources/ThermalScope/Diagnostics/CompatibilityUICheck.swift`.

This is a development preview, not a released binary. Public downloads remain 1.18.23. Locally built with SDK 27, minimum macOS 12; official SDK 26.5 release packaging still targets macOS 11. Current-host rendering does not certify physical MacBook lid behavior or every macOS version.
