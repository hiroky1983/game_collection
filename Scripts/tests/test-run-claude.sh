#!/bin/bash
# Scripts/lib/run-claude.sh のテスト（#2562）: エラー文言の判定・API→サブスクの切り替え・印のファイルの月替わり・キー非出力。
# 本物の claude の代わりに、環境変数 ANTHROPIC_API_KEY の有無で挙動を変える偽コマンドを使う。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T=$(mktemp -d)
FAIL=0
ok() { echo "ok   $1"; }
ng() { echo "FAIL $1"; FAIL=1; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待=[$2] 実際=[$3])"; fi; }

export HOME="$T/home"; mkdir -p "$HOME"
export CLAUDE_API_KEY_FILE="$T/key" CLAUDE_BILLING_STATE_DIR="$T/state"
LOG="$T/log"; log() { echo "$*" >>"$LOG"; }
. "$ROOT/Scripts/lib/run-claude.sh"

# --- 判定 ---
judge() { printf '%s\n' "$1" | claude_billing_is_exhausted && echo switch || echo stay; }
check "クレジット切れ → 切り替える" switch "$(judge 'Credit balance is too low')"
check "API 利用上限 → 切り替える" switch "$(judge 'You have reached your specified API usage limits. You will regain access on 2026-11-01')"
check "usage limit reached → 切り替える" switch "$(judge 'Claude AI usage limit reached')"
check "429 → 切り替えない" stay "$(judge 'API Error: 429 {"type":"rate_limit_error","message":"exceeded your per-minute rate limit"}')"
check "overloaded → 切り替えない" stay "$(judge 'API Error: 529 overloaded_error')"
check "無関係 → 切り替えない" stay "$(judge 'something else failed')"

# --- 偽 claude: キーがあれば $FAKE_API_OUT を出して失敗、無ければ成功 ---
cat >"$T/fake" <<'SH'
#!/bin/bash
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then echo "$FAKE_API_OUT"; echo "key=$ANTHROPIC_API_KEY" >>"$FAKE_SEEN"; exit "${FAKE_API_RC:-1}"; fi
echo "subscription ok"; echo "nokey" >>"$FAKE_SEEN"; exit 0
SH
chmod +x "$T/fake"; export FAKE_SEEN="$T/seen"
M=$(date +%Y%m)
reset() { : >"$LOG"; : >"$FAKE_SEEN"; rm -f "$CLAUDE_BILLING_STATE_DIR"/api-exhausted-*; mkdir -p "$CLAUDE_BILLING_STATE_DIR"; }

# キー無し → サブスク（環境に残ったキーも外す）
reset; rm -f "$CLAUDE_API_KEY_FILE"; ANTHROPIC_API_KEY=leaked run_claude_billed "$T/fake"; rc=$?
check "キー無し: 成功" 0 "$rc"
check "キー無し: キーなしで起動" nokey "$(cat "$FAKE_SEEN")"
grep -q '課金: subscription' "$LOG" && ok "キー無し: ログ" || ng "キー無し: ログ"

# キー有り・成功 → api
reset; echo "sk-secret-123" >"$CLAUDE_API_KEY_FILE"; FAKE_API_RC=0 FAKE_API_OUT=fine run_claude_billed "$T/fake"; rc=$?
check "api 成功: rc" 0 "$rc"
check "api 成功: キーを渡す" "key=sk-secret-123" "$(cat "$FAKE_SEEN")"
grep -q '課金: api$' "$LOG" && ok "api 成功: ログ" || ng "api 成功: ログ"
[ ! -e "$CLAUDE_BILLING_STATE_DIR/api-exhausted-$M" ] && ok "api 成功: 印なし" || ng "api 成功: 印なし"
grep -q 'sk-secret' "$LOG" && ng "キーがログに出ている" || ok "キーはログに出ない"

# クレジット切れ → サブスクで再実行・印を作る
reset; FAKE_API_OUT='Credit balance is too low' run_claude_billed "$T/fake"; rc=$?
check "切れ: 最終 rc はサブスク側" 0 "$rc"
check "切れ: api→サブスクの順に起動" "key=sk-secret-123 nokey" "$(tr '\n' ' ' <"$FAKE_SEEN" | sed 's/ $//')"
[ -e "$CLAUDE_BILLING_STATE_DIR/api-exhausted-$M" ] && ok "切れ: 印を作る" || ng "切れ: 印を作る"
grep -q '課金: api→subscription' "$LOG" && ok "切れ: ログ" || ng "切れ: ログ"
grep -q 'sk-secret' "$LOG" && ng "キーがログに出ている" || ok "キーはログに出ない"

# 印がある月は最初からサブスク
: >"$FAKE_SEEN"; run_claude_billed "$T/fake"
check "印あり: キーなしで起動" nokey "$(cat "$FAKE_SEEN")"

# 月替わり: 先月の印だけなら API に戻る
reset; : >"$CLAUDE_BILLING_STATE_DIR/api-exhausted-200001"
FAKE_API_RC=0 FAKE_API_OUT=fine run_claude_billed "$T/fake"
check "翌月: API に戻る" "key=sk-secret-123" "$(cat "$FAKE_SEEN")"

# 429 → 切り替えず、その回は失敗のまま終える
reset; FAKE_API_OUT='API Error: 429 rate_limit_error' run_claude_billed "$T/fake"; rc=$?
check "429: rc は失敗のまま" 1 "$rc"
check "429: サブスクで再実行しない" "key=sk-secret-123" "$(cat "$FAKE_SEEN")"
[ ! -e "$CLAUDE_BILLING_STATE_DIR/api-exhausted-$M" ] && ok "429: 印なし" || ng "429: 印なし"

exit $FAIL
