#!/bin/bash
# ハブに並ぶゲームの ID を 1 行 1 件で標準出力へ出す（自動QA当番 #2314 が全ゲームを起動するために使う）。
#
# ID は `App/AppGameServices.swift` の `GameRegistry([...])` に**コメントアウトされずに**並んでいる
# `XxxModule()` から、`Packages/GameKit/Sources/**/XxxModule.swift` の `public let id = "..."` を引いて作る。
# ドキュメントや当番側に ID の一覧を持たない設計（CLAUDE.md「解析イベント」）なので、実行時に毎回作る。
# 企画倉庫のゲームは registry の行がコメントアウトされているため、自然に除外される。
#
#   使い方: bash Scripts/list-game-ids.sh [リポジトリのルート]
#   終了コード: 0 = 1 件以上出力 / 1 = registry が読めない・ID を引けないモジュールがある
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
REG="$ROOT/App/AppGameServices.swift"
[ -f "$REG" ] || { echo "registry が見つかりません: $REG" >&2; exit 1; }

# `static let registry = GameRegistry([` から `])` までの、行頭がコメントでない Module 呼び出し
MODULES=$(awk '/static let registry = GameRegistry\(\[/{on=1; next} on && /^[[:space:]]*\]\)/{exit} on' "$REG" \
  | grep -E '^[[:space:]]*[A-Za-z0-9]+Module\(\),' | sed -E 's/^[[:space:]]*([A-Za-z0-9]+Module)\(\),.*/\1/')
[ -n "$MODULES" ] || { echo "registry からモジュールを読み取れませんでした" >&2; exit 1; }

rc=0
for m in $MODULES; do
  f=$(find "$ROOT/Packages/GameKit/Sources" -name "$m.swift" -type f | head -1)
  id=""
  [ -n "$f" ] && id=$(sed -nE 's/^[[:space:]]*public let id = "([^"]+)".*/\1/p' "$f" | head -1)
  if [ -z "$id" ]; then echo "ID を引けません: $m" >&2; rc=1; continue; fi
  echo "$id"
done
exit "$rc"
