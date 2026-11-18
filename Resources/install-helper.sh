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
case "$VERSION" in
  "" | *[!0-9A-Za-z.+-]*)
    echo "bad version: $VERSION" >&2
    exit 1
    ;;
esac
USER_GROUP="$(id -gn "$USER_NAME")"

# Настоящий каталог root или ещё не существует. Симлинк и чужой каталог не годятся:
# через них скрипт от root писал бы туда, куда укажет пользователь
is_safe_dir() {
  [ ! -L "$1" ] && { [ ! -e "$1" ] || { [ -d "$1" ] && [ "$(stat -f %u "$1")" = 0 ]; }; }
}

# Обычный файл, а не симлинк, каталог или что-то ещё
is_plain_file() {
  [ ! -L "$1" ] && [ -f "$1" ]
}

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
rm -f "$HELPER"
install -o root -g wheel -m 755 "$SOURCE" "$HELPER"
# Релизы не подписаны Developer ID: службу с флагом карантина launchd может не запустить,
# а окна, чтобы её разрешить, у демона нет
xattr -c "$HELPER" 2>/dev/null || true

if ! is_safe_dir "$DIR"; then
  echo "refusing to use $DIR: it is not a root-owned directory" >&2
  exit 1
fi
install -d -o root -g wheel -m 755 "$DIR"

# Файл режима пишет приложение, поэтому он принадлежит пользователю.
# Служба берёт из него только слово off, всё остальное считает auto.
# Всё, что не обычный файл, удаляем: chown через симлинк отдал бы пользователю чужой файл
if [ -L "$DIR/mode" ] || [ -e "$DIR/mode" ]; then
  is_plain_file "$DIR/mode" || rm -rf "$DIR/mode"
fi
if [ ! -f "$DIR/mode" ]; then
  echo auto >"$DIR/mode"
fi
chown -h "$USER_NAME:$USER_GROUP" "$DIR/mode"
chmod 644 "$DIR/mode"

rm -f "$DIR/helper-version"
echo "$VERSION" >"$DIR/helper-version"
chmod 644 "$DIR/helper-version"

rm -f "$PLIST"
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
