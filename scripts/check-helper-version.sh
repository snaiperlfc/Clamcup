#!/bin/bash
# Проверяет HELPER_VERSION относительно прошлого релиза. Приложение предлагает обновить
# службу, только когда этот номер отличается от установленного, поэтому:
#  - если изменилось что-то, от чего зависит служба, номер должен измениться;
#  - новый номер равен VERSION и больше прежнего. Так он не совпадёт ни с одним
#    значением, которое уже записано у пользователей, и старая служба
#    не сойдёт за свежую.
#   scripts/check-helper-version.sh [база]   — по умолчанию последний тег до HEAD
set -euo pipefail

cd "$(dirname "$0")/.."
BASE="${1:-$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)}"
if [ -z "$BASE" ]; then
  echo "No earlier release tag, nothing to compare"
  exit 0
fi

# Всё, что меняет бинарник службы, её задание launchd или то, как она ставится.
# uninstall-helper.sh сюда не входит: установленную службу он не меняет
HELPER_PATHS=(
  Sources/ClamcupHelper
  Sources/ClamcupCore
  Resources/install-helper.sh
  Package.swift
  scripts/bundle.sh
)

fail() {
  echo "$*" >&2
  exit 1
}

NEW="$(tr -d '[:space:]' <HELPER_VERSION)"
APP_VERSION="$(tr -d '[:space:]' <VERSION)"
OLD="$(git show "$BASE:HELPER_VERSION" 2>/dev/null | tr -d '[:space:]' || true)"

helper_changed=false
git diff --quiet "$BASE" HEAD -- "${HELPER_PATHS[@]}" || helper_changed=true
number_changed=false
[ "$NEW" = "$OLD" ] || number_changed=true

if $helper_changed && ! $number_changed; then
  git diff --stat "$BASE" HEAD -- "${HELPER_PATHS[@]}" >&2
  fail "Helper files changed since $BASE, but HELPER_VERSION didn't. Set it to VERSION ($APP_VERSION)."
fi

if ! $number_changed; then
  echo "Helper unchanged since $BASE, HELPER_VERSION is $NEW"
  exit 0
fi

# Файла не было в базе: первое значение, сравнивать не с чем
if [ -z "$OLD" ]; then
  echo "HELPER_VERSION appears since $BASE: $NEW"
  exit 0
fi

[ "$NEW" = "$APP_VERSION" ] || fail "HELPER_VERSION $NEW must equal VERSION $APP_VERSION when it changes."
[ "$(printf '%s\n%s\n' "$OLD" "$NEW" | sort -V | tail -1)" = "$NEW" ] ||
  fail "HELPER_VERSION must grow: $OLD at $BASE, $NEW now."
echo "HELPER_VERSION $OLD -> $NEW since $BASE"
