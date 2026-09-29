#!/usr/bin/env bash
# 依存関係の版を固定する（#1579）。
#
# GameCollection.xcodeproj/ は .gitignore で丸ごと除外され、xcodegen generate のたびに作り直される。
# Package.resolved はその中に置かれるため git の管理外で、ビルドのたびに「from: の範囲の最新版」へ
# 解決し直されていた（v1.1.5 が Firebase 12.19.0 で出荷された原因）。
# 版の正典は Config/Package.resolved（git 管理）。xcodegen generate の直後に本スクリプトで
# Xcode が読む場所へ置くと、同じコミットからのビルドは常に同じ版になる。
#
# 依存の版を上げるとき: project.yml を直して xcodegen generate → 本スクリプトを走らせずに
#   xcodebuild -resolvePackageDependencies -project GameCollection.xcodeproj -scheme GameCollection
# を実行し、生成された Package.resolved を Config/Package.resolved へ上書きコピーして PR に含める。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Config/Package.resolved"
DEST_DIR="$ROOT/GameCollection.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"

[ -f "$SRC" ] || { echo "Config/Package.resolved が見つかりません: $SRC" >&2; exit 1; }
[ -d "$ROOT/GameCollection.xcodeproj" ] || { echo "先に xcodegen generate を実行してください" >&2; exit 1; }

mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST_DIR/Package.resolved"
echo "Package.resolved を固定版で配置しました: $DEST_DIR/Package.resolved"
