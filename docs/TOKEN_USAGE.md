# Local agent usage

Usage statistics has separate Electricity and Token tabs. Day/week/month/year ranges use the system time zone. The homepage keeps a compact summary card.

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

## Menu bar and account allowance (1.18.17)

Use the pin button beside Token usage, or a quota card's pin, to add a menu bar component. Its editor selects a tool, Day/Week/Month/Year history range, quota window, display style, icon and independent color. Monochrome stays the default. Token sparklines use their actual reporting interval; percentages do not borrow a CPU warning scale. The popover includes a compact Token summary when such a component is configured.

Account allowance is provider-reported percentage, separate from local token totals and the historical date filter. It is not an absolute remaining-token balance. The standard Codex pool is preferred over independent model pools unless a specific window is chosen. Readings older than 15 minutes, more than a minute in the future, or past their reported reset time are not shown as current. A reset never creates a fabricated 100% value.

Codex reads bounded tails (up to 1 MiB each) from at most 32 recently modified local JSONL rollouts. Discovery is capped at 20,000 files. It uses token_count rate_limits metadata and the actual window_minutes, percentage and reset fields. It does not open auth.json, use the Keychain, contact account APIs or infer a signed-in account identity. The UI describes the tool's last local report; switching accounts without a new report cannot identify a new account.

Claude Code sync is off until explicitly enabled from the connection sheet. The sheet explains its change to ~/.claude/settings.json. The command forwards existing status-line output and captures the documented rate_limits.five_hour / seven_day metadata. Its numeric cache is ~/Library/Application Support/ShowMac/ClaudeQuota/quota.json (0600). The original statusLine configuration, including its command, is separately saved as original-statusline.json (0600) for restoration. No other settings are copied into that restoration record. Conversation input is processed in memory and never written to the allowance cache. The inherited original command retains its previous behavior. Unknown settings formats and configurations changed by other tools are preserved instead of overwritten.

Without a readable local quota source, a tool's token history still works but account allowance is unavailable. Codex and opt-in Claude Code quota are supported in this version; 60-source history support does not imply all 60 services expose a local account allowance.

## Display units (1.18.18)

Chinese compact totals use 万 / 百万 / 千万 / 亿 / 万亿 (Traditional Chinese equivalents when selected), consistently in cards, menu bar components, the popover and tool totals. English keeps K/M/B. Precise sampled and model counts remain unabridged; only presentation changes, never accounting.

## Cache hit rate (1.18.20)

The summary card shows recorded cache-read tokens / input tokens for the selected tool and time range. Input already includes cache reads and cache writes; output is excluded. Aggregate counts first, then divide, rather than averaging per-event percentages. No input or inconsistent counters show unavailable. Hover to inspect the exact numerator and denominator. Counts remain stored unchanged; sources that omit cache details cannot describe their actual caching performance.

## Agent statistics

Use the Agent selector to filter agents with locally recorded usage, or click an Agent statistics row. Click the selected row again to show all agents. Cards, trends, models and agent rows share the selected date range and agent filter. Sort the list by total tokens, input, output, cache hit rate or name, then use the arrow button to reverse the direction. Missing cache hit rates remain last; all model records for one agent are combined before the rate is calculated. The list scrolls to expose every recorded agent, without a top-six cutoff. All 60 supported source adapters remain available in data sources.

## Model total display

By model uses the shared localized compact formatter, matching summary cards and agent rows: English K/M/B from 1,000; Chinese 万 / 百万 / 千万 / 亿 / 万亿 from 10,000, with Traditional Chinese equivalents where selected. Hover a model total to inspect its exact localized count; accessibility also retains the exact count. Raw records and exports are unchanged.
