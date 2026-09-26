# Contributing to ctxscope

Thanks for taking a look. Bug reports, ideas and pull requests are all
welcome, and adapters for other harnesses most of all.

## Build and check

You need macOS 26 with Xcode 26 on Apple silicon.

```bash
swift build
swift test
swift format lint --strict --recursive Sources Tests
scripts/check-architecture.sh
scripts/bundle.sh && open build/ctxscope.app
```

The four checks must pass before a pull request can be merged; CI runs the
same ones. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers the CLI, the
snapshot tool, the demo session and releases.
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the pieces fit.

## Code rules

Most of these are enforced by `scripts/check-architecture.sh`.

- **Dependencies point one way**: ScopeCore, then ScopeCapture, then ScopeUI,
  then the app. ScopeConnect depends on nothing. ScopeCore imports Foundation
  only. No third-party packages.
- **The UI never parses harness data, adapters never compute metrics,
  analyzers are pure** and never touch files, the clock or the network.
- **One source of truth each**: bands and kinds (`BandRegistry`), the token
  estimator, the `UseJudge` protocol, prices, number formatting, the `Theme`.
  If you need something twice, move it to the module that owns it.
- **No color or font literals outside the Theme.** Views ask for roles from
  `Theme`, `Typography` and `Metrics`.
- **No file over 300 lines, no type with two jobs, no copy-pasted logic.**
- **No dead code, no commented-out code, no TODOs.** Finish it, or open an
  issue.
- **No timers or repeating animations** in the UI: the app does nothing while
  nothing changes.
- **Plain, neutral UI words**: size, reused, unused, carried, zone, and
  "block" for what the code calls a segment. No judgments, no metaphors, no
  em-dashes.
- Match the naming and comment density of the code around you. Small commits,
  one logical change each.

## Adding a harness adapter

Capture sits behind one protocol in `Sources/ScopeCapture/HarnessAdapter.swift`:

```swift
public protocol HarnessAdapter: Sendable {
  var name: String { get }
  func sessions(reusing known: [String: SessionRef]) throws -> [SessionRef]
  func capture(_ session: SessionRef, includeSubagents: Bool) throws -> CapturedSession
}
```

An adapter lists the sessions it can find and turns one into a `Recording`
(lanes of snapshots and segments, see
[ARCHITECTURE.md](docs/ARCHITECTURE.md#data-model)). It maps the harness's
content onto the existing bands, takes request totals from whatever the
harness reports as measured usage, and sizes blocks with the shared estimator
and `SegmentSizer`, so that segment sizes sum to the measured totals. It never
computes metrics: every analyzer and view then works unchanged.
`ClaudeCodeAdapter` is the reference. Add sanitized fixtures and tests for the
new format under `Tests/`.

## Privacy

- Transcripts are read-only input. Never copy real transcript text, or
  screenshots of real sessions, into the repository, an issue, a pull request
  or a commit message.
- Fixtures are made only with `scripts/sanitize-transcript.py`, which keeps
  structure and lengths and replaces all text and identifiers.
- Tests and scripts use a temporary home and never write to `~/.claude`.
- No network calls, no telemetry.

## License

ctxscope is licensed under the
[GNU General Public License, version 3](LICENSE). By contributing, you agree
that your contributions are licensed under the same terms.
