# ctxscope: rules for AI agents contributing here

Read `docs/ARCHITECTURE.md` and `docs/HOW_IT_MEASURES.md` before touching
code. `docs/DEVELOPMENT.md` has the commands, `docs/TRANSCRIPT_FORMAT.md` the
input format.

## Architecture (enforced by `scripts/check-architecture.sh`)

- One Swift package, Swift 6 language mode, strict concurrency, macOS 15+.
- Dependencies point one way: ScopeCore <- ScopeCapture <- ScopeUI <- app.
  ScopeConnect depends on no other module. ScopeCore imports Foundation only.
  No third-party packages.
- The UI never parses harness data. Adapters never compute metrics.
  Analyzers are pure functions and never touch files.
- One source of truth each: bands and kinds (`BandRegistry`), the token
  estimator, the `UseJudge` protocol, prices, number formatting, the `Theme`.
- Views contain no color literals and no font literals: everything comes
  from `Theme`, `Typography` and `Metrics`.
- No timers, polling or repeating animations in ScopeUI or the app.
- No file over 300 lines. No type with two jobs. No copy-pasted logic. If
  you need something twice, move it to the module that owns it.
- No dead code, no commented-out code, no TODOs left behind: finish it or
  describe it in the pull request.

## Testing

- `swift build` and `swift test` must pass before every commit.
- `swift format lint --strict --recursive Sources Tests` must be clean.
- `scripts/check-architecture.sh` must pass.
- Analyzers are tested against sanitized fixtures in
  `Tests/ScopeCaptureTests/Fixtures` and synthetic lanes.
- Never claim something works without running it. Include the commands you
  ran and their results in your summary or pull request.

## Privacy and safety

- `~/.claude/projects` is read-only input. Never copy real transcript text
  into the repo, commit messages, logs, issues or pull requests. Fixtures are
  produced by `scripts/sanitize-transcript.py` (structure and lengths kept,
  text replaced).
- Only the Connect panel and `ctxscope-cli connect` and `disconnect`, run by
  a person on purpose, write to `~/.claude`. Agents and tests use a temporary
  home (`--claude-home`, `--home`) and never touch anything else outside the
  repo.
- No network calls, no paid API calls, no telemetry.

## Writing

- Never use em-dashes, anywhere: code comments, docs, commit messages, UI.
- UI language is plain and neutral: size, reused, unused, carried, zone, and
  "block" for what the code calls a segment. No judgments, no metaphors.
  ScopeCore keeps "referenced" internally.
- Match comment density and naming of the surrounding code.

## Git

- Small commits: one logical change each, commit as soon as it works.
- Work on a branch and open a pull request against `main`.
