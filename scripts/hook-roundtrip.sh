#!/bin/bash
# Posts hook payloads, shaped the way Claude Code's hooks reference shapes
# them, at the app's own listener, opens the url the /ctxscope skill opens, and
# checks what comes back. It proves the hooks work end to end without any
# settings file being touched: the app runs with --print-hooks, which binds a
# port and writes down what reaches it, and nothing here goes anywhere near
# ~/.claude. The url opens the instrument
# window for the second before the app is stopped again. It refuses to run
# while a ctxscope is up, because there has to be exactly one instance for the
# url to reach the one being watched, and stopping somebody else's is not this
# script's to do.
set -uo pipefail
cd "$(dirname "$0")/.."

app="build/ctxscope.app/Contents/MacOS/ctxscope"
[ -x "$app" ] || { echo "no bundled app: run scripts/bundle.sh first"; exit 2; }

# Launched through Launch Services, the way a ctxscope:// url launches it, so
# that the url half of this is delivered to the instance being watched. An app
# launched that way has no standard error anybody can read, so --print-hooks is
# given a file to write to.
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

out="$(mktemp)"
trap 'stop; rm -f "$out"' EXIT
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

# One payload per event ctxscope writes into the settings file, shaped the way
# the hooks reference shapes them. The session id is made up; no transcript on
# this machine is read or named.
post() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
    -H 'Content-Type: application/json' -X POST --data "$2" "$url" 2>/dev/null
}

check "SessionEnd" 200 "$(post x '{"session_id":"round-trip","transcript_path":"/dev/null","cwd":"/tmp","hook_event_name":"SessionEnd","reason":"other"}')"
# Everything else is answered and dropped, which is what a settings file
# written by an older ctxscope keeps posting.
check "UserPromptSubmit" 200 "$(post x '{"session_id":"round-trip","hook_event_name":"UserPromptSubmit"}')"
check "Stop" 200 "$(post x '{"session_id":"round-trip","hook_event_name":"Stop","stop_hook_active":false}')"
check "SubagentStart" 200 "$(post x '{"session_id":"round-trip","hook_event_name":"SubagentStart","agent_id":"a1"}')"
check "an event we do not listen for" 200 "$(post x '{"session_id":"round-trip","hook_event_name":"PreToolUse"}')"
check "a body that is not JSON" 200 "$(post x 'not json at all')"

# The answer to a well formed post is an empty JSON object.
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

# What the /ctxscope skill runs. The URL goes through Launch Services to the
# app that is already up, which is the whole point of the scheme.
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

# A hook posted while ctxscope is not running has to be refused at once.
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
# And the five ctxscope used to ask for reach nobody, however often a file
# that still has them posts one.
for event in UserPromptSubmit Stop SubagentStart SubagentStop PostModelSwitch; do
  if grep -q "^event     $event " "$out"; then
    echo "FAIL  $event reached the model"
    fail=1
  fi
done
echo "ok    the five events ctxscope no longer asks for reach nobody"

[ "$fail" -eq 0 ] && echo "hook round trip: ok"
exit "$fail"
