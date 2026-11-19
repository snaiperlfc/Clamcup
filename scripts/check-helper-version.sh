#!/bin/bash
# Проверяет, что HELPER_VERSION подняли, если с прошлого релиза изменились служба,
# ClamcupCore или установщик. Иначе приложение сочло бы старую установленную
# службу актуальной и не предложило бы её обновить.
#   scripts/check-helper-version.sh [база]   — по умолчанию последний тег до HEAD
set -euo pipefail

cd "$(dirname "$0")/.."
BASE="${1:-$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)}"
if [ -z "$BASE" ]; then
  echo "No earlier release tag, nothing to compare"
  exit 0
fi

HELPER_PATHS=(Sources/ClamcupHelper Sources/ClamcupCore Resources/install-helper.sh)
if git diff --quiet "$BASE" HEAD -- "${HELPER_PATHS[@]}"; then
  echo "Helper unchanged since $BASE"
  exit 0
fi
if git diff --quiet "$BASE" HEAD -- HELPER_VERSION; then
  echo "Helper files changed since $BASE, but HELPER_VERSION didn't:" >&2
  git diff --stat "$BASE" HEAD -- "${HELPER_PATHS[@]}" >&2
  echo "Set HELPER_VERSION to the new app version." >&2
  exit 1
fi
echo "Helper changed since $BASE, HELPER_VERSION is $(tr -d '[:space:]' <HELPER_VERSION)"
