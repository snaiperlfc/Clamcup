#!/bin/bash
# Живой прогон службы без root: настоящие уведомления IOKit и kqueue, pmset только на чтение.
# Запуск: Tests/helper-live-test.sh (после swift build)
set -u

cd "$(dirname "$0")/.."
BIN="$(swift build --show-bin-path)/ClamcupHelper"
[ -x "$BIN" ] || { echo "Сначала swift build" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'kill "$PID" 2>/dev/null; rm -rf "$TMP"' EXIT
fails=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }
expect_log() { grep -q -- "$1" "$TMP/log" && pass "в журнале: $1" || fail "в журнале: $1"; }

echo auto >"$TMP/mode"
CLAMCUP_SUPPORT_DIR="$TMP" CLAMCUP_DRY_RUN=1 "$BIN" >"$TMP/log" 2>&1 &
PID=$!
sleep 1

[ "$(cat "$TMP/helper.pid" 2>/dev/null)" = "$PID" ] && pass "pid-файл записан" || fail "pid-файл записан"

# Запись в файл, как это делает приложение: служба должна заметить её без опроса
echo off >"$TMP/mode"
sleep 0.3
expect_log "mode off"

# Подмена файла целиком: наблюдение должно встать заново
echo auto >"$TMP/mode.new" && mv "$TMP/mode.new" "$TMP/mode"
sleep 0.3
echo off >"$TMP/mode"
sleep 0.3
[ "$(grep -c 'mode off' "$TMP/log")" -ge 2 ] && pass "файл подменили, смена всё равно замечена" || fail "файл подменили, смена всё равно замечена"

# Мусор в файле считается auto
echo 'rm -rf /' >"$TMP/mode"
sleep 0.3
[ "$(grep -c 'mode auto' "$TMP/log")" -ge 2 ] && pass "мусор в файле = auto" || fail "мусор в файле = auto"

kill -TERM "$PID"
for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
kill -0 "$PID" 2>/dev/null && fail "остановка по TERM" || pass "остановка по TERM"
[ -e "$TMP/helper.pid" ] && fail "pid-файл удалён" || pass "pid-файл удалён"
expect_log "started, mode auto, dry run"
expect_log "stopped"

# На зарядке без отключённого сна служба должна захотеть его отключить
if pmset -g ps | head -1 | grep -q "AC Power" && ! pmset -g | grep -q 'SleepDisabled[[:space:]]*1'; then
  expect_log "dry run: pmset -a disablesleep 1"
fi

echo "--- журнал"
cat "$TMP/log"
echo "---"
[ "$fails" -eq 0 ] && echo "Все проверки прошли" || echo "Провалено: $fails"
exit "$fails"
