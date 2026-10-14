#!/bin/bash
# aso-daily.py の検証（#2231・#2238）。
#
# API は呼ばない（--no-fetch）。手書きの TSV を食わせて、日次の集計・重複排除（同じ日付が複数の
# インスタンスに入るので processingDate の新しい方だけを使う）・再実行で行が増えないこと・
# スプレッドシートに出す各タブの中身（--sheets-dump で TSV に出す）・GA4 の応答 JSON からの保存と取り直しの上書き・
# 取得失敗を週次まとめの先頭に出すこと・ASC は GET 以外を使わないことを確かめる。
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
# 既定では AdMob の画面取得 CSV を読まない（この Mac の本物の ~/asobiba-kpi/admob/history_ui_export.csv を
# 誤って拾ってテストが環境依存にならないよう、存在しないパスを既定にする。個別のテストで上書きする）
NOADMOB="$TMP/no-admob.csv"

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

run() { "$PY" "$TARGET" --out-dir "$OUT" --admob-history "$NOADMOB" "$@"; }
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
run --no-fetch --no-sheets --import-engagement-tsv "$TMP"/in/eng/*.tsv --import-downloads-tsv "$TMP"/in/dl/*.tsv >/dev/null 2>"$TMP/err" \
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
run --no-fetch --no-sheets --import-engagement-tsv "$TMP"/in/eng/*.tsv >/dev/null 2>&1
run --no-fetch --no-sheets >/dev/null 2>&1
if cmp -s "$TMP/before.csv" "$OUT/daily.csv"; then ok "daily.csv が変わらない"; else ng "再実行で daily.csv が変わった"; diff "$TMP/before.csv" "$OUT/daily.csv"; fi

echo "== 3. スプレッドシートの中身（ASO・API は呼ばず TSV に出す） =="
DUMP="$TMP/dump"
run --no-fetch --today 2026-10-12 --sheets-dump "$DUMP" >/dev/null 2>"$TMP/err" && ok "タブの書き出しが成功する" || { ng "タブの書き出しが失敗した"; cat "$TMP/err"; }
for t in 週次まとめ "ASO（日次）" "GA4（日次）" "ゲーム別（日次）" "広告（日次）"; do
  [ -f "$DUMP/${t}.tsv" ] && ok "タブ「${t}」がある" || ng "タブ「${t}」が無い"
done
expect_eq "ASO（日次）は daily.csv の全行（見出し + 4 日）" "$(wc -l <"$DUMP/ASO（日次）.tsv" | tr -d ' ')" "5"
expect_eq "ASO（日次）の見出しは日本語" "$(head -1 "$DUMP/ASO（日次）.tsv" | cut -f1-2)" "日付${T}インプレッション"
expect_eq "ASO（日次）の 10/05 の行" "$(grep '^2026-10-05' "$DUMP/ASO（日次）.tsv" | cut -f1-2)" "2026-10-05${T}250"
W="$DUMP/週次まとめ.tsv"
grep -q '^最終更新: .*（ASC・GA4 とも取得成功）$' "$W" && ok "先頭に最終更新" || { ng "先頭の行が違う"; head -2 "$W"; }
# 表は 47 行目から。月曜（10/12）の実行では 10/5〜10/11 が最新の週（終わった週）
expect_eq "表の見出し" "$(sed -n 47p "$W" | cut -f1-6)" "指標${T}基準（10/3〜10/11）${T}目安（会長）${T}10/5〜10/11${T}前週比${T}基準比"
# 10/5 週のインプレッション 1 日平均 (250+300)/2 = 275、前週 (1000+100)/2 = 550 → -50.0%、基準 (100+250+300)/3 = 216.67 → +26.9%
expect_eq "インプレッションの 1 日平均・前週比・基準比・目安" "$(grep '^インプレッション（合計）' "$W" | cut -f2-6)" "216.67${T}4000${T}275.0${T}-50.0%${T}+26.9%"
# 割合は期間合計の比で、比較は差（ポイント）: 10/5 週 (20+30)/(250+300) = 9.09%、前週 (40+10)/(1000+100) = 4.55%
expect_eq "押される割合は期間合計の比・差はポイント" "$(grep '^押される割合' "$W" | cut -f4-5)" "9.09${T}+4.5pt"
expect_eq "データのある日数（ASO）" "$(grep '^データのある日数（ASO）' "$W" | cut -f4)" "2"
run --no-fetch --today 2026-10-14 --sheets-dump "$DUMP" >/dev/null 2>&1
expect_eq "月曜以外は途中の週も出す" "$(sed -n 47p "$DUMP/週次まとめ.tsv" | cut -f4)" "10/12〜10/18（途中）"

echo "== 4. 週次コメントは投稿しない =="
if grep -nE "issue comment|gh_cmd|ASO_GH" "$TARGET"; then ng "Issue へのコメント投稿が残っている"; else ok "Issue へのコメント投稿が無い"; fi

echo "== 5. ASC は GET だけ =="
# ASC の API を呼ぶ部分（class Asc〜fetch）だけを見る。GA4・Sheets は POST/PUT を使う
ASC_SRC="$(awk '/^class Asc:/{f=1} /^# -+ GA4/{f=0} f' "$TARGET")"
[ -n "$ASC_SRC" ] && ok "ASC の部分を切り出せる" || ng "ASC の部分を切り出せない"
if grep -nE "method *=|\"(POST|PATCH|PUT|DELETE)\"" <<<"$ASC_SRC"; then ng "ASC で GET 以外のリクエストを組み立てている"; else ok "ASC は GET 以外のメソッド指定が無い"; fi
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
grun() { "$PY" "$TARGET" --out-dir "$OUT" --ga4-out-dir "$GOUT" --no-fetch --admob-history "$NOADMOB" "$@"; }
gcol() {  # gcol <date> <metric> [game_id] [ad_unit]
  "$PY" - "$GOUT/daily.csv" "$1" "$2" "${3:-}" "${4:-}" <<'PY'
import csv, sys
v = [r["value"] for r in csv.DictReader(open(sys.argv[1], encoding="utf-8"))
     if (r["date"], r["metric"], r["game_id"], r["ad_unit"]) == tuple(sys.argv[2:6])]
print(",".join(v) if v else "<none>")
PY
}
grun --no-sheets --ga4-from-json "$G1" >/dev/null 2>"$TMP/gerr" && ok "GA4 の取り込みが成功する" || { ng "GA4 の取り込みが失敗した"; cat "$TMP/gerr"; }
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

grun --no-sheets --ga4-from-json "$G2" >/dev/null 2>&1
expect_eq "取り直した日は上書き（アクティブ 100→111）" "$(gcol 2026-10-12 active_users)" "111"
expect_eq "取り直した日は上書き（anzan 20→25）" "$(gcol 2026-10-12 game_start_count anzan)" "25"
expect_eq "取り直しで返らなくなった行は消える（shogi）" "$(gcol 2026-10-12 game_start_count shogi)" "<none>"
expect_eq "取り直していない日は残る（10/13）" "$(gcol 2026-10-13 active_users)" "101"
cp "$GOUT/daily.csv" "$TMP/ga4-before.csv"
grun --no-sheets --ga4-from-json "$G2" >/dev/null 2>&1
grun --no-sheets >/dev/null 2>&1
if cmp -s "$TMP/ga4-before.csv" "$GOUT/daily.csv"; then ok "再実行で GA4 の CSV が変わらない（重複しない）"; else ng "再実行で GA4 の CSV が変わった"; fi
expect_eq "(date, metric, game_id, ad_unit) が一意" "$(tail -n +2 "$GOUT/daily.csv" | cut -d, -f1-4 | sort | uniq -d | wc -l | tr -d ' ')" "0"

echo "== 7. スプレッドシートの中身（GA4） =="
GD="$TMP/gdump"
"$PY" "$TARGET" --out-dir "$OUT" --ga4-out-dir "$GOUT" --no-fetch --admob-history "$NOADMOB" --today 2026-10-19 --sheets-dump "$GD" >/dev/null 2>"$TMP/gerr" \
  && ok "GA4 込みのタブの書き出しが成功する" || { ng "GA4 込みのタブの書き出しが失敗した"; cat "$TMP/gerr"; }
row() { grep "^$2" "$GD/$1.tsv"; }
expect_eq "GA4（日次）10/12: アクティブ（App Store 版）" "$(row 'GA4（日次）' 2026-10-12 | cut -f2)" "111"
# 末尾に AdMob の画面取得（円）の列が 1 本付く（この区間は --admob-history を渡していないので空）
expect_eq "GA4（日次）10/12: 広告収益・表示回数・クリック" "$(row 'GA4（日次）' 2026-10-12 | awk -F'\t' '{print $(NF-3)"/"$(NF-2)"/"$(NF-1)}')" "1.5/1000/3"
expect_eq "GA4（日次）10/12: AdMob 画面の列は空（CSV を渡していない）" "$(row 'GA4（日次）' 2026-10-12 | awk -F'\t' '{print $NF}')" ""
expect_eq "ゲーム別（日次）: anzan の 10/12（ID・名前・開いた・人数・プレイ開始・人数）" "$(row 'ゲーム別（日次）' "2026-10-12${T}'anzan" | cut -f2-7)" "'anzan${T}ぱっと暗算${T}0${T}0${T}25${T}9"
# 広告（日次）は 取得元 列が増えた（日付・取得元・ユニット・推定収益円・収益USD・表示回数・クリック・eCPM円・1,000回あたりUSD・リクエスト・マッチ率・表示率）
expect_eq "広告（日次）: 10/12 GA4 全体（収益・表示・クリック・1,000 回あたり）" "$(row '広告（日次）' "2026-10-12${T}GA4${T}全体" | cut -f5-7,9)" "1.5${T}1000${T}3${T}1.5"
expect_eq "広告（日次）: GA4 ユニット別" "$(row '広告（日次）' "2026-10-12${T}GA4${T}Rewarded/rescue" | cut -f5)" "1.5"
expect_eq "広告（日次）: リンク前の 0 の日（10/11）は 1,000 回あたりを空に" "$(row '広告（日次）' "2026-10-11${T}GA4${T}全体" | cut -f9)" ""
GWS="$GD/週次まとめ.tsv"
expect_eq "表の最新の週は 10/12〜10/18" "$(sed -n 47p "$GWS" | cut -f4)" "10/12〜10/18"
# 前週 (111+101+102+103+104+105+106)/7 = 104.57、前々週 80 → +30.7%
expect_eq "アクティブユーザーの 1 日平均と前週比" "$(grep '^アクティブユーザー（App Store 版）' "$GWS" | cut -f4-5)" "104.57${T}+30.7%"
# 広告は表示回数 0 の日（10/11）を除く。10/12・10/13 の 2 日: 収益 (1.5+0.5)/2、表示 750、1,000 回あたり 2.0/1500*1000
expect_eq "広告収益の 1 日平均（0 の日を除く）" "$(grep '^広告収益 USD' "$GWS" | cut -f4)" "1.0"
expect_eq "広告の表示回数の 1 日平均" "$(grep '^広告の表示回数' "$GWS" | cut -f4)" "750.0"
expect_eq "1,000 回あたりの収益" "$(grep '^1,000 回あたりの収益' "$GWS" | cut -f4)" "1.33"
expect_eq "前々週は広告のデータなし（0 の日だけ）→ 空" "$(grep '^広告収益 USD' "$GWS" | cut -f7)" ""
expect_eq "新ゲームの推移（ぱっと暗算のプレイ開始）" "$(grep '^プレイ開始 ぱっと暗算' "$GWS" | cut -f4)" "25.0"

echo "== 8. 取得の失敗を黙らない =="
cp "$GOUT/daily.csv" "$TMP/ga4-keep.csv"
"$PY" "$TARGET" --out-dir "$OUT" --ga4-out-dir "$GOUT" --no-fetch --admob-history "$NOADMOB" --ga4-from-json "$GBAD" --today 2026-10-19 --sheets-dump "$GD" >"$TMP/glog" 2>&1
expect_eq "GA4 が失敗したら終了コード 1" "$?" "1"
grep -q 'エラー: GA4' "$TMP/glog" && ok "ログに GA4 のエラーが出る" || { ng "ログに GA4 のエラーが無い"; cat "$TMP/glog"; }
grep -q '^取得失敗: .* JST・GA4 — ' "$GWS" && ok "週次まとめの先頭に「取得失敗: 日時・どの取得か」" || { ng "取得失敗の行が無い"; head -3 "$GWS"; }
expect_eq "取得失敗は 1 行目" "$(head -1 "$GWS" | cut -c1-5)" "取得失敗:"
expect_eq "失敗しても保存済みの数字でタブを作る" "$(grep '^アクティブユーザー（App Store 版）' "$GWS" | cut -f4)" "104.57"
expect_eq "GA4 が失敗しても ASO のタブは作る" "$(wc -l <"$GD/ASO（日次）.tsv" | tr -d ' ')" "5"
if cmp -s "$TMP/ga4-keep.csv" "$GOUT/daily.csv"; then ok "失敗しても GA4 の CSV を消さない"; else ng "失敗で GA4 の CSV が変わった"; fi
if grep -nE "print\(.*(private_key|access_token|assertion|tok\b)|log\(.*(private_key|access_token|assertion|tok\b)" "$TARGET"; then ng "鍵・トークンを出力している疑い"; else ok "鍵・トークンを出力しない"; fi

echo "== 9. AdMob の画面取得（過去分）の組み込み（会長指示・#2238 追補） =="
# 10/11・10/12 は GA4 にもデータがある日。10/11 は GA4 側が表示回数 0（AdMob リンク前のダミー）なので、
# AdMob 画面の行が無いと「データなし」扱いだった → AdMob 画面があれば優先して使われることを確かめる。
# 2026-08-27 は GA4 側に無い日（AdMob 画面だけの日）で、GA4（日次）に行として出ること（日付の和集合）も見る。
ADMOB_CSV="$TMP/admob-history.csv"
{
  echo "date,est_revenue_jpy,ecpm_jpy,requests,match_rate_pct,matched_requests,show_rate_pct,impressions,clicks"
  echo "2026-08-27,2,92,25,100.00,25,96.00,24,0"
  echo "2026-10-11,20,60,600,85.00,510,91.00,5000,8"
  echo "2026-10-12,30,70,700,86.00,600,92.00,6000,9"
} >"$ADMOB_CSV"
AD="$TMP/admobdump"
"$PY" "$TARGET" --out-dir "$OUT" --ga4-out-dir "$GOUT" --no-fetch --admob-history "$ADMOB_CSV" --today 2026-10-19 --sheets-dump "$AD" >/dev/null 2>"$TMP/aerr" \
  && ok "AdMob 込みのタブの書き出しが成功する" || { ng "AdMob 込みのタブの書き出しが失敗した"; cat "$TMP/aerr"; }
arow() { grep "^$2" "$AD/$1.tsv"; }
expect_eq "広告（日次）: AdMob 画面の行（10/12・推定収益・表示・クリック・eCPM・リクエスト・マッチ率・表示率）" \
  "$(arow '広告（日次）' "2026-10-12${T}AdMob 画面${T}合計" | cut -f4,6-8,10-12)" "30${T}6000${T}9${T}70${T}700${T}86${T}92"
expect_eq "広告（日次）: 同じ日の GA4 の行は消えずに残る（10/12・取得元=GA4）" \
  "$(arow '広告（日次）' "2026-10-12${T}GA4${T}全体" | cut -f6)" "1000"
expect_eq "GA4（日次）: 末尾の AdMob 推定収益（円）列（10/12）" "$(arow 'GA4（日次）' 2026-10-12 | awk -F'\t' '{print $NF}')" "30"
expect_eq "GA4（日次）: GA4 に無い日も AdMob の日付で出る（8/27）" "$(grep -c '^2026-08-27' "$AD/GA4（日次）.tsv")" "1"
AWS="$AD/週次まとめ.tsv"
# 表示回数: 現週(10/12-10/18) は 10/12 が AdMob 画面(6000)優先・10/13 は GA4(500)のみ → (6000+500)/2 = 3250.0
expect_eq "広告の表示回数（AdMob 画面優先・現週）" "$(grep '^広告の表示回数' "$AWS" | cut -f4)" "3250.0"
# 基準(10/3-10/11): AdMob 画面が 10/11 にあるので、GA4 の 0 の日として除外されていた 10/11 が 5000 として入る
expect_eq "広告の表示回数（AdMob 画面優先・基準。GA4 の 0 の日を上書き）" "$(grep '^広告の表示回数' "$AWS" | cut -f2)" "5000.0"
expect_eq "AdMob 推定収益 円（過去分・現週。10/12 のみ）" "$(grep '^AdMob 推定収益 円' "$AWS" | cut -f4)" "30.0"
expect_eq "AdMob eCPM 円（過去分・基準。10/11 のみ）" "$(grep '^AdMob eCPM 円' "$AWS" | cut -f2)" "60.0"
# 広告収益 USD（GA4）行は AdMob の有無に関係なく GA4 のみの集計のまま（通貨が違うため混ぜない）
expect_eq "広告収益 USD（GA4）は AdMob と混ぜない（現週は変わらず 1.0）" "$(grep '^広告収益 USD' "$AWS" | cut -f4)" "1.0"

echo "== 10. 並べ替え・絞り込みができる表（addTable/updateTable の組み立て。API は呼ばない） =="
"$PY" - "$TARGET" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("aso_daily", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
ok, ng = 0, 0


def check(label, cond):
    global ok, ng
    if cond:
        ok += 1
        print("  ok   - %s" % label)
    else:
        ng += 1
        print("  NG   - %s" % label)


header = ["日付", "取得元", "広告フォーマット/ユニット", "収益 USD"]
spec_ads = {"date_idx": 0, "text_idxs": {1, 2}}
m.TABLE_COL_SPECS[m.TAB_ADS] = spec_ads

# 新規（表がまだ無い）: addTable で、日付は DATE・取得元とユニットは TEXT・それ以外は DOUBLE
req = m.table_requests(m.TAB_ADS, 999, header, 5, [])
check("表が無ければ addTable を返す", "addTable" in req)
t = req["addTable"]["table"]
check("tableId は固定（二重に作らないための鍵）", t["tableId"] == m.TABLE_IDS[m.TAB_ADS])
check("範囲は渡した行数（見出し込み）に従う", t["range"]["endRowIndex"] == 5 and t["range"]["startRowIndex"] == 0)
cols = {c["columnIndex"]: c["columnType"] for c in t["columnProperties"]}
check("日付列は DATE", cols[0] == "DATE")
check("取得元列は TEXT（数値型にしない）", cols[1] == "TEXT")
check("ユニット列は TEXT", cols[2] == "TEXT")
check("収益列は DOUBLE（数値型）", cols[3] == "DOUBLE")

# 既存（表が既にある）: updateTable で範囲だけ。列の型・見出しは触らない（ヘッダ文字列を壊さないため）
req2 = m.table_requests(m.TAB_ADS, 999, header, 5, [{"tableId": m.TABLE_IDS[m.TAB_ADS]}])
check("表が既にあれば updateTable を返す（addTable で二重に作らない）", "updateTable" in req2)
check("updateTable は range だけ書き換える", req2["updateTable"]["fields"] == "range")
check("updateTable に columnProperties を含めない（見出し文字列を上書きしない）",
      "columnProperties" not in req2["updateTable"]["table"])

# 行が増えた日（毎日の書き込み）: 範囲が追従して広がる
req3 = m.table_requests(m.TAB_ADS, 999, header, 12, [{"tableId": m.TABLE_IDS[m.TAB_ADS]}])
check("行が増えると範囲が広がる（5→12 行）", req3["updateTable"]["table"]["range"]["endRowIndex"] == 12)
# 行が減った日（CSV を作り直して行数が減る想定）: 範囲も追従して縮む
req4 = m.table_requests(m.TAB_ADS, 999, header, 3, [{"tableId": m.TABLE_IDS[m.TAB_ADS]}])
check("行が減ると範囲も縮む（12→3 行）", req4["updateTable"]["table"]["range"]["endRowIndex"] == 3)

check("並べ替え・絞り込みの対象は日次 4 タブ（週次・メモは対象外）",
      set(m.TABLE_IDS) == {m.TAB_ASO, m.TAB_GA4, m.TAB_GAMES, m.TAB_ADS})
check("tableId はタブごとに別々（取り違えて二重に作らない）", len(set(m.TABLE_IDS.values())) == len(m.TABLE_IDS))

print("小計: %d 件成功 / %d 件失敗" % (ok, ng))
sys.exit(1 if ng else 0)
PY
if [ "$?" -eq 0 ]; then ok "table_requests のリクエスト組み立て（上の小計すべて成功）"; else ng "table_requests のリクエスト組み立てで失敗あり"; fi

echo
echo "結果: ${PASS} 件成功 / ${FAIL} 件失敗"
[ "$FAIL" -eq 0 ]
