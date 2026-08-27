#!/bin/bash
# 入稿パック（docs/aso/metadata-vX.Y.Z.md）が主張する収録本数が、実際に登録されている
# ゲーム数（App/AppGameServices.swift の GameRegistry）と一致していることを確認する（#281）。
#
# なぜ要るか: 同じ食い違いが3回起きている。
#   8本 → 10本  #178（大富豪・麻雀ソリティアが商品ページのどこにも無かった）
#   10本 → 12本 #281（麻雀（四人打ち）・数独が同上）
# いずれも「売り物を検索面から丸ごと落とす」状態で、人手の棚卸しでしか見つかっていない。
#
# なぜ CI で常時実行しないか（check-marketing-version.sh #161 と同じ検討をしたうえでの判断）:
#   新しいゲームを追加する PR は、マージされた瞬間に必ずこの不一致を作る。入稿パックの是正には
#   キーワードの実測（iTunes Search API）と字数の再設計が要り、ゲーム実装の PR に同梱できる作業ではない。
#   CI で常時落とすと「ゲームを1本足すたびに ASO の文言作業が完了するまでマージできない」ことになり、
#   正常な途中状態を事故として扱ってしまう。
#   よって check-marketing-version.sh と同じく「一致していなければならない唯一の瞬間」だけで落とす。
#   その瞬間は `fastlane beta`（= そのバージョンで出荷する中身が確定し、会長の実機確認・入稿へ渡る直前）。
#
# 使い方: Scripts/check-aso-game-count.sh [入稿パックのパス] [AppGameServices.swift のパス]
#   引数を省略すると、現在のブランチ名 release/vX.Y.Z から docs/aso/metadata-vX.Y.Z.md を導く。
# 終了コード: 0 = 一致 or 検証対象外 / 1 = 不一致 or 読み取り失敗
set -uo pipefail

PACK="${1:-}"
SOURCE="${2:-}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
[ -n "$SOURCE" ] || SOURCE="$ROOT/App/AppGameServices.swift"

if [ -z "$PACK" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  case "$BRANCH" in
    release/v*)
      PACK="$ROOT/docs/aso/metadata-${BRANCH#release/}.md"
      ;;
    *)
      # main・feature ブランチ・detached HEAD ではどのパックを見るべきか導けない。
      # 黙って通ると「チェックが働いた」と誤解されるため、対象外である旨は必ず出す。
      echo "check-aso-game-count: 現在のブランチ [$BRANCH] は release/vX.Y.Z ではないため検証しません"
      echo "  パックを指定して単体で走らせられます: Scripts/check-aso-game-count.sh docs/aso/metadata-v1.1.1.md"
      exit 0
      ;;
  esac
  if [ ! -f "$PACK" ]; then
    # そのバージョンの入稿パックがまだ書かれていない段階の TestFlight 配信は正常。
    # ただし「見に行った先が無かった」ことは黙らない（入稿までには必ず要るため）。
    echo "check-aso-game-count: 入稿パックがまだありません: $PACK"
    echo "  このバージョンを App Store に入稿する前に作成してください（雛形は docs/aso/metadata-v1.1.1.md）。"
    exit 0
  fi
fi

if [ ! -f "$SOURCE" ]; then
  echo "check-aso-game-count: ゲーム登録元が見つかりません: $SOURCE" >&2
  exit 1
fi
if [ ! -f "$PACK" ]; then
  echo "check-aso-game-count: 入稿パックが見つかりません: $PACK" >&2
  exit 1
fi

# 1. 実装側の本数 = GameRegistry([ ... ]) に並んだ `XxxModule()` の数。
#    行コメント（// 数独（#262）は末尾に足す 等）に Module() が現れても数えないよう、先に落とす。
ACTUAL="$(awk '
  /GameRegistry\(\[/ { inside = 1 }
  inside {
    line = $0
    sub(/\/\/.*/, "", line)
    n = gsub(/[A-Za-z0-9_]+Module\(\)/, "", line)
    count += n
    if (line ~ /\]\)/) { inside = 0 }
  }
  END { print count + 0 }
' "$SOURCE")"

if [ "$ACTUAL" -eq 0 ]; then
  echo "check-aso-game-count: $SOURCE から GameRegistry の登録を読み取れませんでした" >&2
  echo "  registry の書き方が変わった場合は本スクリプトの awk も更新してください。" >&2
  exit 1
fi

# 2. パック側の主張 = **入稿する文言そのもの**（```text で囲われたブロック）に現れる「N本」「N種」。
#    本文の散文には過去の経緯（「8本前提だった」等）が意図的に残してあるため、そこは見ない。
#    見るのは会長が ASC にコピペするブロックだけ = 実際に商品ページへ出る主張だけ。
# 「N本」「N種」をそのまま拾うと、収録本数ではない言い回しを誤検知する
#   （v1.1.0 パックの説明文「8つの定番ゲームが**これ1本**。」が実例）。
# 誤検知は `fastlane beta` を止めてしまうので、**収録本数を主張していることが明らかな構文だけ**を見る:
#   - 「定番<N>種」「定番ゲーム<N>種」（サブタイトル。`定番` と数字のあいだに他の語は挟ませない。
#     緩めると「8つの定番ゲームがこれ1本」の `1` を拾ってしまう）
#   - 「<N>本を収録」「<N>種を収録」（説明文・プロモーションテキスト）
#   - 「<N>本すべて」「<N>本全て」（オフライン訴求）
# 別の言い回しに変えた場合はここに合致しなくなるが、そのときは「記述がありません」で落ちる
# （黙って通さない = fail safe）。「本」「種」はマルチバイトなので切り出しは awk の中で完結させる
# （sed の `[本種]` はバイト単位に効いて文字を壊す）。
CLAIMS="$(awk '
  function harvest(line, re,   hit, num) {
    while (match(line, re)) {
      hit = substr(line, RSTART, RLENGTH)
      num = hit
      gsub(/[^0-9]/, "", num)
      print num
      line = substr(line, RSTART + RLENGTH)
    }
  }
  /^```text[[:space:]]*$/ { fence = 1; next }
  /^```[[:space:]]*$/     { fence = 0; next }
  fence {
    # 正規表現は**文字列で**渡す。awk で /re/ を式として書くと $0 ~ /re/ の 0/1 に化ける。
    harvest($0, "定番(ゲーム)?[0-9]+(本|種)")
    harvest($0, "[0-9]+(本|種)(を収録|すべて|全て)")
  }
' "$PACK" | sort -un)"

CLAIM_COUNT="$(printf '%s' "$CLAIMS" | grep -c . || true)"

if [ "$CLAIM_COUNT" -eq 0 ]; then
  echo "check-aso-game-count: $PACK の入稿文言（\`\`\`text ブロック）に収録本数の記述がありません" >&2
  echo "  拾える書き方は「定番N種」「N本を収録」「N本すべて」です。" >&2
  echo "  言い回しを変えた場合は本スクリプトのパターンも追加してください。" >&2
  echo "  文言から本数の主張を意図的に外したのであれば、呼び出し側でこの検証を外してください。" >&2
  exit 1
fi

MISMATCH=""
for c in $CLAIMS; do
  [ "$c" = "$ACTUAL" ] || MISMATCH="$MISMATCH $c"
done

if [ -n "$MISMATCH" ]; then
  FOUND=""
  for c in $MISMATCH; do FOUND="$FOUND ${c}本"; done
  cat >&2 <<EOF
check-aso-game-count: 入稿パックの収録本数が実装と一致しません

  実装（$SOURCE の GameRegistry）:$( printf ' %s本' "$ACTUAL")
  パック（$PACK の入稿文言）      :$FOUND

売り物を検索面・商品ページから落とさないため、入稿前に次を是正してください:
  - サブタイトル（「定番${ACTUAL}種」）
  - 説明文の冒頭（ゲーム名の列挙と「${ACTUAL}本を収録」「${ACTUAL}本すべてが最後まで遊べます」）
  - プロモーションテキスト（同上）
  - キーワード欄（新しいゲームの正式名が1枠目に入っているか）
  - オフライン訴求の根拠（${ACTUAL}本での取り直し）

過去の同じ食い違い: #178（8→10）・#281（10→12）
EOF
  exit 1
fi

echo "check-aso-game-count: OK（実装 ${ACTUAL}本 / $(basename "$PACK") の主張 ${ACTUAL}本）"
