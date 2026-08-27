#!/bin/bash
# check-aso-game-count.sh の検証（#281）。
#
# このチェックは配信（fastlane beta）を止める側なので、見逃し（食い違いを通す）も
# 誤検知（正常なのに落ちる）もそのまま事故になる。特に誤検知は実績があり
# （v1.1.0 の説明文「8つの定番ゲームがこれ1本。」の `1` を収録本数と読み違える）、
# そのケースを固定するのが本テストの主目的。
#
# 使い方: bash Scripts/tests/test-check-aso-game-count.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../check-aso-game-count.sh"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 指定した数だけ XxxModule() を並べた AppGameServices.swift 相当を作る
swiftsrc() {
  local path="$TMP/src-$1.swift" i
  {
    echo "enum AppGameServices {"
    echo "    static let registry = GameRegistry(["
    for ((i = 1; i <= $1; i++)); do echo "        Game${i}Module(),"; done
    echo "    ])"
    echo "}"
  } > "$path"
  printf '%s' "$path"
}

# 入稿パック相当を作る。引数は ```text ブロックに入れる行。
pack() {
  local path="$TMP/pack-$RANDOM$RANDOM.md" line
  {
    echo "# 入稿パック（テスト用）"
    echo ""
    # 散文には過去の経緯が意図的に残る。**入稿文言と同じ言い回し**で残るので、
    # fence を見ずに全文を走査すると必ず誤検知する（この行がその見張り）。
    echo "初版のサブタイトルは「定番8種」で、説明文も 8本を収録 と主張していた（#178 で是正）。"
    echo ""
    echo '```text'
    for line in "$@"; do echo "$line"; done
    echo '```'
    echo ""
    echo "この行も散文。9999本すべてが遊べる、と書いてあっても検証には効かない。"
  } > "$path"
  printf '%s' "$path"
}

# 引数: 説明 / 期待する終了コード / パック / ソース
check() {
  local desc="$1" want="$2" p="$3" s="$4" got
  bash "$TARGET" "$p" "$s" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (期待: 終了コード $want / 実際: $got)"; fi
}

echo "== 1. 一致・不一致の判定 =="
check "本数が一致していれば通る"            0 "$(pack 'オフラインで遊べる定番12種｜勝手に出る全画面広告なし')" "$(swiftsrc 12)"
check "パックが古い（10本のまま）と落ちる"  1 "$(pack 'オフラインで遊べる定番10種｜勝手に出る全画面広告なし')" "$(swiftsrc 12)"
check "パックが先走っていても落ちる"        1 "$(pack 'オフラインで遊べる定番13種｜…')"                        "$(swiftsrc 12)"
check "複数箇所が揃っていれば通る"          0 "$(pack '定番12種' '将棋ほかの12本を収録しています。' '12本すべてが最後まで遊べます。')" "$(swiftsrc 12)"
check "1箇所だけ直し漏れても落ちる"         1 "$(pack '定番12種' '将棋ほかの12本を収録しています。' '10本すべてが最後まで遊べます。')" "$(swiftsrc 12)"

echo "== 2. 収録本数ではない言い回しを誤検知しない（v1.1.0 パックの実例）=="
check "「これ1本」は収録本数と読まない"      0 "$(pack 'オフラインで遊べる定番ゲーム8種の詰め合わせ' '8つの定番ゲームがこれ1本。通信不要のオフライン対応です。')" "$(swiftsrc 8)"
check "「これ1本」だけでは本数の主張と見ない" 1 "$(pack '8つの定番ゲームがこれ1本。')" "$(swiftsrc 8)"
check "キーワード欄の 2048 を拾わない"       0 "$(pack '定番12種' '大富豪,麻雀ソリティア,2048,数独,麻雀')" "$(swiftsrc 12)"

echo "== 3. 見るのは入稿文言（\`\`\`text ブロック）だけ =="
# pack() は散文側に 8本 / 10種 / 9999本 を必ず書いている。それでも通ることを見る。
check "散文に残した過去の本数は無視する"     0 "$(pack '定番12種')" "$(swiftsrc 12)"

echo "== 4. 読み取り失敗は黙って通さない =="
check "パックに本数の記述が無い"             1 "$(pack 'あそびば：神経衰弱 マインスイーパー 五目並べ 将棋')" "$(swiftsrc 12)"
check "パックが存在しない"                   1 "$TMP/no-such-pack.md"      "$(swiftsrc 12)"
check "ソースが存在しない"                   1 "$(pack '定番12種')"        "$TMP/no-such-source.swift"
printf 'enum AppGameServices {}\n' > "$TMP/empty.swift"
check "registry が読み取れない"              1 "$(pack '定番12種')"        "$TMP/empty.swift"

echo "== 5. registry の数え方 =="
cat > "$TMP/commented.swift" <<'SWIFT'
enum AppGameServices {
    static let registry = GameRegistry([
        Game2048Module(), ShogiModule(),
        // 数独（#262）は末尾に足す。DummyModule() と書いてあっても数えない。
        SudokuModule(),
    ])
}
SWIFT
check "コメント内の Module() は数えない"     0 "$(pack '定番3種')" "$TMP/commented.swift"
cat > "$TMP/after.swift" <<'SWIFT'
enum AppGameServices {
    static let registry = GameRegistry([
        Game2048Module(), ShogiModule(), SudokuModule(),
    ])
    static let unrelated = [OtherModule(), YetAnotherModule()]
}
SWIFT
check "registry の外の Module() は数えない"  0 "$(pack '定番3種')" "$TMP/after.swift"

# ブロックコメント内の `])` を終端と誤認すると、そこで数え終えて後続を落とす（CodeRabbit 指摘・PR #294）
cat > "$TMP/block.swift" <<'SWIFT'
enum AppGameServices {
    static let registry = GameRegistry([
        /* DummyModule(), ]) */
        Game1Module(),
        Game2Module(),
    ])
}
SWIFT
check "1行のブロックコメントを無視する"      0 "$(pack '定番2種')" "$TMP/block.swift"
cat > "$TMP/block-multi.swift" <<'SWIFT'
enum AppGameServices {
    static let registry = GameRegistry([
        Game1Module(),
        /* 旧構成:
           OldModule(),
           ]) ← ここで終わらせてはいけない
        */
        Game2Module(), Game3Module(),
    ])
    static let unrelated = [AfterModule()]
}
SWIFT
check "複数行のブロックコメントを無視する"   0 "$(pack '定番3種')" "$TMP/block-multi.swift"
cat > "$TMP/block-inline.swift" <<'SWIFT'
enum AppGameServices {
    static let registry = GameRegistry([
        Game1Module(), /* Game9Module() */ Game2Module(),
    ])
}
SWIFT
check "行中のブロックコメントを無視する"     0 "$(pack '定番2種')" "$TMP/block-inline.swift"

echo "== 6. ブランチからパックを導く（引数なし）=="
GIT_TMP="$TMP/repo"
mkdir -p "$GIT_TMP/docs/aso" "$GIT_TMP/App"
git -C "$GIT_TMP" init -q 2>/dev/null
git -C "$GIT_TMP" config user.email t@example.com
git -C "$GIT_TMP" config user.name t
cp "$(swiftsrc 12)" "$GIT_TMP/App/AppGameServices.swift"
git -C "$GIT_TMP" add -A && git -C "$GIT_TMP" commit -qm init

branch_check() {
  local desc="$1" want="$2" branch="$3" got
  git -C "$GIT_TMP" checkout -q -B "$branch" 2>/dev/null
  ( cd "$GIT_TMP" && bash "$TARGET" >/dev/null 2>&1 )
  got=$?
  if [ "$got" = "$want" ]; then ok "$desc"; else ng "$desc (期待: 終了コード $want / 実際: $got)"; fi
}

branch_check "release 以外のブランチは検証対象外"       0 "feature/foo"
branch_check "パック未作成の release ブランチは通す"    0 "release/v9.9.9"
cp "$(pack '定番12種')" "$GIT_TMP/docs/aso/metadata-v9.9.9.md"
branch_check "パックがあり一致すれば通る"               0 "release/v9.9.9"
cp "$(pack '定番10種')" "$GIT_TMP/docs/aso/metadata-v9.9.9.md"
branch_check "パックがあり食い違えば落ちる"             1 "release/v9.9.9"

echo "== 7. 実物のパックで動く（回帰の最終確認）=="
if bash "$TARGET" "$REPO/docs/aso/metadata-v1.1.1.md" "$REPO/App/AppGameServices.swift" >/dev/null 2>&1; then
  ok "docs/aso/metadata-v1.1.1.md が現在の実装と一致している"
else
  ng "docs/aso/metadata-v1.1.1.md が現在の実装と一致していない"
fi

echo "== 8. 配信レーンから呼ばれている（仕込み忘れの検出）=="
# Fastfile 全体を grep すると、別レーンやコメントに文字列があるだけで通ってしまう
# （beta から外しても気づけない）。`lane :beta do` 〜 対応する `end` の中だけを見る。
beta_lane() {
  awk '
    /lane[[:space:]]*:beta[[:space:]]+do/ { indent = substr($0, 1, index($0, "lane") - 1); inside = 1; next }
    inside && $0 == indent "end" { inside = 0; next }
    inside
  ' "$1"
}
calls_checker_in_beta() {
  beta_lane "$1" | grep -qF 'sh("bash", "../Scripts/check-aso-game-count.sh")'
}

if calls_checker_in_beta "$REPO/fastlane/Fastfile"; then
  ok "fastlane の beta レーンが check-aso-game-count.sh を呼んでいる"
else
  ng "fastlane の beta レーンが check-aso-game-count.sh を呼んでいない"
fi

# 上の判定が「Fastfile のどこかにあれば通る」ものに退化していないことを固定する
cat > "$TMP/Fastfile-outside" <<'RUBY'
platform :ios do
  lane :lint do
    sh("bash", "../Scripts/check-aso-game-count.sh")
  end

  lane :beta do
    # check-aso-game-count.sh はここから外してある
    sh("xcodegen", "generate", "--project", "..")
  end
end
RUBY
if calls_checker_in_beta "$TMP/Fastfile-outside"; then
  ng "beta の外にだけ呼び出しがある Fastfile を誤って通した"
else
  ok "beta の外にだけ呼び出しがある Fastfile は通さない"
fi

echo
echo "結果: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
