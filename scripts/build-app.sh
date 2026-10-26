#!/bin/bash
# Builds DocuDesk.app into ./build. Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
VERSION="1.0.0"

swift build -c "$CONFIG" --product DocuDesk
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/DocuDesk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DocuDesk" "$APP/Contents/MacOS/DocuDesk"
if [ -f scripts/AppIcon.icns ]; then cp scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DocuDesk</string>
    <key>CFBundleDisplayName</key><string>DocuDesk</string>
    <key>CFBundleIdentifier</key><string>com.shreetech.docudesk</string>
    <key>CFBundleExecutable</key><string>DocuDesk</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.business</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© Shree Tech</string>
</dict>
</plist>
PLIST

# Ad-hoc signature for local use. Distribution builds need a Developer ID and notarization.
codesign --force --sign - "$APP"
echo "Built $APP"
