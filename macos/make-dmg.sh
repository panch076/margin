#!/bin/bash
# Packs Margin.app into a disk image (Margin-<version>.dmg) with a shortcut to the Applications folder.
# Builds the app first if it is not there yet.
set -euo pipefail
cd "$(dirname "$0")"

[ -d Margin.app ] || ./make-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Margin.app/Contents/Info.plist)"
DMG="Margin-$VERSION.dmg"

STAGE="$(mktemp -d)"
cp -R Margin.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Margin" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Built $(pwd)/$DMG"
