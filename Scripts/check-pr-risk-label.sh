#!/bin/bash
# アプリコードを触る PR に risk:* ラベルが無ければ落とす（#823）。
#
# 規程（docs/ai-devops.md「マージ規則」）は `risk:*` を「マージ可否ではなく分類として必ず付ける」と
# 定めている。会長はリリース前の実機確認で重点的に見る対象（risk:ui / risk:sensitive）を PR 一覧の
# ラベルから拾うため、付け忘れた PR はその網から黙って漏れる。
#
# 実害: 2026-09-13 にマージされた release/v1.1.5 向けの PR のうち 6 本（#767 #770 #772 #773 #794 #803）が
# ラベル無しのままマージされていた（監査レポート #808 の欠陥 15）。プロンプトの記述だけでは守られなかった。
#
# 使い方: Scripts/check-pr-risk-label.sh <base> <head> <ラベル一覧のパス> [変更ファイル一覧のパス]
#   ラベル一覧は 1 行 1 ラベル。変更ファイル一覧を省略すると標準入力から読む（1 行 1 パス）。
# 終了コード: 0 = 問題なし or 検証対象外 / 1 = ラベル無しのアプリコード変更 / 2 = 使い方の誤り
set -uo pipefail

BASE="${1:-}"
HEAD_REF="${2:-}"
LABELS_PATH="${3:-}"
FILES_PATH="${4:-}"

if [ -z "$BASE" ] || [ -z "$HEAD_REF" ] || [ -z "$LABELS_PATH" ]; then
  echo "使い方: Scripts/check-pr-risk-label.sh <base> <head> <ラベル一覧のパス> [変更ファイル一覧のパス]" >&2
  exit 2
fi
if [ ! -f "$LABELS_PATH" ]; then
  echo "check-pr-risk-label: ラベル一覧 [$LABELS_PATH] を読めません" >&2
  exit 2
fi

# check-pr-base.sh と同じく、バージョン番号の形まで見る（名前を似せるだけで迂回させない）。
is_version() {
  local v="$1" dots
  case "$v" in
    ""|*[!0-9.]*|.*|*.|*..*) return 1 ;;
  esac
  dots="${v//[!.]/}"
  [ "${#dots}" = 2 ]
}

# 束ねて運ぶだけの PR は見ない。中身は元の PR でそれぞれ分類済みで、束に 1 つのラベルを
# 付けても分類にならない（risk:ui と risk:logic が混ざる）。
#   - release/vX.Y.Z → main の取り込み、release/vX.Y.Z → 次の release の同期
#   - 凍結回避の中間ブランチ（#558 の chore/merge-release-v113-to-main）
#   - release 間の同期ブランチ（#903 の chore/sync-v115-to-v116-0915 など）。base が release/vX.Y.Z のときだけ
BUNDLE=""
case "$HEAD_REF" in
  release/v*)
    is_version "${HEAD_REF#release/v}" && BUNDLE="release ブランチ"
    ;;
  chore/merge-release-v*)
    rest="${HEAD_REF#chore/merge-release-v}"
    case "$rest" in
      [0-9]*-to-main) [ "$BASE" = "main" ] && BUNDLE="凍結回避の中間ブランチ" ;;
    esac
    ;;
  chore/sync-?*)
    case "$BASE" in
      release/v*) is_version "${BASE#release/v}" && BUNDLE="release 間の同期ブランチ" ;;
    esac
    ;;
esac

if [ -n "$BUNDLE" ]; then
  echo "check-pr-risk-label: head が [${HEAD_REF}]（${BUNDLE}）で、分類済みの変更を束ねて運ぶ PR のため検証しません"
  exit 0
fi

if [ -n "$FILES_PATH" ]; then
  if [ ! -f "$FILES_PATH" ]; then
    echo "check-pr-risk-label: 変更ファイル一覧 [$FILES_PATH] を読めません" >&2
    exit 2
  fi
  FILES="$(cat "$FILES_PATH")"
else
  FILES="$(cat)"
fi

APP_FILES=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    App/*|Packages/*|project.yml) APP_FILES="${APP_FILES}${f}"$'\n' ;;
  esac
done <<< "$FILES"

if [ -z "$APP_FILES" ]; then
  echo "check-pr-risk-label: アプリコード（App/ Packages/ project.yml）を含まないため検証しません"
  exit 0
fi

# 規程の 3 種だけを数える。`risk:` の前方一致にすると、存在しないラベル（risk:low 等）でも通ってしまう。
FOUND=""
while IFS= read -r l; do
  case "$l" in
    risk:logic|risk:ui|risk:sensitive) FOUND="${FOUND:+$FOUND }$l" ;;
  esac
done < "$LABELS_PATH"

if [ -n "$FOUND" ]; then
  echo "check-pr-risk-label: アプリコードの変更に分類ラベル [$FOUND] が付いています"
  exit 0
fi

echo "check-pr-risk-label: アプリコードを触る PR に risk:* ラベルがありません"
echo
printf '%s' "$APP_FILES" | head -20 | sed 's/^/  - /'
echo
echo "docs/ai-devops.md「マージ規則」の表から 1 つ付けてください:"
echo "  risk:logic     … ロジック・バグ修正など UI/収益に触れない変更"
echo "  risk:ui        … 画面・操作感に影響する変更（スクリーンショット添付必須）"
echo "  risk:sensitive … 広告・課金・ATT/プライバシー・審査事項"
echo "ラベルを付ければこのチェックは自動で再実行されます。"
exit 1
