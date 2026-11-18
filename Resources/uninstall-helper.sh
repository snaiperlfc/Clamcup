#!/bin/bash
# Удаляет службу Clamcup и возвращает обычный сон. Приложение запускает скрипт
# от root через запрос пароля администратора. Можно и вручную:
#   sudo /Applications/Clamcup.app/Contents/Resources/uninstall-helper.sh
set -uo pipefail

LABEL=io.github.snaiperlfc.Clamcup.helper
HELPER=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
DIR="/Library/Application Support/Clamcup"
LOG=/var/log/clamcup.log

if [ "$(id -u)" -ne 0 ]; then
  echo "uninstall-helper.sh must run as root" >&2
  exit 1
fi

# Служба при остановке сама возвращает сон, pmset ниже — на случай, если она уже не работала
launchctl bootout system/"$LABEL" 2>/dev/null || true
pmset -a disablesleep 0

rm -f "$PLIST" "$HELPER" "$LOG"
rm -rf "$DIR"
echo "Clamcup helper removed"
