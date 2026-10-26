# Development

## Requirements

- macOS 15 or later to run; macOS 26 with **Xcode 26** to build (the package
  uses Swift tools 6.2).
- Apple silicon. Releases are built for arm64.
- No other dependencies. There is no Xcode project: everything is one Swift
  package.

## Build, test, check

```bash
swift build
swift test
swift format lint --strict --recursive Sources Tests
scripts/check-architecture.sh
```

All four must pass before every commit; CI (`.github/workflows/ci.yml`) runs
exactly these on every push and pull request to `main`. Warnings are errors.
Tests never read the real `~/.claude`: every test that touches harness files
is handed a temporary folder.

`scripts/check-architecture.sh` enforces what the compiler cannot: import
direction between modules, the 300-line file limit, no color or font literals
outside the Theme, pure analyzers, no timers in the UI, no concurrency escape
hatches, no TODOs, no em-dashes. The full list is in
[ARCHITECTURE.md](ARCHITECTURE.md#rules-enforced-by-scriptscheck-architecturesh).

## The app bundle

```bash
scripts/bundle.sh            # release build into build/ctxscope.app
scripts/bundle.sh debug      # debug build
open build/ctxscope.app
```

`bundle.sh` builds the `ctxscope` product, copies the resource bundles (the
themes) into `Contents/Resources`, compiles the app icon from
`Resources/Assets.xcassets` with `actool`, writes `Info.plist` (bundle id, the
`ctxscope://` URL scheme, `LSUIElement` so it runs as a menu bar app) and signs
ad hoc, so it launches on the machine that built it. The version lives only in
`bundle.sh` (`CFBundleShortVersionString`, `CFBundleVersion`).

`build/ctxscope.app/Contents/MacOS/ctxscope --window` starts with the window
open.

## The command line

```bash
swift build -c release
.build/release/ctxscope-cli help
```

| Command | What it does |
|---|---|
| `sessions [--limit N] [--project TEXT]` | Sessions on this machine, newest first |
| `analyze <session> [--lane ID] [--at REQUEST] [--json]` | Composition, cache, cost, reused share and the largest unused blocks at a request (counted from one) |
| `validate <session> [--lane ID] [--json]` | Checks that block sizes sum to the API totals on every request, and reports the estimator residual |
| `export <session> --format json\|csv [--lane ID] [--out PATH]` | The recording and its metrics |
| `calibrate [--limit N]` | Refits the estimator prior from local sessions |
| `bench [--requests N] [--window N] [--capture-requests N]` | Times the analyzers on a synthetic recording of a given scale |
| `connect [--port N] [--yes]` | Adds the hooks and the `/ctxscope` skill after showing the diff |
| `disconnect [--yes]` | Takes them out again after showing the diff |
| `doctor` | Reports the settings file, the hooks and their port, the listener, the skill and the URL scheme; never writes |
| `demo --home DIR [--live SECONDS] [--start TIME]` | Writes the made-up demo session into `DIR/.claude/projects` |

Common options: `--window N` to measure fill against a known window,
`--no-subagents` for the main lane only. A session can be named by a unique
prefix of its id.

`connect` and `disconnect` accept `--claude-home DIR` to work on a temporary
folder instead of `~/.claude`. Use it for anything that is not a deliberate
change to your own setup.

## The snapshot tool

`ctxscope-snapshots` renders sample screens and the views to PNG, in light
and dark, without a window server session or screen capture permission:

```bash
swift run ctxscope-snapshots --out artifacts            # every view
swift run ctxscope-snapshots --samples --out artifacts  # the sample screens, into artifacts/samples
```

Use it to look at UI changes. The sample screens are filled with made-up
values, which is what the pictures in the README are made from. `--session <id> [--page context|timeline]`
renders a real session's pages; those images contain transcript text, so
write them outside the repository and never commit them. `artifacts/` is not
for committing either.

## Integration checks

None of them touches `~/.claude`. The two hook checks launch a bundled build
and refuse to run while any ctxscope is up.

| Script | What it checks |
|---|---|
| `scripts/connect-cli.sh` | `ctxscope-cli connect`, `doctor` and `disconnect` against a temporary home |
| `scripts/hook-roundtrip.sh` | hook payloads posted to the app's listener, and the `/ctxscope` URL, end to end, without touching any settings file |
| `scripts/wake-timing.sh` | how long the session start hook's command takes, with ctxscope running and not |

## The demo session

A session in which every word is made up, for screenshots and screen
recordings where nothing private can appear:

```bash
scripts/bundle.sh                    # once
scripts/demo.sh --focus              # the finished session, focused
scripts/demo.sh --focus --live 60    # the same, growing over a minute
```

`demo.sh` refuses to start while ctxscope is running, creates a fresh
temporary home with `mktemp -d`, refuses any path that is or contains the real
home, writes the session with `ctxscope-cli demo`, and starts the app with
`CFFIXED_USER_HOME` pointing at that home. The app then reads only the demo's
`~/.claude`, and keeps its focus and power state in a separate defaults suite,
so your own settings are untouched.

The story: a session called "retry-policy" in `~/code/api-client`, 87
requests over 9 prompts, two subagent lanes, and three cache breaks (a
CLAUDE.md edit, a pause long enough for the cache to expire, and an MCP server
connecting). Usage is computed from the adapter's own estimator, so every lane
passes `validate`. `DemoTests` reads it back through the adapter and checks it.

## Releases

1. Set `CFBundleShortVersionString` (and bump `CFBundleVersion`) in
   `scripts/bundle.sh` and commit.
2. Rehearse locally: `scripts/release.sh 0.2` bundles, fails unless the bundle
   says 0.2, verifies the signature, starts a copy of the bundle once with the
   build folder out of the way (`--print-themes`, so the themes must come from
   the bundle itself), and writes `build/ctxscope-0.2.zip`, its `.sha256` and
   `build/release-notes.md` (install notes plus the commits since the previous
   tag).
3. Tag and push: `git tag v0.2 && git push origin v0.2`.
   `.github/workflows/release.yml` runs the same script on a `macos-26` runner
   and creates the GitHub release with the zip, the checksum and the notes.

The app is ad hoc signed, arm64 only, and not notarized. Developer ID
signing, notarization (`xcrun notarytool submit --wait`, then
`xcrun stapler staple`) and a universal binary would go into
`scripts/release.sh` between the bundle step and the zip, with the certificate
and notary credentials stored as repository secrets and imported into a
temporary keychain in the workflow.

## Privacy rules for contributors

- `~/.claude/projects` is read-only input. Nothing in ctxscope, its tests or
  its scripts writes there.
- Never copy real transcript text into the repository, an issue, a pull
  request, a commit message or a log. That includes screenshots of real
  sessions.
- Test fixtures are made only with the sanitizer:

  ```bash
  scripts/sanitize-transcript.py INPUT OUTPUT [--tail N]
  ```

  It keeps structure exactly (entry order, parent links, request grouping,
  usage numbers, attachment types, block shapes and every text length),
  replaces text with filler derived from a hash, remaps every identifier, and
  shifts timestamps. Fixtures live in `Tests/ScopeCaptureTests/Fixtures`.
- Only Connect (the panel, or `ctxscope-cli connect` and `disconnect`) writes
  to `~/.claude`, and only when a person asks. Tests and scripts use a
  temporary home.
- No network calls, no telemetry. The only socket is the hook listener on
  127.0.0.1.
