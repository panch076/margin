#!/bin/bash
# Builds Margin.app next to this script. Needs Xcode 26 or its command line tools (macOS 26 SDK).
set -euo pipefail
cd "$(dirname "$0")"

# UNIVERSAL=1 builds for both Apple silicon and Intel Macs; the default is this Mac's own architecture.
ARCH_FLAGS=""
if [ "${UNIVERSAL:-0}" = "1" ]; then ARCH_FLAGS="--arch arm64 --arch x86_64"; fi

# shellcheck disable=SC2086
swift build -c release --product Margin $ARCH_FLAGS
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)/Margin"
VERSION="$(sed -n 's/.*static let currentVersion = "\(.*\)".*/\1/p' Sources/MarginCore/Updater.swift)"

APP="Margin.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Margin"
cp Margin.icns "$APP/Contents/Resources/Margin.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Margin</string>
    <key>CFBundleDisplayName</key><string>Margin</string>
    <key>CFBundleIdentifier</key><string>local.margin.app</string>
    <key>CFBundleExecutable</key><string>Margin</string>
    <key>CFBundleIconFile</key><string>Margin</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION:-1.0.0}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
