# 温控台 · ThermalScope

**简体中文** | [English](README.en.md)

<img src="Resources/AppIcon.png" width="96" alt="温控台应用图标">

macOS 温度、CPU、风扇和性能诊断工具，提供 Intel 版与实验性 Apple Silicon 风扇控制版。当前应用版本为 **1.17.2 / build 263**，支持 macOS 11+，统一各版本的主体界面样式。

## 功能

- 状态栏显示温度、CPU 使用率和风扇转速，左键打开紧凑趋势面板并快速切换风扇档位。
- 控制台查看实时指标、传感器、CPU/内存/磁盘进程活动和性能诊断依据。
- 性能诊断优先展示需要关注的项目；当前读数使用简洁列表，负载来源、日常观察和判定规则按需展开。
- 传感器页默认展示可读名称、用途说明和常用读数。常用卡片支持 5/10/30 分钟趋势及详细图表，本次运行保留最近 30 分钟，退出后清空；完整温度、风扇、功耗、电压和电流可按名称、类型和编号搜索，未确认用途的探头单独收纳。
- 自动、安静、均衡、强劲和自定义风扇档位，以及可编辑的温度—风扇转速曲线。
- 独立 Intel 睿频控制、操作记录和采样导出。
- 系统/浅色/深色主题、多语言、状态栏自定义和 WidgetKit 小组件。
- 状态栏组件支持拖动组合与排序，可选择任意可读传感器，独立设置图标、颜色和显示样式；默认黑白，文字与数值横排，外边距与内边距均可设为零。
- 菜单栏弹窗支持 1–8 张指标卡片，可在弹窗或“设置 → 弹窗卡片”中添加、排序和删除；风扇控制与 CPU 占用排行可独立显示，配置自动保存。
- 固定随机种子的模拟压测、性能预算、原始采样和基线回归比较。

当前源码的 ARM 版提供预设散热档位、可拖动风扇曲线和 5 秒风扇测试，首次控制需要管理员授权；Intel 睿频与电源设置控制仍禁用。实现与验证范围见 [Apple Silicon 风扇说明](docs/APPLE_SILICON_FANS.txt)。`v1.17.2` 的 ARM 安装包已包含这些改动；旧 `v1.16.0` ARM 附件仍保留为原监测版。状态面板以两列紧凑卡片显示数值与近期趋势，单数最后一张铺满一行；共用时间范围和更新时间，并按既有阈值显示警告颜色。下方可直接选择风扇档位，点击指标进入详情。历史不足及缺失读数会显示说明。设置页分别管理顶部菜单栏组件和弹窗卡片，字体与外观选项按需展开。

## 截图

以下为开发过程中保存的实机截图，数值代表拍摄时的状态。

### 状态栏曲线面板

左键点击状态栏即可查看温度、CPU 和风扇趋势，直接选择风扇档位，或进入控制台调整曲线。

<img src="docs/screenshots/status-panel.png" width="420" alt="温控台状态栏面板：CPU 温度、CPU 使用率与风扇转速曲线">

### 温度与风扇控制

当前源码可直接选档，或拖动曲线并松手生效；下图保留旧版界面。

![温度控制：运行模式、风扇曲线和 Intel 睿频](docs/screenshots/thermal-control.png)

### CPU 历史与指标详情

支持时间范围、固定/自动刻度、线条/面积以及暂停图表。

![CPU 历史：使用率、采样趋势和统计](docs/screenshots/cpu-history.png)

截图版本与来源见 [截图记录](docs/screenshots/README.txt)。

## 安装与首次启动

### 下载应用包（无需编译）

1. 登录有此私有仓库访问权限的 GitHub 账号，打开 [Releases](https://github.com/Jackkakaya/ThermalScope/releases)。
2. 按芯片选择 `v1.17.2` 的 **`ThermalScope-1.17.2-macOS-x86_64.zip`**（Intel）或 **`ThermalScope-1.17.2-macOS-arm64.zip`**（Apple Silicon 实验版），解压后将 `ThermalScope.app` 拖到“应用程序”。
3. 打开应用，点击顶部状态栏图标开始使用。预编译应用不需要安装 Xcode、Swift 或 Python。
4. 在“设置 → 语言”切换简体中文或 English。应用还支持繁体中文、日语、韩语、德语、法语和西班牙语；本轮部分新增文案在非中文语种下回退英文。

两个应用包最低均为 **macOS 11**。Intel 版当前实测机型为 MacBookPro16,1。ARM 版提供实验性风扇控制，已验证机型与限制见 [Apple Silicon 风扇说明](docs/APPLE_SILICON_FANS.txt)；CI 的虚拟机检查不代表所有机型均已验证。当前为本地 **ad-hoc 签名、未经公证**的开发构建，macOS 可能提示无法验证开发者。Developer ID 签名与公证仍待完成。

Release 为每个架构提供独立的双语安装指南、构建清单和校验值。Intel 版为 `INSTALL.txt`、`release-manifest.json`、`SHA256SUMS.txt`；ARM 版为 `INSTALL-arm64.txt`、`release-manifest-arm64.json`、`SHA256SUMS-arm64.txt`。下载所选架构的四个附件后，运行 `shasum -a 256 -c SHA256SUMS.txt`（Intel）或 `shasum -a 256 -c SHA256SUMS-arm64.txt`（ARM）。

macOS 11+ 使用同一套侧栏、主题、圆角和图表绘制，保留真实趋势、警告色、读数查询与可拖动风扇曲线。侧栏默认统一为 220 pt，选中项使用固定主题颜色，不随系统玻璃或桌面背景改变。CI 使用同一个安装包在 macOS 26、27 上渲染 14 个浅深色场景，并比较侧栏尺寸、位置和实际像素颜色。小组件支持 macOS 11+ 通知中心、macOS 14+ 桌面；macOS 11/12 真机运行验证仍待完成。

### 从源码构建

源码构建需要完整 Xcode 26.5/26.6（含 macOS 26.5 SDK）、Git 和 Python 3；预编译应用以 macOS 11 为最低部署目标。Xcode 27 的最低部署目标已为 macOS 12，不能用于此发布构建。

先安装并首次启动完整 Xcode 26.5/26.6；如需指定工具链，将路径调整为实际安装位置：

```sh
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
xcodebuild -version
xcrun --sdk macosx --show-sdk-version
```

访问此私有仓库需要 GitHub 账号已有权限。完成认证后：

```sh
git clone https://github.com/Jackkakaya/ThermalScope.git
cd ThermalScope
make build
open build/ThermalScope.app
```

`make build` 会生成主程序、辅助程序和 WidgetKit 扩展，并进行签名校验；当前使用本地 ad-hoc 签名。正式分发所需的 Developer ID 签名、公证与权限配置仍待完成。

## 使用方式

1. **打开监测**：启动后先在状态栏监测，不自动弹出控制台。监测默认只读，不需要管理员密码。
2. **查看曲线**：左键点击状态栏图标，打开温度、CPU 使用率和风扇转速面板；右键打开操作菜单。
3. **打开控制台**：点击面板的“打开温控台”，或点击 Dock 图标。选择“实时监测”“性能诊断”“进程活动”等页面查看详情。
4. **调整散热**：在“温度控制”直接选择自动、安静、均衡、强劲或自定义档位；拖动曲线控制点，松手后自动应用。首次接管需要系统管理员授权，30 分钟后恢复自动。
5. **恢复自动**：使用“恢复系统自动”将风扇控制交回系统，并查看操作结果是否确认。
6. **后台运行**：关闭主窗口后隐藏 Dock 图标，状态栏继续监测；再次打开控制台时恢复 Dock 图标。彻底退出请使用应用菜单或状态栏的“退出温控台”。
7. **语言切换**：在“设置 → 语言”选择简体中文、English 或跟随系统；不需要修改系统语言。

控制台首页优先展示 CPU 温度、风扇转速、CPU 使用率与完整温度趋势，其余指标位于下方。指标详情可通过标题旁的返回按钮或再次点击“实时监测”返回。进程页支持搜索应用、原始进程名和 PID，并可展开全部可读进程。风扇控制采用一排档位和一张 RPM 曲线，选档立即生效、拖动松手后自动应用；控制剩余时间和高温保护状态显示在顶部。

### 温控与睿频依赖

风扇能力取决于本机 AppleSMC 接口。实际控制前先退出 Macs Fan Control 等其他风扇控制软件，避免同时控制。

睿频控制复用本机已安装且获系统批准的 `com.rugarciap.DisableTurboBoost` 扩展（例如已有 Turbo Boost Switcher 安装）。工程不附带新内核驱动，也不会自动下载驱动或绕过系统安全设置。没有该扩展时，睿频控制可能不可用，仍可使用可读的监测功能。使用睿频控制前先退出其他睿频控制器，避免规则互相覆盖。

CPU 使用率、系统性能限制和睿频状态是不同指标；传感器与历史缺失保持缺失，不补造零读数。

## 工程位置

开发仓库位于 `~/codejk/ThermalScope`。源码、测试和 `.git` 均在此目录，历史构建交付物保留在原聊天输出目录。

## 开发构建

没有第三方 Swift 包依赖。在仓库目录中运行：

```sh
make build
```

也可指定输出位置：

```sh
make build APP="$PWD/build/ThermalScope.app"
# 或直接调用构建脚本
bash scripts/build.sh "$PWD/build/ThermalScope.app"
```

需要生成新的应用 ZIP、清单、双语安装说明与校验值时：

```sh
bash scripts/package-release.sh "$PWD/build/releases/v1.17.2"
```

目标目录必须不存在；脚本要求 Git 工作区干净，并验证 ZIP 解压后的签名与执行权限。交叉编译 ARM 包：

```sh
THERMALSCOPE_ARCH=arm64 bash scripts/package-release.sh "$PWD/build/releases/v1.17.2-arm64"
```

主程序、辅助程序和小组件统一为 arm64；跨架构时不运行目标二进制，清单明确标记运行时检查未执行。两种架构共用同一个版本标签，独立清单记录相同源码提交与各自的验证范围；历史发布标签和附件保持原样。

## 检查与压测

```sh
make check
make perf-smoke
```

`make check` 运行 75 项领域检查、18 项性能工具检查，以及隐藏视图更新检查。`make perf-smoke` 运行完整模拟负载套件，结果保存在带时间标记的 `performance-results/` 子目录。

```sh
make perf-standard
make perf-soak
```

standard 为每场景三个种子、每轮 120 秒采样；soak 为每场景 30 分钟。两者都会持续制造单核负载。测试使用独立模拟进程，不写风扇、睿频或电源设置，也不接管正在运行的监控应用。

精确指定结果目录、场景与基线的方法见 [压测使用说明](docs/performance/SUITE.txt)。CPU 侧绘图耗时不等于屏幕帧率；真实 UI 交互、睡眠恢复、硬件控制、整机功耗和长期泄漏仍需专项验证。

## 代码结构

| 目录 | 职责 |
|---|---|
| `Sources/CSMC` | AppleSMC、IOKit 与底层原生接口 |
| `Sources/ThermalCore` | 采样模型、历史、诊断规则、控制协议与故障恢复 |
| `Sources/ThermalScope/Application` | 应用入口、窗口生命周期和 AppModel |
| `Sources/ThermalScope/State` | 实时读数、历史、诊断和电源优化状态 |
| `Sources/ThermalScope/Services` | 控制客户端、进程观察和小组件发布 |
| `Sources/ThermalScope/MenuBar` | 状态栏绘制、快捷面板与外观设置 |
| `Sources/ThermalScope/Views` | 控制台、指标详情、诊断和设置界面 |
| `Sources/ThermalScope/Support` | 主题和本地化 |
| `Sources/ThermalScope/Diagnostics` | 独立检查、渲染基准与模拟压测 |
| `Sources/ThermalScopeHelper` | 需要授权的硬件控制辅助程序 |
| `WidgetSupport` / `Widgets` | 小组件共享模型、界面与扩展入口 |
| `Tests` | 领域检查和 Python 性能工具测试 |
| `scripts` / `tools` | 构建、图标打包、采样和性能报告工具 |
| `docs` | 当前说明、历史计划、发布与验证记录 |

SwiftPM 递归发现各 target 内的源码，目录整理不改变 target 名称或运行逻辑。

## 文档与版本管理

当前使用说明提供 [简体中文](README.md) / [English](README.en.md)，[发布安装指南](docs/INSTALL.txt) 与 Release 说明为双语；历史计划和验证日志保留原文。

- [开发与 Git 约定](docs/DEVELOPMENT.txt)
- [性能场景与人工验收](docs/performance/SCENARIOS.txt)
- [产品要求](docs/PRODUCT_REQUIREMENTS.txt)
- [验证历史](docs/validation/HISTORY.txt)
- [历次计划](docs/plans/) / [发布记录](docs/releases/)
- [整理前的完整使用说明（历史资料）](docs/archive/README-1.16.md)

本地 Git 仓库使用 `main` 分支，整理前的原始快照已单独提交。编译缓存、应用包、性能原始输出、编辑器状态和本地签名材料不纳入版本管理。GitHub 远程仓库为 `Jackkakaya/ThermalScope`，初始可见性为 **Private**。

## 自动构建与发版

推送 `main`、提交 PR 或手动运行 [Build and Release](https://github.com/Jackkakaya/ThermalScope/actions/workflows/build-release.yml) 会执行检查并产出 Intel/ARM64 构建附件（保留 14 天）。推送与 `Info.plist` 一致的 `vX.Y.Z` 标签后，CI 在两种架构打包、签名、解压和 SHA-256 校验全部通过后发布 Release。流程、签名状态与操作说明见 [CI 与发布](docs/CI-RELEASE.md)。
