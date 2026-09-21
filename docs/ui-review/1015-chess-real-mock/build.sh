#!/bin/bash
# 使い方: bash build.sh <作業ディレクトリ>  （macOS 上でビルドして比較画像を出す）
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../../../Packages/GameKit/Sources/GameChess"
WORK="${1:?作業ディレクトリを渡す}"
mkdir -p "$WORK"
# 本物の駒描画コードを使う（Core への依存だけ外す）
sed '/^import Core$/d' "$SRC/ChessPieceShapes.swift" >"$WORK/ChessPieceShapes.swift"
sed '/^import Core$/d' "$SRC/ChessPieceStyle.swift" >"$WORK/ChessPieceStyle.swift"
swiftc -swift-version 5 -O -o "$WORK/mock" \
  "$HERE/prelude.swift" "$HERE/RealMockProfiles.swift" "$HERE/RealMockA2D.swift" "$HERE/RealMockScene.swift" \
  "$WORK/ChessPieceShapes.swift" "$WORK/ChessPieceStyle.swift" "$HERE/main.swift"
"$WORK/mock" "$WORK/out"
