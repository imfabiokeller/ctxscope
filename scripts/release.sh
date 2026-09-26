#!/bin/bash
# Builds the release files into build/: app, zip, SHA-256 and notes. Publishes nothing.
# Usage: scripts/release.sh [VERSION]  (fails unless bundle.sh writes VERSION)
set -euo pipefail
cd "$(dirname "$0")/.."

expected="${1:-}"
app="build/ctxscope.app"

scripts/bundle.sh release

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [ -n "$expected" ] && [ "$version" != "$expected" ]; then
  echo "error: the bundle is version $version, the release is $expected" >&2
  echo "set CFBundleShortVersionString in scripts/bundle.sh, then tag again" >&2
  exit 1
fi

# bundle.sh ignores signing failures, so a broken signature is caught here.
codesign --verify --strict "$app"

zip="ctxscope-$version.zip"
rm -f "build/$zip" "build/$zip.sha256"
ditto -c -k --keepParent "$app" "build/$zip"
(cd build && shasum -a 256 "$zip" > "$zip.sha256")

notes="build/release-notes.md"
previous="$(git describe --tags --abbrev=0 --match 'v*' HEAD^ 2>/dev/null || true)"
{
  echo "Download \`$zip\`, unzip it and move \`ctxscope.app\` to Applications."
  echo "The app is not notarized, so macOS asks before the first launch. The"
  echo "Install section of the README says how to open it, and how to check the"
  echo "download against \`$zip.sha256\`."
  echo
  if [ -n "$previous" ]; then
    echo "## Changes since $previous"
    echo
    git log --no-merges --pretty='- %s' "$previous..HEAD"
  else
    echo "The first release."
  fi
} > "$notes"

echo "version $version"
cat "build/$zip.sha256"
echo "wrote build/$zip, build/$zip.sha256 and $notes"
