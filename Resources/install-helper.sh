#!/bin/bash
# Ставит или обновляет службу Clamcup. Приложение запускает скрипт от root через
# стандартный запрос пароля администратора:
#   install-helper.sh <пользователь> <версия>
# Пути совпадают с Sources/ClamcupCore/Constants.swift — менять вместе.
set -euo pipefail

LABEL=io.github.snaiperlfc.Clamcup.helper
HELPER=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
DIR="/Library/Application Support/Clamcup"
LOG=/var/log/clamcup.log

USER_NAME=${1:?usage: install-helper.sh <user> <version>}
VERSION=${2:?usage: install-helper.sh <user> <version>}
CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$CONTENTS/MacOS/ClamcupHelper"

if [ "$(id -u)" -ne 0 ]; then
  echo "install-helper.sh must run as root" >&2
  exit 1
fi
if ! id -u "$USER_NAME" >/dev/null 2>&1; then
  echo "unknown user: $USER_NAME" >&2
  exit 1
fi
if [ ! -x "$SOURCE" ]; then
  echo "helper binary not found: $SOURCE" >&2
  exit 1
fi
USER_GROUP="$(id -gn "$USER_NAME")"

stop_job() {
  launchctl bootout system/"$1" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print system/"$1" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
}

stop_job "$LABEL"

# Бинарник и каталоги службы принадлежат root. Будь они доступны на запись
# пользователю, любой его процесс получил бы root без пароля
if [ ! -d /Library/PrivilegedHelperTools ]; then
  install -d -o root -g wheel -m 1755 /Library/PrivilegedHelperTools
fi
install -o root -g wheel -m 755 "$SOURCE" "$HELPER"
# Карантин от скачанного DMG launchd не нужен
xattr -c "$HELPER" 2>/dev/null || true

install -d -o root -g wheel -m 755 "$DIR"
# Файл режима пишет приложение, поэтому он принадлежит пользователю.
# Служба берёт из него только слово off, всё остальное считает auto
if [ ! -f "$DIR/mode" ]; then
  echo auto >"$DIR/mode"
fi
chown "$USER_NAME:$USER_GROUP" "$DIR/mode"
chmod 644 "$DIR/mode"
echo "$VERSION" >"$DIR/helper-version"
chmod 644 "$DIR/helper-version"

cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$HELPER</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>10</integer>
	<key>StandardOutPath</key>
	<string>$LOG</string>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootstrap system "$PLIST"
echo "Clamcup helper $VERSION installed"
