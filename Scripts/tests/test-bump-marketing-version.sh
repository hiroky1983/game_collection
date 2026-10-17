#!/bin/bash
# bump-marketing-version.sh の検証（2026-10-06・版数の上げ忘れの仕組み化と「後方の番号を出さない」保証）。
#
# 1. plan（純粋関数）: 床（公開版・タグ・凍結済みブランチ・既存のビルド番号）より後方の番号を決して出さないこと
# 2. rewrite: project.yml の 2 行だけを書き換えること
# 3. 本体: 偽の origin（bare リポジトリ）と偽の gh で、作業ツリーに触らず 2 行だけのコミットを push し、
#    固定タイトル（「出荷準備に入った」合図）の PR を出すこと。後方の番号なら何も push しないこと
# 4. 仕込み忘れの検出: ship-beta.sh・当番プロンプト・規程がこのスクリプトを呼んで（参照して）いること
#
# 使い方: bash Scripts/tests/test-bump-marketing-version.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../bump-marketing-version.sh"
ROOT="$SCRIPT_DIR/../.."
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 引数: 版 / ビルド番号 → project.yml のパス（周りに無関係な行も置く）
yml() {
  local path="$TMP/project-$1-$2.yml"
  {
    echo "settings:"
    echo "  base:"
    echo '        CFBundleShortVersionString: "$(MARKETING_VERSION)"'
    echo "        MARKETING_VERSION: \"$1\""
    echo "        CURRENT_PROJECT_VERSION: \"$2\""
    echo '        SWIFT_VERSION: "6.0"'
  } >"$path"
  printf '%s' "$path"
}

# 引数: 説明 / 期待する出力（"FAIL" は終了コード 1 を期待）/ plan の引数…
check_plan() {
  local desc="$1" want="$2" got rc
  shift 2
  got="$(bash "$TARGET" plan "$@" 2>/dev/null)"
  rc=$?
  if [ "$want" = "FAIL" ]; then
    if [ "$rc" -eq 1 ] && [ -z "$got" ]; then ok "$desc"; else ng "$desc (期待: 止まる / 実際: 終了コード ${rc}・出力 [$got])"; fi
  else
    if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (期待: [$want] / 実際: 終了コード ${rc}・出力 [$got])"; fi
  fi
}

echo "== 1. plan: 上げるべき番号を決める =="
check_plan "前の版のまま（v1.1.10 の実例）→ 1.1.10 / build 14" "1.1.10 14" 1.1.10 "$(yml 1.1.9 13)" "1.1.9 1.1.8" "13 12"
check_plan "ビルド番号が既に床より大きければ保つ"            "1.1.10 20" 1.1.10 "$(yml 1.1.9 20)" "1.1.9" "13"
check_plan "既に正しければ noop"                              "noop 1.1.10 14" 1.1.10 "$(yml 1.1.10 14)" "1.1.9" "13"
check_plan "版は正しいがビルド番号が床以下なら上げる"        "1.1.10 14" 1.1.10 "$(yml 1.1.10 13)" "1.1.9" "13"
check_plan "数値で比べる（1.1.10 > 1.1.9・文字列比較の罠）"  "1.1.10 14" 1.1.10 "$(yml 1.1.9 13)" "1.1.9 1.1.2" "13"
check_plan "数値で比べる（1.2.0 > 1.1.99）"                  "1.2.0 14"  1.2.0  "$(yml 1.1.99 13)" "1.1.99" "13"
check_plan "ビルド番号も数値で比べる（9 と 10）"             "1.1.10 11" 1.1.10 "$(yml 1.1.9 9)" "1.1.9" "9 10"

echo "== 2. plan: 後方の番号は出さない（止める）=="
check_plan "公開版と同じ版は止める"                          FAIL 1.1.9  "$(yml 1.1.9 13)" "1.1.9" "13"
check_plan "公開版より小さい版は止める"                      FAIL 1.1.8  "$(yml 1.1.8 13)" "1.1.9" "13"
check_plan "提出済みタグ・凍結済みの版と同じなら止める"      FAIL 1.1.10 "$(yml 1.1.9 13)" "1.1.9 1.1.10" "13"
check_plan "文字列では大きく見える 1.1.9 < 1.1.10 を止める"  FAIL 1.1.9  "$(yml 1.1.8 12)" "1.1.8 1.1.10" "12"
check_plan "project.yml の値から下げることになるなら止める"  FAIL 1.1.10 "$(yml 1.1.11 15)" "1.1.9" "13"
check_plan "床の版が 1 つも無い（取得失敗）なら止める"       FAIL 1.1.10 "$(yml 1.1.9 13)" "" "13"
check_plan "床のビルド番号が 1 つも無いなら止める"           FAIL 1.1.10 "$(yml 1.1.9 13)" "1.1.9" ""
check_plan "床の版が壊れていたら止める"                      FAIL 1.1.10 "$(yml 1.1.9 13)" "1.1.9 next" "13"
check_plan "床のビルド番号が数字でなければ止める"            FAIL 1.1.10 "$(yml 1.1.9 13)" "1.1.9" "13 abc"
check_plan "版が X.Y.Z でなければ止める"                     FAIL 1.1    "$(yml 1.1.9 13)" "1.1.9" "13"
check_plan "project.yml が無ければ止める"                    FAIL 1.1.10 "$TMP/none.yml" "1.1.9" "13"
printf 'settings:\n        MARKETING_VERSION: "1.1.9"\n        MARKETING_VERSION: "1.1.8"\n        CURRENT_PROJECT_VERSION: "13"\n' >"$TMP/split.yml"
check_plan "MARKETING_VERSION が割れていたら止める"          FAIL 1.1.10 "$TMP/split.yml" "1.1.9" "13"

echo "== 3. rewrite: 2 行だけを書き換える =="
P="$(yml 1.1.9 13)"
cp "$P" "$TMP/before.yml"
bash "$TARGET" rewrite "$P" 1.1.10 14
CHANGED="$(diff "$TMP/before.yml" "$P" | grep -c '^>')"
if [ "$CHANGED" = 2 ]; then ok "変わった行はちょうど 2 行"; else ng "変わった行が 2 行ではない（${CHANGED}）"; fi
if grep -qx '        MARKETING_VERSION: "1.1.10"' "$P" && grep -qx '        CURRENT_PROJECT_VERSION: "14"' "$P"; then
  ok "インデントと引用符を保って書き換える"
else
  ng "書き換え後の行の形が違う: $(grep -E 'MARKETING_VERSION:|CURRENT_PROJECT_VERSION:' "$P" | tr '\n' '|')"
fi
if bash "$SCRIPT_DIR/../check-marketing-version.sh" release/v1.1.10 "$P" >/dev/null 2>&1; then
  ok "書き換え後は check-marketing-version.sh を通る"
else
  ng "書き換え後に check-marketing-version.sh を通らない"
fi

echo "== 4. 本体: 偽の origin と gh で PR を出す =="
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
ORIGIN="$TMP/origin.git"
WORK="$TMP/work"
git init -q --bare "$ORIGIN"
git init -q "$WORK"
git -C "$WORK" remote add origin "$ORIGIN"
cp "$(yml 1.1.8 12)" "$WORK/project.yml"
echo "a" >"$WORK/other.txt"
git -C "$WORK" add -A && git -C "$WORK" commit -qm v118
git -C "$WORK" tag v1.1.8-submitted && git -C "$WORK" tag v1.1.8
cp "$(yml 1.1.9 13)" "$WORK/project.yml"
git -C "$WORK" commit -qam v119
git -C "$WORK" tag v1.1.9-submitted && git -C "$WORK" tag v1.1.9
git -C "$WORK" push -q origin HEAD:refs/heads/release/v1.1.9 --tags
echo "b" >"$WORK/other.txt"
git -C "$WORK" commit -qam "work on 1.1.10"
git -C "$WORK" push -q origin HEAD:refs/heads/release/v1.1.10
git -C "$WORK" checkout -q -b release/v1.1.10
echo "dirty" >"$WORK/other.txt"   # 作業ツリーの未コミットの変更に触らないこと

# 偽の gh: 呼び出しを記録し、保護設定は lock_branch=$FAKE_LOCK を返す
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'EOF'
#!/bin/bash
printf "%s\n" "$(echo "$*" | tr "\n" " ")" >>"$FAKE_GH_LOG"
case "$1 $2" in
  "api "*) [[ "$2" == *protection ]] && echo "${FAKE_LOCK:-false}"; exit 0 ;;
  "pr list") exit 0 ;;
  "pr create") echo "https://github.com/hiroky1983/game_collection/pull/9999"; exit 0 ;;
  "pr checks")
    # FAKE_NOCHECKS_FILE に数字があれば、その回数だけ「まだチェックが付いていない」を返す
    n="$(cat "${FAKE_NOCHECKS_FILE:-/dev/null}" 2>/dev/null)"
    if [ -n "$n" ] && [ "$n" -gt 0 ]; then echo $((n - 1)) >"$FAKE_NOCHECKS_FILE"; echo "no checks reported on the 'x' branch"; exit 1; fi
    [ "${FAKE_CHECKS:-pass}" = pass ] && exit 0
    echo "test fail"; exit 1 ;;
  "pr merge") exit "${FAKE_MERGE_RC:-0}" ;;
  "pr view") echo "${FAKE_STATE:-MERGED}"; exit 0 ;;
esac
exit 0
EOF
chmod +x "$TMP/bin/gh"
export FAKE_GH_LOG="$TMP/gh.log"

run_main() { (cd "$WORK" && PATH="$TMP/bin:$PATH" BUMP_STORE_VERSION="$1" bash "$TARGET" >"$TMP/out.txt" 2>&1); }

: >"$FAKE_GH_LOG"
if run_main 1.1.9; then ok "前の版のままなら PR を出して終了コード 0"; else ng "本体が失敗した: $(cat "$TMP/out.txt")"; fi
NEWREF="$(git --git-dir="$ORIGIN" rev-parse -q --verify refs/heads/chore/release-version-v1.1.10-b14)"
if [ -n "$NEWREF" ]; then ok "chore/release-version-v1.1.10-b14 を push した"; else ng "版数更新ブランチが push されていない"; fi
if [ -n "$NEWREF" ]; then
  FILES="$(git --git-dir="$ORIGIN" diff --name-only refs/heads/release/v1.1.10 "$NEWREF")"
  if [ "$FILES" = "project.yml" ]; then ok "コミットの差分は project.yml だけ"; else ng "差分に project.yml 以外がある: $FILES"; fi
  PARENT="$(git --git-dir="$ORIGIN" rev-parse "$NEWREF^")"
  if [ "$PARENT" = "$(git --git-dir="$ORIGIN" rev-parse refs/heads/release/v1.1.10)" ]; then ok "親は release/v1.1.10 の HEAD"; else ng "親が release/v1.1.10 の HEAD ではない"; fi
  git --git-dir="$ORIGIN" show "$NEWREF:project.yml" >"$TMP/pushed.yml"
  if bash "$SCRIPT_DIR/../check-marketing-version.sh" release/v1.1.10 "$TMP/pushed.yml" >/dev/null 2>&1 \
     && grep -q 'CURRENT_PROJECT_VERSION: "14"' "$TMP/pushed.yml"; then
    ok "push した project.yml は 1.1.10 / build 14"
  else
    ng "push した project.yml の値が違う"
  fi
fi
if grep -q 'pr create .*--base release/v1.1.10 .*--title chore(release): バージョンを 1.1.10 (build 14) に更新 .*--label risk:logic' "$FAKE_GH_LOG"; then
  ok "固定タイトル・base・risk:logic で PR を作る"
else
  ng "PR 作成の引数が違う: $(grep 'pr create' "$FAKE_GH_LOG" | cut -c1-200)"
fi
if [ "$(cat "$WORK/other.txt")" = "dirty" ] && [ "$(git -C "$WORK" rev-parse --abbrev-ref HEAD)" = "release/v1.1.10" ]; then
  ok "呼び出し元の作業ツリー・ブランチに触らない"
else
  ng "呼び出し元の作業ツリーかブランチが変わった"
fi

# 公開版がすでに 1.1.10（= 後方になる）なら何も push しない
git --git-dir="$ORIGIN" update-ref -d refs/heads/chore/release-version-v1.1.10-b14
: >"$FAKE_GH_LOG"
if run_main 1.1.10; then ng "公開版と同じ版なのに止まらない"; else ok "公開版が 1.1.10 なら止める"; fi
if [ -z "$(git --git-dir="$ORIGIN" for-each-ref 'refs/heads/chore/*')" ] && ! grep -q 'pr create' "$FAKE_GH_LOG"; then
  ok "止めたときは何も push せず PR も作らない"
else
  ng "止めたのに push か PR 作成をしている"
fi

# 自分の版の release ブランチが凍結済みなら止める
: >"$FAKE_GH_LOG"
if (cd "$WORK" && PATH="$TMP/bin:$PATH" FAKE_LOCK=true BUMP_STORE_VERSION=1.1.9 bash "$TARGET" >/dev/null 2>&1); then
  ng "凍結済みの版なのに止まらない"
else
  ok "凍結（lock_branch）済みの版なら止める"
fi

# 公開版を取得できなければ止める（BUMP_STORE_VERSION に壊れた値）
if run_main "unknown"; then ng "公開版が取れないのに止まらない"; else ok "公開版を取得できなければ止める"; fi

clear_chore() {
  local r
  for r in $(git --git-dir="$ORIGIN" for-each-ref --format='%(refname)' 'refs/heads/chore/'); do
    git --git-dir="$ORIGIN" update-ref -d "$r"
  done
  : >"$FAKE_GH_LOG"
}
# 引数: 環境変数の代入… → --wait 付きで本体を実行（公開版は 1.1.9）
run_wait() { (cd "$WORK" && env PATH="$TMP/bin:$PATH" BUMP_STORE_VERSION=1.1.9 BUMP_POLL_SECONDS=0 "$@" bash "$TARGET" --wait >"$TMP/out.txt" 2>&1); }

echo "== 4-b. --dry-run は何も作らない =="
clear_chore
if (cd "$WORK" && PATH="$TMP/bin:$PATH" BUMP_STORE_VERSION=1.1.9 bash "$TARGET" --dry-run >"$TMP/out.txt" 2>&1) \
   && grep -q 'build 14' "$TMP/out.txt" \
   && [ -z "$(git --git-dir="$ORIGIN" for-each-ref 'refs/heads/chore/')" ] && ! grep -q 'pr create' "$FAKE_GH_LOG"; then
  ok "--dry-run は予定（build 14）を出すだけで push も PR も作らない"
else
  ng "--dry-run の挙動が違う: $(cat "$TMP/out.txt")"
fi

echo "== 4-c. --wait: チェック待ち → マージ → MERGED の確認 =="
clear_chore
echo 2 >"$TMP/nochecks"
if run_wait FAKE_NOCHECKS_FILE="$TMP/nochecks" && grep -q '^pr merge 9999' "$FAKE_GH_LOG" && grep -q '^pr view 9999' "$FAKE_GH_LOG"; then
  ok "チェックが付くのを待ち、通ったらマージして state を確かめる"
else
  ng "--wait の成功経路が違う: $(cat "$TMP/out.txt")"
fi
clear_chore
if run_wait FAKE_CHECKS=fail; then ng "必須チェックが落ちているのに成功した"; else
  if grep -q '^pr merge' "$FAKE_GH_LOG"; then ng "必須チェックが落ちているのにマージを試みた"; else ok "必須チェックが落ちたらマージせず止める"; fi
fi
clear_chore
if run_wait FAKE_MERGE_RC=1; then ng "マージに失敗したのに成功した"; else ok "マージに失敗したら止める"; fi
clear_chore
if run_wait FAKE_STATE=OPEN; then ng "state が MERGED でないのに成功した"; else ok "マージ後の state が MERGED でなければ止める（握りつぶさない）"; fi

echo "== 4-d. 過去タグのビルド番号が読めなければ止める（黙って床から外さない）=="
clear_chore
printf 'settings:\n        MARKETING_VERSION: "1.1.7"\n        CURRENT_PROJECT_VERSION: "13"\n        CURRENT_PROJECT_VERSION: "50"\n' >"$TMP/broken.yml"
BLOB="$(git -C "$WORK" hash-object -w "$TMP/broken.yml")"
TREE="$(printf '100644 blob %s\tproject.yml\n' "$BLOB" | git -C "$WORK" mktree)"
BROKEN="$(git -C "$WORK" commit-tree "$TREE" -m broken)"
git -C "$WORK" tag v1.1.7-submitted "$BROKEN"
if run_main 1.1.9; then ng "値が割れたタグがあるのに止まらない（build 50 以下を出しうる）"; else ok "値が割れたタグがあれば止める"; fi
if [ -z "$(git --git-dir="$ORIGIN" for-each-ref 'refs/heads/chore/')" ]; then ok "そのときも何も push しない"; else ng "止めたのに push している"; fi
git -C "$WORK" tag -d v1.1.7-submitted >/dev/null

echo "== 5. 仕込み忘れの検出 =="
grep -q 'Scripts/bump-marketing-version.sh --wait' "$ROOT/Scripts/ship-beta.sh" \
  && ok "ship-beta.sh が --wait 付きで呼んでいる" || ng "ship-beta.sh が bump-marketing-version.sh を呼んでいない"
grep -q 'bump-marketing-version.sh' "$ROOT/Scripts/ai-duty-prompt.md" \
  && ok "当番プロンプト（仕事13）が参照している" || ng "当番プロンプトが bump-marketing-version.sh を参照していない"
grep -q 'bump-marketing-version.sh' "$ROOT/docs/ai-devops.md" \
  && ok "docs/ai-devops.md が参照している" || ng "docs/ai-devops.md が bump-marketing-version.sh を参照していない"
grep -q 'bump-marketing-version.sh' "$ROOT/Scripts/check-marketing-version.sh" \
  && ok "check-marketing-version.sh の失敗メッセージが案内している" || ng "check-marketing-version.sh が案内していない"
# 合図のタイトルは規程の「次版」の定義と一字一句そろっていること
grep -q 'chore(release): バージョンを' "$TARGET" && grep -q 'chore(release): バージョンを' "$ROOT/docs/ai-devops.md" \
  && ok "PR タイトルが規程の合図（chore(release): バージョンを…）とそろっている" || ng "PR タイトルと規程の合図がずれている"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
