#!/bin/bash
# Builds build/ctxscope.app from the package, with no Xcode project.
# Usage: scripts/bundle.sh [release|debug]
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

# ThemeLoader looks for the theme resource bundle in Contents/Resources.
for bundle in "$binary"/*.bundle; do
  [ -e "$bundle" ] || continue
  cp -R "$bundle" "$contents/Resources/"
done

xcrun actool Resources/Assets.xcassets --compile "$contents/Resources" \
  --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
  --output-partial-info-plist "build/AppIcon.plist" >/dev/null

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
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>0.1.2</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <!-- Without this a hook launch flashes a Dock icon before the delegate sets the policy. -->
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
codesign --force --sign - "$app" >/dev/null 2>&1 || true

echo "built $app"
