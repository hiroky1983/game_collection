#!/bin/bash
# 実装当番のローカル発火チェック。launchd から1時間おきに呼ばれる。
# 仕事（承認済み Issue / 未解決 CodeRabbit スレッド）がある時だけ claude を起動する。
# 作業は専用クローン（~/.asobiba-duty/）で行い、人間の作業ツリーとは衝突しない。
# セットアップ手順は docs/ai-devops.md の「実装ループ」参照。
set -uo pipefail

DUTY_DIR="$HOME/.asobiba-duty/game_collection"
LOCK_DIR="${TMPDIR:-/tmp}/asobiba-ai-duty.lock"
LOG="$HOME/Library/Logs/asobiba-ai-duty.log"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

# 多重起動防止（前回の当番がまだ働いていたらスキップ）
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "前回実行中のためスキップ"
  exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT

gh auth status >/dev/null 2>&1 || { log "gh 未認証またはオフライン"; exit 0; }

# 仕事1: 承認済みで未着手の Issue
APPROVED=$(gh issue list -R hiroky1983/game_collection --label "ai:approved" --state open \
  --json number,labels \
  --jq '[.[] | select([.labels[].name] | index("ai:in-progress") | not)] | length' 2>/dev/null || echo 0)

# 仕事2: オープン PR 上の未解決 CodeRabbit スレッド
THREADS=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    pullRequests(states: OPEN, first: 20) {
      nodes {
        reviewThreads(first: 50) {
          nodes {
            isResolved
            comments(first: 1) { nodes { author { login } } }
          }
        }
      }
    }
  }
}' --jq '[.data.repository.pullRequests.nodes[].reviewThreads.nodes[]
  | select(.isResolved == false)
  | select(.comments.nodes[0].author.login | test("coderabbitai"))] | length' 2>/dev/null || echo 0)

if [ "${APPROVED:-0}" -eq 0 ] && [ "${THREADS:-0}" -eq 0 ]; then
  log "仕事なし (approved=0, cr_threads=0)"
  exit 0
fi

# 専用クローンを用意して main に同期（人間の作業ツリーには触らない）
if [ ! -d "$DUTY_DIR/.git" ]; then
  mkdir -p "$(dirname "$DUTY_DIR")"
  gh repo clone hiroky1983/game_collection "$DUTY_DIR" >>"$LOG" 2>&1 || { log "clone 失敗"; exit 0; }
fi
git -C "$DUTY_DIR" checkout main >>"$LOG" 2>&1
git -C "$DUTY_DIR" pull origin main >>"$LOG" 2>&1

log "当番起動 (approved=$APPROVED, cr_threads=$THREADS)"
cd "$DUTY_DIR" || exit 0
claude --model opus \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep,WebFetch,WebSearch" \
  -p "$(cat "$DUTY_DIR/Scripts/ai-duty-prompt.md")" >>"$LOG" 2>&1
log "当番終了 (exit=$?)"
