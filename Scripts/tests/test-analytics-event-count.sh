#!/bin/bash
# AnalyticsEvent の case 数と docs/spec-app.md「解析仕様」の食い違いを検知する（#3428）。
#
# 「表の10種」が 11 種のまま取り残される事故が #2986・#3207・#3228 と繰り返したため、機械で見張る。
# 見るのは 3 つ: ① enum の case 数 ② spec-app.md の表のイベント行数 ③ 本文の「下の表のN種」の N。
# 3 つが一致していなければ落ちる。ケースを足したら表の行と「N種」も同じ PR で直す。
#
# 加えて語彙（#3479）: ④ RewardPurpose の case 数 = 本文「次のN個」= purpose 表の行数 = reward_ad 行の「上表のN値」、
# ⑤ AnalyticsEndCause の case 集合 = game_end 行の cause 列挙 = 本文「語彙は…のN値」の列挙。
#
# さらに（#3523）: ⑥ AnalyticsMode の値の集合 = 「mode」節の列挙、⑦ GameOpenSource の値の集合 = game_open 行の source 列挙。
# ⑥ は docs が release ブランチ先行で書かれる版（main の enum にまだ無い値）を MODE_PENDING に列挙して両側から除いて比べる
# （リリース後の同期で enum に入っても落ちない。入れ忘れ・書き忘れは MODE_PENDING 以外なら落ちる）。
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

# enum <名前> の直下にある case 名（バッククォート除去・改行区切り・ソート済み）
enum_cases() { # <swift> <enum名>
  awk -v e="$2" '$0 ~ "^public enum " e "[ :]"{f=1; next} f&&/^}/{exit} f&&/^    case /{sub(/^    case /,""); gsub(/`/,""); print}' "$1" | sort
}

# 「解析仕様」直前の purpose 表（| purpose | 内容 | で始まる表）のデータ行の purpose 名
purpose_rows() {
  awk '
    /^\| purpose \| 内容 \|/ {tbl=1; next}
    tbl && /^\|---/ {next}
    tbl && /^[[:space:]]*\| `[^`[:space:]]+` \|/ {s=$2; gsub(/`/,"",s); print s; next}
    tbl && /^[[:space:]]*\|/ {print "<invalid-purpose-row>"; next}
    tbl {exit}' "$1" | sort
}

purpose_declared() { grep -o '次の[0-9]*個に閉じる' "$1" | head -1 | grep -o '[0-9]*'; }
# reward_offer 行「上表のN値のうち、… `a`・`b` を除くM値」: N と M と除外名の数を返す（#3508）
offer_row() { grep '^| `reward_offer` |' "$1" | head -1; }
offer_all() { offer_row "$1" | grep -o '上表の[0-9]*値' | head -1 | grep -o '[0-9]*'; }
offer_rest() { offer_row "$1" | grep -o '除く[0-9]*値' | head -1 | grep -o '[0-9]*'; }
offer_excluded() { local t; t="$(offer_row "$1")"; t="${t#*上表の*値のうち}"; t="${t%%を除く*}"; printf '%s' "$t" | grep -o '`[^`]*`' | grep -c .; }
purpose_ad_declared() { grep '^| `reward_ad` |' "$1" | grep -o '上表の[0-9]*値' | head -1 | grep -o '[0-9]*'; }

# game_end 行の cause(a\|b\|…・ → 値の集合 / 本文「語彙は … のN値」の `値` の集合
cause_in_table() {
  grep '^| `game_end` |' "$1" | grep -o 'cause`([^・)]*' | head -1 | sed 's/cause`(//' | tr -d '\\' | tr '|' '\n' | sort
}
cause_in_prose() {
  tr '\n' ' ' < "$1" | sed -n 's/.*語彙は \(`pit`\)/\1/; s/値に閉じ.*//p' | grep -o '`[^`]*`' | tr -d '`' | sort
}

check_vocab() { # <説明> <swift> <spec> <期待: pass|fail>
  local rc rr rd ra result=pass ec ct cp
  rc="$(enum_cases "$2" RewardPurpose | grep -c .)"
  rr="$(purpose_rows "$3" | grep -c .)"
  rd="$(purpose_declared "$3")"; ra="$(purpose_ad_declared "$3")"
  [ "$rc" -gt 0 ] && [ "$rc" = "$rr" ] && [ "$rc" = "${rd:-x}" ] && [ "$rc" = "${ra:-x}" ] \
    && [ "$(enum_cases "$2" RewardPurpose)" = "$(purpose_rows "$3")" ] || result=fail
  local oa or ox
  oa="$(offer_all "$3")"; or="$(offer_rest "$3")"; ox="$(offer_excluded "$3")"
  [ "$rc" = "${oa:-x}" ] && [ "$ox" -gt 0 ] && [ "${or:-x}" = "$((rc - ox))" ] || result=fail
  ec="$(enum_cases "$2" AnalyticsEndCause)"; ct="$(cause_in_table "$3")"; cp="$(cause_in_prose "$3")"
  [ -n "$ec" ] && [ "$ec" = "$ct" ] && [ "$ec" = "$cp" ] || result=fail
  local d="purpose case=$rc/表=$rr/本文=${rd:-なし}/reward_ad=${ra:-なし}, reward_offer=${oa:-なし}→${or:-なし}(除外$ox), cause enum=$(echo $ec | wc -w | tr -d ' ')/表=$(echo $ct | wc -w | tr -d ' ')/本文=$(echo $cp | wc -w | tr -d ' ')"
  if [ "$result" = "$4" ]; then ok "$1 ($d)"; else ng "$1 ($d)"; fi
}

# enum <名前> の直下の case の「生の値」（`case a = "x"` なら x、`case b` なら b）
enum_values() { # <swift> <enum名>
  awk -v e="$2" '$0 ~ "^public enum " e "[ :]"{f=1; next} f&&/^}/{exit} f&&/^    case /{
    sub(/^    case /,""); gsub(/`/,"");
    if (match($0, /"[^"]*"/)) print substr($0, RSTART+1, RLENGTH-2); else {sub(/[ ,].*/,""); print}}' "$1" | sort
}

# release 先行で docs にだけ載っている mode の値（main の enum に入るまで。#3517）
MODE_PENDING="turtle pyramid cross"
# 「mode（AnalyticsMode）」の箇条書き（「写像は」の手前まで）にある `値`。本文中の鍵名は除く
mode_in_prose() {
  tr '\n' ' ' < "$1" | sed -n 's/.*- `mode`（`AnalyticsMode`）//; s/写像は.*//p' | grep -o '`[a-z_]*`' | tr -d '`' \
    | grep -vx -e level -e variant -e mode | sort -u
}
# 値の集合から MODE_PENDING を除く
minus_pending() { local w; w="$(printf '%s\n' $MODE_PENDING)"; grep -vxF -e "$w" || true; }
source_in_table() {
  grep '^| `game_open` |' "$1" | grep -o 'source`([^)]*' | head -1 | sed 's/source`(//' | tr -d '\\' | tr '|' '\n' | sort
}

check_vocab2() { # <説明> <swift> <spec> <期待: pass|fail>
  local result=pass me mp se st
  me="$(enum_values "$2" AnalyticsMode | minus_pending)"; mp="$(mode_in_prose "$3" | minus_pending)"
  [ -n "$me" ] && [ "$me" = "$mp" ] || result=fail
  se="$(enum_values "$2" GameOpenSource)"; st="$(source_in_table "$3")"
  [ -n "$se" ] && [ "$se" = "$st" ] || result=fail
  local d="mode enum=$(echo $me | wc -w | tr -d ' ')/本文=$(echo $mp | wc -w | tr -d ' '), source enum=$(echo $se | wc -w | tr -d ' ')/表=$(echo $st | wc -w | tr -d ' ')"
  if [ "$result" = "$4" ]; then ok "$1 ($d)"; else ng "$1 ($d)"; fi
}

echo "== 実物 =="
check "Analytics.swift・spec-app.md・本文の種数が一致する" "$SWIFT" "$SPEC" pass
check_vocab "RewardPurpose・AnalyticsEndCause の語彙が docs と一致する" "$SWIFT" "$SPEC" pass
check_vocab2 "AnalyticsMode・GameOpenSource の語彙が docs と一致する" "$SWIFT" "$SPEC" pass

echo "== 検知の自己検証（検査が空振りしていないこと）=="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed 's/下の表の\([0-9]*\)種/下の表の99種/' "$SPEC" > "$TMP/spec-wrong-n.md"
check "本文の N が違えば落ちる" "$SWIFT" "$TMP/spec-wrong-n.md" fail
grep -v '^| `reward_grant` |' "$SPEC" > "$TMP/spec-missing-row.md"
check "表の行が欠ければ落ちる" "$SWIFT" "$TMP/spec-missing-row.md" fail
awk '/^public enum AnalyticsEvent/{print; print "    case extraEvent"; next} {print}' "$SWIFT" > "$TMP/Analytics-extra.swift"
check "case が増えて docs が追随していなければ落ちる" "$TMP/Analytics-extra.swift" "$SPEC" fail

sed 's/次の\([0-9]*\)個に閉じる/次の99個に閉じる/' "$SPEC" > "$TMP/spec-wrong-purpose-n.md"
check_vocab "purpose の個数宣言が違えば落ちる" "$SWIFT" "$TMP/spec-wrong-purpose-n.md" fail
sed '/^| `reward_offer` |/s/上表の12値/上表の9値/' "$SPEC" > "$TMP/spec-wrong-offer.md"
check_vocab "reward_offer 行の総数が古ければ落ちる" "$SWIFT" "$TMP/spec-wrong-offer.md" fail
sed '/^| `reward_offer` |/s/除く10値/除く9値/' "$SPEC" > "$TMP/spec-wrong-offer2.md"
check_vocab "reward_offer 行の提示あり数が違えば落ちる" "$SWIFT" "$TMP/spec-wrong-offer2.md" fail
grep -v '^| `reroll` |' "$SPEC" > "$TMP/spec-missing-purpose.md"
check_vocab "purpose 表の行が欠ければ落ちる" "$SWIFT" "$TMP/spec-missing-purpose.md" fail
awk '/^public enum RewardPurpose/{print; print "    case extraPurpose"; next} {print}' "$SWIFT" > "$TMP/Analytics-purpose.swift"
check_vocab "RewardPurpose が増えて docs が追随していなければ落ちる" "$TMP/Analytics-purpose.swift" "$SPEC" fail
awk '/^public enum AnalyticsEndCause/{print; print "    case extraCause"; next} {print}' "$SWIFT" > "$TMP/Analytics-cause.swift"
check_vocab "AnalyticsEndCause が増えて docs が追随していなければ落ちる" "$TMP/Analytics-cause.swift" "$SPEC" fail
sed 's/animal\\|sink\\|hospital\\|buried・/animal\\|sink・/' "$SPEC" > "$TMP/spec-old-cause.md"
check_vocab "game_end 表の cause 列挙が古ければ落ちる" "$SWIFT" "$TMP/spec-old-cause.md" fail

awk '/^public enum AnalyticsMode/{print; print "    case extraMode"; next} {print}' "$SWIFT" > "$TMP/Analytics-mode.swift"
check_vocab2 "AnalyticsMode が増えて docs が追随していなければ落ちる" "$TMP/Analytics-mode.swift" "$SPEC" fail
sed 's/`bishop_cpu`（角落ち）/（角落ち）/' "$SPEC" > "$TMP/spec-missing-mode.md"
check_vocab2 "mode の列挙から値が欠ければ落ちる" "$SWIFT" "$TMP/spec-missing-mode.md" fail
awk '/^public enum GameOpenSource/{print; print "    case extraSource"; next} {print}' "$SWIFT" > "$TMP/Analytics-source.swift"
check_vocab2 "GameOpenSource が増えて docs が追随していなければ落ちる" "$TMP/Analytics-source.swift" "$SPEC" fail
sed 's/\\|deeplink\\|pickup)/)/' "$SPEC" > "$TMP/spec-old-source.md"
check_vocab2 "game_open の source 列挙が古ければ落ちる" "$SWIFT" "$TMP/spec-old-source.md" fail

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
