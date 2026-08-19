#!/bin/bash
# 経営企画室の日次発火。launchd（~/Library/LaunchAgents/com.asobiba.ai-management.plist、
# StartInterval 86400）から毎日呼ばれる。
# 開発当番（ai-duty.sh、毎時）とは役割が異なる: コードは一切変更せず、
#   1) 未承認の ai:proposed への優先度・工数分析コメント付与
#   2) 滞留した ringi:pending へのリマインド
#   3) 週1回、ロードマップ（docs/ai-company.md）と実績の差分レビュー
#   4) 分析の結果、真に必要と判断したときだけ新規提案を起票（機械的な数合わせはしない）
# を行う。2026-08-19 会長指摘「開発部だけが自律的で経営企画室が機能していない」を受けて新設。
# 旧「枯渇駆動の企画モード」（ai-duty.sh 内、分析なしの機械的な起票のみ）は本スクリプトへ
# 責務を移管し廃止した。セットアップ手順は docs/ai-devops.md 参照。
set -uo pipefail

MGMT_DIR="$HOME/.asobiba-mgmt/game_collection"
LOCK_DIR="${TMPDIR:-/tmp}/asobiba-ai-management.lock"
LOG="$HOME/Library/Logs/asobiba-ai-management.log"
MGMT_FETCH_TIMEOUT="${MGMT_FETCH_TIMEOUT:-90}"
MGMT_FETCH_KILL_GRACE="${MGMT_FETCH_KILL_GRACE:-5}"
MGMT_LOCK_GRACE="${MGMT_LOCK_GRACE:-2}"  # PID_FILE 書き込み前のロック取得直後を stale と誤認しないための猶予秒数
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

# タイムアウト付き fetch（自己更新・本更新の両方から使う共通処理）。
# macOS には timeout(1) が無いため自前で見張り、上限を超えたら諦める。
#   - SIGTERM → 猶予 → SIGKILL → 猶予 と escalate し、それでも終了を確認できなければ
#     wait せずに諦める（残る子プロセスはゾンビだが、当番の進行を止めるよりはよい）
# 戻り値: 0=成功 / 1=失敗 or タイムアウト
fetch_with_timeout() {
  local dir="$1" gpid waited=0
  GIT_TERMINAL_PROMPT=0 git -C "$dir" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
    fetch origin --prune --quiet >>"$LOG" 2>&1 &
  gpid=$!
  while [ "$waited" -lt "$MGMT_FETCH_TIMEOUT" ] && kill -0 "$gpid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$gpid" 2>/dev/null; then
    local sig grace
    for sig in TERM KILL; do
      kill -"$sig" "$gpid" 2>/dev/null
      grace=0
      while [ "$grace" -lt "$MGMT_FETCH_KILL_GRACE" ] && kill -0 "$gpid" 2>/dev/null; do
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
    log "fetch が ${MGMT_FETCH_TIMEOUT} 秒を超えたため見送り"
    return 1
  fi
  wait "$gpid" 2>/dev/null
}

# 自己更新: ai-duty.sh と同一パターン・同一の理由（launchd は会長の作業ツリーの本ファイルを
# 起動するため、main へマージしただけでは反映されない。#128 の教訓を最初から踏まえる）。
# セキュリティ考慮（所有者専用ディレクトリ・blob ハッシュ名・構文検証）も ai-duty.sh に準拠。
self_update() {
  [ -n "${MGMT_SELF_UPDATED:-}" ] && return 0
  [ -d "$MGMT_DIR/.git" ] || return 0
  fetch_with_timeout "$MGMT_DIR" || return 0
  local oid cache fresh tmp
  oid=$(git -C "$MGMT_DIR" rev-parse "origin/main:Scripts/ai-management-duty.sh" 2>/dev/null) || return 0
  [ -n "$oid" ] || return 0
  cache="$HOME/.asobiba-mgmt/bin"
  mkdir -p "$cache" && chmod 700 "$cache" || return 0
  find "$cache" -maxdepth 1 -type f -name 'ai-management-*.sh' -mtime +7 -delete 2>/dev/null
  fresh="$cache/ai-management-${oid}.sh"
  tmp=$(mktemp "$cache/ai-management-XXXXXX") || return 0
  if ! git -C "$MGMT_DIR" show "origin/main:Scripts/ai-management-duty.sh" >"$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
    rm -f "$tmp"; return 0
  fi
  if ! bash -n "$tmp" 2>/dev/null; then
    rm -f "$tmp"; log "自己更新: origin/main の ai-management-duty.sh が構文エラーのため見送り"; return 0
  fi
  if cmp -s "$tmp" "$0"; then rm -f "$tmp"; return 0; fi
  mv -f "$tmp" "$fresh" || { rm -f "$tmp"; return 0; }
  log "自己更新: origin/main の ai-management-duty.sh へ切り替え (実行中=$0, blob=${oid:0:7})"
  export MGMT_SELF_UPDATED=1
  exec /bin/bash "$fresh" "$@"
}
self_update "$@"

# 多重起動防止（前回がまだ働いていたらスキップ。死んだプロセスのロックは回収）。
#   - mkdir でロックを取ってから PID_FILE に書き込むまでの一瞬、PID_FILE が空の状態が生じる
#     （CodeRabbit 指摘・PR #163）。この空白を「前回プロセスが死んで stale 化した」と誤認して
#     即座に rm -rf すると、ほぼ同時に起動した2つのインスタンスが両方ロックを取ってしまい、
#     Issue コメントやドキュメント PR が重複しうる。LOCK_DIR の生成時刻が直近（$MGMT_LOCK_GRACE
#     秒未満）なら「今まさに書き込み中」とみなし、stale と決めつけずに諦める（次回の日次起動で
#     再試行される。取りこぼしはあっても重複よりましというCodeRabbitの助言に沿う）
PID_FILE="$LOCK_DIR/pid"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    log "前回実行中 (pid=$OLD_PID) のためスキップ"
    exit 0
  fi
  if [ -z "$OLD_PID" ]; then
    LOCK_MTIME=$(stat -f %m "$LOCK_DIR" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if [ "$LOCK_MTIME" -gt 0 ] && [ $((NOW - LOCK_MTIME)) -lt "$MGMT_LOCK_GRACE" ]; then
      log "ロック取得直後の書き込み待ちの可能性があるため今回は見送り（次回に再試行）"
      exit 0
    fi
  fi
  log "停止済みプロセスのロックを回収 (pid=${OLD_PID:-不明})"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
echo $$ >"$PID_FILE"
trap 'rm -rf "$LOCK_DIR"' EXIT

gh auth status >/dev/null 2>&1 || { log "gh 未認証またはオフライン"; exit 0; }

# ベースクローンを用意（開発当番とは別クローン。worktree の同時操作で衝突させないため）
if [ ! -d "$MGMT_DIR/.git" ]; then
  mkdir -p "$(dirname "$MGMT_DIR")"
  gh repo clone hiroky1983/game_collection "$MGMT_DIR" >>"$LOG" 2>&1 || { log "clone 失敗"; exit 0; }
fi
# fetch 失敗時はここで終了する（CodeRabbit指摘）。素通りすると古い origin/main のまま
# worktree を作り、経営判断や docs 更新が古い状態に基づいてしまう
fetch_with_timeout "$MGMT_DIR" || { log "fetch 失敗のため今回は見送り"; exit 0; }

# 1実行 = 1使い捨て worktree
RUNS_DIR="$HOME/.asobiba-mgmt/runs"
mkdir -p "$RUNS_DIR"
find "$RUNS_DIR" -maxdepth 1 -type d -name 'run-*' -mtime +3 | while read -r d; do
  case "$d" in
    "$RUNS_DIR"/run-*) git -C "$MGMT_DIR" worktree remove --force "$d" >>"$LOG" 2>&1 || rm -rf "$d" ;;
  esac
done
git -C "$MGMT_DIR" worktree prune >>"$LOG" 2>&1

RUN_DIR="$RUNS_DIR/run-$(date +%Y%m%d-%H%M%S)"
git -C "$MGMT_DIR" worktree add --detach "$RUN_DIR" origin/main >>"$LOG" 2>&1 || { log "worktree 作成失敗"; exit 0; }

# 書き込み範囲を docs/ 配下に技術的に制限する（CodeRabbit指摘: プロンプトの指示だけに
# コード変更禁止を委ねるな、というセキュリティ指摘への対応）。GitHub Issue 本文や
# WebSearch の結果には信頼できない第三者の文言が混ざりうるため、万一プロンプト注入で
# エージェントが App/ や Packages/ を編集しようとしても、コミット時にこの pre-commit
# フックが拒否する。Issue へのコメント・ラベル操作等（gh コマンド経由）はこのフックの
# 対象外だが、コード変更という最大の実害はここで技術的に塞ぐ。
#   - worktree の `.git` は共通 gitdir を指す**ファイル**であり、`.git/hooks/` は
#     全 worktree（会長の作業ツリーや開発当番のworktreeも含む）で共有されている。
#     そこへ直接書くと、この経営当番の実行がリポジトリ全体のコミットを止めてしまう
#     （実際に手元で検証し、共有ディレクトリであることを確認した上でこの実装を避けた）。
#   - 代わりに `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` で
#     `core.hooksPath` をこのプロセスの環境変数としてのみ上書きする。これは git が
#     コマンドラインの `-c` と同じ優先度で読む環境変数オーバーライドで、**ディスク上の
#     どのファイルにも書き込まない**。`claude` の子プロセス（Bash ツール経由の git
#     コマンド）にも環境変数として継承される。他の worktree・会長の作業ツリーには
#     一切影響しないことを実際に検証済み
MGMT_HOOKS_DIR="$RUN_DIR/.mgmt-hooks"
mkdir -p "$MGMT_HOOKS_DIR"
cat > "$MGMT_HOOKS_DIR/pre-commit" <<'HOOK'
#!/bin/bash
# ai-management-duty.sh が実行時に GIT_CONFIG_* 経由で有効化。docs/ 以外への変更を含む
# コミットを拒否する（このプロセスの実行中のみ有効。他の worktree には影響しない）。
set -uo pipefail
offending=$(git diff --cached --name-only | grep -v '^docs/' || true)
if [ -n "$offending" ]; then
  echo "経営当番は docs/ 配下しか変更できません。以下がその対象外です:" >&2
  echo "$offending" >&2
  exit 1
fi
exit 0
HOOK
chmod +x "$MGMT_HOOKS_DIR/pre-commit"
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.hooksPath
export GIT_CONFIG_VALUE_0="$MGMT_HOOKS_DIR"

# 週次ロードマップレビューの実施判定を、git のコミット時刻ではなくここで永続化した
# スタンプファイルで行う（CodeRabbit指摘）。docs/ai-company.md のコミット時刻を基準にすると、
# 「レビューした結果、更新不要だった」回に時刻が進まず、6日を超えた翌日以降は毎日
# レビューが再実行されてしまう。実行の要否に関わらずレビューを行った日に必ずこのファイルを
# touch することで、真に週1回のペースを保つ
ROADMAP_STAMP="$HOME/.asobiba-mgmt/last-roadmap-review"
MGMT_ROADMAP_REVIEW_DUE=0
if [ ! -f "$ROADMAP_STAMP" ] || [ -n "$(find "$ROADMAP_STAMP" -mtime +6 2>/dev/null)" ]; then
  MGMT_ROADMAP_REVIEW_DUE=1
fi
export MGMT_ROADMAP_REVIEW_DUE

log "経営当番起動 (workdir=$RUN_DIR, roadmap_review_due=$MGMT_ROADMAP_REVIEW_DUE)"
cd "$RUN_DIR" || exit 0
claude --model opus \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep,WebFetch,WebSearch" \
  -p "$(cat "$RUN_DIR/Scripts/ai-management-prompt.md")" >>"$LOG" 2>&1
RC=$?
[ "$MGMT_ROADMAP_REVIEW_DUE" = "1" ] && touch "$ROADMAP_STAMP"
log "経営当番終了 (exit=$RC)"
