# CI 与发布 / CI and releases

工作流：[Build and Release](https://github.com/Jack4A/ShowMac/actions/workflows/build-release.yml)。

## 自动构建

推送 `main`、提交 PR 或从 Actions 手动运行，都会执行 `make check`，然后产出 ARM64 和 Intel 两套构建附件，保留 14 天。`make check` 使用明确的 macOS SDK 和 SwiftPM native 构建后端，包含领域检查、性能工具单元测试、发布附件校验测试、隐藏视图采样、本地化和六组菜单/卡片/告警诊断。本地化检查要求英文完整，并核对各语种已有翻译、明确的英文回退、繁体转换与格式参数。测试使用隔离数据，不授权或写入真实硬件。

构建使用 GitHub 的 `macos-26` 托管 runner，明确选择 Xcode 26.6 / macOS 26.5 SDK，并以 macOS 11 为部署目标。Xcode 27 / SwiftPM 会将最低目标抬高到 macOS 12，因此不能用于此发布构建。ARM64 执行原生隔离检查，Intel 为交叉编译包；清单明确记录运行时验证范围。官方 Actions 均固定到完整提交 SHA。

同一份已检查的应用还会分别在 macOS 26 与 macOS 27 上打开真实标题栏窗口，渲染 14 个浅、深色场景并保存 PNG。比较任务核对侧栏宽高、起点、底部设置位置以及侧栏和选中态的实际颜色；缺少测量或出现偏移都会阻止版本发布。侧栏共用 macOS 11+ 的材质与主题着色，选中高光使用固定灰紫渐变；图表也共用实现，标准控件继续由系统提供。

## 发布新版本

1. 修改 `Resources/Info.plist` 的版本及递增 build，同步两份 README、两份安装说明，并添加 `docs/releases/vX.Y.Z.md`。
2. 运行 `make check`，提交并推送源码。检查 Actions 中的双架构包。
3. 创建并推送匹配的版本标签，例如：

   ```sh
   git tag -a v1.17.4 -m "ThermalScope v1.17.4"
   git push origin v1.17.4
   ```

4. 标签工作流重新检查、构建两种架构，校验源码提交、主应用/辅助程序/小组件的实际 Mach-O 最低版本 11.0、主应用/小组件的 Info.plist、架构、签名、ZIP 解压和 SHA-256。新框架必须弱链接，Swift 并发运行库必须随包提供并具有可移植搜索路径，构建机工具链路径不会进入安装包。
5. Release job 只在版本标签上获得 `contents: write`。它先创建草稿并上传八个附件，核对 GitHub 记录的大小及 SHA-256 后再发布。失败时草稿保持未发布，修复后可重新运行；已发布版本不会被自动覆盖。

普通 push 和 PR 的工作流只有读取源码的权限，不发布版本。历史标签与附件保留。构建输出、日志和缓存位于 Git 忽略目录，不提交到仓库。

## 本地打包与校验

要求工作区干净，输出目录必须不存在：

```sh
THERMALSCOPE_ARCH=arm64 bash scripts/package-release.sh build/releases/local-arm64
THERMALSCOPE_ARCH=x86_64 bash scripts/package-release.sh build/releases/local-intel
```

将两套包各自的 ZIP、INSTALL、manifest 和 SHA256SUMS 文件复制到一个新目录，然后运行：

```sh
python3 scripts/verify-release-assets.py build/releases/pair \
  --version 1.17.4 --commit "$(git rev-parse HEAD)"
```

## Signing and validation scope

Current packages use ad-hoc signing without Apple notarization; no Developer ID credentials are stored in CI. All binaries are checked for signatures, target architecture, SDK stamp and system-only dependencies. Manifests record the source commit, architecture, SDK, builder and workflow URL. Native fixture checks and cross-compiled static checks are distinguished explicitly. This does not replace physical fan-control, older-system, sleep/resume or long-duration validation.

Pushes and pull requests build artifacts only. A matching version tag publishes the two verified architecture packages after all checks pass. Published assets are never overwritten by reruns.

The checks also render fourteen light/dark layouts using the macOS 11/12 control paths on the current runner. A separate matrix renders the exact same checked binary in titled windows on macOS 26 and 27, uploads PNGs and measurements, and blocks publication if sidebar geometry or measured colors drift. This is not old-OS runtime certification; physical-device macOS 11/12 validation remains pending.

Runner references: [macOS 26 software](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), [Apple deployment targets](https://developer.apple.com/xcode/system-requirements).

## Explicit single-run publishing

Manual **Build and Release → Run workflow** offers `publish` (default false). When true, the Info.plist version is published only after the same native checks, macOS appearance comparison, dual-architecture packaging and asset checks pass. It creates the version tag at the checked commit using the workflow token, avoiding a second tag-triggered build. Normal main pushes remain build-only; tag publication still works. Published releases cannot be overwritten. Running this on main also makes the engine cache available to later branch/tag builds.

GitHub references: [GITHUB_TOKEN event behavior](https://docs.github.com/en/actions/concepts/security/github_token), [manual workflow inputs](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).
