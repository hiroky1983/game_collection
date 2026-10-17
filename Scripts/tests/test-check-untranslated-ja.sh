#!/bin/bash
# check-untranslated-ja.py（訳し漏れの機械チェック・#2169）の検証。
#
# 見逃し（表を通していない日本語を通す）と誤検知（コメント・tr のキー・開発者向けの文を数える）の
# 両方を、小さなツリーを組み立てて直接確かめる。
#
# 使い方: bash Scripts/tests/test-check-untranslated-ja.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-untranslated-ja.py"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ツリーを作り直す。モジュール Foo の表に「完了」だけを載せる。
reset_tree() {
  rm -rf "$TMP/root"
  mkdir -p "$TMP/root/App/Localization" "$TMP/root/Scripts" \
    "$TMP/root/Packages/GameKit/Sources/Foo/Resources/Localization"
  cat > "$TMP/root/App/Localization/Localizable.xcstrings" <<'EOF'
{ "sourceLanguage" : "ja", "strings" : {}, "version" : "1.0" }
EOF
  cat > "$TMP/root/Packages/GameKit/Sources/Foo/Resources/Localization/Localizable.xcstrings" <<'EOF'
{ "sourceLanguage" : "ja", "strings" : {
  "完了" : { "extractionState" : "manual", "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Done" } } } },
  "%lld手" : { "extractionState" : "manual", "localizations" : { "en" : { "variations" : { "plural" : {
    "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld move" } },
    "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld moves" } } } } } } }
}, "version" : "1.0" }
EOF
  : > "$TMP/root/Scripts/i18n-check-exclusions.txt"
}

# 引数: 説明 / 期待する終了コード / 期待する「訳し漏れ」の件数 / Foo/View.swift の中身
check() {
  local desc="$1" want="$2" want_count="$3" code="$4" out got count
  printf '%s\n' "$code" > "$TMP/root/Packages/GameKit/Sources/Foo/View.swift"
  out="$(python3 "$TARGET" --root "$TMP/root" 2>&1)"
  got=$?
  count="$(printf '%s\n' "$out" | sed -n 's/^訳し漏れ（表を通していない日本語）: \([0-9]*\) 件$/\1/p')"
  if [ "$got" = "$want" ] && [ "$count" = "$want_count" ]; then
    ok "$desc"
  else
    ng "${desc}（終了コード ${got}・件数 ${count}。期待は ${want}・${want_count}）"
    printf '%s\n' "$out" | sed 's/^/        /'
  fi
}

echo "訳し漏れを拾う"
reset_tree
check "Text の生の日本語" 1 1 'Text("完了")'
check "補間の中の日本語も拾う" 1 1 'Text("\(done ? "済み" : "")")'
check "複数行の文字列" 1 1 'let s = """
はじめよう
"""'
check "表に無い tr のキーは表の不備" 1 0 'Text(tr("未登録"))'
check "tr のキーに補間を使うのは表の不備" 1 0 'Text(tr("完了\(n)"))'

echo "数えないもの"
reset_tree
check "tr のキー" 0 0 'Text(tr("完了"))'
check "書式付きの tr のキー" 0 0 'Text(tr("%lld手", n))'
check "モジュール名つきの tr" 0 0 'Text(Foo.tr("完了"))'
check "コメント" 0 0 '// 完了
/* 完了 */
let a = 1 /* 入れ子 /* 完了 */ まだコメント */'
check "開発者向けの文（precondition・fatalError・print）" 0 0 'precondition(ok, "壊れた")
fatalError("来ない")
print("ログ")'
check "#Preview の中" 0 0 '#Preview {
    Text("見本")
}'
check "行末の i18n-keep" 0 0 'let w = "りんご"  // i18n-keep: しりとりの単語'
check "直前の行の i18n-keep" 0 0 '// i18n-keep: しりとりの単語
let w = "りんご"'
check "英数字だけの文字列" 0 0 'Text("2048")'

echo "除外の一覧"
reset_tree
echo 'keep Packages/GameKit/Sources/Foo/View.swift DEBUG専用' > "$TMP/root/Scripts/i18n-check-exclusions.txt"
check "keep のファイルは数えない" 0 0 'Text("見本")'
echo 'in-progress Packages/GameKit/Sources/Foo/* #9999 担当中' > "$TMP/root/Scripts/i18n-check-exclusions.txt"
check "in-progress は既定では数えない" 0 0 'Text("見本")'
out="$(python3 "$TARGET" --root "$TMP/root" --include-in-progress 2>&1)"
if [ $? = 1 ] && printf '%s' "$out" | grep -q '訳し漏れ（表を通していない日本語）: 1 件'; then
  ok "--include-in-progress では数える"
else
  ng "--include-in-progress では数える"
fi
if printf '%s' "$(python3 "$TARGET" --root "$TMP/root")" | grep -q '担当中として除外: 1 件（#9999 1 件）'; then
  ok "担当中の件数を issue ごとに出す"
else
  ng "担当中の件数を issue ごとに出す"
fi

echo "表の検査"
reset_tree
python3 - "$TMP/root/Packages/GameKit/Sources/Foo/Resources/Localization/Localizable.xcstrings" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["strings"]["%@を開く"] = {"localizations": {"en": {"stringUnit": {"value": "Open"}}}}
d["strings"]["終わり"] = {"localizations": {"en": {"stringUnit": {"value": "おわり"}}}}
d["strings"]["訳なし"] = {"localizations": {}}
json.dump(d, open(p, "w"), ensure_ascii=False)
EOF
out="$(python3 "$TARGET" --root "$TMP/root" 2>&1)"
for want in "書式指定が食い違う" "英語に日本語が残っている" "英語の訳が無い"; do
  if printf '%s' "$out" | grep -q "$want"; then ok "表の不備: $want"; else ng "表の不備: $want"; fi
done

echo
echo "結果: ok $PASS / NG $FAIL"
[ "$FAIL" -eq 0 ]
