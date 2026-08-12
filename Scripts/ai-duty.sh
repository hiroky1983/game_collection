#!/bin/bash
# 実装当番のローカル発火チェック。launchd から1時間おきに呼ばれる。
# 仕事（承認済み Issue / 未解決 CodeRabbit スレッド / レビュー未着の PR）がある時だけ claude を起動する。
# 作業は専用クローン（~/.asobiba-duty/）で行い、人間の作業ツリーとは衝突しない。
# セットアップ手順は docs/ai-devops.md の「実装ループ」参照。
set -uo pipefail

DUTY_DIR="$HOME/.asobiba-duty/game_collection"
LOCK_DIR="${TMPDIR:-/tmp}/asobiba-ai-duty.lock"
LOG="$HOME/Library/Logs/asobiba-ai-duty.log"
DUTY_FETCH_TIMEOUT="${DUTY_FETCH_TIMEOUT:-90}"  # 自己更新の fetch の上限秒数（テストから短縮できるよう外出し）
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

# 自己更新: launchd が起動するのは会長の作業ツリー（~/myspace/game_collection）の本ファイルであり、
# main へマージしただけでは反映されない。会長が git pull するまで旧版が動き続け、修正済みの
# 発火条件が効かないまま空振り起動を繰り返す（2026-08-12: #73 の blocked 除外がこの理由で効かず、
# 10分おきに当番が空振り起動していた）。会長の手作業に依存せず、当番専用クローンから
# origin/main の最新版を取り出して実行し直す。
#   - 取得元は当番専用クローンのみ。会長の作業ツリーには一切触れない（別セッションとの競合回避）
#   - ロック取得より **前** に行う。exec は PID を変えないため、ロック取得後に exec すると
#     再入した自分自身を「前回実行中」と誤認して以後永久にスキップしてしまう
#   - 取り出し先は共有 /tmp ではなく所有者専用ディレクトリ（700）。共有 /tmp だとファイル名が
#     公開済みの blob ハッシュから予測でき、同一マシンの第三者が構文の通る偽スクリプトを先回りで
#     置くと、それをそのまま exec してしまう（PR #75 の CodeRabbit 指摘・Critical）。
#     既存ファイルの内容も信用せず、毎回 origin/main から取り出し直して照合する
#   - 実体は blob ハッシュ名で保存する。実行中の旧インスタンスが同じファイルを読んでいても
#     内容が同一で、置換も mv（原子的・inode 差し替え）なので破損しない
#   - この fetch はロックの外側で走るため、ハングすると launchd の10分間隔でプロセスが
#     積み上がる（ロックを取れていないので後続も素通りして同じ場所で詰まる）。
#     macOS には timeout(1) が無いので自前で見張り、上限を超えたら自己更新を諦めて先へ進む
self_update() {
  [ -n "${DUTY_SELF_UPDATED:-}" ] && return 0
  [ -d "$DUTY_DIR/.git" ] || return 0
  local gpid waited=0
  GIT_TERMINAL_PROMPT=0 git -C "$DUTY_DIR" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
    fetch origin --prune --quiet >>"$LOG" 2>&1 &
  gpid=$!
  while [ "$waited" -lt "$DUTY_FETCH_TIMEOUT" ] && kill -0 "$gpid" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$gpid" 2>/dev/null; then
    kill "$gpid" 2>/dev/null
    wait "$gpid" 2>/dev/null
    log "自己更新: fetch が ${DUTY_FETCH_TIMEOUT} 秒を超えたため見送り"
    return 0
  fi
  if ! wait "$gpid" 2>/dev/null; then
    log "自己更新: fetch に失敗したため見送り"
    return 0
  fi
  local oid cache fresh tmp
  oid=$(git -C "$DUTY_DIR" rev-parse "origin/main:Scripts/ai-duty.sh" 2>/dev/null) || return 0
  [ -n "$oid" ] || return 0
  cache="$HOME/.asobiba-duty/bin"
  mkdir -p "$cache" && chmod 700 "$cache" || return 0
  # 古いキャッシュの掃除。このあと作る $fresh より前に行うので、更新対象を消してしまうことはない
  find "$cache" -maxdepth 1 -type f -name 'ai-duty-*.sh' -mtime +7 -delete 2>/dev/null
  fresh="$cache/ai-duty-${oid}.sh"
  tmp=$(mktemp "$cache/ai-duty-XXXXXX") || return 0
  if ! git -C "$DUTY_DIR" show "origin/main:Scripts/ai-duty.sh" >"$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
    rm -f "$tmp"; return 0
  fi
  # 壊れたスクリプトへ乗り換えて当番が止まるのを防ぐ
  if ! bash -n "$tmp" 2>/dev/null; then
    rm -f "$tmp"; log "自己更新: origin/main の ai-duty.sh が構文エラーのため見送り"; return 0
  fi
  if cmp -s "$tmp" "$0"; then rm -f "$tmp"; return 0; fi
  mv -f "$tmp" "$fresh" || { rm -f "$tmp"; return 0; }
  log "自己更新: origin/main の ai-duty.sh へ切り替え (実行中=$0, blob=${oid:0:7})"
  export DUTY_SELF_UPDATED=1
  exec /bin/bash "$fresh" "$@"
}
self_update "$@"

# 多重起動防止（前回の当番がまだ働いていたらスキップ。死んだプロセスのロックは回収）
PID_FILE="$LOCK_DIR/pid"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    log "前回実行中 (pid=$OLD_PID) のためスキップ"
    exit 0
  fi
  log "停止済みプロセスのロックを回収 (pid=${OLD_PID:-不明})"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
echo $$ >"$PID_FILE"
trap 'rm -rf "$LOCK_DIR"' EXIT

gh auth status >/dev/null 2>&1 || { log "gh 未認証またはオフライン"; exit 0; }

# 仕事1: 承認済みで未着手の Issue
# ai:in-progress（着手済み）と ringi:pending（会長の決裁待ち = 当番には進められない）は除外する。
# 除外しないと、成果物を出して決裁待ちになった Issue を毎時拾い直して同じ作業を繰り返す。
# blocked（Issue 自身が定めた着手条件が未達 = 外部イベント待ち）も同じ理由で除外する。
# 例: 「v1.1.0 リリースから2週間経過後」のような条件は当番の努力では満たせないため、
# 除外しないと条件成立まで毎時空振りで当番を起動し続けることになる（#54 で実際に発生）。
APPROVED=$(gh issue list -R hiroky1983/game_collection --label "ai:approved" --state open \
  --json number,labels \
  --jq '[.[] | ([.labels[].name]) as $l
        | select(($l | index("ai:in-progress")) == null and ($l | index("ringi:pending")) == null
                 and ($l | index("blocked")) == null)] | length' 2>/dev/null || echo 0)

# 仕事2: オープン PR 上の未解決 CodeRabbit スレッド
# 上限 50 PR × 100 スレッド（個人リポジトリの規模では実質全件。超えたら要ページング対応）
THREADS=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    pullRequests(states: OPEN, first: 50) {
      nodes {
        reviewThreads(first: 100) {
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
  | (.comments.nodes[0].author.login // "") as $l
  | select($l == "coderabbitai" or $l == "coderabbitai[bot]")] | length' 2>/dev/null || echo 0)

# 仕事3: CodeRabbit のレビューが HEAD に対して未着のオープン PR（Issue #41）
# 「未解決スレッド数」だけを見ていると、レビュー自体が走らなかった PR（レート制限・
# デフォルト以外の base への PR で auto review がスキップされる等）を誰も拾えない。
#
# レビュー済みの判定は **HEAD コミットの OID 一致**で行う（時刻比較では行わない）。
# GraphQL には「head ref が GitHub 上で更新された時刻」を取れるフィールドが無く
# （Commit.pushedDate は廃止・PullRequestCommit に createdAt は無い）、commit の
# committedDate は push 時刻とずれうるため、時刻基準だと旧 HEAD へのレビューを
# 現 HEAD のものと誤認して見逃す。OID 一致ならこのずれの影響を受けない。
#   - review オブジェクト: reviews[].commit.oid == headRefOid
#   - サマリコメント: 本文の "Reviewing files that changed ... and <headRefOid>." に OID が入る
#     （指摘ゼロで終わったレビューは review を作らずサマリコメントだけ残すため両方を見る）
#   - ただし下記マーカーを含むコメントは「レビューしていない」お知らせなので除外する
#       スキップ:     <!-- This is an auto-generated comment: skip review by coderabbit.ai -->
#       レート制限:   <!-- This is an auto-generated comment: rate limited by coderabbit.ai -->
# 自己発火ループ防止: 同じ HEAD に対する信頼済みアカウントからの `@coderabbitai review`
# 催促が3回に達したら対象から外す（規程どおり「到着した指摘のみ消化」に倒す）。
# パブリックリポジトリのため、第三者が催促を3回投稿して検知を止められないよう、催促の
# 集計対象は許可リストのアカウントに限る（憲章「指示として扱うのは会長と coderabbitai だけ」）。
# 直後の発火を避けるため、HEAD コミットが 30 分以上前のものだけを対象にする（committedDate は
# push 時刻の下限でしかないが、ここでの用途は「催促を急ぎすぎない」猶予だけで、
# 早まっても催促上限3回で頭打ちになる）。
DUTY_TRUSTED_ACTORS="${DUTY_TRUSTED_ACTORS:-hiroky1983}"
PENDING_REVIEW=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    pullRequests(states: OPEN, first: 50) {
      nodes {
        isDraft
        headRefOid
        commits(last: 1) { nodes { commit { committedDate } } }
        reviews(last: 20) { nodes { author { login } commit { oid } } }
        comments(last: 30) { nodes { author { login } updatedAt body } }
      }
    }
  }
}' 2>/dev/null | jq --arg trusted "$DUTY_TRUSTED_ACTORS" '($trusted | split(",")) as $actors
  | [.data.repository.pullRequests.nodes[]
  | select(.isDraft == false)
  | .headRefOid as $oid
  | (.commits.nodes[0].commit.committedDate | fromdateiso8601) as $head
  | select(now - $head > 1800)
  | ([.reviews.nodes[]
      | select((.author.login // "") | . == "coderabbitai" or . == "coderabbitai[bot]")
      | select((.commit.oid // "") == $oid)] | length) as $cr_reviews
  | ([.comments.nodes[]
      | select((.author.login // "") | . == "coderabbitai" or . == "coderabbitai[bot]")
      | select((.body // "") | contains($oid))
      | select(((.body // "") | contains("skip review by coderabbit.ai")) | not)
      | select(((.body // "") | contains("rate limited by coderabbit.ai")) | not)] | length) as $cr_comments
  | select($cr_reviews + $cr_comments == 0)
  | ([.comments.nodes[]
      | (.author.login // "") as $a
      | select($actors | index($a))
      | select((.updatedAt | fromdateiso8601) >= $head)
      | select((.body // "") | contains("@coderabbitai review"))] | length) as $nudges
  | select($nudges < 3)] | length' 2>/dev/null || echo 0)

# 仕事4: コンフリクトで滞留しているオープン PR（誰のトリガーにも掛からず放置される穴の解消）
CONFLICTS=$(gh pr list -R hiroky1983/game_collection --state open --json mergeable \
  --jq '[.[] | select(.mergeable == "CONFLICTING")] | length' 2>/dev/null || echo 0)

# 仕事5: 決裁コメントの着信（ringi:pending の Issue に決裁スレッド以外の新規コメントが付いたら
# 会長の決裁着信の可能性として当番を起こす。判定と反映は当番エージェントが行う）
# 注: 当番(AI)のコメントも会長と同じアカウント(hiroky1983)で投稿されるため、この2者は author では
#     区別できない。よって「最後のコメントが決裁スレッド(【要決裁】)でも反映記録(決裁反映)でもない」
#     ことを検知条件とする。ただし coderabbitai 等の bot・第三者のコメントは決裁になり得ないため、
#     許可リスト外の author は無視して「最後の信頼済みコメント」で判定する
#     （2026-08-11: Issue #68 に CodeRabbit の自動プランが付き毎時の空振り起動が発生したため追加）。
RINGI_REPLIES=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    issues(states: OPEN, labels: ["ringi:pending"], first: 20) {
      nodes {
        number
        comments(last: 20) { nodes { body author { login } } }
      }
    }
  }
}' 2>/dev/null | jq --arg trusted "$DUTY_TRUSTED_ACTORS" '($trusted | split(",")) as $actors
  | [.data.repository.issues.nodes[]
  | ([.comments.nodes[]
      | select((.author.login // "") as $l | ($actors | index($l)) != null)
      | .body] | last // "") as $b
  | select(($b | contains("【要決裁】")) | not)
  | select(($b | contains("決裁反映")) | not)
  | select($b != "")] | length' 2>/dev/null || echo 0)

# 仕事6: マージ可能なのに放置されている PR（CLEAN かつ auto-merge 未設定）
# 「完成したのに誰もマージしない」滞留（PR #58 で実際に発生）の検知
STALLED=$(gh pr list -R hiroky1983/game_collection --state open --json mergeStateStatus,autoMergeRequest \
  --jq '[.[] | select(.mergeStateStatus == "CLEAN") | select(.autoMergeRequest == null)] | length' 2>/dev/null || echo 0)

# 仕事7: App Store で公開済みなのに main へ未マージの release ブランチ
# 規程（ai-devops.md）では「公開後に release/vX.Y.Z → main をマージしタグを打つ」のは AI の責務だが、
# その起点はリリース Issue への会長の「公開された」コメントしかなく、Issue が閉じられると
# どのトリガーにも掛からず宙に浮く（#68 が審査提出の時点で close され、実際にこの状態になった）。
# 会長の申告を待たず App Store の公開バージョン（iTunes Lookup API）を直接見て、release ブランチの
# バージョンに追いついたら当番を起こす。main へ取り込み済みなら ahead_by == 0 になり再発火しない。
DUTY_APP_ID="${DUTY_APP_ID:-6781719499}"
RELEASED=0
REL_BRANCH=$(gh api "repos/hiroky1983/game_collection/git/matching-refs/heads/release/v" \
  --jq '.[].ref | sub("^refs/heads/";"")' 2>/dev/null | sort -V | tail -1)
if [ -n "${REL_BRANCH:-}" ]; then
  AHEAD=$(gh api "repos/hiroky1983/game_collection/compare/main...$REL_BRANCH" --jq '.ahead_by' 2>/dev/null || echo 0)
  if [ "${AHEAD:-0}" -gt 0 ]; then
    STORE_VER=$(curl -sf --max-time 10 "https://itunes.apple.com/lookup?id=${DUTY_APP_ID}&country=jp" 2>/dev/null \
      | jq -r '.results[0].version // empty' 2>/dev/null)
    REL_VER="${REL_BRANCH#release/v}"
    # 公開バージョン >= release ブランチのバージョン（= 世に出た）なら仕事あり
    if [ -n "${STORE_VER:-}" ] \
      && [ "$(printf '%s\n%s\n' "$REL_VER" "$STORE_VER" | sort -V | tail -1)" = "$STORE_VER" ]; then
      RELEASED=1
    fi
  fi
fi

# 仕事8: 企画議論の着信（未承認の ai:proposed Issue に会長がコメントしたら経営企画室が応答する）
# 決裁検知（仕事5）は ringi:pending しか見ておらず、提案段階の議論は誰も拾わなかった穴の解消。
# 承認済み・着手済み・blocked のものは他のフローが担当するため除外。
# 応答側は必ず「企画議論」で始まるコメントを返す（それが再検知を止める目印になる）。
PROPOSED_REPLIES=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    issues(states: OPEN, labels: ["ai:proposed"], first: 20) {
      nodes {
        number
        labels(first: 10) { nodes { name } }
        comments(last: 20) { nodes { body author { login } } }
      }
    }
  }
}' 2>/dev/null | jq --arg trusted "$DUTY_TRUSTED_ACTORS" '($trusted | split(",")) as $actors
  | [.data.repository.issues.nodes[]
  | ([.labels.nodes[].name]) as $l
  | select(($l | index("ai:approved")) == null and ($l | index("ai:in-progress")) == null and ($l | index("blocked")) == null)
  | ([.comments.nodes[]
      | select((.author.login // "") as $a | ($actors | index($a)) != null)
      | .body] | last // "") as $b
  | select($b != "")
  | select(($b | startswith("企画議論")) | not)
  | select(($b | contains("【要決裁】")) | not)
  | select(($b | contains("決裁反映")) | not)] | length' 2>/dev/null || echo 0)

# 仕事9: 孤児化した ai:in-progress の回収（Issue #83）
# 当番が着手直後に異常終了すると ai:in-progress が残留し、その Issue は仕事1の集計から
# 恒久的に外れて誰も着手できなくなる（#80 で発生。12:07 の実行が着手直後に死亡し約2.5時間滞留）。
#
# 誤検知ガードは2重:
#   1) ロック — ここに到達している時点で他の当番は動いていない。生きている先行プロセスが
#      あればロック取得の段階で既に exit 済みで、この行は実行されない。つまり
#      「ロックが存在せず（= 当番が動いていない）」という条件は到達自体が保証している。
#      逆に言うと、実行中の当番が長時間かけて実装している Issue は、次回の launchd 起動が
#      ロックで弾かれるため対象にならない。
#   2) 経過時間 — 最終更新から30分以上のものだけを対象にする。着手宣言・進捗コメント・
#      ラベル操作はいずれも updatedAt を更新するため、生きている作業は時間切れにならない。
#   3) 成果物 — オープン PR に紐づいている Issue（PR 本文の `Closes #N`）は除外する。
#      実装が PR まで到達していれば孤児ではなく、ラベルは PR のマージ（= Issue の close）で
#      自然に片付く。除外しないと、当番が「PR があるのでラベルは残す」と正しく判断するたびに
#      次の毎時起動でまた同じ Issue を拾い、マージされるまで空振りが続く。
DUTY_ORPHAN_MIN_AGE="${DUTY_ORPHAN_MIN_AGE:-1800}"  # 孤児とみなす無更新の秒数（テストから短縮できるよう外出し）
LINKED_ISSUES=$(gh api graphql -f query='
query {
  repository(owner: "hiroky1983", name: "game_collection") {
    pullRequests(states: OPEN, first: 50) {
      nodes { closingIssuesReferences(first: 10) { nodes { number } } }
    }
  }
}' --jq '[.data.repository.pullRequests.nodes[].closingIssuesReferences.nodes[].number]' 2>/dev/null)
# 取得に失敗したら「全部が紐づいている」とみなすのではなく空集合に倒すが、その場合でも
# 経過時間ガードが効くため、当番が起きて状況を確認するだけで実害は無い
LINKED_ISSUES="${LINKED_ISSUES:-[]}"
ORPHANS=$(gh issue list -R hiroky1983/game_collection --label "ai:in-progress" --state open \
  --json number,updatedAt 2>/dev/null \
  | jq --argjson age "$DUTY_ORPHAN_MIN_AGE" --argjson linked "$LINKED_ISSUES" \
     '[.[] | . as $i
           | select(($i.updatedAt | fromdateiso8601) < (now - $age))
           | select(($linked | index($i.number)) == null)] | length' 2>/dev/null || echo 0)
ORPHANS="${ORPHANS:-0}"

# 実行モード決定。仕事が無ければ「枯渇駆動の企画モード」を検討する
MODE="duty"
PROMPT_FILE="Scripts/ai-duty-prompt.md"
PLANNING_STAMP="$HOME/.asobiba-duty/last-planning"
if [ "${APPROVED:-0}" -eq 0 ] && [ "${THREADS:-0}" -eq 0 ] && [ "${PENDING_REVIEW:-0}" -eq 0 ] && [ "${CONFLICTS:-0}" -eq 0 ] && [ "${RINGI_REPLIES:-0}" -eq 0 ] && [ "${STALLED:-0}" -eq 0 ] && [ "${RELEASED:-0}" -eq 0 ] && [ "${PROPOSED_REPLIES:-0}" -eq 0 ] && [ "${ORPHANS:-0}" -eq 0 ]; then
  # 乱造ガード: 未承認の企画（ai:proposed のみ）が3件以上滞留していたら起案しない
  PROPOSED=$(gh issue list -R hiroky1983/game_collection --label "ai:proposed" --state open \
    --json number,labels \
    --jq '[.[] | select([.labels[].name] | index("ai:approved") | not)] | length' 2>/dev/null || echo 99)
  if [ "${PROPOSED:-99}" -ge 3 ]; then
    log "仕事なし（未承認の企画 ${PROPOSED} 件が滞留中のため企画モードもスキップ）"
    exit 0
  fi
  # 頻度ガード: 企画モードは1日1回まで
  if [ -f "$PLANNING_STAMP" ] && [ -z "$(find "$PLANNING_STAMP" -mtime +1 2>/dev/null)" ]; then
    log "仕事なし（企画モードは前回から24時間未経過のためスキップ）"
    exit 0
  fi
  MODE="planning"
  PROMPT_FILE="Scripts/ai-planning-prompt.md"
fi

# ベースクローンを用意（fetch 専用。ここでは一切作業しない）
if [ ! -d "$DUTY_DIR/.git" ]; then
  mkdir -p "$(dirname "$DUTY_DIR")"
  gh repo clone hiroky1983/game_collection "$DUTY_DIR" >>"$LOG" 2>&1 || { log "clone 失敗"; exit 0; }
fi
git -C "$DUTY_DIR" fetch origin --prune >>"$LOG" 2>&1

# 1実行 = 1使い捨て worktree。前回の残骸（異常終了時の未コミット変更等）と物理的に隔離する
RUNS_DIR="$HOME/.asobiba-duty/runs"
mkdir -p "$RUNS_DIR"
# 3日より古い実行用 worktree を掃除
find "$RUNS_DIR" -maxdepth 1 -type d -name 'run-*' -mtime +3 | while read -r d; do
  case "$d" in
    "$RUNS_DIR"/run-*) git -C "$DUTY_DIR" worktree remove --force "$d" >>"$LOG" 2>&1 || rm -rf "$d" ;;
  esac
done
git -C "$DUTY_DIR" worktree prune >>"$LOG" 2>&1

RUN_DIR="$RUNS_DIR/run-$(date +%Y%m%d-%H%M%S)"
git -C "$DUTY_DIR" worktree add --detach "$RUN_DIR" origin/main >>"$LOG" 2>&1 || { log "worktree 作成失敗"; exit 0; }

log "当番起動 (mode=$MODE, approved=$APPROVED, cr_threads=$THREADS, cr_pending=$PENDING_REVIEW, conflicts=$CONFLICTS, ringi_replies=$RINGI_REPLIES, stalled=$STALLED, released=$RELEASED, proposed_replies=$PROPOSED_REPLIES, orphans=$ORPHANS, workdir=$RUN_DIR)"
cd "$RUN_DIR" || exit 0
claude --model opus \
  --allowedTools "Bash,Read,Edit,Write,Glob,Grep,WebFetch,WebSearch" \
  -p "$(cat "$RUN_DIR/$PROMPT_FILE")" >>"$LOG" 2>&1
RC=$?
[ "$MODE" = "planning" ] && touch "$PLANNING_STAMP"
log "当番終了 (mode=$MODE, exit=$RC)"
