#!/bin/bash
# Enforces the architecture rules (docs/ARCHITECTURE.md) that a compiler cannot:
# import direction, file length, and the single sources of truth.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
report() {
  fail=1
  echo "FAIL: $1"
}

# 1. Import direction. Each module may import only the ones below it, and a
# module nobody listed may import nothing at all, so a new directory has to be
# declared here before it can depend on anything.
allowed_ScopeCore="Foundation"
allowed_ScopeCapture="Foundation ScopeCore"
allowed_ScopeConnect="Foundation Network Dispatch Darwin CoreServices"
allowed_ScopeUI="Foundation SwiftUI CoreGraphics Observation Dispatch Darwin ScopeCore ScopeCapture ScopeConnect"
allowed_ctxscope="Foundation SwiftUI AppKit Carbon Combine Observation ScopeCore ScopeCapture ScopeConnect ScopeUI"
allowed_ctxscope_snapshots="Foundation SwiftUI AppKit CoreGraphics ScopeCore ScopeCapture ScopeConnect ScopeUI"
allowed_ctxscope_cli="Foundation Dispatch ScopeCore ScopeCapture ScopeConnect"
allowed_Tests="Foundation Testing SwiftUI CoreGraphics AppKit Carbon Network ScopeCore ScopeCapture ScopeConnect ScopeUI ctxscope ctxscope_cli"

check_imports() {
  local dir="$1" allowed="$2" module
  module="$(basename "$dir")"
  [ -d "$dir" ] || return 0
  while IFS= read -r line; do
    local file rest
    file="${line%%:*}"
    rest="${line#*:}"
    # Several imports on one line are several imports.
    echo "$rest" | tr ';' '\n' | while IFS= read -r piece; do
      case "$piece" in
        *import*) ;;
        *) continue ;;
      esac
      name="$(echo "$piece" | sed -E 's/.*import +([A-Za-z_][A-Za-z0-9_.]*).*/\1/' | cut -d. -f1)"
      [ -n "$name" ] || continue
      case " $allowed " in
        *" $name "*) ;;
        *) echo "FAIL: $file imports $name, which $module may not import" ;;
      esac
    done
  done < <(grep -rEn '^[[:space:]]*(@[A-Za-z_]+ +)*(public |internal |package |fileprivate |private )?import ' "$dir" --include='*.swift' | sed -E 's/^([^:]+):[0-9]+:/\1:/') > "$violations"

  if [ -s "$violations" ]; then
    while IFS= read -r line; do
      fail=1
      echo "$line"
    done < "$violations"
  fi
  : > "$violations"
}

violations="$(mktemp)"

check_imports Sources/ScopeCore "$allowed_ScopeCore"
check_imports Sources/ScopeCapture "$allowed_ScopeCapture"
check_imports Sources/ScopeConnect "$allowed_ScopeConnect"
check_imports Sources/ScopeUI "$allowed_ScopeUI"
check_imports Sources/ctxscope-cli "$allowed_ctxscope_cli"
check_imports Sources/ctxscope "$allowed_ctxscope"
check_imports Sources/ctxscope-snapshots "$allowed_ctxscope_snapshots"
check_imports Tests "$allowed_Tests"

# Default deny: a module directory nobody declared above may import nothing,
# so adding one without declaring it fails rather than passing silently.
declared="ScopeCore ScopeCapture ScopeConnect ScopeUI ctxscope ctxscope-cli ctxscope-snapshots"
for dir in Sources/*/; do
  name="$(basename "$dir")"
  case " $declared " in
    *" $name "*) ;;
    *) report "Sources/$name has no declared import rule in $0" ;;
  esac
done

# An @_exported import smuggles a dependency through a module that is allowed
# to have it, which is exactly what the arrows are meant to prevent.
hits="$(grep -rn '@_exported' Sources Tests --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "@_exported import hides a dependency: $hits"
fi

# 2. No file over 300 lines.
while IFS= read -r file; do
  lines="$(wc -l < "$file" | tr -d ' ')"
  if [ "$lines" -gt 300 ]; then
    report "$file is $lines lines, the limit is 300"
  fi
done < <(find Sources Tests -name '*.swift' 2>/dev/null)

# 3. The band list lives only in BandRegistry.
hits="$(grep -rln 'case sys, tools, mcp\|enum Band' Sources --include='*.swift' | grep -v 'Sources/ScopeCore/Bands.swift' || true)"
if [ -n "$hits" ]; then
  report "the Band enum appears outside Sources/ScopeCore/Bands.swift: $hits"
fi

# 4. Analyzers stay pure: ScopeCore never touches the file system, the network,
# the clock, the environment, or another process.
impure='FileManager|URLSession|Process\(|Date\(\)|ProcessInfo|String\(contentsOf|Data\(contentsOf|FileHandle|DispatchTime|CFAbsoluteTime|readLine\(|print\('
hits="$(grep -rlnE "$impure" Sources/ScopeCore --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "ScopeCore reaches outside itself in: $hits"
fi

# 5. Nothing left behind.
hits="$(grep -rn 'TODO\|FIXME\|XXX' Sources Tests --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "unfinished markers: $hits"
fi

# 6. No em-dashes, anywhere in the repo's own text. The character is built
# with printf so this check does not match itself.
dash="$(printf '\xe2\x80\x94')"
hits="$(grep -rlF "$dash" Sources Tests docs scripts artifacts/README.md CLAUDE.md CONTRIBUTING.md \
  README.md .github 2>/dev/null || true)"
if [ -n "$hits" ]; then
  report "em-dash found in: $hits"
fi

# 7. No color and no font literal outside the Theme. Everything comes from it,
# which is the only way a theme can be swapped at runtime. The rule
# covers all of ScopeUI except its Theme folder, and both app targets: a model
# that names a color is no better than a view that does.
# Styles are often written over two lines, and a call whose argument is on the
# next line used to slip through every pattern below. Each file is therefore
# checked with its continuation lines joined onto the call that opened them.
joined="$(mktemp -d)"
trap 'rm -rf "$joined" "$violations"' EXIT
join_lines() {
  local file="$1" out
  out="$joined/$(echo "$file" | tr '/' '_')"
  perl -0pe 's/\(\s*\n\s*/(/g' "$file" > "$out"
  echo "$out"
}

literals='(^|[^A-Za-z0-9_])(Color|CGColor|NSColor|NSFont|Font) *(\(|\.init\()'
literals="$literals"'|(^|[^A-Za-z0-9_])(Color|NSColor|Font) *\.[a-z]'
literals="$literals"'|\.(foregroundStyle|foregroundColor|fill|background|backgroundStyle|tint'
literals="$literals"'|stroke|strokeBorder|shadow|border|overlay|underlay|glassEffect)\( *(color: *)?\.[a-z]'
literals="$literals"'|\.color\(\.|\.color\(white:|LinearGradient\(colors:|RadialGradient\(colors:'
literals="$literals"'|Font\.system|Font\.custom|\.system\(size:|\.font\(\.[a-z]|\.font\(Font\.|\.bold\(\)|\.fontWeight\('
# An AppKit font is a font literal too, whatever it is spelled after.
literals="$literals"'|NSFont\.[a-z]|systemFont\(ofSize: *[0-9]'
literals="$literals"'|#[0-9A-Fa-f]{3,8}([^0-9A-Fa-f]|$)|oklch\(|rgba?\([0-9]'
# The menu bar's type and its ink belong to the system, not to a theme: an
# item has to sit on the same baseline as every other one and invert with the
# bar. Naming one of the system's own roles is not naming a literal, and it is
# the only way to have what the system has.
system_owned='NSColor\.labelColor|NSFont\.systemFontSize|NSFont\.monospacedDigitSystemFont'
# A theme color or an OKLCH built anywhere but the Theme, however it is
# spelled, including a bare .init( that infers the type from the context.
built='(^|[^A-Za-z0-9_])(ThemeColor|OKLCH) *(\(|\.init\()'
built="$built"'|: *(ThemeColor|OKLCH) *= *\.init\(|return *\.init\('
for dir in Sources/ScopeUI Sources/ctxscope Sources/ctxscope-snapshots; do
  [ -d "$dir" ] || continue
  while IFS= read -r file; do
    # The Theme owns colors. Nothing else may name one.
    case "$file" in
      Sources/ScopeUI/Theme/*) continue ;;
    esac
    flat="$(join_lines "$file")"
    hits="$(grep -nE "$literals" "$flat" | grep -vE "$system_owned" || true)"
    if [ -n "$hits" ]; then
      report "a color or font literal outside the Theme: $file: $hits"
    fi
    hits="$(grep -nE "$built" "$flat" || true)"
    if [ -n "$hits" ]; then
      report "a ThemeColor or OKLCH built outside Sources/ScopeUI/Theme: $file: $hits"
    fi
  done < <(find "$dir" -name '*.swift')
done
# The rest of the package may not build one either.
hits="$(grep -rnE "$built" Sources/ScopeCore Sources/ScopeCapture Sources/ctxscope-cli \
  --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "a ThemeColor or OKLCH built outside Sources/ScopeUI/Theme: $hits"
fi

# A view draws. It does not read files, parse harness data, schedule timers or
# put up file dialogs, whatever its imports happen to allow.
forbidden='JSONSerialization|JSONDecoder|contentsOf|contentsOfFile|FileHandle|FileManager'
forbidden="$forbidden"'|Timer\.|NSSavePanel|NSOpenPanel|NSWorkspace|URLSession'
hits="$(grep -rnE "$forbidden" Sources/ScopeUI/Views --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "a view reaching outside itself: $hits"
fi

# Timers are the thing the idle budget forbids, in the UI and in the app that
# owns the menu bar item.
timers='Timer\.|CADisplayLink|DispatchSourceTimer|makeTimerSource|AsyncTimerSequence'
timers="$timers"'|TimelineView|repeatForever|asyncAfter'
# A repeating or self-driving animation spends the idle budget the same way a
# timer does, whatever the API is called this year.
timers="$timers"'|phaseAnimator|keyframeAnimator|symbolEffect|repeatCount|autoreverses'
for dir in Sources/ScopeUI Sources/ctxscope; do
  hits="$(grep -rnE "$timers" "$dir" --include='*.swift' || true)"
  if [ -n "$hits" ]; then
    report "a timer or a repeating animation, which the idle budget forbids: $hits"
  fi
done

# A loop that sleeps is a timer with extra steps, and it spends the idle
# budget the same way. Braces are counted rather than matched by a pattern, so
# a sleep nested two blocks inside a `while` or a `repeat` is still found, and
# a sleep that merely follows one is not.
for dir in Sources/ScopeUI Sources/ctxscope; do
  while IFS= read -r file; do
    hits="$(perl -ne '
      s{//.*}{};
      if ($loop >= 0 && /Task\.sleep/) { print "$.\n"; }
      my $opens = () = /\{/g;
      my $closes = () = /\}/g;
      if ($loop < 0 && /\b(while|repeat)\b/ && $opens > 0) { $loop = $depth; }
      $depth += $opens - $closes;
      if ($loop >= 0 && $depth <= $loop) { $loop = -1; }
      BEGIN { $depth = 0; $loop = -1; }
    ' "$file")"
    if [ -n "$hits" ]; then
      report "$file sleeps inside a loop at line $hits, which the idle budget forbids"
    fi
  done < <(find "$dir" -name '*.swift')
done

# A loop that waits on the injected clock spins the same way one that sleeps
# does, and the clock is how liveness waits.
for dir in Sources/ScopeUI Sources/ctxscope; do
  while IFS= read -r file; do
    hits="$(perl -ne '
      s{//.*}{};
      if ($loop >= 0 && /\bwait\(seconds:/) { print "$.\n"; }
      my $opens = () = /\{/g;
      my $closes = () = /\}/g;
      if ($loop < 0 && /\b(while|repeat)\b/ && $opens > 0) { $loop = $depth; }
      $depth += $opens - $closes;
      if ($loop >= 0 && $depth <= $loop) { $loop = -1; }
      BEGIN { $depth = 0; $loop = -1; }
    ' "$file")"
    if [ -n "$hits" ]; then
      report "$file waits on the clock inside a loop at line $hits"
    fi
  done < <(find "$dir" -name '*.swift')
done

# AppKit reaches ScopeUI through SwiftUI, which re-exports it. The status
# item, its image and anything else AppKit belongs to the app target.
appkit='(^|[^A-Za-z0-9_`])(NSScreen|NSPanel|NSWindow|NSView|NSApplication|NSApp|NSColor|NSFont'
appkit="$appkit"'|NSMenu|NSEvent|NSViewRepresentable|NSHostingView|NSHostingController|NSWorkspace'
appkit="$appkit"'|NSImage|NSBitmapImageRep|NSStatusItem|NSStatusBar|NSPopover|NSAppearance'
appkit="$appkit"'|NSAttributedString|NSPasteboard|NSSound|NSCursor)\b'
hits="$(grep -rnE "$appkit" Sources/ScopeUI --include='*.swift' \
  | grep -vE '^[^:]+:[0-9]+: *(///|//|\*)' || true)"
if [ -n "$hits" ]; then
  report "an AppKit type in ScopeUI, which may only speak SwiftUI: $hits"
fi

# A preconcurrency import turns a concurrency error into a warning, and
# warnings are errors here for a reason.
hits="$(grep -rn '@preconcurrency' Sources --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "@preconcurrency import: $hits"
fi

# Strict concurrency is the rule, not a suggestion. An escape hatch in the UI
# is a race nobody has had yet.
hits="$(grep -rnE '@unchecked +Sendable|nonisolated\(unsafe\)|assumeIsolated' Sources \
  --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "a concurrency escape hatch: $hits"
fi

# unsafeFlags anywhere in the manifest, commented or not.
if grep -vE '^[[:space:]]*//' Package.swift | grep -q 'unsafeFlags'; then
  report "unsafeFlags in Package.swift"
fi

# 8. No warnings. The package treats them as errors, so this only has to check
# that nobody turned that off.
if ! grep -q 'treatAllWarnings(as: .error)' Package.swift; then
  report "Package.swift no longer treats warnings as errors"
fi

if [ "$fail" -eq 0 ]; then
  echo "architecture: ok"
fi
exit "$fail"
