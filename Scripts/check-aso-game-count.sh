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
#    コメントの中の Module() や `])` を拾うと本数も終端位置も狂うので、**先にコメントを落としてから**
#    数える。行コメント（// 数独（#262）は末尾に足す）だけでなくブロックコメント（/* ... */）も、
#    複数行にまたがるものを状態を持って除去する（CodeRabbit 指摘・PR #294）。
ACTUAL="$(awk '
  # 行からコメントを取り除いて返す。inblock はブロックコメントの継続状態（グローバル）。
  function strip(line,   out, i) {
    out = ""
    while (length(line) > 0) {
      if (inblock) {
        i = index(line, "*/")
        if (i == 0) return out
        line = substr(line, i + 2)
        inblock = 0
        continue
      }
      i = index(line, "/*")
      if (i > 0 && (index(line, "//") == 0 || index(line, "//") > i)) {
        out = out substr(line, 1, i - 1)
        line = substr(line, i + 2)
        inblock = 1
        continue
      }
      sub(/\/\/.*/, "", line)
      return out line
    }
    return out
  }
  { line = strip($0) }
  line ~ /GameRegistry\(\[/ { inside = 1 }
  inside {
    count += gsub(/[A-Za-z0-9_]+Module\(\)/, "", line)
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
# 誤検知は `fastlane beta` を止めてしまうので、**収録本数を主張していることが明らかな構文だけ**を見る。
# 欄ごとに正しさの基準が違う（会長決裁 2026-10-24・#2053）ので、EXACT（実装本数とちょうど一致）と
# ROUND（実装本数を10の位で丸めた数）の2種類に分けて拾う:
#   - EXACT（説明文・プロモーションテキスト。ちょうどの本数で書く欄）
#       「定番<N>種」「定番ゲーム<N>種」（サブタイトルの旧い言い回し。`定番` と数字のあいだに
#       他の語は挟ませない。緩めると「8つの定番ゲームがこれ1本」の `1` を拾ってしまう）
#       「遊べる<N>種」「遊べる<N>本」（サブタイトルの旧い言い回し。v1.1.11 で「定番」を外した。#1873）
#       「<N>本を収録」「<N>種を収録」（説明文・プロモーションテキスト）
#       「<N>本すべて」「<N>本全て」（オフライン訴求）
#   - ROUND（サブタイトル。v1.1.14 からの言い回し。#2053）
#       「(定番)?<N>種以上」「(定番)?<N>本以上」「遊べる<N>種以上」。会長決裁で、サブタイトルの本数は
#       **ちょうどの本数ではなく10の位で丸めて書き、10の位が上がったとき（32本→40本）だけ更新する**。
#       例: 「大富豪・ソリティアなど定番30種以上｜全画面広告なし」（実装32本→30種以上）。
#       英語（en-US）は同じ決まりで「30+ Offline Games」のように `N+` と書くが、英語パックを検証する
#       呼び出しは今のところ無い（store-en-vX.Y.Z.md は fastlane からは読まれない）。
# 別の言い回しに変えた場合はここに合致しなくなるが、そのときは「記述がありません」で落ちる
# （黙って通さない = fail safe）。「本」「種」はマルチバイトなので切り出しは awk の中で完結させる
# （sed の `[本種]` はバイト単位に効いて文字を壊す）。
CLAIMS="$(awk '
  function harvest(line, re, kind,   hit, num) {
    while (match(line, re)) {
      hit = substr(line, RSTART, RLENGTH)
      num = hit
      gsub(/[^0-9]/, "", num)
      print num, kind
      line = substr(line, RSTART + RLENGTH)
    }
  }
  /^```text[[:space:]]*$/ { fence = 1; next }
  /^```[[:space:]]*$/     { fence = 0; next }
  fence {
    # 正規表現は**文字列で**渡す。awk で /re/ を式として書くと $0 ~ /re/ の 0/1 に化ける。
    round_re = "(定番(ゲーム)?|遊べる)?[0-9]+(本|種)以上"
    harvest($0, round_re, "ROUND")
    # EXACT 側はいったん ROUND の構文（「定番30種以上」等）を空文字に落としてから拾う。
    # 落とさないと「定番30種以上」の前半「定番30種」を EXACT 側にも二重に拾ってしまう。
    exact_line = $0
    gsub(round_re, "", exact_line)
    harvest(exact_line, "定番(ゲーム)?[0-9]+(本|種)", "EXACT")
    harvest(exact_line, "遊べる[0-9]+(本|種)", "EXACT")
    harvest(exact_line, "[0-9]+(本|種)(を収録|すべて|全て)", "EXACT")
  }
' "$PACK")"

CLAIM_COUNT="$(printf '%s\n' "$CLAIMS" | grep -c . || true)"

if [ "$CLAIM_COUNT" -eq 0 ]; then
  echo "check-aso-game-count: $PACK の入稿文言（\`\`\`text ブロック）に収録本数の記述がありません" >&2
  echo "  拾える書き方は「定番N種」「遊べるN種」「N本を収録」「N本すべて」「N種以上」です。" >&2
  echo "  言い回しを変えた場合は本スクリプトのパターンも追加してください。" >&2
  echo "  文言から本数の主張を意図的に外したのであれば、呼び出し側でこの検証を外してください。" >&2
  exit 1
fi

EXACT_CLAIMS="$(printf '%s\n' "$CLAIMS" | awk '$2=="EXACT"{print $1}' | sort -un)"
ROUND_CLAIMS="$(printf '%s\n' "$CLAIMS" | awk '$2=="ROUND"{print $1}' | sort -un)"
ROUNDED_EXPECT=$(((ACTUAL / 10) * 10))

MISMATCH=""
for c in $EXACT_CLAIMS; do
  [ "$c" = "$ACTUAL" ] || MISMATCH="$MISMATCH ${c}本（ちょうど一致の欄）"
done
for c in $ROUND_CLAIMS; do
  [ "$c" = "$ROUNDED_EXPECT" ] || MISMATCH="$MISMATCH ${c}種以上（サブタイトル・10の位で丸めた欄）"
done

if [ -n "$MISMATCH" ]; then
  cat >&2 <<EOF
check-aso-game-count: 入稿パックの収録本数が実装と一致しません

  実装（$SOURCE の GameRegistry）                 : ${ACTUAL}本（サブタイトルは丸めて ${ROUNDED_EXPECT}種以上）
  パック（$PACK の入稿文言）:$MISMATCH

売り物を検索面・商品ページから落とさないため、入稿前に次を是正してください:
  - サブタイトル（「${ROUNDED_EXPECT}種以上」。10の位で丸めた本数＋「種以上」。ちょうどの本数には戻さない）
  - 説明文の冒頭（ゲーム名の列挙と「${ACTUAL}本を収録」「${ACTUAL}本すべてが最後まで遊べます」）
  - プロモーションテキスト（同上。ちょうどの本数）
  - キーワード欄（新しいゲームの正式名が1枠目に入っているか）
  - オフライン訴求の根拠（${ACTUAL}本での取り直し）

過去の同じ食い違い: #178（8→10）・#281（10→12）
EOF
  exit 1
fi

SUMMARY="実装 ${ACTUAL}本 / $(basename "$PACK") の主張 ちょうど${ACTUAL}本"
[ -z "$ROUND_CLAIMS" ] || SUMMARY="${SUMMARY}・サブタイトル${ROUNDED_EXPECT}種以上"
echo "check-aso-game-count: OK（${SUMMARY}）"
