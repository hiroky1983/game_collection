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
# ■ 何と比べるか
#   比較先は**同じツリー（既定は HEAD）の GameRegistry**。main の LP は main の registry
#   （= App Store で公開済みの集合・docs/ai-devops.md）と、release/vX.Y.Z の LP はその版の
#   registry と一致していなければならない。
#   かつての既定は「もっとも新しい release/vX.Y.Z」だったが、それは「LP を未リリース版へ先行させる」
#   ことを CI が強制する設計で、2026-08-27 の #299（v1.1.1 収録の麻雀・数独を含む 12本 LP が
#   アプリ公開前に本番 LP へ出た）の一因になった（2026-08-28 改定・会長指示）。
#   未リリースゲームの LP 変更は該当 release ブランチに積み、その版の公開時の main へのマージで
#   本番に出す（振り分け基準は Scripts/ai-duty-prompt.md / docs/ai-devops.md）。
#
#   同一ツリー比較になったので「他所のマージで緑だった PR が後から赤くなる」問題は無い。
#   実行は .github/workflows/lp-game-list.yml が games.ts / registry を触る変更に絞って走らせる。
#
# 使い方: Scripts/check-lp-game-list.sh [比較先の ref（省略時 HEAD）] [games.ts のパス]
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
  # 既定は同一ツリー（HEAD）の registry。LP と registry は同じブランチで一緒に動くのが
  # 新ルール（ヘッダ参照）なので、比較先を別の ref に探しに行かない。
  REF="HEAD"
  echo "check-lp-game-list: 比較先: HEAD（同一ツリーの registry）"
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

# 3. LP 側の slug を取り出す。`comingSoon: true` の付いたエントリ（「配信予定」表示・
#    未リリースゲーム）は registry 照合の対象外（2026-08-28 改定）。
#    games.ts の整形（エントリは2スペースの `{`、フィールドは4スペース）に依存する。
ACTUAL="$(awk '
  /^  \{/                     { slug = ""; soon = 0; next }
  /^    slug: "/              { s = $0; sub(/^    slug: "/, "", s); sub(/".*$/, "", s); slug = s; next }
  /^    comingSoon: true/     { soon = 1; next }
  /^  \},/                    { if (slug != "" && !soon) print slug }
' "$LIST")"

if [ -z "$ACTUAL" ]; then
  echo "check-lp-game-list: $LIST から slug を読み取れませんでした" >&2
  exit 1
fi

# 比較は**顔ぶれ（集合）**で行う。並び順の機械検証は、配信予定エントリの挟まりや
# バージョン間の登録順差で成立しなくなったため廃止した（並びはレビューで見る）。
MISSING="$(comm -23 <(printf '%s' "$EXPECTED" | sort) <(printf '%s' "$ACTUAL" | sort) | tr '\n' ' ')"
EXTRA="$(comm -13 <(printf '%s' "$EXPECTED" | sort) <(printf '%s' "$ACTUAL" | sort) | tr '\n' ' ')"

if [ -z "$MISSING" ] && [ -z "$EXTRA" ]; then
  echo "check-lp-game-list: OK（$REF の registry $(printf '%s\n' "$MODULES" | grep -c .)本と $(basename "$LIST") の配信済み分が一致）"
  exit 0
fi

{
  echo "check-lp-game-list: LP のゲーム一覧がアプリの登録と一致しません"
  echo
  echo "  アプリ（$REF の GameRegistry・登録順）:"
  printf '%s' "$EXPECTED" | sed 's/^/    /'
  echo "  LP（${LIST}・comingSoon を除く）:"
  printf '%s' "$ACTUAL" | sed 's/^/    /'
  echo
  [ -n "$MISSING" ] && echo "  LP に無い（= /games/<slug> が 404 になる）:$MISSING"
  [ -n "$EXTRA" ]   && echo "  アプリに無い（= 存在しないゲームを宣伝している。未リリースなら comingSoon: true を付ける）:$EXTRA"
  echo
  echo "過去の同じ食い違い: #156（8→10・本番404が3日間）・#296（10→12）・#299（未リリース12本 LP の先行公開）"
} >&2
exit 1
