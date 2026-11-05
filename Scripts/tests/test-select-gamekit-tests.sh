#!/bin/bash
# select-gamekit-tests.py の検証（#2953）。
#
# 守りたいのは「漏らさない」こと。選びすぎは CI が遅いだけだが、選び漏らすと壊れたまま main に入る。
# 実績のある（起こりうる）漏れ方を固定する:
#   - 共通の部品（Core）を変えたのに、それを使うゲームのテストが選ばれない（依存を逆にたどれていない）
#   - Sources を丸ごと走査するテスト（ThemeTests 型）が、無関係に見えるモジュールの変更で選ばれない
#   - `Sources/GameB/...` を名指しで読む走査テストが、import していない GameB の変更で選ばれない
#   - App/・Package.swift・CI の定義を変えたのに全部回らない
#   - テストを使うテストを依存とみなして、無関係なテストまで連鎖して選ぶ（選びすぎ）
#
# 使い方: bash Scripts/tests/test-select-gamekit-tests.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../select-gamekit-tests.py"
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  NG   - $1"; }

TMP="$(mktemp -d)"
trap 'rm -r -f "$TMP"' EXIT

# 検証用のパッケージ（Package.swift の dump-package 相当の JSON と、テストのソース）
ROOT="$TMP/repo"
PK="$ROOT/Packages/GameKit"
mkdir -p "$PK/Tests/ScanAllTests" "$PK/Tests/NamedScanTests" "$PK/Tests/GameATests" "$PK/Tests/GameBTests" \
         "$PK/Tests/CoreTests" "$PK/Tests/HelperUserTests" "$PK/Tests/GameKitTestSupport"
printf 'import GameA\n' >"$PK/Tests/GameATests/A.swift"
printf 'import GameB\n' >"$PK/Tests/GameBTests/B.swift"
printf 'import Core\n' >"$PK/Tests/CoreTests/C.swift"
printf 'import GameKitTestSupport\n' >"$PK/Tests/HelperUserTests/H.swift"
printf 'let r = SourceScan.packageRoot.appendingPathComponent("Sources")\nlet e = FileManager.default.enumerator(at: r)\n' >"$PK/Tests/ScanAllTests/S.swift"
printf 'let s = try SourceScan.packageSource("Sources/GameB/BView.swift")\n' >"$PK/Tests/NamedScanTests/N.swift"

python3 - "$TMP/pkg.json" <<'PY'
import json, sys
def dep(*n): return [{"byName": [x, None]} for x in n]
def t(name, ty, *deps): return {"name": name, "type": ty, "dependencies": dep(*deps), "path": None}
json.dump({"targets": [
    t("Core", "regular"), dict(t("GameKitTestSupport", "regular"), path="Tests/GameKitTestSupport"),
    t("GameA", "regular", "Core"), t("GameB", "regular", "Core"),
    t("CoreTests", "test", "Core"), t("GameATests", "test", "GameA"), t("GameBTests", "test", "GameB"),
    t("HelperUserTests", "test", "GameKitTestSupport"),
    t("ScanAllTests", "test", "Core", "GameKitTestSupport"),
    t("NamedScanTests", "test", "Core", "GameKitTestSupport"),
]}, open(sys.argv[1], "w"))
PY

pick() { printf '%s\n' "$@" | python3 "$TARGET" --root "$ROOT" --package-json "$TMP/pkg.json" 2>/dev/null; }

expect() { # 説明 期待値 変更ファイル...
  local label="$1" want="$2"; shift 2
  local got; got="$(pick "$@")"
  if [ "$got" = "$want" ]; then ok "$label"; else ng "$label（期待: $want / 実際: $got）"; fi
}

expect "ゲーム A のソースだけ: A のテスト + 全走査 (B を名指しで読むテストは選ばない)" \
  '^(GameATests|ScanAllTests)\.' "Packages/GameKit/Sources/GameA/AView.swift"
expect "ゲーム B のソース: B のテスト + 全走査 + B を名指しで読む走査テスト" \
  '^(GameBTests|NamedScanTests|ScanAllTests)\.' "Packages/GameKit/Sources/GameB/BView.swift"
expect "共通部品 Core: Core を使う全部" \
  '^(CoreTests|GameATests|GameBTests|NamedScanTests|ScanAllTests)\.' "Packages/GameKit/Sources/Core/X.swift"
expect "テストファイルだけ変えた: そのテストターゲット" \
  '^(GameATests)\.' "Packages/GameKit/Tests/GameATests/A.swift"
expect "テスト支援 (GameKitTestSupport): それを使うテスト" \
  '^(HelperUserTests|NamedScanTests|ScanAllTests)\.' "Packages/GameKit/Tests/GameKitTestSupport/SourceScan.swift"
expect "複数ターゲットの変更は和" \
  '^(GameATests|GameBTests|NamedScanTests|ScanAllTests)\.' "Packages/GameKit/Sources/GameA/a.swift" "Packages/GameKit/Sources/GameB/b.swift"
expect "リソースだけの変更も所属ターゲットで選ぶ" \
  '^(GameATests|ScanAllTests)\.' "Packages/GameKit/Sources/GameA/Resources/Localization/x.xcstrings"
expect "App/ の変更は全部" all "App/AppGameServices.swift"
expect "Config/ の変更は全部" all "Config/Package.resolved"
expect "project.yml の変更は全部" all "project.yml"
expect "Package.swift の変更は全部" all "Packages/GameKit/Package.swift"
expect "ターゲットに属さない Packages の変更は全部" all "Packages/GameKit/Sources/Unknown/x.swift"
expect "ci.yml の変更は全部" all ".github/workflows/ci.yml"
expect "この選別スクリプト自身の変更は全部" all "Scripts/select-gamekit-tests.py"
expect "docs だけの変更は none" none "docs/ai-devops.md"
expect "空の入力は none" none
expect "全部を要する変更が 1 件でも混ざれば全部" all "docs/x.md" "Packages/GameKit/Sources/GameA/a.swift" "App/x.swift"

# 実際のパッケージ（swift が使えるときだけ）。ゲームを足しても設定が要らないこと・別ゲームのテストを選ばないこと
if command -v swift >/dev/null 2>&1; then
  REAL="$SCRIPT_DIR/../.."
  got="$(echo "Packages/GameKit/Sources/GameHanoi/HanoiModel.swift" | python3 "$TARGET" --root "$REAL" 2>/dev/null)"
  case "$got" in *GameHanoiTests*) ok "実パッケージ: ハノイの変更でハノイのテストが選ばれる";; *) ng "実パッケージ: ハノイのテストが選ばれない（$got）";; esac
  case "$got" in *GameFifteenTests*|*GameShogiTests*) ng "実パッケージ: 無関係なゲームのテストまで選ばれた（$got）";; *) ok "実パッケージ: 無関係なゲームのテストは選ばれない";; esac
  got="$(echo "Packages/GameKit/Sources/Core/GameButtonStyle.swift" | python3 "$TARGET" --root "$REAL" 2>/dev/null)"
  case "$got" in *GameHanoiTests*GameShogiTests*) ok "実パッケージ: Core の変更で各ゲームのテストが選ばれる";; *) ng "実パッケージ: Core の変更でゲームのテストが選ばれない（$got）";; esac
else
  echo "  skip - 実パッケージの検証（swift が無い）"
fi

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
