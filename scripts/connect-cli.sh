#!/bin/bash
# Checks connect, disconnect and doctor against a temporary Claude home, never ~/.claude.
# Usage: swift build && scripts/connect-cli.sh
set -uo pipefail
cd "$(dirname "$0")/.."

cli="$(swift build --show-bin-path)/ctxscope-cli"
[ -x "$cli" ] || { echo "no cli: run swift build first"; exit 2; }

home="$(mktemp -d)/claude"
mkdir -p "$home"
trap 'rm -rf "$(dirname "$home")"' EXIT

fail=0
check() {
  if [ "$2" = "$3" ]; then
    echo "ok    $1"
  else
    echo "FAIL  $1: wanted $2, got $3"
    fail=1
  fi
}

printf '{\n  "model": "opus",\n  "permissions": {\n    "allow": ["Bash(git *)"]\n  }\n}\n' \
  > "$home/settings.json"
chmod 600 "$home/settings.json"
cp -p "$home/settings.json" "$home/original.json"

"$cli" connect --claude-home "$home" < /dev/null > /dev/null 2>&1
check "no terminal and no --yes writes nothing" same \
  "$(cmp -s "$home/settings.json" "$home/original.json" && echo same || echo changed)"

"$cli" connect --claude-home "$home" --yes < /dev/null > /dev/null
check "connect writes" changed \
  "$(cmp -s "$home/settings.json" "$home/original.json" && echo same || echo changed)"
check "the file is still valid JSON" 0 \
  "$(python3 -m json.tool "$home/settings.json" > /dev/null 2>&1; echo $?)"
check "one entry that posts to ctxscope" 1 \
  "$(grep -c 'ctxscope/hook' "$home/settings.json")"
check "one entry that starts ctxscope" 1 \
  "$(grep -c 'ctxscope://wake' "$home/settings.json")"
check "the settings file keeps its mode" 600 "$(stat -f %Lp "$home/settings.json")"
check "the backup is never wider" 600 "$(stat -f %Lp "$home/settings.json.ctxscope-backup")"
check "the backup is the original" same \
  "$(cmp -s "$home/settings.json.ctxscope-backup" "$home/original.json" && echo same || echo changed)"
check "the skill is installed" yes \
  "$([ -f "$home/skills/ctxscope/SKILL.md" ] && echo yes || echo no)"

"$cli" connect --claude-home "$home" --yes < /dev/null | tail -1 \
  | grep -q "already connected" \
  && echo "ok    connecting twice writes nothing" \
  || { echo "FAIL  connecting twice"; fail=1; }

"$cli" doctor --claude-home "$home" > "$home/doctor.txt" 2>&1
grep -q "hooks          2 of 2 events, port" "$home/doctor.txt" \
  && echo "ok    doctor sees the hooks" \
  || { echo "FAIL  doctor: $(cat "$home/doctor.txt")"; fail=1; }

"$cli" disconnect --claude-home "$home" --yes < /dev/null > /dev/null
check "undo is byte identical" same \
  "$(cmp -s "$home/settings.json" "$home/original.json" && echo same || echo changed)"
check "the backup is gone" no \
  "$([ -f "$home/settings.json.ctxscope-backup" ] && echo yes || echo no)"
check "the skill is gone" no \
  "$([ -f "$home/skills/ctxscope/SKILL.md" ] && echo yes || echo no)"

printf '{\n  "model": "opus",\n}\n' > "$home/settings.json"
cp -p "$home/settings.json" "$home/broken.json"
"$cli" connect --claude-home "$home" --yes < /dev/null > "$home/refusal.txt" 2>&1
check "a file the harness could not read is refused" same \
  "$(cmp -s "$home/settings.json" "$home/broken.json" && echo same || echo changed)"
grep -q "left it alone" "$home/refusal.txt" \
  && echo "ok    the refusal says so in plain words" \
  || { echo "FAIL  refusal: $(cat "$home/refusal.txt")"; fail=1; }

[ "$fail" -eq 0 ] && echo "connect cli: ok"
exit "$fail"
