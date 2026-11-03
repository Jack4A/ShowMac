# ThermalScope · 温控台

[简体中文](README.md) | **English**

<img src="Resources/AppIcon.png" width="96" alt="ThermalScope application icon">

A native macOS temperature, CPU, fan and performance diagnostics utility, with an Intel build and an experimental Apple Silicon fan-control build. Current application version: **1.17.2 / build 263**, including native UI, sensors, menu customization and automated builds.

macOS 11+ shares the same app-owned sidebar, theme, corners and chart renderer, retaining real samples, warning colors, inspection and draggable fan curves. The sidebar is 220 pt wide; its selection colors do not follow system glass or wallpaper. CI renders the same checked binary on macOS 26 and 27 and compares fourteen light/dark layouts, sidebar geometry and measured colors. Widgets support Notification Center on macOS 11+ and the desktop on macOS 14+. Physical-device runtime validation on macOS 11/12 remains pending.

## Features

- Menu bar readings and a popover with temperature, CPU usage and fan history.
- A console for live metrics, sensors, CPU/memory/disk process activity and evidence-based diagnostics.
- Performance diagnosis puts actionable findings first, with a compact readings list and expandable activity sources, routine observations and rules.
- A sensor overview with readable names and explanations, 5/10/30-minute trends on common cards and detailed charts. The last 30 minutes are kept for the current session and cleared on quit. Complete temperature, fan, power, voltage and current readings are searchable by name, type and ID; probes with unconfirmed purposes are grouped separately.
- Auto, Quiet, Balanced, Boost and Custom fan presets, plus editable temperature-to-fan-speed curves.
- Independent Intel Turbo Boost control, operation history and sample export.
- System/light/dark appearance, language selection, configurable menu bar and WidgetKit widgets.
- Drag menu-bar components to combine and reorder icons, values and trends from any readable sensor. Each component has its own icon, color and style; black/white and horizontal labels are the defaults. Inner and outer padding can both be zero.
- Choose 1–8 popover cards from either the popover editor or Settings → Popover cards, with ordering, removal and automatic saving. Fan controls and top CPU processes can be shown independently.
- Seeded synthetic stress tests, performance budgets, raw captures and baseline comparisons.

## Screenshots

These are actual application captures saved during development. Readings reflect the capture time. The screenshots use the Chinese interface; select **English** in Settings → Language for the English interface.

### Menu bar graphs

Left-click the menu bar item for temperature, CPU and fan trends, with links into the console.

<img src="docs/screenshots/status-panel.png" width="420" alt="ThermalScope popover with CPU temperature, CPU usage and fan speed history">

### Temperature and fan control

Current source applies a mode immediately, or applies a curve when a dragged point is released. The image below retains the earlier interface.

![Thermal modes, fan curve entry and Intel Turbo Boost controls](docs/screenshots/thermal-control.png)

### CPU history and metric details

Choose the time range, fixed/automatic scale, line/area display or pause the chart.

![CPU utilization, actual sampled history and statistics](docs/screenshots/cpu-history.png)

The popover and thermal-control captures are from 1.16; the CPU-detail capture is from 1.15, whose layout is retained in 1.16. [Original capture records](docs/screenshots/README.txt).

## Download and first launch

### Prebuilt app — no compilation required

1. Sign in to a GitHub account with access to this private repository and open [Releases](https://github.com/Jackkakaya/ThermalScope/releases).
2. Choose **`ThermalScope-1.17.2-macOS-x86_64.zip`** for Intel or **`ThermalScope-1.17.2-macOS-arm64.zip`** for experimental Apple Silicon fan control from `v1.17.2`. Extract it and drag `ThermalScope.app` into Applications.
3. Launch the app, then click its item in the top menu bar. The prebuilt app does not require Xcode, Swift or Python.
4. Select English or Simplified Chinese in Settings → Language. Traditional Chinese, Japanese, Korean, German, French and Spanish are also available; some new strings use English fallback in other locales.

Both packages require **macOS 11 or later**. The Intel build is validated on MacBookPro16,1. The arm64 archive includes experimental fan controls; see [hardware validation scope](docs/APPLE_SILICON_FANS.txt) for tested machines and limits. CI virtual-machine checks do not establish support for every model. This development build uses **ad-hoc signing and is not notarized**; macOS may report that the developer cannot be verified. Developer ID signing and notarization remain pending.

The release provides per-architecture install notes, manifests and checksums. Intel uses `INSTALL.txt`, `release-manifest.json` and `SHA256SUMS.txt`; ARM uses `INSTALL-arm64.txt`, `release-manifest-arm64.json` and `SHA256SUMS-arm64.txt`. Download the four assets for your architecture into one directory, then run `shasum -a 256 -c SHA256SUMS.txt` (Intel) or `shasum -a 256 -c SHA256SUMS-arm64.txt` (ARM).

### Build from source

Source builds require full Xcode 26.5/26.6 (including the macOS 26.5 SDK), Git and Python 3. Prebuilt applications target macOS 11 or later. Xcode 27 raises the deployment floor to macOS 12 and cannot be used for this release build. Install and open full Xcode 26.5/26.6 first. To select it explicitly, adjust the path to your installation:

```sh
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
```

After authenticating with an account that can access the private repository:

```sh
git clone https://github.com/Jackkakaya/ThermalScope.git
cd ThermalScope
make build
open build/ThermalScope.app
```

`make build` packages the host application, privileged helper and WidgetKit extension, then verifies their signatures. Local builds default to ad-hoc signing.

## How to use

1. **Monitor:** startup begins monitoring in the menu bar without automatically opening the console. Monitoring is read-only by default and does not require an administrator password.
2. **View graphs:** left-click the menu bar item for temperature, CPU usage and fan curves. Right-click for the actions menu.
3. **Open the console:** use “Open ThermalScope” in the popover, or click the Dock icon. Navigate to live monitoring, performance diagnosis or process activity.
4. **Adjust cooling:** choose Auto, Quiet, Balanced, Boost or Custom under Temperature Control. Drag a curve point and release to apply it automatically. First use requires macOS administrator authorization; control returns to automatic after 30 minutes.
5. **Restore automatic control:** use the system automatic fan action, then check whether the operation is confirmed.
6. **Keep monitoring:** closing the main window hides the Dock icon while the menu bar continues monitoring. Opening the console brings the Dock icon back. Use Quit from the application or menu bar menu to fully exit.
7. **Change language:** choose English, Simplified Chinese or Follow System in Settings → Language; changing the system language is unnecessary.

The console prioritizes CPU temperature, fan speed, CPU usage and the full temperature trend, with other metrics below. Return from metric details using the visible back button or Live Monitoring in the sidebar. Process Activity searches app names, raw process names and PIDs, and can show every readable process. Fan control uses one mode selector and one RPM curve. Modes take effect immediately; curve edits apply on release. Remaining time and thermal-protection state appear above the selector.

### Fan and Turbo Boost dependencies

Fan capabilities depend on the machine's AppleSMC interface. Quit other fan controllers, such as Macs Fan Control, before applying fan control to avoid competing controllers.

Turbo Boost control reuses the already installed and macOS-approved `com.rugarciap.DisableTurboBoost` extension, for example from an existing Turbo Boost Switcher installation. This repository does not distribute a new kernel driver or automatically download one. Turbo control may be unavailable without that extension; readable monitoring features remain usable. Quit other Turbo controllers before making Turbo changes to avoid conflicting rules.

CPU utilization, system performance limits and Turbo state are distinct measurements. Missing sensors and history remain missing rather than being represented as zero readings.

## Development workspace

The local development repository is `~/codejk/ThermalScope`; source, tests and `.git` are kept together. Historical delivery artifacts remain outside the repository.

## Development builds

There are no third-party Swift package dependencies. From the repository root:

```sh
make build
```

To choose an output path:

```sh
make build APP="$PWD/build/ThermalScope.app"
# Or invoke the build script directly:
bash scripts/build.sh "$PWD/build/ThermalScope.app"
```

For a fresh release archive, manifest, bilingual install notes and checksums:

```sh
bash scripts/package-release.sh "$PWD/build/releases/v1.17.2"
```

The destination must not already exist. The packaging script verifies the extracted archive as well as the original app bundle. To cross-compile the ARM package:

```sh
THERMALSCOPE_ARCH=arm64 bash scripts/package-release.sh "$PWD/build/releases/v1.17.2-arm64"
```

The host app, helper and widget all target arm64. Cross-architecture runtime checks are skipped and explicitly marked as unexecuted in the manifest. Both architectures share a version tag; their independent manifests record the same source commit and their validation scope. Historical tags and release assets are preserved.

## Checks and stress tests

```sh
make check
make perf-smoke
```

`make check` runs 75 domain checks, 18 performance-tool checks and the hidden-view update check. `make perf-smoke` executes the complete synthetic workload suite and stores timestamped results under `performance-results/`.

```sh
make perf-standard
make perf-soak
```

Standard runs three seeds per scenario with 120 seconds of process sampling each. Soak runs 30 minutes per scenario. Both generate sustained single-core load. Tests use isolated fixture processes, do not write fan/Turbo/power settings and do not take over a running monitoring instance.

The detailed [performance suite guide](docs/performance/SUITE.txt) and [manual scenario matrix](docs/performance/SCENARIOS.txt) are currently in Chinese. The commands above work regardless of interface language. CPU-side rendering timings are not display FPS. Real UI interactions, sleep/wake, hardware control, whole-machine power and long-term leaks require separate validation.

## Repository layout

| Directory | Responsibility |
|---|---|
| `Sources/CSMC` | AppleSMC, IOKit and native interfaces |
| `Sources/ThermalCore` | Models, history, diagnostic rules, control protocols and recovery |
| `Sources/ThermalScope/Application` | Application entry, window lifecycle and AppModel |
| `Sources/ThermalScope/State` | Readings, history, diagnostics and power optimization state |
| `Sources/ThermalScope/Services` | Control client, process observation and widget publishing |
| `Sources/ThermalScope/MenuBar` | Menu bar rendering, popover and appearance settings |
| `Sources/ThermalScope/Views` | Console, metric details, diagnosis and settings |
| `Sources/ThermalScope/Support` | Theme and localization |
| `Sources/ThermalScope/Diagnostics` | Explicit checks, render benchmarks and synthetic stress |
| `Sources/ThermalScopeHelper` | Privileged hardware control helper |
| `WidgetSupport` / `Widgets` | Shared widget models, views and extension entry |
| `Tests` | Domain and Python performance-tool checks |
| `scripts` / `tools` | Build, packaging, capture and performance reporting tools |
| `docs` | Guides and historical planning, release and validation records |

SwiftPM discovers sources recursively within each target. The directory organization does not change target names or runtime behavior.

## Documentation and Git

Current usage documentation is available in [简体中文](README.md) / [English](README.en.md). [Release installation instructions](docs/INSTALL.txt) and release notes are bilingual. Historical planning and validation logs retain their original language.

- [Development and Git conventions (Chinese)](docs/DEVELOPMENT.txt)
- [Product requirements (Chinese)](docs/PRODUCT_REQUIREMENTS.txt)
- [Validation history](docs/validation/HISTORY.txt)
- [Plans](docs/plans/) / [Release records](docs/releases/)
- [Archived pre-organization usage guide](docs/archive/README-1.16.md)

The main branch is `main`; a separate commit and the `pre-organization` tag preserve the original snapshot. Build caches, app bundles, raw performance output, editor state and local signing credentials are ignored. The GitHub repository is `Jackkakaya/ThermalScope`, initially **Private**.

### UI availability and compact monitoring

Current source supports fan-only presets, draggable fan curves and a five-second fan test on Apple Silicon after administrator authorization. Intel Turbo Boost and power-setting controls remain unavailable. The v1.17.2 ARM archive includes these changes; the historical v1.16.0 archive remains the original monitoring-only build. See docs/APPLE_SILICON_FANS.txt for validation scope. The status popover uses two columns of compact cards, with an odd final card spanning the row, a shared time range and an update timestamp. Real trends use the existing warning thresholds. Fan presets are available below; click a metric for details. Missing readings and incomplete history are identified explicitly. Settings manages top-menu components and popover cards separately, with typography and appearance options in a disclosure section.

## Automated builds and releases

Pushes to `main`, pull requests and manual runs of [Build and Release](https://github.com/Jackkakaya/ThermalScope/actions/workflows/build-release.yml) run checks and upload Intel/ARM64 build artifacts for 14 days. A `vX.Y.Z` tag matching `Info.plist` publishes a Release only after both packages pass architecture, signature, extraction and SHA-256 verification. See [CI and releases](docs/CI-RELEASE.md) for the workflow and signing status.
