#!/usr/bin/env bash
# App Store 用スクリーンショットをシミュレータから撮り直す。
#
#   bash Scripts/capture-aso-screenshots.sh [出力ディレクトリ] [シミュレータ名]
#
# 既定: docs/aso/screenshots / "iPhone 17 Pro Max"（6.9インチ = App Store Connect の必須サイズ）
#
# iPad 分（#472。TARGETED_DEVICE_FAMILY に 2 を含む版では入稿に必須）は出力先とデバイス名を渡す:
#
#   bash Scripts/capture-aso-screenshots.sh docs/aso/screenshots/ipad "iPad Pro 13-inch (M5)"
#
# 13インチ iPad の native は 2064×2752 portrait で、そのまま ASC の 13" 枠に入る
# （他の iPad サイズは Apple 側で自動縮小される）。スクリプト側の分岐は不要。
#
# 仕組み:
#   1. Debug ビルドを作り、`-screenshotMode` で起動する（広告を出さず ATT も聞かない。
#      シミュレータは AdMob 側で自動的にテストデバイス扱いになるため、Release ビルドでも
#      バナーに `Test mode` の帯が写り込む。過去のスクショ混入の原因はこれ）。
#   2. 各ゲームの中断スナップショット（デモ用の盤面）をアプリのコンテナに置いてから
#      `-startGame <id>` で直接その画面を開く。セーブがある扱いになるため初回の設定シートも出ない。
#      = シミュレータへのタップ操作なしで狙った画面を撮れる。
#   3. ステータスバーを 9:41・電波フル・満充電に固定してから撮影する。
#      注: マインスイーパー・ナンプレ・ソリティア・麻雀ソリティアは画面内のタイマーが起動後に進むため、
#      経過秒の表示は毎回わずかにずれる。
#   4. 遊び方ガイドの帯（初回だけ出る `HowToPlayGuide.hint`）を「表示済み」に固定して撮る。
#      これはシミュレータに残る `playLog_guidedGameIDs_v1` 次第で出たり出なかったりするので、
#      放っておくと**撮るたびに違う絵になる**。実際、#472 までの入稿物は iPhone 側が帯なし・
#      iPad 側が帯ありで、同じ順番で入稿する2セットの見た目が食い違っていた。
#      NSArgumentDomain（`-<キー名> <値>` で渡す起動引数）は永続化された値より優先されるため、
#      シミュレータの履歴に関係なく決定的になる。既に入稿済みのスクショも帯なしなので、そちらに揃える。
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-docs/aso/screenshots}"
DEVICE_NAME="${2:-iPhone 17 Pro Max}"
BUNDLE_ID="com.hirockysan1983.asobiba"
DERIVED_DATA="${DERIVED_DATA:-/tmp/aso-screenshots-dd}"
SNAPSHOT_SRC="$(mktemp -d)"
LAUNCH_WAIT="${LAUNCH_WAIT:-4}"

# 撮る画面: 出力ファイル名 | 注入するスナップショットの gameID（空 = 置かない） | 追加の起動引数
#
# 収録ゲームは v1.1.3 で16本になったが、App Store のスクショ枠は**10枚まで**なので
# 全部は入稿できない。そこで**ファイル名の番号 = 入稿の優先順**にしてある（#184）:
# 先頭の `01`〜`10` がそのまま入稿する10枚で、`11` 以降は撮るが入稿しない控え。
# 選定は「1枚目のハブに名前が写らない4本を個別枠で必ず見せる」を軸にしてある。
# 根拠と入れ替え手順は docs/aso/metadata-v1.1.1.md §11 を参照。
#
# ⚠️ **このリストは「まだ公開していない版のツリー」で実行する前提**。gameID は
# 実行するツリーの GameRegistry（App/AppGameServices.swift）に合わせること。
# 例: go / chess / solitaire / blocks は release/v1.1.3 で追加された4本で、
# main（= 公開済みの集合）には無い。main のツリーで走らせるとその4枚はハブ画面になる。
SHOTS=(
  # ここから入稿する10枚（順番 = 商品ページに並ぶ順）
  "01-hub||"
  "02-shogi|shogi|-startGame shogi"
  "03-sudoku|sudoku|-startGame sudoku"
  "04-mahjong4|mahjong4|-startGame mahjong4"
  # ソリティアは盤面を保存しない設計（種 + 手順から再生）なので、JSON では配札の種だけを
  # 固定し、中盤の絵は撮影用の DEBUG 経路 `-solitaireMidgame` に作らせる（詳細は
  # Scripts/aso-demo-snapshots.py の snapshot_solitaire を参照）。
  "05-solitaire|solitaire|-startGame solitaire -solitaireMidgame"
  "06-2048|2048|-startGame 2048"
  # 07〜10 はハブの1枚目に名前が写らない4本（スクロールしないと出てこない）。
  "07-minesweeper|minesweeper|-startGame minesweeper"
  "08-gomoku|gomoku|-startGame gomoku"
  "09-concentration|concentration|-startGame concentration"
  "10-blocks|blocks|-startGame blocks"
  # ここから控え（入稿枠に入らない残り6本 + 設定画面）。差し替えたくなったときに
  # 撮り直さずに済むよう、収録している16本は全部撮る。
  "11-go|go|-startGame go"
  "12-chess|chess|-startGame chess"
  "13-othello|othello|-startGame othello"
  "14-mahjong-solitaire|mahjong|-startGame mahjong"
  "15-daifugo|daifugo|-startGame daifugo"
  "16-poker|poker|-startGame poker"
  "17-blackjack|blackjack|-startGame blackjack"
  "18-settings||-showSettings"
)

echo "==> シミュレータ「${DEVICE_NAME}」を探す"
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
want = sys.argv[1]
data = json.load(sys.stdin)['devices']
for runtime in sorted(data, reverse=True):  # 新しい iOS を優先
    for dev in data[runtime]:
        if dev['name'] == want:
            print(dev['udid']); sys.exit(0)
sys.exit('シミュレータが見つかりません: ' + want)
" "$DEVICE_NAME")
echo "    udid=$UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "==> ビルド（Debug・署名なし）"
command -v xcodegen >/dev/null && xcodegen generate >/dev/null
xcodebuild -project GameCollection.xcodeproj -scheme GameCollection \
  -configuration Debug -sdk iphonesimulator -destination "id=$UDID" \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO build >/dev/null

APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/GameCollection.app"
[ -d "$APP" ] || { echo "ビルド成果物が見つかりません: $APP" >&2; exit 1; }

echo "==> インストールとデモ状態の生成"
xcrun simctl install "$UDID" "$APP"
python3 Scripts/aso-demo-snapshots.py "$SNAPSHOT_SRC" >/dev/null

CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
[ -d "$CONTAINER" ] || { echo "アプリのコンテナが取得できません" >&2; exit 1; }
SNAP_DIR="$CONTAINER/Library/Application Support/Snapshots"

xcrun simctl status_bar "$UDID" override \
  --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

# 遊び方ガイドの帯を「表示済み」に固定するための起動引数（上記の仕組み 4）。
# 値は old-style plist の配列で、SHOTS に出てくる gameID をそのまま使う。
GUIDED_IDS=""
for shot in "${SHOTS[@]}"; do
  IFS='|' read -r _ shot_game_id _ <<<"$shot"
  [ -n "$shot_game_id" ] && GUIDED_IDS="${GUIDED_IDS}\"${shot_game_id}\","
done
GUIDED_ARG="(${GUIDED_IDS%,})"

mkdir -p "$OUT_DIR"
for shot in "${SHOTS[@]}"; do
  IFS='|' read -r name game_id extra_args <<<"$shot"
  echo "==> $name"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true

  # 前の撮影で置いたスナップショットを毎回捨てる（ハブの「続きから」バッジが混ざらないように）
  rm -rf "$SNAP_DIR"
  mkdir -p "$SNAP_DIR"
  [ -n "$game_id" ] && cp "$SNAPSHOT_SRC/$game_id.json" "$SNAP_DIR/"

  # shellcheck disable=SC2086 # extra_args は意図的に単語分割する
  xcrun simctl launch "$UDID" "$BUNDLE_ID" \
    -screenshotMode -playLog_guidedGameIDs_v1 "$GUIDED_ARG" $extra_args >/dev/null
  sleep "$LAUNCH_WAIT"
  xcrun simctl io "$UDID" screenshot --type png "$OUT_DIR/$name.png"
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
rm -rf "$SNAPSHOT_SRC"

echo "==> 完了: $OUT_DIR"
ls -1 "$OUT_DIR"
