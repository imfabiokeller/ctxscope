#!/bin/bash
# Builds build/ctxscope.app from the package. No Xcode project: the app is the
# executable plus the resource bundles SwiftPM produced, arranged the way
# macOS expects to find them.
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-release}"
app="build/ctxscope.app"
contents="$app/Contents"

swift build -c "$configuration" --product ctxscope
binary="$(swift build -c "$configuration" --show-bin-path)"

rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$binary/ctxscope" "$contents/MacOS/ctxscope"

# Resource bundles hold the themes. Bundle.module finds them beside the
# executable, so they go into Contents/Resources.
for bundle in "$binary"/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$contents/Resources/"
done

cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ctxscope</string>
  <key>CFBundleDisplayName</key><string>ctxscope</string>
  <key>CFBundleIdentifier</key><string>dev.fabiokeller.ctxscope</string>
  <key>CFBundleExecutable</key><string>ctxscope</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <!-- An accessory from the first moment. Without this a launch through the
       SessionStart hook flashes a Dock icon before the delegate sets the
       policy, and the window still makes the app a regular one when it opens. -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>ctxscope</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>dev.fabiokeller.ctxscope.url</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>CFBundleURLSchemes</key><array><string>ctxscope</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$contents/PkgInfo"
# Ad hoc signature, so the app launches on the machine that built it without
# anything being installed or trusted.
codesign --force --sign - "$app" >/dev/null 2>&1 || true

echo "built $app"
