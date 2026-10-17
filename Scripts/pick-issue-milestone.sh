#!/bin/bash
# 自動起票（当番・監査当番・経営企画室・自動QA当番）の Issue に付けるマイルストーン名を決めて出す
# （会長決裁 2026-10-16）。
#
# 経緯: 自動起票は「次版」（docs/ai-devops.md「ブランチ戦略」）に積む運用だったが、当番が着手できる Issue が
# 現行版に 1 件も無いときまで次の版へ積まれ、会長が毎回「1.1.13 を 1.1.12 に付け替えて」と手で直していた
# （直近で 3 回）。会長指示「当番が着手できるタスクが 0 なら今回の版につけるとか工夫は必要そう」。
# LLM の判断に任せるとぶれるので、判定はここで決定論的に出し、各当番のシェルが起動時に呼んでプロンプトへ渡す。
#
# 判定:
#   現行版 = オープンなマイルストーン（vX.Y.Z の形）のうち、凍結していない最小の版。
#            凍結 = `vX.Y.Z-submitted` タグか `vX.Y.Z`（公開）タグがある、または release/vX.Y.Z に lock_branch。
#   - 現行版が出荷準備の最中でない（版数更新 PR `chore/release-version-vX.Y.Z-b<N>` が開いていない）**かつ**
#     現行版で当番が着手できる Issue が 0 件 → 現行版
#     （着手できる = オープン・ai:approved で、ai:in-progress / blocked / ai:hold / ringi:pending / duty:heavy の
#      どれも無い。ai-duty.sh 仕事1 の候補と同じ除外に ai:hold を足したもの）
#   - それ以外 → 現行版の次のオープンなマイルストーン（従来の「次版」）
#   版数更新 PR がマージ済みであること・`出荷準備: vX.Y.Z @…` の依頼コメントがあることは凍結に数えない。
#   どちらも会長の実機確認（TestFlight）の段階で立ち、その版はまだ修正を受け入れている。数えると、着手できる
#   Issue が 0 件になって出荷準備が始まった版（= 会長が付け替えていた版）が常に対象外になり、決裁が効かない。
#   企画倉庫・会長のライブ QA 指摘の積み先はこのスクリプトの対象外（呼び出し側の規程どおり）。
#
# 取得に失敗したときは安全側（次の版）に倒す。次の版のマイルストーンが無いとき:
#   着手できる Issue があるだけなら現行版を出す（凍結していないので積める。マイルストーンの新設は会長決裁なので
#   ここでは作らない）。版数更新 PR が開いている・数え損ねたときは出す版が無いので 1 で終わる。
#
# 使い方: Scripts/pick-issue-milestone.sh
#   標準出力: マイルストーン名 1 行（例: v1.1.12）。タイトルの接頭辞は `[<この名前>]`
#   標準エラー: 判定の理由 1 行（ログ用）
# 終了コード: 0 = 決定 / 1 = 決められない（推測で付けない）
# 環境変数: PICK_MILESTONE_REPO（既定 hiroky1983/game_collection）
set -uo pipefail

REPO="${PICK_MILESTONE_REPO:-hiroky1983/game_collection}"

fail() { echo "pick-issue-milestone: $*" >&2; exit 1; }

if ! MILESTONES=$(gh api "repos/${REPO}/milestones?state=open&per_page=100" --jq '.[].title' 2>/dev/null); then
  fail "オープンなマイルストーンを取得できません"
fi
VERSIONS=$(printf '%s\n' "$MILESTONES" | sed -n 's/^v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$/\1/p' | sort -V -u)
[ -n "$VERSIONS" ] || fail "vX.Y.Z の形のオープンなマイルストーンがありません"

if ! TAGS=$(gh api "repos/${REPO}/git/matching-refs/tags/v" --jq '.[].ref' 2>/dev/null); then
  fail "タグを取得できません（凍結を判定できない）"
fi

has_tag() {  # has_tag <ref>（完全一致。v1.1.1 のタグで v1.1.10 を落とさない）
  printf '%s\n' "$TAGS" | grep -Fqx "$1"
}

CURRENT=""
NEXT=""
FROZEN_NOTE=""
for V in $VERSIONS; do
  if [ -n "$CURRENT" ]; then NEXT="$V"; break; fi
  if has_tag "refs/tags/v${V}-submitted" || has_tag "refs/tags/v${V}"; then
    FROZEN_NOTE="${FROZEN_NOTE}v${V}（提出・公開済み）"; continue
  fi
  # 保護設定が無い・ブランチが無いと gh はエラーになる。ai-duty.sh 仕事13 と同じく "true" だけを凍結とみなす
  LOCK=$(gh api "repos/${REPO}/branches/release%2Fv${V}/protection" --jq '.lock_branch.enabled' 2>/dev/null || true)
  if [ "$LOCK" = "true" ]; then
    FROZEN_NOTE="${FROZEN_NOTE}v${V}（凍結済み）"; continue
  fi
  CURRENT="$V"
done
[ -n "$CURRENT" ] || fail "凍結していないオープンなマイルストーンがありません（${FROZEN_NOTE}）"

pick_next() {  # pick_next <理由>
  if [ -n "$NEXT" ]; then
    echo "v${NEXT}"
    echo "pick-issue-milestone: v${NEXT}（次の版）: $1" >&2
    exit 0
  fi
  return 1
}

# 出荷準備の最中か（版数更新 PR が開いている）
if ! BUMP_PRS=$(gh pr list -R "$REPO" --state open --base "release/v${CURRENT}" --limit 100 \
    --json headRefName --jq "[.[] | select(.headRefName | startswith(\"chore/release-version-v${CURRENT}-b\"))] | length" 2>/dev/null) \
  || ! [[ "$BUMP_PRS" =~ ^[0-9]+$ ]]; then
  pick_next "現行版 v${CURRENT} の版数更新 PR を確認できないため" \
    || fail "現行版 v${CURRENT} の版数更新 PR を確認できず、次の版のマイルストーンもありません"
fi
if [ "$BUMP_PRS" -gt 0 ]; then
  pick_next "現行版 v${CURRENT} は版数更新 PR が開いている（出荷準備中）" \
    || fail "現行版 v${CURRENT} は出荷準備中で、次の版のマイルストーンがありません（新設は会長決裁）"
fi

# 現行版で当番が着手できる Issue の件数
if ! READY=$(gh issue list -R "$REPO" --milestone "v${CURRENT}" --state open --label "ai:approved" --limit 500 \
    --json number,labels \
    --jq '[.[] | ([.labels[].name]) as $l
          | select(($l | index("ai:approved")) != null and ($l | index("ai:in-progress")) == null
                   and ($l | index("blocked")) == null
                   and ($l | index("ai:hold")) == null and ($l | index("ringi:pending")) == null
                   and ($l | index("duty:heavy")) == null)] | length' 2>/dev/null) \
  || ! [[ "$READY" =~ ^[0-9]+$ ]]; then
  pick_next "現行版 v${CURRENT} の着手できる Issue を数えられないため" \
    || fail "現行版 v${CURRENT} の着手できる Issue を数えられず、次の版のマイルストーンもありません"
fi
if [ "$READY" -gt 0 ]; then
  pick_next "現行版 v${CURRENT} に当番が着手できる Issue が ${READY} 件ある" && exit 0
  echo "v${CURRENT}"
  echo "pick-issue-milestone: v${CURRENT}（現行版）: 着手できる Issue が ${READY} 件あるが、次の版のマイルストーンが無い" >&2
  exit 0
fi
echo "v${CURRENT}"
echo "pick-issue-milestone: v${CURRENT}（現行版）: 出荷準備中でなく、当番が着手できる Issue が 0 件" >&2
exit 0
