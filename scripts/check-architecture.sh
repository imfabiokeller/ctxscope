#!/bin/bash
# Checks the architecture rules a compiler cannot: import direction, file length, sources of truth.
# Usage: scripts/check-architecture.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
report() {
  fail=1
  echo "FAIL: $1"
}

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

declared="ScopeCore ScopeCapture ScopeConnect ScopeUI ctxscope ctxscope-cli ctxscope-snapshots"
for dir in Sources/*/; do
  name="$(basename "$dir")"
  case " $declared " in
    *" $name "*) ;;
    *) report "Sources/$name has no declared import rule in $0" ;;
  esac
done

hits="$(grep -rn '@_exported' Sources Tests --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "@_exported import hides a dependency: $hits"
fi

while IFS= read -r file; do
  lines="$(wc -l < "$file" | tr -d ' ')"
  if [ "$lines" -gt 300 ]; then
    report "$file is $lines lines, the limit is 300"
  fi
done < <(find Sources Tests -name '*.swift' 2>/dev/null)

hits="$(grep -rln 'case sys, tools, mcp\|enum Band' Sources --include='*.swift' | grep -v 'Sources/ScopeCore/Bands.swift' || true)"
if [ -n "$hits" ]; then
  report "the Band enum appears outside Sources/ScopeCore/Bands.swift: $hits"
fi

impure='FileManager|URLSession|Process\(|Date\(\)|ProcessInfo|String\(contentsOf|Data\(contentsOf|FileHandle|DispatchTime|CFAbsoluteTime|readLine\(|print\('
hits="$(grep -rlnE "$impure" Sources/ScopeCore --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "ScopeCore reaches outside itself in: $hits"
fi

hits="$(grep -rn 'TODO\|FIXME\|XXX' Sources Tests --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "unfinished markers: $hits"
fi

# The character is built with printf so this check does not match itself.
dash="$(printf '\xe2\x80\x94')"
hits="$(grep -rlF "$dash" Sources Tests docs scripts artifacts/README.md CLAUDE.md CONTRIBUTING.md \
  README.md .github 2>/dev/null || true)"
if [ -n "$hits" ]; then
  report "em-dash found in: $hits"
fi

# Calls split over several lines are joined first, so the patterns see their arguments.
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
literals="$literals"'|NSFont\.[a-z]|systemFont\(ofSize: *[0-9]'
literals="$literals"'|#[0-9A-Fa-f]{3,8}([^0-9A-Fa-f]|$)|oklch\(|rgba?\([0-9]'
# The menu bar's type and ink are the system's own roles, not theme literals.
system_owned='NSColor\.labelColor|NSFont\.systemFontSize|NSFont\.monospacedDigitSystemFont'
built='(^|[^A-Za-z0-9_])(ThemeColor|OKLCH) *(\(|\.init\()'
built="$built"'|: *(ThemeColor|OKLCH) *= *\.init\(|return *\.init\('
for dir in Sources/ScopeUI Sources/ctxscope Sources/ctxscope-snapshots; do
  [ -d "$dir" ] || continue
  while IFS= read -r file; do
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
hits="$(grep -rnE "$built" Sources/ScopeCore Sources/ScopeCapture Sources/ctxscope-cli \
  --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "a ThemeColor or OKLCH built outside Sources/ScopeUI/Theme: $hits"
fi

forbidden='JSONSerialization|JSONDecoder|contentsOf|contentsOfFile|FileHandle|FileManager'
forbidden="$forbidden"'|Timer\.|NSSavePanel|NSOpenPanel|NSWorkspace|URLSession'
hits="$(grep -rnE "$forbidden" Sources/ScopeUI/Views --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "a view reaching outside itself: $hits"
fi

timers='Timer\.|CADisplayLink|DispatchSourceTimer|makeTimerSource|AsyncTimerSequence'
timers="$timers"'|TimelineView|repeatForever|asyncAfter'
timers="$timers"'|phaseAnimator|keyframeAnimator|symbolEffect|repeatCount|autoreverses'
for dir in Sources/ScopeUI Sources/ctxscope; do
  hits="$(grep -rnE "$timers" "$dir" --include='*.swift' || true)"
  if [ -n "$hits" ]; then
    report "a timer or a repeating animation, which the idle budget forbids: $hits"
  fi
done

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

appkit='(^|[^A-Za-z0-9_`])(NSScreen|NSPanel|NSWindow|NSView|NSApplication|NSApp|NSColor|NSFont'
appkit="$appkit"'|NSMenu|NSEvent|NSViewRepresentable|NSHostingView|NSHostingController|NSWorkspace'
appkit="$appkit"'|NSImage|NSBitmapImageRep|NSStatusItem|NSStatusBar|NSPopover|NSAppearance'
appkit="$appkit"'|NSAttributedString|NSPasteboard|NSSound|NSCursor)\b'
hits="$(grep -rnE "$appkit" Sources/ScopeUI --include='*.swift' \
  | grep -vE '^[^:]+:[0-9]+: *(///|//|\*)' || true)"
if [ -n "$hits" ]; then
  report "an AppKit type in ScopeUI, which may only speak SwiftUI: $hits"
fi

hits="$(grep -rn '@preconcurrency' Sources --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "@preconcurrency import: $hits"
fi

hits="$(grep -rnE '@unchecked +Sendable|nonisolated\(unsafe\)|assumeIsolated' Sources \
  --include='*.swift' || true)"
if [ -n "$hits" ]; then
  report "a concurrency escape hatch: $hits"
fi

if grep -vE '^[[:space:]]*//' Package.swift | grep -q 'unsafeFlags'; then
  report "unsafeFlags in Package.swift"
fi

if ! grep -q 'treatAllWarnings(as: .error)' Package.swift; then
  report "Package.swift no longer treats warnings as errors"
fi

if [ "$fail" -eq 0 ]; then
  echo "architecture: ok"
fi
exit "$fail"
