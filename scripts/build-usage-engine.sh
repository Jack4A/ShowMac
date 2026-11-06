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
cargo +"$TOOLCHAIN" build --manifest-path "$ROOT/UsageEngine/Cargo.toml" --locked --release --target "$TARGET" --jobs 2
mkdir -p "$(dirname "$1")"
cp "$CARGO_TARGET_DIR/$TARGET/release/showmac-usage-engine" "$1"

python3 - "$1" "$ROOT/Sources/ThermalCore/TokenUsage.swift" "$ROOT/Sources/ThermalCore/AgentUsageEngine.swift" <<'PYCODE'
import json,re,subprocess,sys
from pathlib import Path
report=json.loads(subprocess.check_output([sys.argv[1],'--capabilities'],text=True))
swift=Path(sys.argv[2]).read_text().split('public static let allCases:[Self]=[',1)[1].split(']',1)[0]
assert set(report['providers'])==set(re.findall(r'Self\("([^\"]+)"\)',swift)), 'Agent catalog mismatch'
assert report['commit'] in Path(sys.argv[3]).read_text(), 'Upstream pin mismatch'
print('Verified native engine catalog:',len(report['providers']),'sources')
PYCODE
