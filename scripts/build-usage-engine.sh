#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${THERMALSCOPE_ARCH:-$(uname -m)}"
MINIMUM_OS="${2:-11.0}"
case "$ARCH" in arm64) TARGET=aarch64-apple-darwin;; x86_64) TARGET=x86_64-apple-darwin;; *) exit 2;; esac
if rustup run 1.97.1 rustc --version >/dev/null 2>&1; then TOOLCHAIN=1.97.1
elif rustc --version | /usr/bin/grep -q '^rustc 1.97.1 '; then TOOLCHAIN=stable
else echo 'Install Rust 1.97.1 with rustup to build the bundled Tokscale engine.' >&2; exit 1; fi
rustup target add --toolchain "$TOOLCHAIN" "$TARGET" >/dev/null
export MACOSX_DEPLOYMENT_TARGET="$MINIMUM_OS"
export SDKROOT="${THERMALSCOPE_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
export CARGO_TARGET_DIR="${SHOWMAC_ENGINE_BUILD_DIR:-$ROOT/UsageEngine/target}/macos-$MINIMUM_OS"
mkdir -p "$(dirname "$1")"
# CI may restore the final binary from a cache keyed by all engine sources,
# lockfiles, architecture, deployment floor, SDK and Rust version. Local builds
# keep compiling from source unless an explicit cache path is supplied.
ENGINE_CACHE="${SHOWMAC_ENGINE_CACHE:-}"
if [[ -n "$ENGINE_CACHE" && -x "$ENGINE_CACHE" ]]; then
    cp "$ENGINE_CACHE" "$1"
else
    cargo +"$TOOLCHAIN" build --manifest-path "$ROOT/UsageEngine/Cargo.toml" --locked --release --target "$TARGET" --jobs 2
    cp "$CARGO_TARGET_DIR/$TARGET/release/showmac-usage-engine" "$1"
    if [[ -n "$ENGINE_CACHE" ]]; then mkdir -p "$(dirname "$ENGINE_CACHE")"; cp "$1" "$ENGINE_CACHE"; fi
fi

python3 - "$1" "$ROOT/Sources/ThermalCore/TokenUsage.swift" "$ROOT/Sources/ThermalCore/AgentUsageEngine.swift" <<'PYCODE'
import json,re,subprocess,sys
from pathlib import Path
report=json.loads(subprocess.check_output([sys.argv[1],'--capabilities'],text=True))
swift=Path(sys.argv[2]).read_text().split('public static let allCases:[Self]=[',1)[1].split(']',1)[0]
assert set(report['providers'])==set(re.findall(r'Self\("([^\"]+)"\)',swift)), 'Agent catalog mismatch'
assert report['commit'] in Path(sys.argv[3]).read_text(), 'Upstream pin mismatch'
print('Verified native engine catalog:',len(report['providers']),'sources')
PYCODE
