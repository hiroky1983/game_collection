#!/bin/bash
# 夜間ワークフロー（nightly-gamekit-full.yml・nightly-shogi-selfplay.yml）が schedule で赤になったら
# Issue を 1 本起票する（#3077）。
#
# 経緯: schedule の実行は PR に紐づかないため、PR の CI のように赤が当番の PR 消化に載らない。
# 失敗に気づく経路が GitHub 既定のメール通知（会長の受信箱）しか無かった。
#
# 動き: 各ワークフローの main の最新の schedule 実行を 1 件読み、conclusion が failure のときだけ、
#   run URL と `gh run view --log-failed` の先頭を書いた Issue を起票する。同じ run（databaseId）では
#   二重に起票しない（本文の `nightly-run-id: <id>` を検索で確かめる）。success に戻ったら何もしない
#   （Issue は開発当番が通常の手順で直して閉じる）。
#
# 呼び出し: ai-duty.sh のスロット1が毎回（仕事14 の自動ハンコの直後に）呼ぶ。失敗しても当番を止めない。
# 使い方: Scripts/check-nightly-failures.sh
#   環境変数: NIGHTLY_MILESTONE_CMD（積み先を出すコマンド。既定は同ディレクトリの pick-issue-milestone.sh）
set -uo pipefail

REPO="hiroky1983/game_collection"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MILESTONE_CMD="${NIGHTLY_MILESTONE_CMD:-bash $SCRIPT_DIR/pick-issue-milestone.sh}"
WORKFLOWS=(nightly-gamekit-full.yml nightly-shogi-selfplay.yml)

for wf in "${WORKFLOWS[@]}"; do
  run=$(gh run list -R "$REPO" --workflow "$wf" --branch main --event schedule --limit 1 \
    --json conclusion,databaseId,url --jq '.[0] // empty | "\(.conclusion)\t\(.databaseId)\t\(.url)"' 2>/dev/null) || continue
  [ -n "$run" ] || continue
  IFS=$'\t' read -r conclusion id url <<<"$run"
  [ "$conclusion" = failure ] || continue

  found=$(gh issue list -R "$REPO" --state all --search "nightly-run-id: $id in:body" --json number --jq 'length' 2>/dev/null) || continue
  [ "${found:-0}" = 0 ] || continue

  failed=$(gh run view "$id" -R "$REPO" --log-failed 2>/dev/null | head -20)
  milestone=$($MILESTONE_CMD 2>/dev/null) || milestone=""
  title="運用: 夜間ワークフロー ${wf%.yml} が schedule で失敗"
  [ -n "$milestone" ] && title="[$milestone] $title"
  body=$(printf '%s\n' \
    "## 概要" \
    "夜間ワークフロー \`$wf\` の main の schedule 実行が失敗しました（#3077 の検知）。" \
    "" \
    "- run: $url" \
    "- nightly-run-id: $id" \
    "" \
    "## 落ちたログの先頭（\`gh run view --log-failed\`）" \
    '```' \
    "${failed:-（ログを取得できませんでした。run を開いて確認してください）}" \
    '```' \
    "" \
    "## 受け入れ条件" \
    "- 原因を直し、次の夜間（または workflow_dispatch）が success になる" \
    "" \
    "自動ハンコの区分: 不具合")
  args=(issue create -R "$REPO" --title "$title" --body "$body" --label bug --label ai:proposed --label stamp:auto)
  [ -n "$milestone" ] && args+=(--milestone "$milestone")
  gh "${args[@]}" >/dev/null 2>&1
done
exit 0
