#!/bin/bash
# capture-aso-screenshots.sh の分岐の検証（#2331）。
#
# 撮影は提出前の1日にしか走らず、引数・出力先・端末の指し方が壊れても CI が拾えないため、
# 提出当日に初めて気づく。ここでは xcrun / xcodebuild / xcodegen を偽物に差し替えて
#   ①既定の引数で 22 枚ぶん撮影コマンドが流れる ②出力先と端末（UDID）の引数が効く
#   ③端末が見つからない・同名が複数ある・ビルド成果物が無い・コンテナが取れないときは非 0 で落ちる
#   ④中断データの置き方（ゲームごとに1本・ハブには無し）と起動引数（-screenshotMode / -startGame / -showSettings /
#     遊び方ガイド抑止）が SHOTS の定義どおり
# を固定する。実際のシミュレータ撮影・画像の中身は対象外。
#
# 注: Scripts/duty-xcrun-shim/xcrun は UDID の記録係で、本物の xcrun へ素通しする（偽物ではない）ため流用せず、
#     ここで simctl を丸ごと偽物にしている。
#
# スクリプトは `cd "$(dirname "$0")/.."` でリポジトリ直下へ移動して相対パスで動くので、
# 一時ディレクトリに Scripts/ を複製した作業場を作り、本物のリポジトリを汚さない。
# aso-demo-snapshots.py と apply-package-resolved.sh は別のテスト・環境依存（xcodeproj が要る）のためスタブにする。
#
# 使い方: bash Scripts/tests/test-capture-aso-screenshots.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../capture-aso-screenshots.sh"
PASS=0
FAIL=0
N=0

ok()    { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()    { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/capture-aso-test.XXXXXX") || exit 1
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/bin"

# --- 偽物のコマンド（呼び出しは $CALLS に1行ずつ記録する） ---
cat >"$ROOT/bin/xcrun" <<'STUB'
#!/bin/bash
echo "xcrun $*" >>"$CALLS"
[ "${1:-}" = "simctl" ] || exit 0
case "${2:-}" in
  list)          cat "$FAKE_DEVICES_JSON" ;;
  get_app_container)
    [ -n "${FAKE_NO_CONTAINER:-}" ] && exit 0
    echo "$FAKE_CONTAINER" ;;
  launch)
    # 起動時点で置かれている中断データを記録する（ゲームごとに1本・ハブは無し、を見るため）
    echo "snap-at-launch: $(ls "$FAKE_CONTAINER/Library/Application Support/Snapshots" 2>/dev/null | tr '\n' ' ')" >>"$CALLS" ;;
  io)
    # simctl io <udid> screenshot --type png <path>
    : >"${@: -1}" ;;
esac
exit 0
STUB
cat >"$ROOT/bin/xcodegen" <<'STUB'
#!/bin/bash
echo "xcodegen $*" >>"$CALLS"
STUB
cat >"$ROOT/bin/xcodebuild" <<'STUB'
#!/bin/bash
echo "xcodebuild $*" >>"$CALLS"
[ -n "${FAKE_NO_APP:-}" ] && exit 0
while [ $# -gt 0 ]; do
  if [ "$1" = "-derivedDataPath" ]; then
    mkdir -p "$2/Build/Products/Debug-iphonesimulator/GameCollection.app"
  fi
  shift
done
STUB
chmod +x "$ROOT/bin/"*
export PATH="$ROOT/bin:$PATH"

UDID_A="AAAAAAAA-0000-0000-0000-000000000001"
UDID_B="BBBBBBBB-0000-0000-0000-000000000002"
device_json() { # $1=名前 $2=UDID [$3=名前 $4=UDID（同名の2台目）]
  python3 - "$@" <<'PY'
import json, sys
a = sys.argv[1:]
# 端末ごとに別ランタイムへ置く（Xcode 27 で iOS 26.4 の端末一式が 26.5 側に複製された実環境と同じ形。
# 同一ランタイムに同名が並ぶと本体の sorted(hits) が dict 同士の比較で落ちるが、実環境では起きない）
devices = {}
for i in range(0, len(a), 2):
    rt = "com.apple.CoreSimulator.SimRuntime.iOS-26-%d" % (5 - i // 2)
    devices.setdefault(rt, []).append({"name": a[i], "udid": a[i + 1], "state": "Shutdown", "isAvailable": True})
print(json.dumps({"devices": devices}))
PY
}

# ケースごとに作業場を作る（Scripts/ の複製 + スタブ）。$W が作業場、$CALLS が呼び出し記録
setup() {
  N=$((N + 1)); CASE="$ROOT/case$N"; W="$CASE/work"; CALLS="$CASE/calls"
  export CALLS
  mkdir -p "$W/Scripts" "$CASE/container/Library/Application Support"
  : >"$CALLS"
  cp "$TARGET" "$W/Scripts/capture-aso-screenshots.sh"
  echo '#!/bin/bash' >"$W/Scripts/apply-package-resolved.sh"
  cat >"$W/Scripts/aso-demo-snapshots.py" <<'PY'
import os, sys
os.makedirs(sys.argv[1], exist_ok=True)
for g in ("shogi", "sudoku", "go"):
    open(os.path.join(sys.argv[1], g + ".json"), "w").write("{}")
PY
  export FAKE_CONTAINER="$CASE/container"
  export FAKE_DEVICES_JSON="$CASE/devices.json"
  export DERIVED_DATA="$CASE/dd"
  export LAUNCH_WAIT=0
  unset FAKE_NO_APP FAKE_NO_CONTAINER
  device_json "iPhone 17 Pro Max" "$UDID_A" >"$FAKE_DEVICES_JSON"
}
run() { (cd "$W" && bash Scripts/capture-aso-screenshots.sh "$@") >"$CASE/stdout" 2>"$CASE/stderr"; }
calls() { grep -c "$1" "$CALLS"; }

# 期待する撮影枚数 = SHOTS 配列の要素数（"NN-名前|..." の行）
EXPECTED=$(grep -cE '^  "[0-9]{2}-[a-z0-9-]+\|' "$TARGET")

echo "# (1) 既定の引数"
setup
run; rc=$?
check "終了コード 0" 0 "$rc"
check "既定の出力先 docs/aso/screenshots に SHOTS 全数（$EXPECTED 枚）の PNG" "$EXPECTED" "$(ls "$W/docs/aso/screenshots"/*.png 2>/dev/null | wc -l | tr -d ' ')"
check "既定端末「iPhone 17 Pro Max」の UDID で boot" 1 "$(calls "simctl boot $UDID_A")"
check "xcodebuild を UDID 指定の destination で実行（名前指定にしない）" 1 "$(calls "destination id=$UDID_A")"
check "launch が SHOTS の数だけ" "$EXPECTED" "$(calls 'simctl launch')"
check "全 launch に -screenshotMode" "$EXPECTED" "$(grep 'simctl launch' "$CALLS" | grep -c -- '-screenshotMode')"
check "全 launch に遊び方ガイド抑止 -playLog_guidedGameIDs_v1" "$EXPECTED" "$(grep 'simctl launch' "$CALLS" | grep -c -- '-playLog_guidedGameIDs_v1')"
guided=$(grep 'simctl launch' "$CALLS" | head -1 | grep -o '(.*)' | head -1)
case "$guided" in
  '("shogi",'*'"hanafuda")'|*'"shogi"'*'"hanafuda"'*) ok "ガイド抑止の配列に SHOTS のゲームIDが入る" ;;
  *) ng "ガイド抑止の配列が想定外: [$guided]" ;;
esac
case "$guided" in *'""'*|*',)'*|*'(,'*) ng "ガイド抑止の配列に空要素・余分なカンマ: [$guided]" ;; *) ok "ガイド抑止の配列に空要素なし" ;; esac
check "shogi は -startGame shogi で起動" 1 "$(grep 'simctl launch' "$CALLS" | grep -c -- '-startGame shogi')"
check "設定画面は -showSettings で起動" 1 "$(grep 'simctl launch' "$CALLS" | grep -c -- '-showSettings')"
check "ハブ（01-hub）は -startGame を付けない: -startGame の数 = ゲーム画面の数" \
  "$(grep -cE '^  "[0-9]{2}-[a-z0-9-]+\|[a-z0-9]+\|-startGame' "$TARGET")" \
  "$(grep 'simctl launch' "$CALLS" | grep -c -- '-startGame')"
check "ステータスバーを 9:41 に固定" 1 "$(calls 'status_bar .* override --time 9:41')"
check "撮影の最後にアプリを terminate" 1 "$(tail -1 "$CALLS" | grep -c 'simctl terminate')"

echo "# (2) 中断データの置き方"
# 01-hub（1つ目の launch）は中断データ無し、02-shogi（2つ目）は shogi.json が1本だけ
snaps=$(grep '^snap-at-launch:' "$CALLS")
check "ハブの launch 時点では中断データ無し" "snap-at-launch: " "$(echo "$snaps" | sed -n 1p)"
check "shogi の launch 時点では shogi.json だけ" "snap-at-launch: shogi.json " "$(echo "$snaps" | sed -n 2p)"
check "デモデータが無いゲーム（例: 2048）は中断データ無しで起動" "snap-at-launch: " "$(echo "$snaps" | sed -n 6p)"

echo "# (3) 出力先と端末を引数で指定"
setup
device_json "iPad Pro 13-inch (M5)" "$UDID_B" "iPhone 17 Pro Max" "$UDID_A" >"$FAKE_DEVICES_JSON"
run "$CASE/out-ipad" "iPad Pro 13-inch (M5)"; rc=$?
check "終了コード 0" 0 "$rc"
check "指定した出力先に PNG" "$EXPECTED" "$(ls "$CASE/out-ipad"/*.png 2>/dev/null | wc -l | tr -d ' ')"
check "既定の出力先には作らない" 0 "$([ -d "$W/docs/aso/screenshots" ] && echo 1 || echo 0)"
check "指定端末の UDID で boot" 1 "$(calls "simctl boot $UDID_B")"
check "別の端末は boot しない" 0 "$(calls "simctl boot $UDID_A")"

echo "# (4) UDID をそのまま渡す（同名端末が複数ある環境の唯一の指し方）"
setup
device_json "iPhone 17 Pro Max" "$UDID_A" "iPhone 17 Pro Max" "$UDID_B" >"$FAKE_DEVICES_JSON"
run "$CASE/out" "$UDID_B"; rc=$?
check "終了コード 0" 0 "$rc"
check "渡した UDID で boot" 1 "$(calls "simctl boot $UDID_B")"
check "もう1台の同名端末は触らない" 0 "$(calls "simctl boot $UDID_A")"

echo "# (5) 異常系"
setup
run "$CASE/out" "iPhone 99"; rc=$?
check "端末が見つからない → 非 0" 1 "$rc"
check "  メッセージ「シミュレータが見つかりません」" 1 "$(grep -c 'シミュレータが見つかりません' "$CASE/stderr")"
check "  boot もビルドもしない" 0 "$(grep -cE 'simctl boot|^xcodebuild' "$CALLS")"

setup
device_json "iPhone 17 Pro Max" "$UDID_A" "iPhone 17 Pro Max" "$UDID_B" >"$FAKE_DEVICES_JSON"
run "$CASE/out"; rc=$?
check "同名端末が複数 → 非 0（黙って1台選ばない）" 1 "$rc"
check "  メッセージ「同じ名前のシミュレータが 2 台あります」" 1 "$(grep -c '同じ名前のシミュレータが 2 台あります' "$CASE/stderr")"
check "  両方の UDID を案内する" 2 "$(grep -c -e "$UDID_A" -e "$UDID_B" "$CASE/stderr")"
check "  boot もビルドもしない" 0 "$(grep -cE 'simctl boot|^xcodebuild' "$CALLS")"

setup
FAKE_NO_APP=1 run "$CASE/out"; rc=$?
check "ビルド成果物が無い → 非 0" 1 "$rc"
check "  メッセージ「ビルド成果物が見つかりません」" 1 "$(grep -c 'ビルド成果物が見つかりません' "$CASE/stderr")"
check "  インストール・撮影に進まない" 0 "$(grep -cE 'simctl (install|launch)' "$CALLS")"

setup
FAKE_NO_CONTAINER=1 run "$CASE/out"; rc=$?
check "アプリのコンテナが取れない → 非 0" 1 "$rc"
check "  メッセージ「アプリのコンテナが取得できません」" 1 "$(grep -c 'アプリのコンテナが取得できません' "$CASE/stderr")"
check "  撮影に進まない" 0 "$(calls 'simctl launch')"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
