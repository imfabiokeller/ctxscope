#!/bin/bash
# Posts hook payloads and a ctxscope:// url at the bundled app and checks the answers.
# Usage: scripts/bundle.sh && scripts/hook-roundtrip.sh (quit any running ctxscope first)
set -uo pipefail
cd "$(dirname "$0")/.."

app="build/ctxscope.app/Contents/MacOS/ctxscope"
[ -x "$app" ] || { echo "no bundled app: run scripts/bundle.sh first"; exit 2; }

# Never stop a ctxscope somebody else started: refuse to run instead.
running() { pgrep -f "ctxscope.app/Contents/MacOS/ctxscope" 2>/dev/null; }
if [ -n "$(running)" ]; then
  echo "a ctxscope is already running, so this check did not run"
  echo "quit it first if you want to run it"
  exit 2
fi
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

out="$(mktemp)"
trap 'stop; rm -f "$out"' EXIT
# An app launched through Launch Services has no readable stderr, hence the file.
open -g "build/ctxscope.app" --args --print-hooks "$out"
wait_for_ours || { echo "FAIL: ctxscope did not start"; exit 1; }

port=""
for _ in $(seq 1 100); do
  port="$(sed -n 's/^hooks     listening on 127\.0\.0\.1:\([0-9]*\)$/\1/p' "$out")"
  [ -n "$port" ] && break
  sleep 0.1
done
[ -n "$port" ] || { echo "FAIL: the listener printed no port"; cat "$out"; exit 1; }
echo "listening on 127.0.0.1:$port"

url="http://127.0.0.1:$port/ctxscope/hook"
fail=0
check() {
  local what="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    echo "ok    $what: $got"
  else
    echo "FAIL  $what: wanted $want, got $got"
    fail=1
  fi
}

post() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
    -H 'Content-Type: application/json' -X POST --data "$2" "$url" 2>/dev/null
}

check "SessionEnd" 200 "$(post x '{"session_id":"round-trip","transcript_path":"/dev/null","cwd":"/tmp","hook_event_name":"SessionEnd","reason":"other"}')"
check "UserPromptSubmit" 200 "$(post x '{"session_id":"round-trip","hook_event_name":"UserPromptSubmit"}')"
check "Stop" 200 "$(post x '{"session_id":"round-trip","hook_event_name":"Stop","stop_hook_active":false}')"
check "SubagentStart" 200 "$(post x '{"session_id":"round-trip","hook_event_name":"SubagentStart","agent_id":"a1"}')"
check "an event we do not listen for" 200 "$(post x '{"session_id":"round-trip","hook_event_name":"PreToolUse"}')"
check "a body that is not JSON" 200 "$(post x 'not json at all')"

body="$(curl -s --max-time 2 -H 'Content-Type: application/json' -X POST \
  --data '{"session_id":"round-trip","hook_event_name":"SessionEnd"}' "$url")"
check "the answer body" "{}" "$body"

check "another path" 404 "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 -X POST \
  --data '{}' "http://127.0.0.1:$port/elsewhere")"
check "another method" 405 "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
  "$url")"
huge="$(mktemp)"
head -c 70000 /dev/zero | tr '\0' 'x' > "$huge"
check "a body past the cap" 413 "$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
  -X POST --data-binary "@$huge" "$url")"
rm -f "$huge"

open -g "ctxscope://show?session=round-trip" 2>/dev/null
for _ in $(seq 1 30); do
  grep -q '^url ' "$out" && break
  sleep 0.1
done
if grep -q '^url       show session round-trip$' "$out"; then
  echo "ok    ctxscope://show?session=round-trip reached the app"
else
  echo "FAIL  the ctxscope:// url never reached the app"
  fail=1
fi

stop
for _ in $(seq 1 50); do
  [ -z "$(running)" ] && break
  sleep 0.1
done
started="$(date +%s%N)"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 -X POST --data '{}' "$url")"
took=$(( ( $(date +%s%N) - started ) / 1000000 ))
check "with ctxscope gone" 000 "$code"
if [ "$took" -lt 200 ]; then
  echo "ok    refused in ${took} ms"
else
  echo "FAIL  refusal took ${took} ms"
  fail=1
fi

echo
echo "events the listener reported:"
grep '^event ' "$out" || echo "(none)"
for event in SessionEnd; do
  if grep -q "^event     $event session round-trip$" "$out"; then
    echo "ok    $event reached the model"
  else
    echo "FAIL  $event never reached the model"
    fail=1
  fi
done
for event in UserPromptSubmit Stop SubagentStart SubagentStop PostModelSwitch; do
  if grep -q "^event     $event " "$out"; then
    echo "FAIL  $event reached the model"
    fail=1
  fi
done
echo "ok    the five events ctxscope no longer asks for reach nobody"

[ "$fail" -eq 0 ] && echo "hook round trip: ok"
exit "$fail"
