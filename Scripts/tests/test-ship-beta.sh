#!/bin/bash
# ship-beta.sh の分岐（#2449）の検証。
#   ①release/v* 以外では bump を呼ばない ②bump --wait 失敗なら fastlane を呼ばず非 0
#   ③project.yml に差分が無ければ merge しない／あれば --ff-only で取り込む ④ff できなければ非 0
#   ⑤fastlane の終了コードがそのまま返る
# 本物の git（一時リポジトリ + bare origin）を使い、bump-marketing-version.sh と bundle だけをスタブにする。
# HOME を一時ディレクトリへ差し替えるので、ログ（~/Library/Logs/asobiba-ship）は実環境を汚さない。
#
# 使い方: bash Scripts/tests/test-ship-beta.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../ship-beta.sh"
PASS=0
FAIL=0
N=0

ok()   { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng()   { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ship-beta-test.XXXXXX") || exit 1
trap 'rm -r "$ROOT"' EXIT
export HOME="$ROOT/home"
mkdir -p "$HOME" "$ROOT/bin"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# bundle のスタブ（fastlane の終了コードを FASTLANE_EXIT で差し替える）。呼び出しは $CALLS に記録する
cat >"$ROOT/bin/bundle" <<'STUB'
#!/bin/bash
echo "bundle $*" >>"$CALLS"
echo "fastlane-output"
exit "${FASTLANE_EXIT:-0}"
STUB
chmod +x "$ROOT/bin/bundle"
export PATH="$ROOT/bin:$PATH"

# ケースごとに新しい作業場を作る: $1=ブランチ名。$CASE/origin.git（bare）と $CASE/work（ship-beta.sh の複製入り）
setup() {
  N=$((N + 1)); CASE="$ROOT/case$N"; CALLS="$CASE/calls"; export CALLS
  mkdir -p "$CASE"; : >"$CALLS"
  git init -q --bare "$CASE/origin.git"
  git clone -q "$CASE/origin.git" "$CASE/work" 2>/dev/null
  (
    cd "$CASE/work" || exit 1
    git checkout -q -b "$1"
    mkdir -p Scripts
    cp "$TARGET" Scripts/ship-beta.sh
    cat >Scripts/bump-marketing-version.sh <<'STUB'
#!/bin/bash
echo "bump $*" >>"$CALLS"
exit "${BUMP_EXIT:-0}"
STUB
    echo "version: 1" >project.yml
    git add -A && git commit -q -m init && git push -q origin "$1" 2>/dev/null
  )
}
# origin 側だけ project.yml を進める（版数更新 PR のマージ相当）。$1=ブランチ名
advance_origin() {
  git clone -q "$CASE/origin.git" "$CASE/other" 2>/dev/null
  (cd "$CASE/other" && git checkout -q "$1" && echo "version: 2" >project.yml \
    && git commit -q -am bump && git push -q origin "$1" 2>/dev/null)
}
run() { (cd "$CASE/work" && bash Scripts/ship-beta.sh >"$CASE/out" 2>"$CASE/err"); echo $?; }
calls() { grep -c "$1" "$CALLS"; }

echo "# ①release/v* 以外では bump を呼ばない"
setup feature/x
rc=$(run)
check "終了コード 0" 0 "$rc"
check "bump 未呼び出し" 0 "$(calls '^bump')"
check "fastlane は呼ぶ" 1 "$(calls '^bundle exec fastlane beta')"

echo "# ②bump --wait が失敗したら fastlane を呼ばず非 0"
setup release/v9.9.9
rc=$(BUMP_EXIT=3 run)
check "終了コード 1" 1 "$rc"
check "bump --wait を呼ぶ" 1 "$(calls '^bump --wait')"
check "fastlane 未呼び出し" 0 "$(calls '^bundle')"

echo "# ③project.yml に差分が無ければ merge しない"
setup release/v9.9.9
head_before=$(git -C "$CASE/work" rev-parse HEAD)
rc=$(run)
check "終了コード 0" 0 "$rc"
check "HEAD 不変" "$head_before" "$(git -C "$CASE/work" rev-parse HEAD)"
check "fastlane を呼ぶ" 1 "$(calls '^bundle exec fastlane beta')"

echo "# ③project.yml に差分があれば --ff-only で取り込む"
setup release/v9.9.9
advance_origin release/v9.9.9
rc=$(run)
check "終了コード 0" 0 "$rc"
check "project.yml が取り込まれた" "version: 2" "$(cat "$CASE/work/project.yml")"
check "merge コミットを作らない（親 1 つ）" 1 "$(git -C "$CASE/work" log -1 --format=%p | wc -w | tr -d ' ')"
check "fastlane を呼ぶ" 1 "$(calls '^bundle exec fastlane beta')"

echo "# ④ff できなければ非 0（fastlane を呼ばない）"
setup release/v9.9.9
advance_origin release/v9.9.9
(cd "$CASE/work" && echo local >local.txt && git add -A && git commit -q -m local)
rc=$(run)
check "終了コード 1" 1 "$rc"
check "fastlane 未呼び出し" 0 "$(calls '^bundle')"
check "確認を促す案内を stderr に出す" 1 "$(grep -c '^ship-beta: origin/' "$CASE/err")"

echo "# ⑤fastlane の終了コードがそのまま返る（tee を通しても）"
setup feature/x
rc=$(FASTLANE_EXIT=7 run)
check "失敗コード 7 を返す" 7 "$rc"
setup feature/x
rc=$(FASTLANE_EXIT=0 run)
check "成功コード 0 を返す" 0 "$rc"
check "ログが HOME 配下に残る" 1 "$(find "$HOME/Library/Logs/asobiba-ship" -name 'beta-*.log' 2>/dev/null | head -1 | wc -l | tr -d ' ')"

echo
echo "結果: $PASS 件成功 / $FAIL 件失敗"
[ "$FAIL" -eq 0 ]
