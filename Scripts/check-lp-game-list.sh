#!/bin/bash
# LP（web/app/lib/games.ts）に載っているゲームの顔ぶれ・順序が、アプリの登録
# （App/AppGameServices.swift の GameRegistry）と一致していることを確認する（#296）。
#
# なぜ要るか: 同じ食い違いが LP 側だけで2回起きている。いずれも「売り物のページが丸ごと 404」で、
# 人手の棚卸しでしか見つかっていない。
#   8本 → 10本  #156（LP が8本のまま。さらに release ブランチ止まりで本番は3日間 404・#176）
#   10本 → 12本 #296（麻雀（四人打ち）・数独のページが存在しなかった）
# 入稿パック側の同種の検知は Scripts/check-aso-game-count.sh（#281）。あちらは「本数」だけを見るが、
# LP は URL（slug）と並び順まで一致していなければ意味がないので、こちらは slug 列をそのまま比べる。
#
# ■ 何と比べるか（ここが入稿パック側と決定的に違う）
#   比較先は **次に出す版（release/vX.Y.Z）の GameRegistry** であって、main のものではない。
#   main は「App Store で公開済みの集合」（docs/ai-devops.md）なので、main の registry に LP を
#   合わせると、公開されるまでその版のページが存在しないことになる。それは #176 でまさに起きた失敗
#   （検索インデックスが付く前に、公開直後という最も重要な期間を落とす）。
#   よって既定の比較先は「もっとも新しい release/vX.Y.Z」= これから出る全ゲームの上位集合とする。
#
# ■ なぜ CI で常時実行しないか
#   1. 上のとおり比較先が **別の ref** なので、PR のツリーだけでは判定できない。release ブランチは
#      PR とは無関係に動くため、常時実行すると「一度緑になった PR が、他所のマージで後から赤くなる」。
#   2. 新しいゲームを足す PR は release ブランチへ入り、LP（main）の更新はその後の別 PR になる。
#      途中に必ず不一致の期間があり、常時落とすと正常な途中状態を事故として扱ってしまう
#      （check-aso-game-count.sh と同じ設計判断）。
#   そこで「一致していなければならない唯一の瞬間」だけで走らせる。入稿パックのそれが `fastlane beta`
#   なのに対し、**LP のそれは games.ts を触る PR が main にマージされる瞬間**なので、
#   .github/workflows/lp-game-list.yml で `web/app/lib/games.ts` を変更した PR に限って実行する。
#
# 使い方: Scripts/check-lp-game-list.sh [比較先の ref] [games.ts のパス]
#   例: Scripts/check-lp-game-list.sh origin/release/v1.1.1
# 終了コード: 0 = 一致 or 検証対象外 / 1 = 不一致 or 読み取り失敗
set -uo pipefail

REF="${1:-}"
LIST="${2:-}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
[ -n "$LIST" ] || LIST="$ROOT/web/app/lib/games.ts"

if [ ! -f "$LIST" ]; then
  echo "check-lp-game-list: LP のゲーム一覧が見つかりません: $LIST" >&2
  exit 1
fi

if [ -z "$REF" ]; then
  # もっとも新しい release/vX.Y.Z を選ぶ。バージョンは辞書順だと v1.1.10 < v1.1.2 になるので `sort -V`。
  # **remote 追跡ブランチを優先する**: ローカルの refs/heads/release/* には削除済みのブランチが
  # 残っていることがある（実際にこの検証中、リモートに無い release/v1.1.3 がローカルに残っていて
  # 10本時代の registry を掴んだ。番号の付け替え = docs/ai-devops.md 2026-08-24 の名残）。
  # `git fetch --prune` は remote 追跡側しか掃除しないので、ローカルは最後の手段に留める。
  REF="$(git for-each-ref --format='%(refname)' 'refs/remotes/origin/release/v*' 2>/dev/null \
         | sed 's|^refs/remotes/||' | sort -Vu | tail -1)"
  if [ -z "$REF" ]; then
    REF="$(git for-each-ref --format='%(refname)' 'refs/heads/release/v*' 2>/dev/null \
           | sed 's|^refs/heads/||' | sort -Vu | tail -1)"
    [ -n "$REF" ] && echo "check-lp-game-list: 注意 - origin の release ブランチが無いためローカルの $REF と比べます"
  fi
  if [ -z "$REF" ]; then
    # 黙って通ると「チェックが働いた」と誤解されるため、対象外である旨は必ず出す。
    echo "check-lp-game-list: release/vX.Y.Z ブランチが見当たらないため検証しません"
    echo "  比較先を明示して単体で走らせられます: Scripts/check-lp-game-list.sh origin/release/v1.1.1"
    exit 0
  fi
fi

SOURCE="App/AppGameServices.swift"
if ! REGISTRY_SRC="$(git show "$REF:$SOURCE" 2>/dev/null)"; then
  echo "check-lp-game-list: $REF から $SOURCE を読めませんでした" >&2
  echo "  ref が取得済みか確認してください（CI では actions/checkout に fetch-depth: 0 が要ります）。" >&2
  exit 1
fi

# 1. registry に並んだ `XxxModule()` を**登録順のまま**取り出す。
#    コメントの中の Module() や `])` を拾うと顔ぶれも終端位置も狂うので、先にコメントを落とす。
#    行コメント（// 数独（#262）は末尾に足す）とブロックコメント（/* ... */・複数行）の両方を除く。
#    この awk は check-aso-game-count.sh と同じ構造（あちらは数える・こちらは名前を出す）。
MODULES="$(printf '%s\n' "$REGISTRY_SRC" | awk '
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
    while (match(line, /[A-Za-z0-9_]+Module\(\)/)) {
      name = substr(line, RSTART, RLENGTH - 2)
      print name
      line = substr(line, RSTART + RLENGTH)
    }
    if (line ~ /\]\)/) { inside = 0 }
  }
')"

if [ -z "$MODULES" ]; then
  echo "check-lp-game-list: $REF の $SOURCE から GameRegistry の登録を読み取れませんでした" >&2
  echo "  registry の書き方が変わった場合は本スクリプトの awk も更新してください。" >&2
  exit 1
fi

# LP の slug がアプリの ID と**意図的に**違うものの対応表。
# 原則は「slug = アプリの id」だが、麻雀ソリティアだけは公開時点で LP 側が mahjong-solitaire を
# 使っており（アプリ側の id は "mahjong"）、いま揃えると公開済みの URL が 404 になる。
# アプリ側の "mahjong" は四人打ち麻雀（id: "mahjong4"）と紛らわしいので、LP の表記のほうが正しい。
# ここに足すのは「URL を変えられない既存ページ」だけにすること。新規ゲームは必ず id と揃える。
lp_slug_for() {
  case "$1" in
    mahjong) echo "mahjong-solitaire" ;;
    *)       echo "$1" ;;
  esac
}

# 2. モジュール名 → ゲーム ID。ID は各 XxxModule.swift の `public let id = "..."` にある
#    （registry には型名しか出てこない）。
TREE="$(git ls-tree -r --name-only "$REF" -- Packages/GameKit/Sources 2>/dev/null)"
EXPECTED=""
for M in $MODULES; do
  PATHS="$(printf '%s\n' "$TREE" | grep -x "Packages/GameKit/Sources/[^/]*/$M\.swift" || true)"
  COUNT="$(printf '%s' "$PATHS" | grep -c . || true)"
  if [ "$COUNT" -ne 1 ]; then
    echo "check-lp-game-list: $M の定義ファイルを $REF 上で一意に特定できませんでした（$COUNT 件）" >&2
    exit 1
  fi
  ID="$(git show "$REF:$PATHS" | sed -n 's/^[[:space:]]*public let id = "\([^"]*\)".*/\1/p' | head -1)"
  if [ -z "$ID" ]; then
    echo "check-lp-game-list: $PATHS から 'public let id' を読み取れませんでした" >&2
    exit 1
  fi
  EXPECTED="$EXPECTED$(lp_slug_for "$ID")
"
done

# 3. LP 側の slug を**配列の並び順のまま**取り出す。
ACTUAL="$(sed -n 's/^[[:space:]]*slug: "\([^"]*\)".*/\1/p' "$LIST")"

if [ -z "$ACTUAL" ]; then
  echo "check-lp-game-list: $LIST から slug を読み取れませんでした" >&2
  exit 1
fi

if [ "$(printf '%s' "$EXPECTED")" = "$(printf '%s' "$ACTUAL")" ]; then
  echo "check-lp-game-list: OK（$REF の registry $(printf '%s\n' "$MODULES" | grep -c .)本と $(basename "$LIST") が一致）"
  exit 0
fi

MISSING="$(comm -23 <(printf '%s' "$EXPECTED" | sort) <(printf '%s' "$ACTUAL" | sort) | tr '\n' ' ')"
EXTRA="$(comm -13 <(printf '%s' "$EXPECTED" | sort) <(printf '%s' "$ACTUAL" | sort) | tr '\n' ' ')"

{
  echo "check-lp-game-list: LP のゲーム一覧がアプリの登録と一致しません"
  echo
  echo "  アプリ（$REF の GameRegistry・登録順）:"
  printf '%s' "$EXPECTED" | sed 's/^/    /'
  echo "  LP（${LIST}・配列順）:"
  printf '%s' "$ACTUAL" | sed 's/^/    /'
  echo
  [ -n "$MISSING" ] && echo "  LP に無い（= /games/<slug> が 404 になる）:$MISSING"
  [ -n "$EXTRA" ]   && echo "  アプリに無い（= 存在しないゲームを宣伝している）:$EXTRA"
  if [ -z "$MISSING" ] && [ -z "$EXTRA" ]; then
    echo "  顔ぶれは同じですが並び順が違います（web/app/lib/games.ts 冒頭の規約）。"
  fi
  echo
  echo "過去の同じ食い違い: #156（8→10・本番404が3日間）・#296（10→12）"
} >&2
exit 1
