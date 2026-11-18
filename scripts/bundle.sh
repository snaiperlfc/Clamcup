#!/bin/bash
# Собирает build/Clamcup.app: универсальные бинарники (Apple silicon и Intel),
# ресурсы, подпись ad-hoc. Подписи Apple нет, поэтому macOS предупредит при первом запуске.
#   scripts/bundle.sh            — версия из файла VERSION
#   VERSION=1.2.3 scripts/bundle.sh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(tr -d '[:space:]' <VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP=build/Clamcup.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Clamcup" "$BIN/ClamcupHelper" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

cp Resources/AppIcon.icns Resources/install-helper.sh Resources/uninstall-helper.sh "$APP/Contents/Resources/"
chmod 755 "$APP/Contents/Resources/"*.sh
cp -R Resources/en.lproj Resources/ru.lproj "$APP/Contents/Resources/"

# Сначала вложенный бинарник, потом всё приложение
codesign --force --sign - --identifier io.github.snaiperlfc.Clamcup.helper "$APP/Contents/MacOS/ClamcupHelper"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"

echo "$APP $VERSION ($BUILD_NUMBER): $(lipo -archs "$APP/Contents/MacOS/Clamcup")"
