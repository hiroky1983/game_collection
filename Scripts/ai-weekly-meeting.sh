#!/bin/bash
# 週次経営会議の週次発火。launchd から週1回（月曜朝）呼ばれる
# （設定は会長の Mac の ~/Library/LaunchAgents/com.asobiba.ai-weekly.plist・
#  StartCalendarInterval Weekday=1。ai-duty.sh / ai-management-duty.sh の plist と
#  同じくローカル環境の設定のためリポジトリには含めない）。
#
# 2026-08-24: それまで claude.ai のクラウドルーティンとして動いていたが、Supabase・Canva・
# Sentry・Notion 等アプリの運営に無関係な MCP 接続が大量に紐づいており、ヘッドレス実行時に
# 認証待ち（mcp_auth_required）で即座に詰まって毎週空振りしていた（会長指摘・2026-08-24発覚）。
# ai-duty.sh / ai-management-duty.sh と同じローカル launchd 方式へ移行し、この問題を構造的に無くす
# （ローカル実行は `claude --allowedTools` で渡したツールしか使わないため、無関係な MCP が
# 混入する余地が無い）。
#
# 経営企画室（ai-management-duty.sh・日次）・開発当番（ai-duty.sh・毎時）とは役割が異なる:
# コードは一切変更せず、週次経営レポート（report:weekly ラベルの Issue）を1件作成するだけ。
set -uo pipefail

WEEKLY_DIR="$HOME/.asobiba-weekly/game_collection"
LOCK_DIR="${TMPDIR:-/tmp}/asobiba-ai-weekly.lock"
LOG="$HOME/Library/Logs/asobiba-ai-weekly.log"
WEEKLY_FETCH_TIMEOUT="${WEEKLY_FETCH_TIMEOUT:-90}"
WEEKLY_FETCH_KILL_GRACE="${WEEKLY_FETCH_KILL_GRACE:-5}"
WEEKLY_LOCK_GRACE="${WEEKLY_LOCK_GRACE:-30}"  # PID 未書き込みのロックを「取得直後」とみなす秒数
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

# タイムアウト付き fetch（自己更新・本更新の両方から使う共通処理）。
# パターンは ai-management-duty.sh の fetch_with_timeout と同一（詳細な理由もそちらを参照）。
fetch_with_timeout() {
  local dir="$1" gpid waited=0
  GIT_TERMINAL_PROMPT=0 git -C "$dir" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
    fetch origin --prune --quiet >>"$LOG" 2>&1 &
  gpid=$!
  while [ "$waited" -lt "$WEEKLY_FETCH_TIMEOUT" ] && kill -0 "$gpid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$gpid" 2>/dev/null; then
    local sig grace
    for sig in TERM KILL; do
      kill -"$sig" "$gpid" 2>/dev/null
      grace=0
      while [ "$grace" -lt "$WEEKLY_FETCH_KILL_GRACE" ] && kill -0 "$gpid" 2>/dev/null; do
        sleep 1
        grace=$((grace + 1))
      done
      kill -0 "$gpid" 2>/dev/null || break
    done
    if kill -0 "$gpid" 2>/dev/null; then
      log "fetch (pid=$gpid) が SIGKILL でも終了しないため wait せずに見送り"
      return 1
    fi
    wait "$gpid" 2>/dev/null
    log "fetch が ${WEEKLY_FETCH_TIMEOUT} 秒を超えたため見送り"
    return 1
  fi
  wait "$gpid" 2>/dev/null
}

# 自己更新: ai-duty.sh / ai-management-duty.sh と同一パターン。
self_update() {
  [ -n "${WEEKLY_SELF_UPDATED:-}" ] && return 0
  [ -d "$WEEKLY_DIR/.git" ] || return 0
  fetch_with_timeout "$WEEKLY_DIR" || return 0
  local oid cache fresh tmp
  oid=$(git -C "$WEEKLY_DIR" rev-parse "origin/main:Scripts/ai-weekly-meeting.sh" 2>/dev/null) || return 0
  [ -n "$oid" ] || return 0
  cache="$HOME/.asobiba-weekly/bin"
  mkdir -p "$cache" && chmod 700 "$cache" || return 0
  find "$cache" -maxdepth 1 -type f -name 'ai-weekly-*.sh' -mtime +7 -delete 2>/dev/null
  fresh="$cache/ai-weekly-${oid}.sh"
  tmp=$(mktemp "$cache/ai-weekly-XXXXXX") || return 0
  if ! git -C "$WEEKLY_DIR" show "origin/main:Scripts/ai-weekly-meeting.sh" >"$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
    rm -f "$tmp"; return 0
  fi
  if ! bash -n "$tmp" 2>/dev/null; then
    rm -f "$tmp"; log "自己更新: origin/main の ai-weekly-meeting.sh が構文エラーのため見送り"; return 0
  fi
  if cmp -s "$tmp" "$0"; then rm -f "$tmp"; return 0; fi
  mv -f "$tmp" "$fresh" || { rm -f "$tmp"; return 0; }
  log "自己更新: origin/main の ai-weekly-meeting.sh へ切り替え (実行中=$0, blob=${oid:0:7})"
  export WEEKLY_SELF_UPDATED=1
  exec /bin/bash "$fresh" "$@"
}
self_update "$@"

# 多重起動防止。パターンは ai-management-duty.sh と同一（詳細な理由もそちらを参照）。
lock_age() {
  local mtime now
  mtime=$(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null) || return 1
  [ -n "$mtime" ] || return 1
  now=$(date +%s)
  echo $((now - mtime))
}
PID_FILE="$LOCK_DIR/pid"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    log "前回実行中 (pid=$OLD_PID) のためスキップ"
    exit 0
  fi
  if [ -z "$OLD_PID" ]; then
    AGE=$(lock_age || true)
    if [ -z "$AGE" ] || [ "$AGE" -lt "$WEEKLY_LOCK_GRACE" ]; then
      log "ロック取得直後（PID 未書き込み・経過=${AGE:-不明}秒）のためスキップ"
      exit 0
    fi
  fi
  log "停止済みプロセスのロックを回収 (pid=${OLD_PID:-不明})"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
echo $$ >"$PID_FILE"
sleep 1
if [ "$(cat "$PID_FILE" 2>/dev/null || true)" != "$$" ]; then
  log "ロックの回収が競合したためスキップ (所有者=$(cat "$PID_FILE" 2>/dev/null || echo 不明))"
  exit 0
fi
trap '[ "$(cat "$PID_FILE" 2>/dev/null || true)" = "$$" ] && rm -rf "$LOCK_DIR"' EXIT

gh auth status >/dev/null 2>&1 || { log "gh 未認証またはオフライン"; exit 0; }

# ベースクローンを用意（他の当番とは別クローン。worktree の同時操作で衝突させないため）
if [ ! -d "$WEEKLY_DIR/.git" ]; then
  mkdir -p "$(dirname "$WEEKLY_DIR")"
  gh repo clone hiroky1983/game_collection "$WEEKLY_DIR" >>"$LOG" 2>&1 || { log "clone 失敗"; exit 0; }
fi
fetch_with_timeout "$WEEKLY_DIR" || { log "fetch 失敗のため今回は見送り"; exit 0; }

# 1実行 = 1使い捨て worktree
RUNS_DIR="$HOME/.asobiba-weekly/runs"
mkdir -p "$RUNS_DIR"
find "$RUNS_DIR" -maxdepth 1 -type d -name 'run-*' -mtime +3 | while read -r d; do
  case "$d" in
    "$RUNS_DIR"/run-*) git -C "$WEEKLY_DIR" worktree remove --force "$d" >>"$LOG" 2>&1 || rm -rf "$d" ;;
  esac
done
git -C "$WEEKLY_DIR" worktree prune >>"$LOG" 2>&1

RUN_DIR="$RUNS_DIR/run-$(date +%Y%m%d-%H%M%S)"
git -C "$WEEKLY_DIR" worktree add --detach "$RUN_DIR" origin/main >>"$LOG" 2>&1 || { log "worktree 作成失敗"; exit 0; }

log "週次経営会議起動 (workdir=$RUN_DIR)"
cd "$RUN_DIR" || exit 0
# gh issue create 以外の書き込みは不要な役割のため、Edit/Write は渡さない
# （プロンプト側の「コードは変更しない」という宣言を、渡すツール自体を絞ることで技術的にも裏付ける）。
claude --model sonnet \
  --allowedTools "Bash,Read,Glob,Grep,WebFetch,WebSearch" \
  -p "$(cat "$RUN_DIR/Scripts/ai-weekly-meeting-prompt.md")" >>"$LOG" 2>&1
RC=$?
log "週次経営会議終了 (exit=$RC)"
