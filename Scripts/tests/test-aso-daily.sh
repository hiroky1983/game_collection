#!/bin/bash
# aso-daily.py の検証（#2231）。
#
# API は呼ばない（--no-fetch）。手書きの TSV を食わせて、日次の集計・重複排除（同じ日付が複数の
# インスタンスに入るので processingDate の新しい方だけを使う）・再実行で行が増えないこと・
# 週の表・月曜に前週を投稿し（月曜を逃した週は次の実行で取り戻す）同じ週に二重投稿しないこと・
# GET 以外を使わないことを確かめる。
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

posts() { cat "$FAKE_LOG" 2>/dev/null | grep -c '^issue comment 2231'; }
run --no-fetch --today 2026-10-12 >/dev/null 2>&1   # 月曜 → 10/05 の週
expect_eq "月曜は前週を投稿する" "$(posts)" "1"
grep -q 'aso-weekly:2026-10-05' "$FAKE_COMMENTS" && ok "前週（10/05〜）を投稿" || ng "投稿した週が違う"
run --no-fetch --today 2026-10-12 >/dev/null 2>&1   # 同じ月曜にもう一度
expect_eq "同じ週には二重投稿しない" "$(posts)" "1"
before_api="$(grep -c '^api' "$FAKE_LOG")"
run --no-fetch --today 2026-10-13 >/dev/null 2>&1   # 火曜: 同じ週。控えで見送り、GitHub にも問い合わせない
expect_eq "火曜は投稿しない（同じ週）" "$(posts)" "1"
expect_eq "投稿済みの週は控えで判定し gh を呼ばない" "$(grep -c '^api' "$FAKE_LOG")" "$before_api"
rm -f "$OUT/weekly-posted.txt"                       # 控えが消えても Issue のコメントの印で見送る
run --no-fetch --today 2026-10-14 >/dev/null 2>&1
expect_eq "控えが無くても Issue の印で二重投稿しない" "$(posts)" "1"
run --no-fetch --today 2026-10-19 --no-weekly >/dev/null 2>&1
expect_eq "--no-weekly は月曜でも投稿しない" "$(posts)" "1"
run --no-fetch --today 2026-10-20 >/dev/null 2>&1   # 10/19（月）の実行を逃し火曜に動いた
expect_eq "月曜を逃した週は次の実行で投稿する" "$(posts)" "2"
grep -q 'aso-weekly:2026-10-12' "$FAKE_COMMENTS" && ok "取り戻したのは 10/12〜の週" || ng "取り戻した週が違う"
printf '#!/bin/bash\nexit 1\n' >"$FAKE/gh"
run --no-fetch --today 2026-10-26 >/dev/null 2>&1
expect_eq "gh が失敗したら終了コード 1" "$?" "1"

echo "== 5. ASC は GET だけ =="
if grep -nE "method *=|\"(POST|PATCH|PUT|DELETE)\"" "$TARGET"; then ng "GET 以外のリクエストを組み立てている"; else ok "GET 以外のメソッド指定が無い"; fi
if grep -nE "print\(.*(url|token|_auth|make_jwt)" "$TARGET"; then ng "URL・トークンを出力している疑い"; else ok "URL・トークンを print しない"; fi

echo "== 6. GA4（#2238。runReport の応答 JSON を食わせる・API は呼ばない） =="
G1="$TMP/ga4-1" G2="$TMP/ga4-2" GBAD="$TMP/ga4-bad"
mkdir -p "$G1" "$G2" "$GBAD"
"$PY" - "$G1" "$G2" <<'PY'
import json, os, sys
def rep(dims, mets, rows):
    return {"dimensionHeaders": [{"name": d} for d in dims], "metricHeaders": [{"name": m} for m in mets],
            "rows": [{"dimensionValues": [{"value": v} for v in r[:len(dims)]],
                      "metricValues": [{"value": str(v)} for v in r[len(dims):]]} for r in rows],
            "rowCount": len(rows)}
EV = ["date", "eventName"]; EG = EV + ["customEvent:game_id"]; EM = ["eventCount", "totalUsers"]
AD = ["totalAdRevenue", "publisherAdImpressions", "publisherAdClicks"]
g1 = {
    # 前々週 10/5〜10/11 は 80 人、前週 10/12〜10/18 は 100〜106 人
    "active": rep(["date"], ["activeUsers"], [["202610%02d" % d, 80] for d in range(5, 12)]
                  + [["202610%02d" % d, 88 + d] for d in range(12, 19)]),
    "first_open": rep(["date"], ["eventCount"], [["20261012", 10]]),
    "events": rep(EV, EM, [["20261012", "game_start", 51, 20], ["20261012", "reward_ad", 4, 3],
                           ["20261012", "reward_request", 8, 5], ["20261012", "first_open", 9, 9]]),
    "events_by_game": rep(EG, EM, [["20261012", "game_start", "poker", 30, 10], ["20261012", "game_start", "anzan", 20, 8],
                                   ["20261012", "game_start", "(not set)", 5, 1], ["20261012", "game_start", "shogi", 1, 1],
                                   ["20261005", "game_start", "poker", 15, 5], ["20261012", "reward_ad", "poker", 4, 3]]),
    # 10/11 は AdMob リンク前で 0（データなし扱い）
    "ads": rep(["date"], AD, [["20261011", 0, 0, 0], ["20261012", 1.5, 1000, 3], ["20261013", "0.5", 500, 1]]),
    "ads_by_unit": rep(["date", "adFormat", "adUnitName"], AD, [["20261012", "Rewarded", "rescue", 1.5, 1000, 3]]),
}
# 2 回目: 10/12 の分だけが返り、数字が変わっている（anzan 20→25、shogi は消える、アクティブ 100→111）
def only_1012(r):
    return dict(r, rows=[x for x in r["rows"] if x["dimensionValues"][0]["value"] == "20261012"])
g2 = {k: only_1012(v) for k, v in g1.items()}
g2["active"] = rep(["date"], ["activeUsers"], [["20261012", 111]])
g2["events_by_game"] = only_1012(rep(EG, EM, [["20261012", "game_start", "poker", 30, 10],
                                              ["20261012", "game_start", "anzan", 25, 9],
                                              ["20261012", "reward_ad", "poker", 4, 3]]))
for d, g in ((sys.argv[1], g1), (sys.argv[2], g2)):
    for k, v in g.items():
        json.dump(v, open(os.path.join(d, k + ".json"), "w"))
PY
echo '{not json' >"$GBAD/active.json"
GOUT="$TMP/ga4out"
grun() { "$PY" "$TARGET" --out-dir "$OUT" --ga4-out-dir "$GOUT" --no-fetch "$@"; }
gcol() {  # gcol <date> <metric> [game_id] [ad_unit]
  "$PY" - "$GOUT/daily.csv" "$1" "$2" "${3:-}" "${4:-}" <<'PY'
import csv, sys
v = [r["value"] for r in csv.DictReader(open(sys.argv[1], encoding="utf-8"))
     if (r["date"], r["metric"], r["game_id"], r["ad_unit"]) == tuple(sys.argv[2:6])]
print(",".join(v) if v else "<none>")
PY
}
grun --no-weekly --ga4-from-json "$G1" >/dev/null 2>"$TMP/gerr" && ok "GA4 の取り込みが成功する" || { ng "GA4 の取り込みが失敗した"; cat "$TMP/gerr"; }
expect_eq "CSV の列" "$(head -1 "$GOUT/daily.csv" | tr -d '\r')" "date,metric,game_id,ad_unit,value"
expect_eq "アクティブユーザー（10/12）" "$(gcol 2026-10-12 active_users)" "100"
expect_eq "新規（first_open）" "$(gcol 2026-10-12 new_users)" "10"
expect_eq "game_start 全体の回数・人数" "$(gcol 2026-10-12 game_start_count)/$(gcol 2026-10-12 game_start_users)" "51/20"
expect_eq "game_start ゲーム別（anzan）" "$(gcol 2026-10-12 game_start_count anzan)/$(gcol 2026-10-12 game_start_users anzan)" "20/8"
expect_eq "game_id が (not set) の行はゲーム別に入れない" "$(grep -c 'not set' "$GOUT/daily.csv")" "0"
expect_eq "対象外のイベント（first_open）は events から拾わない" "$(gcol 2026-10-12 first_open_count)" "<none>"
expect_eq "reward_request・reward_ad（全体）" "$(gcol 2026-10-12 reward_request_count)/$(gcol 2026-10-12 reward_ad_count)" "8/4"
expect_eq "reward_ad（ゲーム別）" "$(gcol 2026-10-12 reward_ad_count poker)" "4"
expect_eq "広告収益（小数のまま）" "$(gcol 2026-10-12 ad_revenue)/$(gcol 2026-10-13 ad_revenue)" "1.5/0.5"
expect_eq "広告の表示回数・クリック" "$(gcol 2026-10-12 ad_impressions)/$(gcol 2026-10-12 ad_clicks)" "1000/3"
expect_eq "広告フォーマット/ユニット別" "$(gcol 2026-10-12 ad_revenue '' Rewarded/rescue)" "1.5"

grun --no-weekly --ga4-from-json "$G2" >/dev/null 2>&1
expect_eq "取り直した日は上書き（アクティブ 100→111）" "$(gcol 2026-10-12 active_users)" "111"
expect_eq "取り直した日は上書き（anzan 20→25）" "$(gcol 2026-10-12 game_start_count anzan)" "25"
expect_eq "取り直しで返らなくなった行は消える（shogi）" "$(gcol 2026-10-12 game_start_count shogi)" "<none>"
expect_eq "取り直していない日は残る（10/13）" "$(gcol 2026-10-13 active_users)" "101"
cp "$GOUT/daily.csv" "$TMP/ga4-before.csv"
grun --no-weekly --ga4-from-json "$G2" >/dev/null 2>&1
grun --no-weekly >/dev/null 2>&1
if cmp -s "$TMP/ga4-before.csv" "$GOUT/daily.csv"; then ok "再実行で GA4 の CSV が変わらない（重複しない）"; else ng "再実行で GA4 の CSV が変わった"; fi
expect_eq "(date, metric, game_id, ad_unit) が一意" "$(tail -n +2 "$GOUT/daily.csv" | cut -d, -f1-4 | sort | uniq -d | wc -l | tr -d ' ')" "0"

echo "== 7. GA4 の週の表 =="
GW="$("$PY" "$TARGET" --out-dir "$OUT" --ga4-out-dir "$GOUT" --print-weekly 2026-10-12 2>/dev/null)"
grep -q '^## GA4（App Store 版）$' <<<"$GW" && ok "GA4 の節が付く" || ng "GA4 の節が無い"
# 前週 (111+101+102+103+104+105+106)/7 = 104.6、前々週 80 → +30.7%
grep -q '^| アクティブユーザー | 104.6 | 80.0 | +30.7% |$' <<<"$GW" && ok "アクティブユーザーの 1 日平均と前々週比" || { ng "アクティブユーザーの行が違う"; grep 'アクティブユーザー' <<<"$GW"; }
grep -q '^| 1 | ポーカー（poker） | 30 | 10.0 | 15 | +100.0% |$' <<<"$GW" && ok "プレイ数の 1 位と前々週比" || { ng "上位の行が違う"; grep '^| 1 |' <<<"$GW"; }
grep -q '^| 2 | ぱっと暗算（anzan） | 25 |' <<<"$GW" && ok "プレイ数の 2 位" || ng "2 位の行が違う"
grep -q '^| 10/12 | 0 | 25／9 | 0 |$' <<<"$GW" && ok "新ゲーム・柵越えの推移（10/12）" || { ng "推移の行が違う"; grep '^| 10/12' <<<"$GW"; }
grep -q '前週の視聴完了 4 回（前々週 0 回・—）、要求 8 回、完了率 50.0%' <<<"$GW" && ok "リワード広告の視聴" || { ng "視聴の行が違う"; grep '前週の視聴完了' <<<"$GW"; }
# 表示回数 0 の日（10/11）は除く。前週は 10/12・10/13 の 2 日: 収益 (1.5+0.5)/2、表示 750、eCPM 2.0/1500*1000
grep -q 'データのある日数: 前週 2 日／前々週 0 日' <<<"$GW" && ok "広告は表示回数 0 の日をデータなしにする" || { ng "広告の日数が違う"; grep '前週 .* 日／前々週' <<<"$GW"; }
grep -q '^| 広告収益 | \$1.00 | — | — |$' <<<"$GW" && ok "広告収益の 1 日平均" || { ng "広告収益の行が違う"; grep '^| 広告収益' <<<"$GW"; }
grep -q '^| 表示回数 | 750.0 |' <<<"$GW" && ok "表示回数の 1 日平均" || ng "表示回数の行が違う"
grep -q '^| 1,000 回あたりの収益（eCPM 相当・期間合計の比） | \$1.33 |' <<<"$GW" && ok "1,000 回あたりの収益" || { ng "eCPM の行が違う"; grep 'eCPM' <<<"$GW"; }
grep -q '^| Rewarded/rescue | \$1.50 | 1,000 | \$1.50 |$' <<<"$GW" && ok "広告ユニット別" || { ng "ユニット別の行が違う"; grep 'Rewarded' <<<"$GW"; }
EMPTYW="$("$PY" "$TARGET" --out-dir "$OUT" --ga4-out-dir "$TMP/no-ga4" --print-weekly 2026-10-12 2>/dev/null)"
grep -q '前週のデータがありません' <<<"$EMPTYW" && ok "GA4 のデータが無い週は無いと書く" || ng "データが無い週の表示が違う"

echo "== 8. GA4 の失敗を黙らない =="
cat >"$FAKE/gh" <<'SH'
#!/bin/bash
echo "$*" >>"$FAKE_LOG"
case "$1" in
  api) exit 0 ;;
  issue) while [ $# -gt 0 ]; do [ "$1" = "--body-file" ] && cat "$2" >"$FAKE_BODY"; shift; done
         echo "https://github.com/hiroky1983/game_collection/issues/2231#issuecomment-2"; exit 0 ;;
esac
exit 1
SH
export FAKE_BODY="$TMP/body.md"
cp "$GOUT/daily.csv" "$TMP/ga4-keep.csv"
rm -f "$OUT/weekly-posted.txt"   # 偽の gh は投稿済みの印を返さないので、10/12 の週をもう一度投稿させる
grun --today 2026-10-20 --ga4-from-json "$GBAD" >"$TMP/glog" 2>&1
expect_eq "GA4 が失敗したら終了コード 1" "$?" "1"
grep -q 'エラー: GA4' "$TMP/glog" && ok "ログに GA4 のエラーが出る" || { ng "ログに GA4 のエラーが無い"; cat "$TMP/glog"; }
grep -q 'GA4 の取得に失敗しました' "$FAKE_BODY" && ok "週次コメントに GA4 の失敗が出る" || ng "週次コメントに失敗が出ない"
grep -q '^| アクティブユーザー | 104.6 |' "$FAKE_BODY" && ok "失敗しても保存済みの数字で表を出す" || ng "保存済みの数字が出ない"
grep -q '^## ASO 週次' "$FAKE_BODY" && ok "GA4 が失敗しても ASO の節は出る" || ng "ASO の節が無い"
if cmp -s "$TMP/ga4-keep.csv" "$GOUT/daily.csv"; then ok "失敗しても GA4 の CSV を消さない"; else ng "失敗で GA4 の CSV が変わった"; fi
if grep -nE "print\(.*(private_key|access_token|assertion|tok\b)" "$TARGET"; then ng "鍵・トークンを出力している疑い"; else ok "鍵・トークンを print しない"; fi

echo
echo "結果: ${PASS} 件成功 / ${FAIL} 件失敗"
[ "$FAIL" -eq 0 ]
