#!/bin/bash
# Starts ctxscope on a made-up session, for screenshots and screen recordings
# in which nothing private can appear.
#
#   scripts/demo.sh [--focus] [--live SECONDS]
#
# Makes a fresh temporary home, writes the demo session into it with
# `ctxscope-cli demo`, and starts build/ctxscope.app with CFFIXED_USER_HOME
# pointing at that home, so the app reads the demo's ~/.claude and nothing
# else. The app keeps its focus and power state in a defaults suite of its own
# under a fixed home, so your own saved focus is never touched.
#
#   --focus          open focused on the demo session
#   --live SECONDS   write the first 41 requests at once and the other 46 one
#                    at a time over SECONDS, so the window shows it growing
set -euo pipefail
cd "$(dirname "$0")/.."

focus=0
live=""
while [ $# -gt 0 ]; do
  case "$1" in
    --focus) focus=1 ;;
    --live)
      shift
      live="${1:-}"
      case "$live" in
        ''|*[!0-9]*) echo "--live takes a whole number of seconds" >&2; exit 2 ;;
      esac
      ;;
    *) echo "usage: scripts/demo.sh [--focus] [--live SECONDS]" >&2; exit 2 ;;
  esac
  shift
done

# A ctxscope that is already running is left alone: never killed, never signalled.
if pgrep -x ctxscope >/dev/null; then
  echo "quit your running ctxscope first"
  exit 1
fi

app="build/ctxscope.app/Contents/MacOS/ctxscope"
if [ ! -x "$app" ]; then
  echo "no $app yet: run scripts/bundle.sh first" >&2
  exit 1
fi

swift build --product ctxscope-cli >/dev/null
cli="$(swift build --show-bin-path)/ctxscope-cli"

home="$(mktemp -d -t ctxscope-demo)"
# The account's own home, whatever HOME or CFFIXED_USER_HOME say.
real="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')"
resolved="$(cd "$home" && pwd -P)"
real_resolved="$(cd "$real" && pwd -P)"
case "$real_resolved/" in
  "$resolved"/*)
    echo "refusing: $home would be, or hold, the real home $real" >&2
    exit 1
    ;;
esac
if [ "$resolved" = "$real_resolved" ] || [ -z "$resolved" ]; then
  echo "refusing: $home resolves to the real home" >&2
  exit 1
fi

log="$home/demo.log"
if [ -n "$live" ]; then
  "$cli" demo --home "$home" --live "$live" >"$log" 2>&1 &
  # The first 41 requests are on disk by the time the header is complete.
  for _ in $(seq 100); do
    grep -q '^live' "$log" 2>/dev/null && break
    sleep 0.1
  done
else
  "$cli" demo --home "$home" >"$log" 2>&1
fi
cat "$log"
session="$(awk '/^session/ {print $2}' "$log")"
if [ -z "$session" ]; then
  echo "the demo session was not written, see $log" >&2
  exit 1
fi

# The demo's own settings: a clean slate each run, and the focus if asked.
suite="dev.fabiokeller.ctxscope.demo"
CFFIXED_USER_HOME="$home" defaults delete "$suite" >/dev/null 2>&1 || true
if [ "$focus" -eq 1 ]; then
  CFFIXED_USER_HOME="$home" defaults write "$suite" focus.session "$session"
fi

CFFIXED_USER_HOME="$home" "$app" --window >/dev/null 2>&1 &
echo
echo "demo home  $home"
echo "ctxscope   started as pid $!, reading only that home"
echo "quit it from its menu when done; the home can be deleted afterwards"
