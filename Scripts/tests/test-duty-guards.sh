#!/bin/bash
# 当番の安全装置（Scripts/lib/duty-guards.sh・Scripts/duty-hooks/docs-only-pre-commit）の検証（#3430）。
#   1) docs/ 以外をコミットさせないフック: docs のみ→成功 / docs 以外を含む→失敗 / GIT_CONFIG_* 経由でも効く /
#      リネームで App/ の削除を隠せない / ディスク上の git 設定を書き換えない
#   2) 入力フィルタの起動前検査 install_gh_shim: 正常→成功 / 素通し・本文の過剰除去・部品欠落→失敗（fail closed）
# どちらも壊れても当番は普通に動いてしまう（= 壊れたことに気づけない）ので、壊れた側が止まることを確かめる。
#
# 使い方: bash Scripts/tests/test-duty-guards.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../lib/duty-guards.sh"
HOOK="$SCRIPT_DIR/../duty-hooks/docs-only-pre-commit"
SHIM_SRC="$SCRIPT_DIR/../duty-gh-shim"
PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
contains() { case "$2" in *"$3"*) ok "$1" ;; *) ng "$1 (出力に [$3] が含まれない: [$2])" ;; esac; }
lacks() { case "$2" in *"$3"*) ng "$1 ([$3] が出力に含まれている: [$2])" ;; *) ok "$1" ;; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/duty-guards-test-XXXXXX")" || exit 1
trap 'rm -r "$TMP"' EXIT
LOGF="$TMP/log"
: >"$LOGF"
log() { echo "$*" >>"$LOGF"; }

# 実 gh の代わり（`gh --version` の素通し確認と、プローブのスタブの置き換え先に使う）
printf '#!/bin/bash\necho "gh version stub"\n' >"$TMP/real-gh"
chmod +x "$TMP/real-gh"
export DUTY_REAL_GH="$TMP/real-gh"
export DUTY_TRUSTED_ACTORS="hiroky1983"

# shellcheck source=/dev/null
. "$LIB"

# ---------------------------------------------------------------- 1. docs 専用フック
echo "== 1. docs/ 専用の pre-commit フック =="
MSG="テスト当番は docs/ 配下しか変更できません。以下がその対象外です:"

new_repo() { # new_repo <dir>: 初期コミット済みの一時リポジトリ（フックは有効化しない）
  mkdir -p "$1" && git -C "$1" init -q &&
    git -C "$1" config user.email t@example.com && git -C "$1" config user.name t &&
    git -C "$1" config commit.gpgsign false &&
    mkdir -p "$1/docs" "$1/App" && echo base >"$1/docs/base.md" && echo old >"$1/App/old.swift" &&
    git -C "$1" add -A && git -C "$1" commit -q -m init
}

R="$TMP/repo"
new_repo "$R" || { ng "一時リポジトリを作れない"; exit 1; }

# フックを有効化した子シェルで実行する（install が export する GIT_CONFIG_* を本体シェルへ漏らさない）
in_hooked_repo() { # in_hooked_repo <hooks_dir> <command...>: 標準エラーを含めた出力と終了コードを返す
  local hd="$1"; shift
  ( install_docs_only_hook "$hd" "$MSG" >/dev/null 2>&1 || exit 99
    cd "$R" && "$@" 2>&1 )
}

HD="$TMP/hooks"
echo "doc" >"$R/docs/a.md"; git -C "$R" add docs/a.md
OUT=$(in_hooked_repo "$HD" git commit -m "docs only"); RC=$?
[ "$RC" -eq 0 ] && ok "docs/ のみのコミットは成功する" || ng "docs のみが拒否された: rc=$RC out=[$OUT]"

echo "x" >"$R/App/x.swift"; git -C "$R" add App/x.swift
OUT=$(in_hooked_repo "$HD" git commit -m "code"); RC=$?
[ "$RC" -ne 0 ] && ok "App/ を含むコミットは失敗する" || ng "App/ のコミットが通ってしまった"
contains "拒否メッセージ（当番ごとの 1 行目）が出る" "$OUT" "$MSG"
contains "対象外のファイル名が出る" "$OUT" "App/x.swift"
[ "$(git -C "$R" log --oneline | wc -l | tr -d ' ')" = 2 ] && ok "拒否されたコミットは履歴に入らない" || ng "履歴が増えている"

echo "d2" >"$R/docs/b.md"; git -C "$R" add docs/b.md
OUT=$(in_hooked_repo "$HD" git commit -m "mixed"); RC=$?
[ "$RC" -ne 0 ] && ok "docs/ と App/ が混ざったコミットも失敗する" || ng "混在コミットが通ってしまった"
git -C "$R" reset -q

# リネーム検出が元のパスを隠さない（App/old.swift → docs/moved.swift）
git -C "$R" mv App/old.swift docs/moved.swift
OUT=$(in_hooked_repo "$HD" git commit -m "rename"); RC=$?
[ "$RC" -ne 0 ] && ok "App/ から docs/ への移動（= App/ の削除）は失敗する" || ng "リネームで App/ の削除が通ってしまった"
contains "移動元のパスが対象外として出る" "$OUT" "App/old.swift"
git -C "$R" reset -q --hard

# 有効化はこのプロセス（環境変数）だけ。ディスク上の設定・共有の hooks を書き換えない
[ -z "$(git -C "$R" config --local --get core.hooksPath || true)" ] && ok "リポジトリの git 設定に core.hooksPath を書かない" || ng "core.hooksPath が書かれた"
[ ! -e "$R/.git/hooks/pre-commit" ] && ok "共有の .git/hooks に pre-commit を置かない" || ng ".git/hooks/pre-commit がある"
echo "y" >"$R/App/y.swift"; git -C "$R" add App/y.swift
OUT=$(cd "$R" && git commit -m "unhooked" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "フックの有効化を子シェルに閉じ込めると、元のシェルのコミットは止まらない" || ng "フックが元のシェルに漏れている: $OUT"
git -C "$R" reset -q --hard HEAD~1

# 設定の異常
( install_docs_only_hook "$TMP/h2" "$MSG" "$TMP/none" ) >/dev/null 2>&1; RC=$?
[ "$RC" -ne 0 ] && ok "フック本体が見つからなければ失敗する（呼び出し側は起動しない）" || ng "本体欠落で成功扱い"
contains "欠落はログに残る" "$(cat "$LOGF")" "docs 専用フック"
OUT=$(cd "$R" && echo "z" >App/z.swift && git add App/z.swift && bash "$HOOK" 2>&1); RC=$?
[ "$RC" -ne 0 ] && contains "引数なしでも既定のメッセージで拒否する" "$OUT" "docs/ 配下しか変更できません" || ng "引数なしのフックが通った"
git -C "$R" reset -q --hard

# ---------------------------------------------------------------- 2. install_gh_shim
echo "== 2. install_gh_shim（入力フィルタの起動前検査） =="

shim_case() { # shim_case <src_dir> [trusted]: 結果を $RC に、ログを $LAST_LOG に入れる
  : >"$LOGF"
  install_gh_shim "$TMP/shim-out" "${2:-hiroky1983,coderabbitai}" "$1" >/dev/null 2>&1; RC=$?
  LAST_LOG=$(cat "$LOGF")
}

shim_case "$SHIM_SRC"
[ "$RC" -eq 0 ] && ok "正規のラッパーと filter.jq なら成功する" || ng "正規のラッパーで失敗: rc=$RC log=[$LAST_LOG]"
[ -x "$TMP/shim-out/gh" ] && [ -f "$TMP/shim-out/filter.jq" ] && ok "置き場所に gh と filter.jq が入る" || ng "置き場所の中身が不足"
[ "$(stat -f %Lp "$TMP/shim-out" 2>/dev/null || stat -c %a "$TMP/shim-out")" = 700 ] && ok "置き場所は 700" || ng "置き場所の権限が 700 でない"
[ ! -e "$TMP/shim-out/.probe-gh" ] && [ ! -e "$TMP/shim-out/.probe.json" ] && ok "プローブの一時ファイルが残らない" || ng "プローブの一時ファイルが残った"

# 失敗側 1: 部品が無い
mkdir -p "$TMP/src-missing" && cp "$SHIM_SRC/filter.jq" "$TMP/src-missing/"
shim_case "$TMP/src-missing"
[ "$RC" -ne 0 ] && ok "gh ラッパーが無ければ失敗する" || ng "ラッパー欠落で成功扱い"
contains "欠落の理由がログに残る" "$LAST_LOG" "見つからない"

# 失敗側 2: フィルタが壊れて（何も落とさず）素通しになる
mkdir -p "$TMP/src-leak" && cp "$SHIM_SRC/gh" "$TMP/src-leak/" && echo '.' >"$TMP/src-leak/filter.jq"
shim_case "$TMP/src-leak"
[ "$RC" -ne 0 ] && ok "filter.jq が第三者の本文を落とさなければ失敗する" || ng "素通しのフィルタで成功扱い"
contains "素通しの検知がログに残る" "$LAST_LOG" "素通しした"

# 失敗側 3: `-R` の先置きなど引数の並びによって本文が漏れるラッパー
mkdir -p "$TMP/src-flag" && cp "$SHIM_SRC/filter.jq" "$TMP/src-flag/"
cat >"$TMP/src-flag/gh" <<'EOS'
#!/bin/bash
# 先頭が issue のときだけフィルタに通す（-R / --repo の先置きを読み違えて素通しにする悪いラッパー）
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-}" = issue ]; then
  "$DUTY_REAL_GH" "$@" | jq -c --arg trusted "hiroky1983" -f "$D/filter.jq"
else
  exec "$DUTY_REAL_GH" "$@"
fi
EOS
chmod +x "$TMP/src-flag/gh"
shim_case "$TMP/src-flag"
[ "$RC" -ne 0 ] && ok "-R / --repo の先置きで本文が漏れるラッパーは失敗する" || ng "先置きの漏れで成功扱い"
contains "漏れた gh の呼び方がログに残る" "$LAST_LOG" "-R o/r issue view 1"

# 失敗側 4: 会長の本文まで落とす（フィルタの過剰除去）
mkdir -p "$TMP/src-over" && cp "$SHIM_SRC/gh" "$TMP/src-over/" && echo 'del(.body)' >"$TMP/src-over/filter.jq"
shim_case "$TMP/src-over"
[ "$RC" -ne 0 ] && ok "会長の本文まで落とすフィルタは失敗する" || ng "過剰除去で成功扱い"
contains "過剰除去がログに残る" "$LAST_LOG" "会長の本文まで除去"

# 失敗側 5: 信頼アカウントの指定が実際のラッパーと食い違う（先頭が信頼リストに無い）
shim_case "$SHIM_SRC" "someone-else"
[ "$RC" -ne 0 ] && ok "信頼アカウントの先頭がラッパーの信頼リストに無ければ失敗する" || ng "食い違いで成功扱い"

# 失敗側 6: 素通しの経路（gh --version）が死んでいる
mkdir -p "$TMP/src-dead" && cp "$SHIM_SRC/filter.jq" "$TMP/src-dead/"
printf '#!/bin/bash\nexit 1\n' >"$TMP/src-dead/gh"; chmod +x "$TMP/src-dead/gh"
shim_case "$TMP/src-dead"
[ "$RC" -ne 0 ] && ok "素通しの経路が死んでいれば失敗する" || ng "素通し死亡で成功扱い"
contains "素通し確認の失敗がログに残る" "$LAST_LOG" "素通しの確認に失敗"

# 同じ置き場所を作り直せる（前回の残骸があっても成功する）
shim_case "$SHIM_SRC"
[ "$RC" -eq 0 ] && ok "失敗のあとでも、正規のラッパーで作り直せる" || ng "再作成に失敗: $LAST_LOG"

# 3 本の当番スクリプトが共通関数を使っている（複製が戻ると 1 本だけ直す事故が再発する）
echo "== 3. 当番スクリプトが共通関数を使う =="
for f in ai-duty.sh ai-audit-duty.sh ai-management-duty.sh; do
  S="$SCRIPT_DIR/../$f"
  if grep -q '^install_gh_shim() {' "$S"; then ng "$f に install_gh_shim の複製が残っている"; else ok "$f は install_gh_shim を複製していない"; fi
  grep -q 'lib/duty-guards.sh' "$S" && ok "$f は duty-guards.sh を読み込む" || ng "$f が duty-guards.sh を読み込まない"
done
for f in ai-audit-duty.sh ai-management-duty.sh; do
  S="$SCRIPT_DIR/../$f"
  grep -q 'install_docs_only_hook' "$S" && ! grep -q "<<'HOOK'" "$S" && ok "$f はフックを共通関数で用意する" || ng "$f にフックの複製が残っている"
done

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
