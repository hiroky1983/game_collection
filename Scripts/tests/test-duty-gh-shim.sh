#!/bin/bash
# 当番の入力フィルタ（Scripts/duty-gh-shim/）の検証（Issue #164）。
#
# このフィルタは「PUBLIC リポジトリに第三者が書いた本文を、AI のコンテキストに入る前に機械的に
# 取り除く」ための唯一の層である。壊れても当番は普通に動いてしまい（= 素通しになるだけ）、
# 壊れたことに誰も気づけないので、判定そのものをテストする。
#
# 使い方: bash Scripts/tests/test-duty-gh-shim.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM_DIR="$SCRIPT_DIR/../duty-gh-shim"
SHIM="$SHIM_DIR/gh"
FILTER="$SHIM_DIR/filter.jq"
ACTORS="hiroky1983,coderabbitai,coderabbitai[bot]"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1 (期待: [$2] / 実際: [$3])"; fi; }
contains() { case "$2" in *"$3"*) ok "$1" ;; *) ng "$1 (出力に [$3] が含まれない: [$2])" ;; esac; }
lacks() { case "$2" in *"$3"*) ng "$1 ([$3] が出力に漏れている: [$2])" ;; *) ok "$1" ;; esac; }

filter() { jq -c --arg trusted "$ACTORS" -f "$FILTER"; }

# 実 gh の代わりに使うスタブ。DUTY_STUB_OUT の中身を stdout に出し、DUTY_STUB_RC で終了する。
# 受け取った引数は DUTY_STUB_ARGS に1行1引数で書き出し、ラッパーが gh をどう呼んだかを検証する。
STUB_HOME=$(mktemp -d "${TMPDIR:-/tmp}/duty-gh-shim-test-XXXXXX") || exit 1
trap 'rm -rf "$STUB_HOME"' EXIT
STUB="$STUB_HOME/gh-stub"
cat >"$STUB" <<'STUBEOF'
#!/bin/bash
: >"$DUTY_STUB_ARGS"
for a in "$@"; do printf '%s\n' "$a" >>"$DUTY_STUB_ARGS"; done
cat "$DUTY_STUB_OUT"
exit "${DUTY_STUB_RC:-0}"
STUBEOF
chmod +x "$STUB"
export DUTY_REAL_GH="$STUB"
export DUTY_STUB_OUT="$STUB_HOME/out"
export DUTY_STUB_ARGS="$STUB_HOME/args"
export DUTY_STUB_RC=0
export DUTY_TRUSTED_ACTORS="hiroky1983"

stub_out() { printf '%s' "$1" >"$DUTY_STUB_OUT"; }
stub_args() { cat "$DUTY_STUB_ARGS" 2>/dev/null | tr '\n' ' '; }

echo "== 1. 構文チェック =="
if bash -n "$SHIM" 2>/dev/null; then ok "gh ラッパーの構文"; else ng "gh ラッパーの構文"; fi
if jq -n --arg trusted "$ACTORS" -f "$FILTER" >/dev/null 2>&1; then ok "filter.jq の構文"; else ng "filter.jq の構文"; fi

echo "== 2. filter.jq: 投稿者による本文の除去 =="
OUT=$(echo '{"author":{"login":"hiroky1983"},"body":"OWNER-BODY","title":"OWNER-TITLE"}' | filter)
contains "会長の本文は残る" "$OUT" "OWNER-BODY"
contains "会長のタイトルは残る" "$OUT" "OWNER-TITLE"

OUT=$(echo '{"author":{"login":"coderabbitai[bot]"},"body":"CR-BODY"}' | filter)
contains "coderabbitai の本文は残る" "$OUT" "CR-BODY"

OUT=$(echo '{"author":{"login":"joshuaswarren"},"body":"THIRD-BODY","title":"THIRD-TITLE"}' | filter)
lacks "第三者の本文は除去される" "$OUT" "THIRD-BODY"
lacks "第三者のタイトルも除去される" "$OUT" "THIRD-TITLE"
contains "除去したことと投稿者は残る" "$OUT" "joshuaswarren"

OUT=$(echo '{"user":{"login":"stranger"},"body":"REST-BODY"}' | filter)
lacks "REST 形式（user.login）でも除去される" "$OUT" "REST-BODY"
OUT=$(echo '{"actor":{"login":"stranger"},"body":"TIMELINE-BODY"}' | filter)
lacks "タイムライン形式（actor.login）でも除去される" "$OUT" "TIMELINE-BODY"

OUT=$(echo '{"body":"NOAUTHOR-BODY"}' | filter)
lacks "投稿者を特定できない本文は除去される（fail closed）" "$OUT" "NOAUTHOR-BODY"

OUT=$(echo '{"name":"ai:approved","title":"v1.1.3"}' | filter)
contains "投稿者のいないメタ情報のタイトルは残す" "$OUT" "v1.1.3"

echo "== 3. filter.jq: 入れ子・配列 =="
NESTED='{"data":{"repository":{"issues":{"nodes":[
 {"author":{"login":"hiroky1983"},"title":"OK-TITLE","body":"OK-BODY",
  "comments":{"nodes":[{"author":{"login":"hiroky1983"},"body":"OWNER-COMMENT"},
                       {"author":{"login":"stranger"},"body":"EVIL-COMMENT"}]}}]}}}}'
OUT=$(printf '%s' "$NESTED" | filter)
contains "入れ子の会長コメントは残る" "$OUT" "OWNER-COMMENT"
lacks "入れ子の第三者コメントは除去される" "$OUT" "EVIL-COMMENT"
contains "同じノードの会長本文は巻き添えにしない" "$OUT" "OK-BODY"
contains "bodyText/bodyHTML も対象" \
  "$(echo '{"author":{"login":"x"},"bodyText":"BT","bodyHTML":"BH"}' | filter)" "第三者"
lacks "bodyText が漏れない" "$(echo '{"author":{"login":"x"},"bodyText":"BT-LEAK"}' | filter)" "BT-LEAK"

echo "== 4. ラッパー: 素通しする経路 =="
stub_out ""
"$SHIM" issue comment 164 --body "hello" >/dev/null 2>&1
contains "issue comment は素通し" "$(stub_args)" "issue comment 164 --body hello"
"$SHIM" pr merge 1 --merge >/dev/null 2>&1
contains "pr merge は素通し" "$(stub_args)" "pr merge 1 --merge"
"$SHIM" issue edit 164 --add-label "ai:in-progress" >/dev/null 2>&1
contains "issue edit は素通し" "$(stub_args)" "issue edit 164 --add-label ai:in-progress"

echo "== 5. ラッパー: gh api =="
stub_out '[{"user":{"login":"stranger"},"body":"API-EVIL"},{"user":{"login":"hiroky1983"},"body":"API-OK"}]'
OUT=$("$SHIM" api repos/x/y/issues/1/comments 2>&1)
lacks "gh api の第三者本文が除去される" "$OUT" "API-EVIL"
contains "gh api の会長本文は残る" "$OUT" "API-OK"

OUT=$("$SHIM" api repos/x/y/issues/1/comments --jq '.[].body' 2>&1)
lacks "--jq を付けても第三者本文は漏れない" "$OUT" "API-EVIL"
contains "--jq はフィルタ後に適用される" "$OUT" "API-OK"
lacks "--jq は実 gh へ渡さない" "$(stub_args)" "--jq"

stub_out '{"data":{"repository":{"pullRequests":{"nodes":[{"comments":{"nodes":[{"author":{"login":"attacker"},"body":"GQL-EVIL"}]}}]}}}}'
OUT=$("$SHIM" api graphql -f 'query={...}' 2>&1)
lacks "GraphQL 応答も除去される" "$OUT" "GQL-EVIL"
contains "GraphQL の -f はそのまま渡す" "$(stub_args)" "graphql -f query={...}"

echo "== 6. ラッパー: JSON にできない出力は断る（fail closed） =="
stub_out 'not a json at all'
OUT=$("$SHIM" api repos/x/y/readme 2>&1)
RC=$?
check "JSON でない応答は非ゼロ終了" "78" "$RC"
lacks "JSON でない応答は出力しない" "$OUT" "not a json"

stub_out '{"a":1}'
OUT=$("$SHIM" api repos/x/y --template '{{.a}}' 2>&1)
RC=$?
check "--template は断る" "78" "$RC"

echo "== 7. ラッパー: 実 gh の失敗をそのまま返す =="
stub_out 'gh: Not Found'
DUTY_STUB_RC=1
OUT=$("$SHIM" api repos/x/nope 2>&1)
RC=$?
check "実 gh の終了コードを引き継ぐ" "1" "$RC"
contains "実 gh の出力をそのまま返す" "$OUT" "Not Found"
DUTY_STUB_RC=0

echo "== 8. ラッパー: issue/pr の --json =="
stub_out '[{"number":1,"title":"T1","author":{"login":"hiroky1983"},"body":"LIST-OK"},{"number":2,"title":"EVIL-TITLE","author":{"login":"stranger"},"body":"LIST-EVIL"}]'
OUT=$("$SHIM" issue list --state open --json number,title,body 2>&1)
lacks "issue list --json の第三者本文が除去される" "$OUT" "LIST-EVIL"
lacks "issue list --json の第三者タイトルが除去される" "$OUT" "EVIL-TITLE"
contains "issue list --json の会長本文は残る" "$OUT" "LIST-OK"
contains "--json に author を補って実 gh を呼ぶ" "$(stub_args)" "number,title,body,author"
contains "list のフィルタ条件は保たれる" "$(stub_args)" "--state open"

OUT=$("$SHIM" issue list --json number,author,body --jq '.[] | "\(.number):\(.body)"' 2>&1)
lacks "--jq 併用でも第三者本文は漏れない" "$OUT" "LIST-EVIL"
contains "--jq 併用で会長本文は読める" "$OUT" "1:LIST-OK"

echo "== 9. ラッパー: issue/pr の既定表示（--json 無し） =="
stub_out '{"number":164,"title":"入力フィルタ","state":"OPEN","url":"https://example/164","author":{"login":"hiroky1983"},"labels":[{"name":"ai:approved"}],"milestone":{"title":"v1.1.3"},"body":"VIEW-BODY","comments":[{"createdAt":"2026-09-02T00:00:00Z","author":{"login":"hiroky1983"},"body":"OWNER-C"},{"createdAt":"2026-09-02T01:00:00Z","author":{"login":"stranger"},"body":"EVIL-C"}]}'
OUT=$("$SHIM" issue view 164 --comments 2>&1)
contains "本文が読める" "$OUT" "VIEW-BODY"
contains "会長コメントが読める" "$OUT" "OWNER-C"
lacks "第三者コメントは読めない" "$OUT" "EVIL-C"
contains "タイトル・ラベルが読める" "$OUT" "ai:approved"
contains "マイルストーンが読める" "$OUT" "v1.1.3"
lacks "--comments は実 gh へ渡さない（--json と併用できないため）" "$(stub_args)" "--comments"
contains "既定フィールドで JSON 取得している" "$(stub_args)" "--json"

stub_out '[{"number":9,"title":"PR-T","state":"OPEN","url":"u","author":{"login":"hiroky1983"},"labels":[],"baseRefName":"main","headRefName":"feat/x","isDraft":false,"updatedAt":"2026-09-03T00:00:00Z"}]'
OUT=$("$SHIM" pr list --state open 2>&1)
contains "pr list の既定表示に base/head が出る" "$OUT" "feat/x → main"

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
