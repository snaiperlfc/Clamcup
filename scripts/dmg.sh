#!/bin/bash
# Упаковывает build/Clamcup.app в build/Clamcup-<версия>.dmg с ярлыком «Программы».
# Сначала scripts/bundle.sh.
set -euo pipefail

cd "$(dirname "$0")/.."
APP=build/Clamcup.app
[ -d "$APP" ] || { echo "Сначала соберите приложение: scripts/bundle.sh" >&2; exit 1; }
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
DMG="build/Clamcup-$VERSION.dmg"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Clamcup $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
(cd build && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")
