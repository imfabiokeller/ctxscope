# Architecture

How ctxscope is put together: the modules, the data model, the analyzers,
Connect, the menu bar item and the design system. For what the numbers mean
and how far to trust them, see [HOW_IT_MEASURES.md](HOW_IT_MEASURES.md). For
what the transcripts contain, see [TRANSCRIPT_FORMAT.md](TRANSCRIPT_FORMAT.md).

## Modules

One Swift package (Swift 6 language mode, strict concurrency, macOS 15+, no
third-party dependencies). Dependencies point one way, and the composition
happens in the executables.

```
ScopeCore            domain types, estimator, use judge, pure analyzers
   ^                 imports Foundation only
ScopeCapture         HarnessAdapter protocol, Claude Code adapter,
   ^                 session discovery, reading text back from transcripts
   |
   |   ScopeConnect  settings edits, hook listener, ctxscope:// URLs
   |      ^          depends on no other module
   |      |
ScopeUI              Theme, components, view models, views (SwiftUI only)
   ^
ctxscope             the app: composition root, menu bar item, panel,
                     window shell (the only place AppKit is used)

ctxscope-cli         ScopeCore + ScopeCapture + ScopeConnect, no UI
ctxscope-snapshots   ScopeUI rendered to PNG, no window server needed
```

| Module | Job |
|---|---|
| `ScopeCore` | Bands, kinds and families (`BandRegistry`), grades, segments, snapshots, lanes, recordings, the token estimator and its calibration, the `UseJudge` protocol and `LexicalJudge`, every analyzer, prices, number formatting (`TokenFormat`), validation. Never touches files, the clock, the network or another process. |
| `ScopeCapture` | Streaming JSONL reading, `ClaudeCodeAdapter` (transcript to `Recording`, with subagent lanes), `SessionDiscovery`, typed prompt detection, and reading a block's text or a short description of it back out of the transcript on demand. Measures nothing itself. |
| `ScopeConnect` | Byte-exact edits to `~/.claude/settings.json`, the `/ctxscope` skill, the loopback hook listener, the `ctxscope://` scheme, `doctor`. |
| `ScopeUI` | The `Theme` and its JSON files, generic components, `InstrumentModel` and its analyses, presenters that turn analyses into plain view data, and the views. Speaks SwiftUI only. |
| `ctxscope` | `AppDelegate`, the status item and its panel, window controllers, the global hotkey, stored focus and power state. |
| `ctxscope-cli` | `sessions`, `analyze`, `validate`, `export`, `calibrate`, `bench`, `connect`, `disconnect`, `doctor`, `demo`. Calls the same analyzers as the app. |
| `ctxscope-snapshots` | Renders sample screens and the views to PNG, in both themes. |

Three rules hold the layers apart: the UI never parses harness data, adapters
never compute metrics, and analyzers are pure functions of a recording.

## Data model

| Term | Meaning |
|---|---|
| Recording | The immutable result of reading one session: a list of lanes. All analysis is a pure function of it. |
| Lane | One agent's recording. A session has a main lane plus one lane per subagent (`agentType`, `parentToolUseID`). |
| Snapshot | One request, the unit of time: index, `requestId`, timestamp, model, the API's `usage`, the request it continued from, and the estimator residual. |
| Segment | The smallest addressable piece of context: one system block, one tool definition, one memory file, one message content block, one tool result. The UI calls it a **block**. A segment has a band, a neutral label (never content), a size in tokens with a grade, a character count, a content class, the request it entered at (`born`) and the one it left at (`died`, with a cause). |
| Event | Something that happened to a lane's context: compaction, model switch, cache break, subagent return, inferred retirement. |

### Bands, families and kinds

Bands are ordered by prompt position, which is also cache stability: the
stable prefix first, the volatile tail last. The list lives only in
`ScopeCore/Bands.swift`.

| Band | Family | Kind shown in the UI | Contents |
|---|---|---|---|
| `sys` | prefix | system | System prompt blocks |
| `tools` | prefix | tools | Built-in tool definitions, one block per tool |
| `mcp` | prefix | tools | MCP tool definitions, one block per tool |
| `mem` | prefix | memory | Memory and instruction files (CLAUDE.md and friends) |
| `unattr` | unattributed | none | Tokens the measured totals contain and no recorded block accounts for |
| `user` | dialogue | you | Typed prompts, attachments, injected reminders |
| `asst` | dialogue | agent | Assistant text, compaction summaries |
| `think` | reasoning | agent | Thinking blocks while retained |
| `call` | reasoning | agent | Tool call inputs |
| `read` | results | results | File read results |
| `bash` | results | results | Shell output |
| `srch` | results | results | Search, grep, web and MCP results |
| `agent` | results | results | Subagent return values |

The window uses the six kinds (system, tools, memory, you, agent, results) in
reading order for its legend, its colors and its filters. Unattributed tokens
have no kind and are drawn as an untyped remainder.

### Grades and the "~"

Every token count carries a grade (`Tokens`, `Grade`):

| Grade | Meaning |
|---|---|
| measured | Reported by the API in `usage` |
| derived | Arithmetic on measured values, such as the difference between two request totals |
| estimated | From the local estimator, a judge, or the harness's own `/context` report |

Adding two counts keeps the weaker grade. The UI prints estimated values with
a leading `~` and measured or derived values with nothing; one tooltip
explains the `~`.

## Capture

`ClaudeCodeAdapter` reads `~/.claude/projects/<slug>/<session>.jsonl` and the
lane files under `<session>/subagents/`. It is incremental: a growing file
costs only its new lines.

- The conversation is a tree (`uuid`, `parentUuid`). The context of a request
  is the chain from its assistant entry to the root, plus the results of
  every tool call on that chain (`ChainExpansion`), since parallel results
  hang off the chain.
- Usage is counted once per `requestId`, never per entry.
- The prefix (system prompt, tool definitions, memory) is derived at the
  first request and split into blocks by the best evidence the lane has; see
  [HOW_IT_MEASURES.md](HOW_IT_MEASURES.md).
- When the measured total drops with nothing in the transcript to explain it,
  `LaneBuilder.retire` decides which blocks left and grades those exits
  `inferred`.
- A block's text is never kept in the recording. Content is turned into
  hashed word shingles for the judge on the way past, and the reader reads the
  text back from the transcript by byte range when asked.

### Estimator and normalization

`EstimatorRates` holds characters per token per content class (prose, code,
JSON, image base64), a fixed cost per content block, and a per-request framing
term for what the harness injects and never writes down. `EstimatorCalibration`
refits the rates per lane against derived deltas (ridge toward the prior,
clamped to a factor of three). `ctxscope-cli calibrate` pools fits across
sessions to reproduce the prior.

`SegmentSizer` sizes every block once, when it enters:

1. Groups with a measured total (the blocks of one response against
   `output_tokens`, a thinking block against `thinking_tokens`) share that
   total.
2. Everything else is estimated from its text.
3. The estimates are scaled so the live blocks sum to the measured request
   total. `Normalizer.allocate` does this with the largest-remainder method,
   so the parts are integers that add up exactly.

Because sizes are fixed at entry and each request only adds what entered, the
live blocks sum to the API's total at every request by construction.
`ctxscope-cli validate` checks it.

## Analyzers

All in `ScopeCore/Analyzers` (plus `ReadingOrder` and `LexicalJudge`), pure,
tested against fixtures and synthetic lanes.

| Analyzer | What it answers |
|---|---|
| `CostAnalyzer` | Exact cost per request and cumulative: cache read, cache write and uncached input at their prices, plus output. The extra a cache break added (rewritten tokens at write minus read price). |
| `Prices` / `PriceTable` | Dollars per million tokens for cache write, cache read, input and output, matched on the model id prefix, with one fallback. The only place a price is written. |
| `CacheAnalyzer` | Per request hit rate, and cache breaks: a request whose cache read fell below what its parent had cached. Each break carries the parent request, the gap in seconds, the rewritten tokens, which kind was still read (`readThrough`), and a cause. |
| `CacheBreak` | The prefix change behind a break: the first prefix block, in reading order, that entered or left at that request, the blocks added and removed, and the MCP servers involved. |
| `SegmentCacheAnalyzer` | Per block and request: read from the cache, written to it, or uncached, and how often it has been written. |
| `BlockCostAnalyzer` | Cost so far per block: the request's exact cost attributed by size, at the write price where the block was written and the read price where it was read. |
| `LexicalJudge` / `UseJudge` | Reuse: which five-word shingles of a block appear again in later output or tool inputs, and at which request. Indexed and incremental, never pairwise. Boilerplate shingles are dropped. A tool definition is judged by whether its tool was called. |
| `UseAnalyzer` (`BlockUse`) | Per block at a request: used, unused or not tracked; for tools, called or never called. The unused summary: tokens, share of context, cost so far. |
| `ReferenceAnalyzer` | Reused share of the context, the ratio over assessable tokens with a 90% interval, and the share by position (first, middle, last third). |
| `PromptAnalyzer` | Tasks: from one typed prompt to the next, with requests, context at start and end, cost, cache breaks and the largest block added. |
| `ReadingOrder` | Every block in the order the model reads it, with its offset at any request, the cache boundary and the end of the prefix. The context strip and every timeline column draw from this, one slice per block. |
| `ToolGroupAnalyzer` | Tool definitions grouped by server: built-in first, then one group per MCP server, with size and how many were called. |
| `CarryCostAnalyzer` | Tokens times requests carried per block, how many requests a block has been in, and the ranked list of the largest unused blocks. |
| `CompactionAnalyzer` | What each compaction dropped and kept, against what the harness recorded. |
| `DuplicationAnalyzer` | Blocks with identical content live at the same time. |
| `LengthZones` | Five absolute length steps (50k, 120k, 200k, 500k) per model, one default scale. |
| `Validator` | The checks behind `validate`: totals exact on every request, no negative sizes, estimator residual, comparison with a `/context` report when one exists. |

`ScopeUI/Model/LaneAnalysis` runs these once per change of the lane, and
`PlayheadFigures` holds the figures at the selected request. Presenters
(`ContextPresenter`, `TimelinePresenter`, `PopoverPresenter`,
`HeaderPresenter`) turn them into plain values; views only draw.

## Connect

Connect is optional: past sessions can always be opened without it. It is
done from the menu bar panel (**… > Connect**) or `ctxscope-cli connect`, and
it writes two hook entries into `~/.claude/settings.json` plus one skill.

| Piece | What it is |
|---|---|
| `SessionStart` command hook | `open -g ctxscope://wake --args --woken \|\| true`, async, matcher `startup\|resume\|clear\|fork`. Starts ctxscope in the background when a session starts. It never turns on an instrument that was turned off, and it skips compactions. |
| `SessionEnd` HTTP hook | Posts to `http://127.0.0.1:<port>/ctxscope/hook` with a 1 second timeout, so a session that ends is marked ended at once instead of after the idle window. |
| `~/.claude/skills/ctxscope/SKILL.md` | Makes `/ctxscope` open `ctxscope://show?session=${CLAUDE_SESSION_ID}`, which focuses that session and opens the window. `disable-model-invocation: true`, `allowed-tools: Bash(open *)`. |

How it stays safe:

- Every write is planned first and the plan carries the exact diff, shown
  before anything is written. The file is read again before the write; if it
  changed, the plan is worked out again rather than applied.
- `WriteGuard` refuses files it cannot edit safely (not JSON, not an object,
  a key written twice, bytes Foundation would not accept), and checks before
  writing that the result parses and that removing ctxscope's entries again
  gives back exactly the bytes that were there before.
- Edits are text splices (`JSONSpan`, `JSONEdit`, `SourceText`) that follow
  the file's own indentation and line endings, so nothing else in the file
  moves.
- The original file is kept as `settings.json.ctxscope-backup` on the first
  connect. Disconnect restores the file byte for byte when nothing else
  changed it, and otherwise removes exactly the spans ctxscope added.
- A hand-edited `SKILL.md` is left alone. `disableAllHooks` and an
  `allowedHttpHookUrls` list without ctxscope's URL are reported, never
  changed.

The listener (`HookListener`) binds 127.0.0.1 only, on port 45871 or one of
the next eight, preferring the port already in the settings file. It answers
on its own queue before any work, so a hook never waits for the UI. When
ctxscope is not running, the connection is refused at once, which Claude Code
treats as a non-blocking error.

`ctxscope-cli doctor` reports what is in place and never writes.

## Liveness and focus

- **Focus.** Exactly one session is shown. It is set by `/ctxscope` in a chat
  or by the window's session menu, and nothing else. Focus is kept across
  launches in ctxscope's own defaults (`FocusStore`). An id this machine does
  not have triggers a rescan and replaces the focus only if the scan finds
  it. `ctxscope://show` without an id takes the most recently written session,
  once.
- **Watching.** Only the focused session is watched, with file system events
  and no timers (`SessionWatcher`): its transcript, its subagent lane files and
  the directories they sit in. A subagent lane gaining requests counts as the
  session working. A renamed or deleted transcript is dropped and looked for
  again.
- **Liveness.** A session is live while it was written in the last 180
  seconds (`Liveness`), dropped by one cancellable wait re-armed on each
  write, or at once when `SessionEnd` arrives.
- **Power.** Off means the menu bar item is gone and nothing is read; the
  listener keeps answering. Opening the app or `/ctxscope` turns it on; a
  session starting never does (`PowerStore`).

## Menu bar item and panel

The status item is a 16 pt glyph plus the context size ("143k"), in the
system menu bar font with tabular digits, always a template image so it
follows the bar's own appearance. The glyph is a track filled up to the
window's fill, with a cursor at the fill on half points (`StatusGlyph`). A live
session puts a dot on the cursor, a cache break on the newest request splits
the cursor in two, and an idle session dims the whole glyph and drops the
number. With nothing in focus it is the empty track, dimmed. It has an accessibility name and value in every state. One short
cross-fade when the picture changes, none under Reduce Motion, nothing while
idle.

A click opens a non-activating panel under the item (`StatusPanel`,
`PanelPlacement`): the session, its lane and Live, size and fill, the kind
meter, this request, session so far, carried and unused, the last cache break,
and the context of every request against the window. Buttons: Open window,
Change session, and More (Connect, Turn off, Quit). With nothing focused it
shows the `/ctxscope` command and the recent sessions. It closes on escape,
on an outside click and when the app deactivates. Control-option-command-C
opens the window.

## Window

`InstrumentView` is a header (session menu, lane menu, page picker, request
stepper, Live pill) over one of two pages:

- **Context**: four figures, the strip (one slice per block in reading order,
  with the "sent with every request" and cache brackets and a magnifier on
  hover), the blocks table, and the inspector with the block's origin, facts
  and text.
- **Timeline**: one column per request with every block as a slice, prompt
  bands above, cost per request below, cache breaks marked, and a by-prompt
  table. Columns are drawn once into an image off the main actor
  (`DrawingCache`); hover and click use arithmetic and binary search.

## Design system

- **Theme as data.** Colors live in `Sources/ScopeUI/Resources/Themes/light.json`
  and `dark.json`, decoded into `Theme` and chosen by the system appearance
  (`ThemeStore`). Colors can be written as `#RRGGBB`, `rgba()` or `oklch()`,
  converted to display colors in one place (`ThemeColor`).
- **Roles, not values.** Groups: `surface`, `line`, `text`, `control`,
  `status`, `shadow`, `kind` (the six kind colors), `chart` and `chrome` (the
  window frame drawn only by the snapshots). Views ask for a role, never a
  color.
- **Type and sizes in code.** `Typography` (`theme.type`) defines every text
  role on SF Pro and SF Mono with tabular digits; `Metrics` (`theme.metrics`)
  holds sizes that do not change with appearance.
- **Components.** `Sources/ScopeUI/Components` holds generic, previewable
  pieces that know nothing of sessions: cards, fact tiles, swatches, the
  segmented picker, pop-up and push buttons, the request stepper, the search
  field, `DataTable`, `CodeBlock`, the magnifier rows, the kind meter. Native
  controls are used wherever possible.
- `DesignTokenTests` holds every text role to 4.5:1 contrast on the surfaces
  it is used on, in both appearances.

## Rules enforced by `scripts/check-architecture.sh`

The script runs in CI next to build, test and lint, and fails on:

1. An import against the arrows. Each module has an allow list; a new
   module directory must be declared before it can import anything.
   `@_exported` imports are refused.
2. Any Swift file over 300 lines.
3. The `Band` enum declared anywhere but `ScopeCore/Bands.swift`.
4. ScopeCore reaching outside itself: `FileManager`, `URLSession`,
   `Process`, `Date()`, `ProcessInfo`, file reads, `print`.
5. `TODO`, `FIXME` or `XXX` in sources or tests.
6. An em-dash in sources, tests, docs, scripts or the top-level docs.
7. A color or font literal anywhere in ScopeUI outside `Theme/`, or in the
   app and snapshot targets. A `ThemeColor` or `OKLCH` built outside `Theme/`.
8. A view reading files, parsing JSON, using timers or opening dialogs.
9. Timers, display links, repeating animations, or sleeping or clock-waiting
   loops in ScopeUI or the app (the idle budget).
10. AppKit types in ScopeUI.
11. `@preconcurrency`, `@unchecked Sendable`, `nonisolated(unsafe)`,
    `assumeIsolated`, and `unsafeFlags` in the manifest.
12. `Package.swift` no longer treating warnings as errors.
