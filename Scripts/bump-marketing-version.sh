#!/bin/bash
# release/vX.Y.Z の project.yml の MARKETING_VERSION / CURRENT_PROJECT_VERSION を上げる PR を出す。
#
# なぜ要るか（2026-10-06・会長指示「多分毎回起こってるからちゃんとルール化してくれ」）:
# 版数の更新は「配信直前の手作業」で、出荷のたびに上げ忘れていた（v1.1.1・v1.1.2・v1.1.10 で
# `fastlane beta` の直前まで前の版のまま）。手順書に書いても人（AI）の記憶頼みでは毎回漏れるので、
# 更新そのものをこのスクリプトに寄せ、次の 2 か所から**機械的に**呼ぶ:
#   - `Scripts/ship-beta.sh`（社長が TestFlight へ上げる入口）: 不一致なら自動でこれを --wait 付きで呼び、
#     マージを待ってから fastlane beta に進む
#   - 当番の仕事13（`Scripts/ai-duty-prompt.md` 2.5 の 3.）: 出荷準備に入った版で呼ぶ
# PR のタイトルは常に `chore(release): バージョンを X.Y.Z (build N) に更新` に固定する。
# このマージが「出荷準備に入った」合図（docs/ai-devops.md「ブランチ戦略」の「次版」の定義）なので、
# 手で書くと `chore:` などに揺れて合図として読めなくなる（v1.1.7〜v1.1.9 で実際に揺れていた）。
#
# 後方の番号を出さない（会長指示 2026-10-06「後方バージョンがでない方法を考えること」）:
# 新しい番号は、次の「床」すべてより**大きい**ことを確かめ、満たさなければ何も作らずに止める。
#   - 版: App Store の公開版（iTunes Lookup・キャッシュバスタ付き）/ 既存の `vX.Y.Z`・`vX.Y.Z-submitted`
#         タグの版 / 凍結（lock_branch）済みの release ブランチの版。さらに今の project.yml の値からも下げない
#   - ビルド番号: 既存タグ時点の project.yml の CURRENT_PROJECT_VERSION すべて
# 比較は数値で行う（文字列で比べると 1.1.10 < 1.1.9 になる）。床を取得できないときも止める（取れないまま
# 進むと、比べていないのに「大丈夫」と言ってしまうため）。
#
# 使い方:
#   Scripts/bump-marketing-version.sh [--wait] [X.Y.Z]
#     X.Y.Z を省略すると現在のブランチ名（release/vX.Y.Z）から取る。
#     --wait: 必須チェックの完了を待ってマージし、state=MERGED を確かめてから終わる（ship-beta.sh 用）。
#             付けないときは PR を出して終わる（当番は通常のレビュー・マージのフローに載せる）。
#   Scripts/bump-marketing-version.sh plan <X.Y.Z> <project.yml> <床の版（空白区切り）> <床のビルド番号（空白区切り）>
#     ネットワークに触らない判定だけ。出力は "X.Y.Z B"（更新不要なら "noop X.Y.Z B"）。後方の番号なら終了コード 1。
#   Scripts/bump-marketing-version.sh rewrite <project.yml> <X.Y.Z> <B>
#     project.yml の 2 行だけを書き換える。
# 終了コード: 0 = PR を出した / 既に正しい（PR 不要）/ 1 = 止めた（理由は標準エラー）
set -uo pipefail

REPO="hiroky1983/game_collection"
APP_ID="${BUMP_APP_ID:-6781719499}"

die() { echo "bump-marketing-version: $*" >&2; exit 1; }

# X.Y.Z（数字 3 要素）の完全一致。check-marketing-version.sh と同じ物差し。
is_xyz() {
  local v="$1" dots
  dots="${v//[!.]/}"
  case "$v" in
    *[!0-9.]* | "" | *..* | .* | *.) return 1 ;;
  esac
  [ "${#dots}" -eq 2 ]
}

# 版を数値で比べる。a > b なら 1、等しければ 0、a < b なら -1 を出す。
ver_cmp() {
  local a1 a2 a3 b1 b2 b3 i x y
  IFS=. read -r a1 a2 a3 <<<"$1"
  IFS=. read -r b1 b2 b3 <<<"$2"
  for i in 1 2 3; do
    eval "x=\$a$i; y=\$b$i"
    if [ "$((10#$x))" -gt "$((10#$y))" ]; then echo 1; return; fi
    if [ "$((10#$x))" -lt "$((10#$y))" ]; then echo -1; return; fi
  done
  echo 0
}

# project.yml から値を読む（引用符・CR を落とし、重複は 1 つにまとめる）。
yml_value() {
  awk -v k="$1:" '$1 == k { print $2 }' "$2" | tr -d '\015\042\047' | sort -u
}

is_uint() { case "$1" in "" | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# 新しい番号を決め、床より後方にならないことを検査する（純粋関数）。
plan() {
  [ "$#" -eq 4 ] || die "plan の引数は 4 つです（版 / project.yml / 床の版 / 床のビルド番号）"
  local v="$1" yml="$2" floor_vers="$3" floor_builds="$4"
  local cur_v cur_b f b max_b=0 new_b n=0

  is_xyz "$v" || die "版 [$v] が X.Y.Z の形式ではありません"
  [ -f "$yml" ] || die "project.yml が見つかりません: $yml"
  cur_v="$(yml_value MARKETING_VERSION "$yml")"
  cur_b="$(yml_value CURRENT_PROJECT_VERSION "$yml")"
  [ "$(printf '%s' "$cur_v" | grep -c .)" -eq 1 ] || die "MARKETING_VERSION が無いか値が割れています: [$(printf '%s' "$cur_v" | tr '\n' ' ')]"
  [ "$(printf '%s' "$cur_b" | grep -c .)" -eq 1 ] || die "CURRENT_PROJECT_VERSION が無いか値が割れています: [$(printf '%s' "$cur_b" | tr '\n' ' ')]"
  is_xyz "$cur_v" || die "今の MARKETING_VERSION [$cur_v] が X.Y.Z の形式ではありません"
  is_uint "$cur_b" || die "今の CURRENT_PROJECT_VERSION [$cur_b] が数字ではありません"

  for f in $floor_vers; do
    is_xyz "$f" || die "比較対象の版 [$f] が X.Y.Z の形式ではありません"
    n=$((n + 1))
    if [ "$(ver_cmp "$v" "$f")" != 1 ]; then
      die "版 ${v} は既に公開・提出・凍結された版 ${f} 以下です（後方の番号は出しません）"
    fi
  done
  # 床が 1 つも無いのは取得の失敗。比べずに通すと保証にならないので止める。
  [ "$n" -gt 0 ] || die "比較対象の版（公開版・タグ）が 1 つもありません。取得に失敗していないか確認してください"
  if [ "$(ver_cmp "$v" "$cur_v")" = -1 ]; then
    die "project.yml は既に ${cur_v} で、${v} に下げることになります（後方の番号は出しません）"
  fi

  n=0
  for b in $floor_builds; do
    is_uint "$b" || die "比較対象のビルド番号 [$b] が数字ではありません"
    n=$((n + 1))
    [ "$((10#$b))" -gt "$max_b" ] && max_b="$((10#$b))"
  done
  [ "$n" -gt 0 ] || die "比較対象のビルド番号が 1 つもありません。取得に失敗していないか確認してください"

  new_b="$((10#$cur_b))"
  [ "$new_b" -le "$max_b" ] && new_b=$((max_b + 1))
  # 念のための最終検査（上の計算を将来いじっても、床以下の番号は出さない）
  [ "$new_b" -gt "$max_b" ] || die "ビルド番号 ${new_b} が既存の ${max_b} 以下です"

  if [ "$v" = "$cur_v" ] && [ "$new_b" = "$cur_b" ]; then
    echo "noop $v $new_b"
  else
    echo "$v $new_b"
  fi
}

# project.yml の 2 行だけを書き換える（インデントは保つ。値は二重引用符で書く）。
rewrite() {
  [ "$#" -eq 3 ] || die "rewrite の引数は 3 つです（project.yml / 版 / ビルド番号）"
  local yml="$1" v="$2" b="$3" tmp
  is_xyz "$v" || die "版 [$v] が X.Y.Z の形式ではありません"
  is_uint "$b" || die "ビルド番号 [$b] が数字ではありません"
  [ -f "$yml" ] || die "project.yml が見つかりません: $yml"
  tmp="$(mktemp)"
  awk -v v="$v" -v b="$b" '
    $1 == "MARKETING_VERSION:"       { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) "MARKETING_VERSION: \"" v "\""; next }
    $1 == "CURRENT_PROJECT_VERSION:" { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) "CURRENT_PROJECT_VERSION: \"" b "\""; next }
    { print }
  ' "$yml" >"$tmp" && cat "$tmp" >"$yml"
  rm -f "$tmp"
  [ "$(yml_value MARKETING_VERSION "$yml")" = "$v" ] || die "MARKETING_VERSION の書き換えに失敗しました"
  [ "$(yml_value CURRENT_PROJECT_VERSION "$yml")" = "$b" ] || die "CURRENT_PROJECT_VERSION の書き換えに失敗しました"
}

case "${1:-}" in
  plan) shift; plan "$@"; exit $? ;;
  rewrite) shift; rewrite "$@"; exit $? ;;
esac

# ---- 本体: 床を集めて判定し、PR を出す ----
WAIT=0
V=""
for a in "$@"; do
  case "$a" in
    --wait) WAIT=1 ;;
    -*) die "知らないオプションです: $a" ;;
    *) V="$a" ;;
  esac
done

TOP="$(git rev-parse --show-toplevel 2>/dev/null)" || die "git リポジトリの中で実行してください"
cd "$TOP" || exit 1
if [ -z "$V" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  case "$BRANCH" in
    release/v*) V="${BRANCH#release/v}" ;;
    *) die "現在のブランチ [$BRANCH] は release/vX.Y.Z ではありません。版を引数で渡してください" ;;
  esac
fi
is_xyz "$V" || die "版 [$V] が X.Y.Z の形式ではありません"
BASE="release/v$V"

git fetch -q --tags origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" || die "origin/$BASE を取得できません"
BASE_SHA="$(git rev-parse "origin/$BASE")" || die "origin/$BASE がありません"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git show "$BASE_SHA:project.yml" >"$TMP/project.yml" || die "origin/$BASE に project.yml がありません"

# 床 1: App Store の公開版（キャッシュバスタ必須。無いとエッジキャッシュの古い版を返す）
STORE_VER="${BUMP_STORE_VERSION:-}"
if [ -z "$STORE_VER" ]; then
  STORE_VER="$(curl -sf --max-time 15 "https://itunes.apple.com/lookup?id=${APP_ID}&country=jp&t=$(date +%s)" 2>/dev/null \
    | jq -r '.results[0].version // empty' 2>/dev/null)"
fi
is_xyz "${STORE_VER:-}" || die "App Store の公開版を取得できません（[${STORE_VER:-}]）。比べられないので止めます"
FLOOR_VERS="$STORE_VER"
FLOOR_BUILDS=""

# 床 2: 既存のタグ（公開 vX.Y.Z・提出 vX.Y.Z-submitted）の版と、その時点のビルド番号
for t in $(git tag -l 'v*'); do
  tv="${t#v}"
  tv="${tv%-submitted}"
  is_xyz "$tv" || continue
  FLOOR_VERS="$FLOOR_VERS $tv"
  tb="$(git show "$t:project.yml" 2>/dev/null | awk '$1 == "CURRENT_PROJECT_VERSION:" { print $2 }' | tr -d '\015\042\047' | sort -u)"
  is_uint "$tb" && FLOOR_BUILDS="$FLOOR_BUILDS $tb"
done

# 床 3: 凍結（lock_branch）済みの release ブランチ。自分以上の版のものだけ見ればよい
#（自分より小さい版は床にしても結果が変わらない）。凍結済みかを確かめられなければ止める。
for ref in $(git ls-remote --heads origin 'release/v*' | awk '{ print $2 }'); do
  bv="${ref#refs/heads/release/v}"
  is_xyz "$bv" || continue
  [ "$(ver_cmp "$bv" "$V")" = -1 ] && continue
  lock="$(gh api "repos/$REPO/branches/release%2Fv${bv}/protection" --jq '.lock_branch.enabled' 2>/dev/null)" \
    || die "release/v${bv} の保護設定を取得できません。凍結済みか確かめられないので止めます"
  [ "$lock" = "true" ] && FLOOR_VERS="$FLOOR_VERS $bv"
done

RESULT="$(plan "$V" "$TMP/project.yml" "$FLOOR_VERS" "$FLOOR_BUILDS")" || exit 1
case "$RESULT" in
  noop\ *)
    echo "bump-marketing-version: $BASE は既に MARKETING_VERSION ${V}・build ${RESULT##* } です（PR は不要）"
    exit 0
    ;;
esac
NEW_B="${RESULT##* }"
TITLE="chore(release): バージョンを ${V} (build ${NEW_B}) に更新"
HEAD_BRANCH="chore/release-version-v${V}-b${NEW_B}"

PR="$(gh pr list -R "$REPO" --state open --base "$BASE" --head "$HEAD_BRANCH" --json number --jq '.[0].number // empty' 2>/dev/null)"
if [ -n "$PR" ]; then
  echo "bump-marketing-version: 同じ版数更新の PR #$PR が既に開いています。それを使います"
else
  rewrite "$TMP/project.yml" "$V" "$NEW_B" || exit 1
  # 作業ツリーにもチェックアウトにも触らずにコミットを作る（呼び出し元がどのブランチ・worktree にいてもよい）
  MODE="$(git ls-tree "$BASE_SHA" project.yml | awk '{ print $1 }')"
  BLOB="$(git hash-object -w "$TMP/project.yml")" || die "blob を作れません"
  GIT_INDEX_FILE="$TMP/index" git read-tree "$BASE_SHA" || die "read-tree に失敗しました"
  GIT_INDEX_FILE="$TMP/index" git update-index --cacheinfo "${MODE:-100644},$BLOB,project.yml" || die "update-index に失敗しました"
  TREE="$(GIT_INDEX_FILE="$TMP/index" git write-tree)" || die "write-tree に失敗しました"
  COMMIT="$(git commit-tree "$TREE" -p "$BASE_SHA" -m "$TITLE" -m "Scripts/bump-marketing-version.sh が作成（公開版 ${STORE_VER}・既存タグ・凍結済みブランチより後方でないことを検査済み）")" \
    || die "commit-tree に失敗しました"
  git push -q origin "$COMMIT:refs/heads/$HEAD_BRANCH" || die "$HEAD_BRANCH を push できません（同名のブランチが残っていないか確認してください）"
  BODY="$(cat <<EOF
\`Scripts/bump-marketing-version.sh\` が作成した版数更新 PR です（\`project.yml\` の 2 行だけ）。

- MARKETING_VERSION: ${V}
- CURRENT_PROJECT_VERSION: ${NEW_B}
- 後方の番号でないことの検査: App Store の公開版 ${STORE_VER}・既存の \`vX.Y.Z\` / \`vX.Y.Z-submitted\` タグ・凍結済み release ブランチのどれよりも大きいことを確認済み

このマージが「${V} が出荷準備に入った」合図になります（docs/ai-devops.md「ブランチ戦略」の「次版」の定義）。
EOF
)"
  URL="$(gh pr create -R "$REPO" --base "$BASE" --head "$HEAD_BRANCH" --title "$TITLE" --body "$BODY" --label risk:logic)" \
    || die "PR を作れません（ブランチ $HEAD_BRANCH は push 済み）"
  PR="${URL##*/}"
  echo "bump-marketing-version: PR #$PR を作成しました: $URL"
fi

[ "$WAIT" -eq 1 ] || exit 0

# --wait: 必須チェックを待ってマージし、本当にマージされたことまで確かめる
for _ in $(seq 1 20); do
  gh pr checks "$PR" -R "$REPO" --required >/dev/null 2>&1
  rc=$?
  # 0 = 全部成功 / 8 = 実行中。それ以外（まだチェックが付いていない等）は少し待って取り直す
  [ "$rc" -eq 0 ] || [ "$rc" -eq 8 ] && break
  sleep 15
done
gh pr checks "$PR" -R "$REPO" --required --watch --fail-fast --interval 30 >/dev/null \
  || die "PR #$PR の必須チェックが通りませんでした。PR を確認してください"
gh pr merge "$PR" -R "$REPO" --merge || die "PR #$PR をマージできません（未解決のレビュースレッド等）。PR を確認してください"
STATE="$(gh pr view "$PR" -R "$REPO" --json state --jq '.state')"
[ "$STATE" = "MERGED" ] || die "PR #$PR の状態が MERGED ではありません（$STATE）"
echo "bump-marketing-version: PR #$PR をマージしました（$BASE は MARKETING_VERSION ${V}・build ${NEW_B}）"
