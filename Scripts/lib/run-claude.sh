#!/bin/bash
# `claude -p` を起動する定期スクリプト（当番・監査・QA・経営・週次会議）の共通起動関数（#2562・会長決裁 2026-10-20）。
#
# 方針: Claude の API クレジットが毎月付与されるので、まず API キーで動かし、クレジット切れ・利用上限なら
#       同じ仕事をサブスクの枠でもう一度起動する。切り替えた月は印のファイルを作り、その月は最初からサブスク。
#   - キーは $CLAUDE_API_KEY_FILE（既定 ~/asobiba-secrets/anthropic-api-key）から読む。無ければ今までどおりサブスク。
#     キーはこの関数が起動する子プロセスの環境変数にだけ渡す。シェルの設定ファイルには書かない（会長の対話 Claude Code に影響させない）
#     ・ログにも出さない
#   - 429 などの一時的なレート制限ではサブスクに切り替えない（その回は終えて次の回に任せる）
#
# 使い方: run_claude_billed [コマンド...] — 例 `PATH=… run_claude_billed claude --model sonnet -p "…"`。
#   出力は $LOG に追記し、戻り値は最後に走らせたコマンドの終了コード。呼び出し元は `log` と `LOG` を定義しておく。

CLAUDE_API_KEY_FILE="${CLAUDE_API_KEY_FILE:-$HOME/asobiba-secrets/anthropic-api-key}"
CLAUDE_BILLING_STATE_DIR="${CLAUDE_BILLING_STATE_DIR:-$HOME/.asobiba-duty}"

# 出力の末尾（標準入力）がクレジット切れ・利用上限なら 0。レート制限（429 等）は 1。
# 実行の本文に「usage limit」などの語が出ても誤爆しないよう、呼び出し側は失敗終了時の末尾だけを渡す
claude_billing_is_exhausted() {
  grep -Eiq 'credit balance is too low|specified api usage limits|reached your (monthly )?(spend|usage) limit|spend limit|monthly (usage )?limit|usage limit reached|insufficient (credit|balance)'
}

claude_billing_marker() { echo "$CLAUDE_BILLING_STATE_DIR/api-exhausted-$(date +%Y%m)"; }

run_claude_billed() {
  local key="" out rc reason marker
  marker=$(claude_billing_marker)
  out=$(mktemp "${TMPDIR:-/tmp}/run-claude.XXXXXX") || { "$@" >>"$LOG" 2>&1; return $?; }
  if [ ! -s "$CLAUDE_API_KEY_FILE" ]; then
    reason="キー未配置"
  elif [ -e "$marker" ]; then
    reason="今月はクレジット切れ済み"
  else
    key=$(tr -d '[:space:]' <"$CLAUDE_API_KEY_FILE")
  fi

  if [ -n "$key" ]; then
    ANTHROPIC_API_KEY="$key" "$@" >"$out" 2>&1
    rc=$?
    cat "$out" >>"$LOG"
    if [ "$rc" -ne 0 ] && tail -n 20 "$out" | claude_billing_is_exhausted; then
      mkdir -p "$CLAUDE_BILLING_STATE_DIR" && : >"$marker"
      log "課金: api→subscription（API のクレジット切れ・利用上限を検知。今月はサブスクで動かす: $(basename "$marker")）"
      env -u ANTHROPIC_API_KEY "$@" >"$out" 2>&1
      rc=$?
      cat "$out" >>"$LOG"
    else
      log "課金: api"
    fi
  else
    env -u ANTHROPIC_API_KEY "$@" >"$out" 2>&1
    rc=$?
    cat "$out" >>"$LOG"
    log "課金: subscription（${reason}）"
  fi
  rm -f "$out"
  return "$rc"
}
