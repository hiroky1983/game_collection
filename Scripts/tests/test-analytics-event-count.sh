#!/bin/bash
# AnalyticsEvent の case 数と docs/spec-app.md「解析仕様」の食い違いを検知する（#3428）。
#
# 「表の10種」が 11 種のまま取り残される事故が #2986・#3207・#3228 と繰り返したため、機械で見張る。
# 見るのは 3 つ: ① enum の case 数 ② spec-app.md の表のイベント行数 ③ 本文の「下の表のN種」の N。
# 3 つが一致していなければ落ちる。ケースを足したら表の行と「N種」も同じ PR で直す。
#
# 使い方: bash Scripts/tests/test-analytics-event-count.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
SWIFT="$REPO/Packages/GameKit/Sources/CoreEngine/Analytics.swift"
SPEC="$REPO/docs/spec-app.md"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

# enum AnalyticsEvent の直下にある case の数
count_cases() {
  awk '/^public enum AnalyticsEvent/{f=1; next} f&&/^}/{exit} f&&/^    case [a-z]/{n++} END{print n+0}' "$1"
}

# 「解析仕様」節の、最初の表（| イベント名 | … | で始まる表）のデータ行数
count_rows() {
  awk '
    /^## 解析仕様/ {sec=1; next}
    sec && /^## / {exit}
    sec && /^\| イベント名 \|/ {tbl=1; next}
    tbl && /^\|---/ {next}
    tbl && /^\| `[a-z_]+` \|/ {n++; next}
    tbl {exit}
    END{print n+0}' "$1"
}

# 本文の「下の表のN種」の N
declared() {
  awk '/^## 解析仕様/{sec=1; next} sec && /^## /{exit} sec' "$1" \
    | grep -o '下の表の[0-9]*種' | head -1 | grep -o '[0-9]*'
}

check() { # <説明> <swift> <spec> <期待: pass|fail>
  local c r d result=pass
  c="$(count_cases "$2")"; r="$(count_rows "$3")"; d="$(declared "$3")"
  [ "$c" -gt 0 ] && [ "$c" = "$r" ] && [ "$c" = "${d:-x}" ] || result=fail
  if [ "$result" = "$4" ]; then ok "$1 (case=$c / 表=$r / 本文=${d:-なし})"; else ng "$1 (case=$c / 表=$r / 本文=${d:-なし})"; fi
}

echo "== 実物 =="
check "Analytics.swift・spec-app.md・本文の種数が一致する" "$SWIFT" "$SPEC" pass

echo "== 検知の自己検証（検査が空振りしていないこと）=="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed 's/下の表の\([0-9]*\)種/下の表の99種/' "$SPEC" > "$TMP/spec-wrong-n.md"
check "本文の N が違えば落ちる" "$SWIFT" "$TMP/spec-wrong-n.md" fail
grep -v '^| `reward_grant` |' "$SPEC" > "$TMP/spec-missing-row.md"
check "表の行が欠ければ落ちる" "$SWIFT" "$TMP/spec-missing-row.md" fail
awk '/^public enum AnalyticsEvent/{print; print "    case extraEvent"; next} {print}' "$SWIFT" > "$TMP/Analytics-extra.swift"
check "case が増えて docs が追随していなければ落ちる" "$TMP/Analytics-extra.swift" "$SPEC" fail

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
