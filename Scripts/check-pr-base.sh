#!/bin/bash
# main をベースにしたアプリコードの PR を落とす（#606）。
#
# 規程（docs/ai-devops.md「ブランチ戦略」）では main は「リリース済みバージョンの集合」で、
# アプリコードの PR を向ける場所ではない。ここへ入れた変更は release/vX.Y.Z を経由しないため
# 次版の出荷物に載らず、しかもどの検知にも掛からない（当番の仕事10「取り残しコミット」は
# 「マージ済み PR の head ブランチにあって base にも main にも無いコミット」を探すので、
# main に入ってしまったものは対象外になる）。
#
# 実害: チャリンコおじさんの修正6コミットが PR #593 / #596 で main 直マージされ、
# release/v1.1.4 に載らないまま2日ぶん積み上がった（#606 で cherry-pick して回収）。
# しかも release/v1.1.4 にしか無い走査テスト（GameChromeTests）で1件落ちる状態だったため、
# main 側の CI が green でも「次版で通る」ことの担保になっていなかった。
#
# 使い方: Scripts/check-pr-base.sh <base ブランチ名> <head ブランチ名> [変更ファイル一覧のパス]
#   変更ファイル一覧を省略すると標準入力から読む（1 行 1 パス）。
# 終了コード: 0 = 問題なし or 検証対象外 / 1 = main 直のアプリコード変更 / 2 = 使い方の誤り
set -uo pipefail

BASE="${1:-}"
HEAD_REF="${2:-}"
FILES_PATH="${3:-}"

if [ -z "$BASE" ] || [ -z "$HEAD_REF" ]; then
  echo "使い方: Scripts/check-pr-base.sh <base ブランチ名> <head ブランチ名> [変更ファイル一覧のパス]" >&2
  exit 2
fi

# base が main 以外（= release/vX.Y.Z 向けの通常の開発 PR）は本来の姿なので何も見ない。
if [ "$BASE" != "main" ]; then
  echo "check-pr-base: base が [$BASE] で main ではないため検証しません"
  exit 0
fi

# 公開後の取り込み（release/vX.Y.Z → main）は規程が定める正規の経路で、
# 当然アプリコードを含む。凍結済み release ブランチは push できないため中間ブランチを
# 経由することがあり（#558 の chore/merge-release-v113-to-main）、その形も通す。
case "$HEAD_REF" in
  release/*|chore/merge-release-*)
    echo "check-pr-base: head が [$HEAD_REF] で release の取り込み経路のため検証しません"
    exit 0
    ;;
esac

if [ -n "$FILES_PATH" ]; then
  if [ ! -f "$FILES_PATH" ]; then
    echo "check-pr-base: 変更ファイル一覧 [$FILES_PATH] を読めません" >&2
    exit 2
  fi
  FILES="$(cat "$FILES_PATH")"
else
  FILES="$(cat)"
fi

# アプリのバイナリに入るもの＝ release ブランチを経由しなければならないもの。
# docs/ Scripts/ .github/ web/ は運用系・LP で、規程上 main 直の PR でよい。
VIOLATIONS=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    App/*|Packages/*|project.yml)
      VIOLATIONS="${VIOLATIONS}${f}"$'\n'
      ;;
  esac
done <<< "$FILES"

if [ -z "$VIOLATIONS" ]; then
  echo "check-pr-base: main 直の PR ですが、アプリコード（App/ Packages/ project.yml）は含みません"
  exit 0
fi

echo "check-pr-base: main をベースにしたアプリコードの変更を検出しました"
echo
printf '%s' "$VIOLATIONS" | sed 's/^/  - /'
echo
echo "main は「リリース済みバージョンの集合」です（docs/ai-devops.md）。"
echo "この PR の base を、対象 Issue のマイルストーンと同名の release/vX.Y.Z に付け替えてください。"
echo "対応する release ブランチが無ければ直近の release の HEAD から作成します（同文書の手順）。"
exit 1
