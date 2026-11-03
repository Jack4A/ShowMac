# CI 与发布 / CI and releases

工作流：[Build and Release](https://github.com/Jackkakaya/ThermalScope/actions/workflows/build-release.yml)。

## 自动构建

推送 `main`、提交 PR 或从 Actions 手动运行，都会执行 `make check`，然后产出 ARM64 和 Intel 两套构建附件，保留 14 天。`make check` 使用明确的 macOS SDK 和 SwiftPM native 构建后端，包含领域检查、性能工具单元测试、发布附件校验测试、隐藏视图采样、本地化和六组菜单/卡片/告警诊断。本地化检查要求英文完整，并核对各语种已有翻译、明确的英文回退、繁体转换与格式参数。测试使用隔离数据，不授权或写入真实硬件。

构建使用 GitHub 的 `xcode-27` 托管 runner，以 macOS 27 SDK 编译，并保留 macOS 13 部署目标。ARM64 在原生 runner 上执行隔离检查；Intel 为同一源码的交叉编译包，在清单中标明未执行目标架构运行时检查。使用的官方 Actions 均固定到完整提交 SHA。

## 发布新版本

1. 修改 `Resources/Info.plist` 的版本及递增 build，同步两份 README、两份安装说明，并添加 `docs/releases/vX.Y.Z.md`。
2. 运行 `make check`，提交并推送源码。检查 Actions 中的双架构包。
3. 创建并推送匹配的版本标签，例如：

   ```sh
   git tag -a v1.17.0 -m "ThermalScope v1.17.0"
   git push origin v1.17.0
   ```

4. 标签工作流重新检查、构建两种架构，校验源码提交、包内主应用/小组件版本、架构、签名、ZIP 解压、动态依赖和 SHA-256。
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
  --version 1.17.0 --commit "$(git rev-parse HEAD)"
```

## Signing and validation scope

Current packages use ad-hoc signing without Apple notarization; no Developer ID credentials are stored in CI. All binaries are checked for signatures, target architecture, SDK stamp and system-only dependencies. Manifests record the source commit, architecture, SDK, builder and workflow URL. Native fixture checks and cross-compiled static checks are distinguished explicitly. This does not replace physical fan-control, older-system, sleep/resume or long-duration validation.

Pushes and pull requests build artifacts only. A matching version tag publishes the two verified architecture packages after all checks pass. Published assets are never overwritten by reruns.

Runner references: [GitHub runner images](https://github.com/actions/runner-images), [Xcode 27 runner availability](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/).
