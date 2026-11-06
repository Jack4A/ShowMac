# Local agent usage

Usage statistics combines electricity and AI token history. Day/week/month/year ranges use the system time zone. The homepage keeps a compact summary card.

## Engine and coverage

Starting in 1.18.16, ShowMac directly bundles the MIT-licensed [Tokscale core](https://github.com/junhoyeo/tokscale), pinned at `82613d2f5e96654ce3729892afbb0025979f1c75`. Its complete 60-client registry is exposed in the tool filter and searchable source list. No Node, Python, Rust installation, account login or API key is required on the user's Mac.

Sources include Codex, Claude Code, Cursor, Gemini, OpenCode, Cline, Roo Code, Kilo Code, Kiro, Zed, Trae, Warp, GitHub Copilot, OpenClaw, Kimi, Qwen and the other clients listed in [the complete source catalog](AGENT-USAGE.md). ShowMac uses upstream parsers and deduplication directly rather than maintaining a second hand-written implementation.

Support means the pinned upstream local format is recognized. It does not guarantee every installed tool writes readable usage, or that every release of that tool uses the same format. Cursor requires usage previously synced into Tokscale's local `cursor-cache`; Trae, Warp and other cached/export sources also depend on available local files. ShowMac does not log in, sync usage from providers, or read credentials. Missing data is shown as unavailable. Web chats and other devices are not automatically included.

Some upstream adapters (for example Kiro and Freebuff) estimate tokens from local text when exact counters are absent. The interface discloses upstream estimates; totals are not subscription quotas or invoices. This version exports token counts only, without model pricing.

## Counting and source controls

The bridge uses `parse_local_unified_messages_with_pricing_uncached(..., None)` with all 60 clients selected explicitly, including Cursor. Upstream handles fork/mirror/stream deduplication. It does not combine two parsers for the same source. Input includes upstream input, cache read and cache write; output includes upstream output and reasoning. Total is input plus output, with cache/reasoning already included once. Unknown/partial data remains subject to upstream coverage.

Expand **Sources and counting method** to pause scans, search clients, display all supported sources, restore defaults, or add a custom data folder where supported by the upstream scanner. Custom folders supplement default discovery. Kilo CLI, Crush and Goose keep upstream automatic discovery because its extra-directory scanner excludes those clients. GUI apps may not inherit shell environment variables; use the folder picker where available.

## Storage and performance

The app checks source metadata every minute on a utility queue, reuses unchanged results, and performs a fresh discovery at least every five minutes to find paths outside the primary catalog (such as editor profiles). Manual refresh checks source changes. The parser is a bundled native executable launched by absolute path, with a restricted environment and a 45-second timeout. No executable is downloaded or resolved from PATH. Tokscale's process-wide offline switch is enabled before parsing; no pricing, account-sync or telemetry API is called.

`~/Library/Application Support/ShowMac/agent-usage-cache.json` stores numeric counts, timestamps, model/source names and hashed event identifiers. It is user-private (0600), written atomically, and contains no conversation text or login credentials. Parsing can read transcript files in memory to extract metadata or upstream estimates, but no transcript text leaves the parser. The old Swift-parser cache is left untouched. Existing electricity history is unchanged. A failed engine run preserves the last successful snapshot and shows a coverage warning.

Source code and upstream license are vendored under `Vendor/tokscale`; app resources include `AgentEngineNotices.txt` with upstream MIT, nested Apache-2.0 decoder and dependency notices. Source changes are recorded in `Vendor/tokscale/UPSTREAM.json`. Build/test toolchain is Rust 1.97.1, pinned lockfiles; release targets are Intel/Apple Silicon, macOS 11+. Test fixtures do not read private sessions. UI previews use synthetic sample data.
