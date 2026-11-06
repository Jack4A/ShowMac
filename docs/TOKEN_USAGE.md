# Local token usage

Usage statistics combines electricity and AI token counts. Day/week/month/year ranges use the current system time zone. The homepage card is a compact entry point.

## Supported sources

- Codex: `$CODEX_HOME/sessions` and `archived_sessions`, defaulting to `~/.codex`.
- Claude Code: `$CLAUDE_CONFIG_DIR/projects`, defaulting to `~/.claude/projects`, plus `~/.config/claude/projects`.
- Choose custom directories or pause scans under **Sources and counting method**. GUI apps may not inherit shell environment variables; the folder picker handles those installations.
- Only retained JSONL usage metadata is counted. Web chats, other devices, unsupported tools and deleted/missing logs are outside coverage. Totals are local observations, not account quota or subscription/API invoices. No model pricing is inferred.

## Counting

Input includes cached input. Output includes reasoning output. Total is input plus output, with no additional cache/reasoning addition. Claude's ordinary input, cache read and cache creation categories are combined into input; Codex input already includes its cache categories.

Codex request records use response identities; matching thread cumulative snapshots are not counted again. Older cumulative counters use deltas, repeated snapshots are ignored, and resets start a new counter epoch. First observed records prefer recorded last-request usage rather than manufacturing missing earlier requests. Identifiable fork counter prefixes are excluded using parent history; unresolved fork counters are excluded with partial-coverage status. Explicit request identities also deduplicate mirrored records across files. Unknown models remain unknown.

Claude assistant records use request/message identities. Streaming revisions retain maximum observed counters for that request. Explicit unfinished zero-output proxy records without cache counters are excluded. Missing or invalid data does not become an invented request.

## Storage and performance

The scanner runs on a serial utility queue about once per minute and on manual refresh. It reads bounded chunks, commits only complete JSONL lines, checks file fingerprints/inodes/size/mtime and reuses unchanged files. Partial trailing lines are retried; rewrites/truncation are reparsed. Large irrelevant transcript lines are skipped without keeping their content. Unreadable or ambiguous usage produces a coverage warning.

`~/Library/Application Support/ShowMac/token-usage-cache.json` stores only numeric usage, timestamps, model/session/request identities, hashes and byte offsets. It is private to the user and atomically replaced. Invalid caches are preserved; parsing can recover from original logs without overwriting a damaged cache. No transcript text or credentials are cached. Original logs are read-only. This feature makes no AI-provider network requests.

## Research references

Reviewed upstream local-log counting approaches and edge cases before writing ShowMac's own Swift implementation:

- [ccusage](https://github.com/ccusage/ccusage), MIT, reviewed commit `2c92293e0a1d6a395c6a10a23267855e3205a1a6`: local source discovery, cumulative counters, cache categories and fork replay.
- [CodexBar](https://github.com/steipete/CodexBar), MIT, reviewed commit `49ccb08a17dae1ffdf8528135d2209e1e87fc6eb`: request identity reconciliation, incomplete records and separating local token history from account quota/bills.

Neither project is bundled or required at runtime. Fixtures cover numeric validation, cache normalization, streaming revisions, cumulative/request reconciliation, fork replay, counter resets, period boundaries, incremental partial lines, truncation/deletion and damaged cache preservation. UI previews use isolated sample data rather than private conversation logs.
