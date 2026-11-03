#!/bin/bash
# Scripts/lib/branch-lock.sh（release ブランチの凍結確認・#3227）と、それを使う ai-duty.sh の
# duty_branch_lock_state の検証。gh は PATH の先頭に置いた偽物に差し替える。
# 偽物は GH_MODE で応答を変える: frozen / unfrozen / null / 404 / ratelimit / auth
#
# 使い方: bash Scripts/tests/test-branch-lock.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/branch-lock.sh"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOS'
#!/bin/bash
echo "$*" >>"$GH_LOG"
case "$GH_MODE" in
  frozen)    echo true ;;
  unfrozen)  echo false ;;
  null)      echo null ;;
  404)       echo "gh: Branch not protected (HTTP 404)" >&2; exit 1 ;;
  ratelimit) echo "gh: API rate limit exceeded (HTTP 403)" >&2; exit 1 ;;
  auth)      echo "gh: To use GitHub CLI in automation, set the GH_TOKEN environment variable." >&2; exit 4 ;;
esac
EOS
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log"

# shellcheck source=/dev/null
. "$LIB"

# state <mode> → 標準出力・標準エラー・終了コードを $OUT / $ERR / $RC に入れる
state() {
  GH_MODE="$1" OUT=$(GH_MODE="$1" branch_lock_state hiroky1983/game_collection 1.1.15 2>"$TMP/err"); RC=$?
  ERR=$(cat "$TMP/err")
}

echo "== 1. branch_lock_state =="
state frozen
[ "$OUT" = true ] && [ "$RC" = 0 ] && ok "lock_branch=true → true" || ng "frozen: [$OUT] rc=$RC"
state unfrozen
[ "$OUT" = false ] && [ "$RC" = 0 ] && ok "lock_branch=false → false" || ng "unfrozen: [$OUT] rc=$RC"
state null
[ "$OUT" = false ] && [ "$RC" = 0 ] && ok "lock_branch が無い（null）→ false" || ng "null: [$OUT] rc=$RC"
state 404
[ "$OUT" = false ] && [ "$RC" = 0 ] && ok "HTTP 404（保護設定なし）は従来どおり false" || ng "404: [$OUT] rc=$RC"
state ratelimit
[ -z "$OUT" ] && [ "$RC" = 1 ] && ok "レート制限（HTTP 403）は「凍結なし」と見なさず 1" || ng "ratelimit: [$OUT] rc=$RC"
case "$ERR" in *"release/v1.1.15"*"HTTP 403"*) ok "原因（HTTP ステータス）が標準エラーに残る" ;; *) ng "原因が残らない: [$ERR]" ;; esac
state auth
[ -z "$OUT" ] && [ "$RC" = 1 ] && ok "認証切れ・通信障害でも 1" || ng "auth: [$OUT] rc=$RC"
grep -q 'repos/hiroky1983/game_collection/branches/release%2Fv1.1.15/protection' "$GH_LOG" \
  && ok "保護設定の API を release%2Fv<版> で引く" || ng "API のパスが違う: $(cat "$GH_LOG")"

echo "== 2. ai-duty.sh の duty_branch_lock_state =="
export DUTY_LIB_ONLY=1
unset -f branch_lock_state
# shellcheck source=/dev/null
. "$SCRIPT_DIR/../ai-duty.sh" || { echo "ai-duty.sh の source に失敗"; exit 1; }
unset -f branch_lock_state
export PATH="$TMP/bin:$PATH"  # ai-duty.sh が PATH を組み直すので、偽の gh を先頭に戻す
duty_state() {
  OUT=$(GH_MODE="$1" duty_branch_lock_state 1.1.15 2>"$TMP/err"); RC=$?
}
DUTY_BRANCH_LOCK_LIB="$LIB" duty_state frozen
[ "$OUT" = true ] && [ "$RC" = 0 ] && ok "凍結済みは true" || ng "frozen: [$OUT] rc=$RC"
unset -f branch_lock_state
DUTY_BRANCH_LOCK_LIB="$LIB" duty_state ratelimit
[ -z "$OUT" ] && [ "$RC" != 0 ] && ok "gh の失敗は非 0（呼び出し側が周回を見送れる）" || ng "ratelimit: [$OUT] rc=$RC"
unset -f branch_lock_state
DUTY_BRANCH_LOCK_LIB="$TMP/none.sh" duty_state frozen
[ -z "$OUT" ] && [ "$RC" != 0 ] && ok "lib を読めないときも非 0（「凍結なし」にしない）" || ng "lib 欠落: [$OUT] rc=$RC"

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
