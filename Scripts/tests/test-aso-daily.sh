#!/bin/bash
# aso-daily.py の検証（#2231）。
#
# API は呼ばない（--no-fetch）。手書きの TSV を食わせて、日次の集計・重複排除（同じ日付が複数の
# インスタンスに入るので processingDate の新しい方だけを使う）・再実行で行が増えないこと・
# 週の表・月曜だけ週次コメントを投稿し同じ週に二重投稿しないこと・GET 以外を使わないことを確かめる。
#
# 使い方: bash Scripts/tests/test-aso-daily.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../aso-daily.py"
PY="${PYTHON:-python3}"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
expect_eq() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: '$3' / 実際: '$2')"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out"
mkdir -p "$TMP/in/eng" "$TMP/in/dl"

T=$'\t'
EH="Date${T}App Name${T}App Apple Identifier${T}Event${T}Page Type${T}Source Type${T}Engagement Type${T}Device${T}Platform Version${T}Territory${T}Counts${T}Unique Counts"
DH="Date${T}App Name${T}App Apple Identifier${T}Download Type${T}App Version${T}Device${T}Platform Version${T}Source Type${T}Page Type${T}Pre-Order${T}Territory${T}Counts"
e() { echo "$1${T}あそびば${T}6781719499${T}$2${T}$3${T}$4${T}${T}iPhone${T}iOS 27.2${T}$5${T}$6${T}$7"; }
d() { echo "$1${T}あそびば${T}6781719499${T}$2${T}1.1.11${T}iPhone${T}iOS 27.2${T}$3${T}No page${T}${T}$4${T}$5"; }

# engagement: 2026-10-06 版に 10/04・10/05、2026-10-07 版に 10/05（数字が増えている）・10/06
{
  echo "$EH"
  e 2026-10-04 Impression "No page" "App Store search" JP 100 80
  e 2026-10-04 "Page view" "Product page" "App Store search" JP 10 8
  e 2026-10-05 Impression "No page" "App Store search" JP 999 999
  e 2026-10-05 "Page view" "Product page" "App Store search" JP 99 99
} >"$TMP/in/eng/2026-10-06.tsv"
{
  echo "$EH"
  e 2026-10-05 Impression "No page" "App Store search" JP 200 150
  e 2026-10-05 Impression "No page" "App Store browse" US 50 40
  e 2026-10-05 "Page view" "Product page" "App Store search" JP 20 15
  e 2026-10-05 "Page view" "Developer page" "App Store search" JP 7 7
  e 2026-10-05 Tap "Product page" "App Store search" JP 30 30
  e 2026-10-06 Impression "No page" "Web referrer" JP 300 250
  e 2026-10-06 "Page view" "Product page" "Web referrer" JP 30 25
} >"$TMP/in/eng/2026-10-07.tsv"
# downloads: 2026-10-06 版に 10/05 の一部、2026-10-07 版に 10/05（確定値）・10/06
{
  echo "$DH"
  d 2026-10-05 "First-time download" "App Store search" JP 1
} >"$TMP/in/dl/2026-10-06.tsv"
{
  echo "$DH"
  d 2026-10-05 "First-time download" "App Store search" JP 5
  d 2026-10-05 "First-time download" "App referrer" US 1
  d 2026-10-05 Redownload "App Store browse" JP 2
  d 2026-10-05 Auto-update "App Store search" JP 40
  d 2026-10-06 "First-time download" "Web referrer" JP 6
} >"$TMP/in/dl/2026-10-07.tsv"

# 既存の daily.csv に raw/ に無い日付（10/01）を置いておく。作り直しで消えないこと
mkdir -p "$OUT"
printf 'date,impr_total,pv_total,dl_first_total\n2026-10-01,1000,40,10\n' >"$OUT/daily.csv"

run() { "$PY" "$TARGET" --out-dir "$OUT" "$@"; }
# 列名で値を引く: col <date> <column>
col() {
  "$PY" - "$OUT/daily.csv" "$1" "$2" <<'PY'
import csv, sys
for r in csv.DictReader(open(sys.argv[1], encoding="utf-8")):
    if r["date"] == sys.argv[2]:
        print(r.get(sys.argv[3], "<no column>"))
PY
}

echo "== 1. 取り込みと日次の集計 =="
run --no-fetch --no-weekly --import-engagement-tsv "$TMP"/in/eng/*.tsv --import-downloads-tsv "$TMP"/in/dl/*.tsv >/dev/null 2>"$TMP/err" \
  && ok "取り込みが成功する" || { ng "取り込みが失敗した"; cat "$TMP/err"; }
expect_eq "raw/ に保存される（engagement 2 本）" "$(ls "$OUT/raw/engagement" | wc -l | tr -d ' ')" "2"
expect_eq "raw/ に保存される（downloads 2 本）" "$(ls "$OUT/raw/downloads" | wc -l | tr -d ' ')" "2"
expect_eq "行は日付ごとに 1 行（10/01・10/04・10/05・10/06）" "$(tail -n +2 "$OUT/daily.csv" | cut -d, -f1 | tr '\n' ' ')" "2026-10-01 2026-10-04 2026-10-05 2026-10-06 "
expect_eq "10/04 のインプレッション" "$(col 2026-10-04 impr_total)" "100"
expect_eq "10/05 は新しい版を使う（インプレッション合計 200+50）" "$(col 2026-10-05 impr_total)" "250"
expect_eq "10/05 ユニーク" "$(col 2026-10-05 impr_unique)" "190"
expect_eq "10/05 日本" "$(col 2026-10-05 impr_total_jp)" "200"
expect_eq "10/05 日本以外" "$(col 2026-10-05 impr_total_other)" "50"
expect_eq "10/05 流入元: 検索" "$(col 2026-10-05 impr_search)" "200"
expect_eq "10/05 流入元: ブラウズ" "$(col 2026-10-05 impr_browse)" "50"
expect_eq "10/05 閲覧はプロダクトページだけ" "$(col 2026-10-05 pv_total)" "20"
expect_eq "10/05 初回 DL は新しい版（5+1）" "$(col 2026-10-05 dl_first_total)" "6"
expect_eq "10/05 初回 DL 日本以外" "$(col 2026-10-05 dl_first_other)" "1"
expect_eq "10/05 初回 DL アプリ参照" "$(col 2026-10-05 dl_first_app)" "1"
expect_eq "10/05 再 DL（アップデートは数えない）" "$(col 2026-10-05 dl_redownload_total)" "2"
expect_eq "10/05 押される割合 20/250" "$(col 2026-10-05 press_rate_pct)" "8.0"
expect_eq "10/05 入れる割合 6/20" "$(col 2026-10-05 install_rate_pct)" "30.0"
expect_eq "10/05 使った版の記録" "$(col 2026-10-05 engagement_processing_date)/$(col 2026-10-05 downloads_processing_date)" "2026-10-07/2026-10-07"
expect_eq "10/06 流入元: Web 参照" "$(col 2026-10-06 impr_web)" "300"
expect_eq "10/04 は DL が無いので入れる割合は空" "$(col 2026-10-04 install_rate_pct)" ""
expect_eq "raw/ に無い既存の行（10/01）は残る" "$(col 2026-10-01 impr_total)" "1000"

echo "== 2. 再実行しても重複しない =="
cp "$OUT/daily.csv" "$TMP/before.csv"
run --no-fetch --no-weekly --import-engagement-tsv "$TMP"/in/eng/*.tsv >/dev/null 2>&1
run --no-fetch --no-weekly >/dev/null 2>&1
if cmp -s "$TMP/before.csv" "$OUT/daily.csv"; then ok "daily.csv が変わらない"; else ng "再実行で daily.csv が変わった"; diff "$TMP/before.csv" "$OUT/daily.csv"; fi

echo "== 3. 週の表 =="
# 前週を 10/05〜10/11 とした表。前々週（9/28〜10/04）は 10/01・10/04
WEEK="$(run --print-weekly 2026-10-05 2>/dev/null)"
grep -q '^<!-- aso-weekly:2026-10-05 -->$' <<<"$WEEK" && ok "週の印が入る" || ng "週の印が無い"
grep -q '^## ASO 週次（10/5〜10/11）$' <<<"$WEEK" && ok "見出しの期間" || ng "見出しの期間が違う"
# 前週のインプレッション 1 日平均 = (250+300)/2 = 275、前々週 = (1000+100)/2 = 550 → -50.0%
grep -q '^| インプレッション（合計） | 275.0 | 550.0 | -50.0% |' <<<"$WEEK" && ok "1 日平均と前々週比" || { ng "インプレッションの行が違う"; grep 'インプレッション（合計）' <<<"$WEEK"; }
# 割合は期間合計の比: 前週 (20+30)/(250+300) = 9.1%
grep -q '^| 押される割合（閲覧÷インプレッション） | 9.1% |' <<<"$WEEK" && ok "割合は期間合計の比" || { ng "押される割合の行が違う"; grep '押される割合' <<<"$WEEK"; }
# 基準（10/3〜10/11）の列にも値が入る: インプレッション (100+250+300)/3 = 216.7
grep -q '^| インプレッション（合計） | 275.0 | 550.0 | -50.0% | 216.7 | +26.9% |' <<<"$WEEK" && ok "基準との比較" || ng "基準の列が違う"
expect_eq "表の行数（見出し 1 行 + 指標 16 行）" "$(grep -c '^| ' <<<"$WEEK")" "17"

echo "== 4. 週次コメントの投稿（偽の gh） =="
FAKE="$TMP/fakegh"
mkdir -p "$FAKE"
cat >"$FAKE/gh" <<'SH'
#!/bin/bash
echo "$*" >>"$FAKE_LOG"
case "$1" in
  api) cat "$FAKE_COMMENTS" 2>/dev/null; exit 0 ;;
  issue)
    while [ $# -gt 0 ]; do [ "$1" = "--body-file" ] && cat "$2" >>"$FAKE_COMMENTS"; shift; done
    echo "https://github.com/hiroky1983/game_collection/issues/2231#issuecomment-1"; exit 0 ;;
esac
exit 1
SH
chmod +x "$FAKE/gh"
export FAKE_LOG="$TMP/gh.log" FAKE_COMMENTS="$TMP/comments.txt" ASO_GH="$FAKE/gh"

run --no-fetch --today 2026-10-12 >/dev/null 2>&1   # 月曜 → 10/05 の週
expect_eq "月曜は投稿する" "$(grep -c '^issue comment 2231' "$FAKE_LOG")" "1"
grep -q 'aso-weekly:2026-10-05' "$FAKE_COMMENTS" && ok "前週（10/05〜）を投稿" || ng "投稿した週が違う"
run --no-fetch --today 2026-10-12 >/dev/null 2>&1   # 同じ月曜にもう一度
expect_eq "同じ週には二重投稿しない" "$(grep -c '^issue comment 2231' "$FAKE_LOG")" "1"
run --no-fetch --today 2026-10-14 >/dev/null 2>&1   # 水曜: 同じ週は投稿済みなので見送り
expect_eq "月曜以外の実行でも投稿済みの週は見送る" "$(grep -c '^issue comment 2231' "$FAKE_LOG")" "1"
run --no-fetch --today 2026-10-21 --no-weekly >/dev/null 2>&1   # 水曜（次の週・月曜は逃した）
expect_eq "--no-weekly は投稿しない" "$(grep -c '^issue comment 2231' "$FAKE_LOG")" "1"
run --no-fetch --today 2026-10-21 >/dev/null 2>&1   # 月曜を逃した週: 水曜の実行で取り戻す
expect_eq "月曜を逃しても次の実行で投稿する" "$(grep -c '^issue comment 2231' "$FAKE_LOG")" "2"
grep -q 'aso-weekly:2026-10-12' "$FAKE_COMMENTS" && ok "逃した週（10/12〜）を投稿" || ng "逃した週を投稿していない"
printf '#!/bin/bash\nexit 1\n' >"$FAKE/gh"
run --no-fetch --today 2026-10-19 >/dev/null 2>&1
expect_eq "gh が失敗したら終了コード 1" "$?" "1"

echo "== 5. ASC は GET だけ =="
if grep -nE "method *=|\"(POST|PATCH|PUT|DELETE)\"" "$TARGET"; then ng "GET 以外のリクエストを組み立てている"; else ok "GET 以外のメソッド指定が無い"; fi
if grep -nE "print\(.*(url|token|_auth|make_jwt)" "$TARGET"; then ng "URL・トークンを出力している疑い"; else ok "URL・トークンを print しない"; fi

echo
echo "結果: ${PASS} 件成功 / ${FAIL} 件失敗"
[ "$FAIL" -eq 0 ]
