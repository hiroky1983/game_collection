#!/bin/bash
# ai-duty.sh の会長通知（Issue #132）の検証。
# 実際に通知を出すと検証のたびに会長の Mac に通知が飛ぶため、osascript と gh をモックして
# 「何が呼ばれたか」をファイルに記録し、それを突き合わせる。
#
# 使い方: bash Scripts/tests/test-ai-duty-notify.sh
# モックの仕込み方: ai-duty.sh は先頭で PATH を `$HOME/.local/bin:...` に固定するため、
# HOME をテスト用の一時ディレクトリに差し替え、そこへ偽の osascript / gh を置けば
# 本物の実装コードをそのまま通せる（スクリプト側にテスト用の分岐を持ち込まない）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../ai-duty.sh"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

TEST_HOME=$(mktemp -d "${TMPDIR:-/tmp}/ai-duty-notify-test.XXXXXX") || exit 1
trap 'rm -rf "$TEST_HOME"' EXIT
mkdir -p "$TEST_HOME/.local/bin" "$TEST_HOME/Library/Logs" "$TEST_HOME/.asobiba-duty"

# 偽 osascript: 引数をそのまま記録する（呼ばれたかどうかと本文の中身を見るため）
cat >"$TEST_HOME/.local/bin/osascript" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >>"$MOCK_OSASCRIPT_LOG"
[ -n "${MOCK_OSASCRIPT_FAIL:-}" ] && exit 1
exit 0
MOCK

# 偽 gh: `issue list` のみ対応。--jq のフィルタは本物の jq で評価するので、
# ai-duty.sh 側の jq 式そのものを検証できる
cat >"$TEST_HOME/.local/bin/gh" <<'MOCK'
#!/bin/bash
[ "${1:-}" = "auth" ] && exit "${MOCK_GH_AUTH_RC:-0}"
label=""; filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    --label) label="$2"; shift 2 ;;
    --jq) filter="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ -n "${MOCK_GH_FAIL:-}" ] && exit 1
case "$label" in
  ringi:pending) data="${MOCK_GH_RINGI:-[]}" ;;
  ai:proposed)   data="${MOCK_GH_PROPOSED:-[]}" ;;
  *)             data="[]" ;;
esac
printf '%s' "$data" | jq -r "$filter"
MOCK
chmod +x "$TEST_HOME/.local/bin/osascript" "$TEST_HOME/.local/bin/gh"

export MOCK_OSASCRIPT_LOG="$TEST_HOME/osascript.log"
: >"$MOCK_OSASCRIPT_LOG"

# 関数だけ読み込む（HOME を差し替えてから source すると、LOG も状態ファイルもテスト側に閉じる）
export HOME="$TEST_HOME"
export DUTY_LIB_ONLY=1
# shellcheck source=/dev/null
. "$TARGET" || { echo "source に失敗"; exit 1; }

STATE="$DUTY_NOTIFY_STATE"
notified() { wc -l <"$MOCK_OSASCRIPT_LOG" | tr -d ' '; }
reset_log() { : >"$MOCK_OSASCRIPT_LOG"; }

echo "== 1. 構文チェック =="
if bash -n "$TARGET"; then ok "bash -n が通る"; else ng "bash -n が失敗"; fi

echo "== 2. 収集（collect_notify_targets の jq フィルタ）=="
export MOCK_GH_RINGI='[{"number":128},{"number":106}]'
export MOCK_GH_PROPOSED='[
  {"number":106,"labels":[{"name":"ai:proposed"},{"name":"ringi:pending"}]},
  {"number":79,"labels":[{"name":"ai:proposed"}]},
  {"number":54,"labels":[{"name":"ai:proposed"},{"name":"ai:approved"},{"name":"blocked"}]},
  {"number":141,"labels":[{"name":"ai:proposed"},{"name":"ai:approved"}]},
  {"number":200,"labels":[{"name":"ai:proposed"},{"name":"ai:in-progress"}]}
]'
collect_notify_targets
check "決裁待ちの番号を集める" "128 106" "$NOTIFY_RINGI"
check "承認待ちは未承認の ai:proposed だけ（承認済み・着手中・blocked・決裁待ちは除く）" "79" "$NOTIFY_APPROVAL"
check "収集できたら NOTIFY_READY=1" "1" "$NOTIFY_READY"

echo "== 3. gh 失敗時は通知しない（無音で握り潰さない）=="
# 注: bash では `VAR=x 関数` の前置代入が関数から戻ったあとも残る（コマンドと違って消えない）。
# 以降のテストを汚さないよう、モックの切り替えは export / unset で明示的に行う
NOTIFY_READY=0; NOTIFY_RINGI=""; NOTIFY_APPROVAL=""
export MOCK_GH_FAIL=1
collect_notify_targets
unset MOCK_GH_FAIL
check "gh が失敗したら NOTIFY_READY は 0 のまま" "0" "$NOTIFY_READY"
reset_log; rm -f "$STATE"
notify_pending
check "NOTIFY_READY=0 なら通知しない" "0" "$(notified)"

echo "== 4. 対象0件なら無音 =="
NOTIFY_READY=1; NOTIFY_RINGI=""; NOTIFY_APPROVAL=""
reset_log; rm -f "$STATE"
notify_pending
check "対象0件では osascript を呼ばない" "0" "$(notified)"
if [ -f "$STATE" ]; then ng "対象0件で状態ファイルを作ってしまった"; else ok "対象0件では状態ファイルを作らない"; fi

echo "== 5. 対象ありなら通知し、本文に Issue 番号が入る =="
NOTIFY_RINGI="128 106"; NOTIFY_APPROVAL="79"
reset_log; rm -f "$STATE"
notify_pending
check "1回通知する" "1" "$(notified)"
BODY=$(cat "$MOCK_OSASCRIPT_LOG")
for N in 128 106 79; do
  case "$BODY" in *"#$N"*) ok "本文に #$N が含まれる" ;; *) ng "本文に #$N が無い ($BODY)" ;; esac
done
case "$BODY" in *"決裁待ち"*) ok "何を見ればよいか（決裁待ち）が本文に出る" ;; *) ng "決裁待ちの表示が無い" ;; esac
case "$BODY" in *"承認待ち"*) ok "何を見ればよいか（承認待ち）が本文に出る" ;; *) ng "承認待ちの表示が無い" ;; esac
case "$BODY" in *"3件"*) ok "件数がタイトルに出る" ;; *) ng "件数が出ていない ($BODY)" ;; esac

echo "== 6. 連投防止: 同じ対象は1日に1回まで =="
reset_log
notify_pending
check "同じ対象の2回目は通知しない" "0" "$(notified)"
notify_pending
check "同じ対象の3回目も通知しない" "0" "$(notified)"

echo "== 7. 対象が変わったら即通知（新しい稟議を1日待たせない）=="
reset_log
NOTIFY_RINGI="128 106 999"
notify_pending
check "対象集合が変われば即通知する" "1" "$(notified)"
reset_log
notify_pending
check "変わった直後の再実行はまた抑止される" "0" "$(notified)"

echo "== 8. 24時間経過したら同じ対象でも再通知 =="
reset_log
printf '%s\n%s\n' "$(sed -n '1p' "$STATE")" "$(( $(date +%s) - 86401 ))" >"$STATE"
notify_pending
check "前回から24時間超なら再通知する" "1" "$(notified)"

echo "== 9. 通知に失敗したら状態を更新しない（次回に持ち越す）=="
reset_log; rm -f "$STATE"
NOTIFY_RINGI="128"; NOTIFY_APPROVAL=""
export MOCK_OSASCRIPT_FAIL=1
notify_pending
unset MOCK_OSASCRIPT_FAIL
check "osascript は呼ばれる" "1" "$(notified)"
if [ -f "$STATE" ]; then ng "失敗したのに状態ファイルを更新した"; else ok "失敗時は状態ファイルを更新しない"; fi
reset_log
notify_pending
check "失敗した回の対象は次回に通知される" "1" "$(notified)"

echo "== 10. 通し実行: 早期 exit でも EXIT トラップから通知が出る =="
# 「仕事なし」で早期 exit する回こそ決裁待ちが滞留している回なので、通知経路が生きていることを
# スクリプトを実際に走らせて確認する。claude を起動させないよう、収集の直後で exit する版を作る。
unset DUTY_LIB_ONLY   # 通しで走らせる回はテスト用の入口を無効にする（子プロセスに継承させない）
E2E="$TEST_HOME/ai-duty-e2e.sh"
awk '{ print } /^collect_notify_targets$/ { print "exit 0" }' "$TARGET" >"$E2E"
grep -q '^exit 0$' "$E2E" || ng "テスト用スクリプトの生成に失敗（collect_notify_targets の行が見つからない）"
reset_log; rm -f "$STATE"
MOCK_GH_RINGI='[{"number":128}]' MOCK_GH_PROPOSED='[{"number":79,"labels":[{"name":"ai:proposed"}]}]' \
  TMPDIR="$TEST_HOME" HOME="$TEST_HOME" bash "$E2E"
check "通し実行で1回通知される" "1" "$(notified)"
case "$(cat "$MOCK_OSASCRIPT_LOG")" in
  *"#128"*"#79"*) ok "通し実行の本文に決裁待ち・承認待ちの両方が入る" ;;
  *) ng "通し実行の本文が不正 ($(cat "$MOCK_OSASCRIPT_LOG"))" ;;
esac
reset_log
MOCK_GH_RINGI='[{"number":128}]' MOCK_GH_PROPOSED='[{"number":79,"labels":[{"name":"ai:proposed"}]}]' \
  TMPDIR="$TEST_HOME" HOME="$TEST_HOME" bash "$E2E"
check "通し実行でも連投防止が効く" "0" "$(notified)"
reset_log; rm -f "$STATE"
unset MOCK_GH_RINGI MOCK_GH_PROPOSED   # 偽 gh が 0 件を返す状態にする
TMPDIR="$TEST_HOME" HOME="$TEST_HOME" bash "$E2E"
check "対象0件の通し実行は無音" "0" "$(notified)"
reset_log
MOCK_GH_AUTH_RC=1 TMPDIR="$TEST_HOME" HOME="$TEST_HOME" bash "$E2E"
check "gh 未認証（収集前に exit）でも通知は出ない" "0" "$(notified)"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
