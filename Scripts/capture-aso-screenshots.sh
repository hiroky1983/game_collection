#!/usr/bin/env bash
# App Store 用スクリーンショットをシミュレータから撮り直す。
#
#   bash Scripts/capture-aso-screenshots.sh [出力ディレクトリ] [シミュレータ名]
#
# 既定: docs/aso/screenshots / "iPhone 17 Pro Max"（6.9インチ = App Store Connect の必須サイズ）
#
# 仕組み:
#   1. Debug ビルドを作り、`-screenshotMode` で起動する（広告を出さず ATT も聞かない。
#      シミュレータは AdMob 側で自動的にテストデバイス扱いになるため、Release ビルドでも
#      バナーに `Test mode` の帯が写り込む。過去のスクショ混入の原因はこれ）。
#   2. 各ゲームの中断スナップショット（デモ用の盤面）をアプリのコンテナに置いてから
#      `-startGame <id>` で直接その画面を開く。セーブがある扱いになるため初回の設定シートも出ない。
#      = シミュレータへのタップ操作なしで狙った画面を撮れる。
#   3. ステータスバーを 9:41・電波フル・満充電に固定してから撮影する（毎回同じ絵になる）。
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-docs/aso/screenshots}"
DEVICE_NAME="${2:-iPhone 17 Pro Max}"
BUNDLE_ID="com.hirockysan1983.asobiba"
DERIVED_DATA="${DERIVED_DATA:-/tmp/aso-screenshots-dd}"
SNAPSHOT_SRC="$(mktemp -d)"
LAUNCH_WAIT="${LAUNCH_WAIT:-4}"

# 撮る画面: 出力ファイル名 | 注入するスナップショットの gameID（空 = 置かない） | 追加の起動引数
SHOTS=(
  "01-hub||"
  "02-shogi|shogi|-startGame shogi"
  "03-2048|2048|-startGame 2048"
  "04-gomoku|gomoku|-startGame gomoku"
  "05-othello|othello|-startGame othello"
  "06-minesweeper|minesweeper|-startGame minesweeper"
  "07-poker|poker|-startGame poker"
  "08-blackjack|blackjack|-startGame blackjack"
  "09-concentration|concentration|-startGame concentration"
  "10-settings||-showSettings"
)

echo "==> シミュレータ「$DEVICE_NAME」を探す"
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
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -screenshotMode $extra_args >/dev/null
  sleep "$LAUNCH_WAIT"
  xcrun simctl io "$UDID" screenshot --type png "$OUT_DIR/$name.png"
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
rm -rf "$SNAPSHOT_SRC"

echo "==> 完了: $OUT_DIR"
ls -1 "$OUT_DIR"
