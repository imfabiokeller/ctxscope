#!/bin/bash
# What the SessionStart hook costs a Claude session, measured both ways: with
# ctxscope already running, and with it having to start.
#
# It runs the exact command the hook runs. Nothing here goes near ~/.claude:
# the hook entry is not installed anywhere, the command is simply run. It
# refuses to run while a ctxscope is up, because stopping somebody else's is
# not this script's to do.
set -uo pipefail
cd "$(dirname "$0")/.."

app="build/ctxscope.app"
[ -d "$app" ] || { echo "no bundled app: run scripts/bundle.sh first"; exit 2; }

command="open -g ctxscope://wake --args --woken || true"

# Timed inside one process, because starting a second one to read the clock
# costs more than the command being measured.
took() {
  python3 - "$command" <<'TIMER'
import subprocess, sys, time
started = time.monotonic_ns()
subprocess.run(["/bin/sh", "-c", sys.argv[1]])
print(round((time.monotonic_ns() - started) / 1e6, 1))
TIMER
}

# Never stop a ctxscope somebody else started. If one is running this check
# does not run at all, and says so, rather than taking it away from whoever
# is using it.
running() { pgrep -f "ctxscope.app/Contents/MacOS/ctxscope" 2>/dev/null; }
if [ -n "$(running)" ]; then
  echo "a ctxscope is already running, so this check did not run"
  echo "quit it first if you want to run it"
  exit 2
fi
# Nothing was running, so everything this finds from here on is this script's.
ours=""
stop() { [ -n "$ours" ] && kill "$ours" 2>/dev/null; }
wait_for_ours() {
  for _ in $(seq 1 100); do
    ours="$(running | head -1)"
    [ -n "$ours" ] && return 0
    sleep 0.1
  done
  return 1
}

front() { lsappinfo front 2>/dev/null; }
trap stop EXIT

before="$(front)"
echo "cold, ctxscope is not running:"
echo "  the hook's command returned in $(took) ms"
wait_for_ours && echo "  ctxscope is up" || { echo "  FAIL ctxscope did not start"; exit 1; }
sleep 1
[ "$(front)" = "$before" ] \
  && echo "  the front application did not change" \
  || echo "  FAIL the front application changed"
# An accessory has no Dock icon and is not in the visible process list. The
# window would put it there, because opening one makes the app a regular one.
lsappinfo visibleProcessList 2>/dev/null | grep -q "ctxscope" \
  && echo "  FAIL ctxscope showed a dock icon or a window" \
  || echo "  no dock icon and no window"

echo "warm, ctxscope is already running:"
for _ in $(seq 1 5); do
  echo "  $(took) ms"
done
echo "  instances running: $(running | wc -l | tr -d ' ')"
[ "$(front)" = "$before" ] \
  && echo "  the front application did not change" \
  || echo "  FAIL the front application changed"
