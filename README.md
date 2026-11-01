# 温控台 · ThermalScope

Intel Mac 的温度、CPU、风扇和性能诊断工具。当前应用版本为 **1.16 / build 260**，包含后续 Dock 交互、图标和压测修复。

## 使用行为

启动后先在状态栏监测；状态栏左键打开温度、CPU 和风扇曲线面板，右键打开操作菜单。点击 Dock 图标打开完整控制台；关闭主窗口后隐藏 Dock 图标，状态栏继续监测。再次从面板打开控制台时恢复 Dock 图标。

监测默认只读。风扇、睿频和系统电源调整通过显式操作及系统授权执行。睿频控制复用本机已安装的 `com.rugarciap.DisableTurboBoost` 扩展，不随工程提供新的内核驱动。

## 工程位置

开发仓库位于 `~/codejk/ThermalScope`。源码、测试和 `.git` 均在此目录，历史构建交付物保留在原聊天输出目录。

## 构建

需要 macOS 13+ 和支持 Swift 5.9+ 的 Xcode Command Line Tools。当前验证机器为 Intel MacBookPro16,1，未完成其他机型的能力验证。没有第三方 Swift 包依赖。

```sh
make build
open build/ThermalScope.app
```

也可以直接运行 `bash scripts/build.sh "$PWD/build/ThermalScope.app"`。构建包含主程序、辅助程序和 WidgetKit 扩展，并进行签名校验；默认是本地 ad-hoc 签名。正式分发所需的签名、公证与权限配置仍待完成。

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

- [开发与 Git 约定](docs/DEVELOPMENT.txt)
- [性能场景与人工验收](docs/performance/SCENARIOS.txt)
- [产品要求](docs/PRODUCT_REQUIREMENTS.txt)
- [验证历史](docs/validation/HISTORY.txt)
- [历次计划](docs/plans/) / [发布记录](docs/releases/)
- [整理前的完整使用说明（历史资料）](docs/archive/README-1.16.md)

本地 Git 仓库使用 `main` 分支，整理前的原始快照已单独提交。编译缓存、应用包、性能原始输出、编辑器状态和本地签名材料不纳入版本管理。当前尚未配置远程仓库。
