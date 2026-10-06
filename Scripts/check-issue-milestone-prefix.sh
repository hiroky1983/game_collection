#!/bin/bash
# オープン Issue のタイトル先頭の `[vX.Y.Z]` プレフィックスと、実際のマイルストーンの
# 食い違いを検知する（#619）。
#
# 規程（docs/ai-devops.md「ブランチ戦略」）:
#   「Issue は起票時にマイルストーンを必ず設定し、タイトルの先頭に [vX.Y.Z] を付ける。
#    マイルストーンを変更したらプレフィックスも揃えて直す。バージョン非依存の Issue には
#    プレフィックスを付けない」
#
# 規程はあったが機械的に確認する経路が無く、2026-09-11 の実測でオープン Issue 7 件が
# ズレていた（うち2件はマイルストーン変更にプレフィックスが追随せず、公開済みの旧版を
# 表示し続けるという実害があった）。本スクリプトはそれを毎回検知できるようにする。
#
# **検知するだけで、タイトルは書き換えない**（会長が読む文字列を機械的に書き換える案は
# #619 の検討で見送った。判断が要らない置換に見えても、書き換え自体が事故の種になりうる
# ため、当面は報告に留め、直すかどうかは会長に委ねる）。
#
# gh を直接呼ばない。判定対象は `gh issue list --json number,title,milestone` と同じ形の
# JSON 配列で、呼び出し側（当番プロンプト・テスト）が用意して渡す。呼び出し側から
# 分離してあるのは、この判定ロジックだけを gh 抜きでテストできるようにするため
# （check-pr-base.sh が変更ファイル一覧を外から受け取るのと同じ形）。
#
# 使い方: gh issue list --state open --limit 200 --json number,title,milestone \
#           | Scripts/check-issue-milestone-prefix.sh
#         Scripts/check-issue-milestone-prefix.sh <issues.json のパス>
#   引数を省略すると標準入力から読む。
# 終了コード: 0 = 全件整合 / 1 = 食い違いを検出 / 2 = 使い方の誤り・入力が不正な JSON
set -uo pipefail

INPUT_PATH="${1:-}"

if [ -n "$INPUT_PATH" ]; then
  if [ ! -f "$INPUT_PATH" ]; then
    echo "check-issue-milestone-prefix: 入力ファイル [$INPUT_PATH] を読めません" >&2
    exit 2
  fi
  JSON="$(cat "$INPUT_PATH")"
else
  JSON="$(cat)"
fi

if ! printf '%s' "$JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "check-issue-milestone-prefix: 入力が JSON 配列ではありません（gh issue list --json number,title,milestone の出力を渡してください）" >&2
  exit 2
fi

# 判定はすべて jq 側で行い、シェルは結果行を受け取って表示するだけにする。
#   - マイルストーン有り: タイトル先頭が "[<マイルストーン名>]" と完全一致しなければ違反
#   - マイルストーン無し: タイトル先頭が [vX.Y.Z] の形（バージョンらしきブラケット）なら違反
#     （マイルストーン名が vX.Y.Z 以外の形であっても、規程が定めるのは vX.Y.Z 形式の
#     プレフィックスなので、判定はこの形にだけ反応させる）
REPORT="$(printf '%s' "$JSON" | jq -r '
  def version_prefix:
    (capture("^\\[(?<v>v[0-9]+\\.[0-9]+\\.[0-9]+)\\]") // {v: null}).v;
  .[]
  | . as $issue
  | ($issue.milestone.title // "") as $ms
  | ($issue.title // "") as $title
  | if $ms != "" then
      ("[" + $ms + "]") as $expected
      | if ($title | startswith($expected)) then empty
        else
          ($title | version_prefix) as $actual
          | [
              ($issue.number | tostring),
              $ms,
              $expected,
              (if $actual then ("[" + $actual + "]") else "(無し)" end),
              $title
            ] | join("\t")
        end
    else
      ($title | version_prefix) as $actual
      | if $actual then
          [
            ($issue.number | tostring),
            "(無し)",
            "(プレフィックス無し)",
            "[" + $actual + "]",
            $title
          ] | join("\t")
        else empty
        end
    end
')"

if [ -z "$REPORT" ]; then
  echo "check-issue-milestone-prefix: 食い違いはありません"
  exit 0
fi

echo "check-issue-milestone-prefix: タイトルプレフィックスとマイルストーンが食い違っている Issue があります"
echo
echo "$REPORT" | while IFS=$'\t' read -r num ms expected actual title; do
  echo "  #${num}: milestone=${ms} / 期待するプレフィックス=${expected} / 実際=${actual}"
  echo "        タイトル: ${title}"
done
echo
echo "タイトルは自動で書き換えません。マイルストーン名を正として、会長の確認のうえで直してください"
echo "（docs/ai-devops.md「ブランチ戦略」）。"
exit 1
