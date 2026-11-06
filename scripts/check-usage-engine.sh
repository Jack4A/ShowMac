#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if rustup run 1.97.1 rustc --version >/dev/null 2>&1; then TOOLCHAIN=1.97.1; else TOOLCHAIN=stable; fi
cargo +"$TOOLCHAIN" test --manifest-path "$ROOT/UsageEngine/Cargo.toml" --locked --jobs 2
# Direct upstream tests: local source parsing, deduplication and discovery only.
# These fixtures do not need credentials or live provider/pricing services.
for FILTER in sessions:: scanner:: test_parse_local_clients; do
    CARGO_TARGET_DIR="$ROOT/UsageEngine/target" cargo +"$TOOLCHAIN" test --manifest-path "$ROOT/Vendor/tokscale/Cargo.toml" --locked --jobs 2 -p tokscale-core --lib "$FILTER"
done
