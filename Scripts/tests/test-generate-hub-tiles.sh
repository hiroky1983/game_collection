#!/bin/bash
# generate-hub-tiles.py の検証（#2404）。
#
# 英語名の表（GAMES_EN）と各ゲームの String Catalog の食い違いを止める `check_english_names()` は、
# どの CI からも呼ばれていなかった。タイル周りの不具合（#2319・#2345）が続いたので、表と GAMES の整合を
# ここで機械的に検査する。画像の描画（Chrome・Pillow）は対象外。
#
# Pillow が無い環境（CI の素の python3）でも回せるよう、PIL は空のスタブに差し替えてから読み込む。
#
# 使い方: bash Scripts/tests/test-generate-hub-tiles.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../generate-hub-tiles.py"

TARGET="$TARGET" python3 - <<'PY'
import importlib.util
import os
import re
import sys
import types

pil = types.ModuleType("PIL")
pil.Image = types.ModuleType("PIL.Image")
sys.modules["PIL"] = pil
sys.modules["PIL.Image"] = pil.Image

spec = importlib.util.spec_from_file_location("generate_hub_tiles", os.environ["TARGET"])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

passed = failed = 0


def check(label, cond):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok   - {label}")
    else:
        failed += 1
        print(f"  NG   - {label}")


def raises_assertion(fn):
    try:
        fn()
    except (AssertionError, KeyError):  # 表の欠落は KeyError で落ちる（どちらも書き出しを止める）
        return True
    return False


# 現状のリポジトリで通ること
check("check_english_names が現状の表で通る", not raises_assertion(m.check_english_names))
check("GAMES と GAMES_EN のゲーム ID が一致する", set(m.GAMES) == set(m.GAMES_EN))
check("EN_NOT_IN_CATALOG は GAMES の部分集合", m.EN_NOT_IN_CATALOG <= set(m.GAMES))
check("REDRAWN は GAMES の部分集合", m.REDRAWN <= set(m.GAMES))
check("日本語名が重複しない", len({n for n, _ in m.GAMES.values()}) == len(m.GAMES))
check("英語名が重複しない", len(set(m.GAMES_EN.values())) == len(m.GAMES_EN))
check("下線の色が #RRGGBB 形式", all(re.fullmatch(r"#[0-9A-Fa-f]{6}", c) for _, c in m.GAMES.values()))
check("日本語名・英語名が空でない", all(n.strip() for n, _ in m.GAMES.values()) and all(v.strip() for v in m.GAMES_EN.values()))
check("asset_name: 日本語は名前そのまま", m.asset_name("hubtile-poker", "ja") == "hubtile-poker")
check("asset_name: 英語は末尾に -en", m.asset_name("hubtile-poker", "en") == "hubtile-poker-en")

# 食い違いを実際に検出すること（検出器が素通しになっていないことの確認）
orig_en = dict(m.GAMES_EN)
try:
    m.GAMES_EN["poker"] = "Poker Wrong"
    check("英語名が String Catalog と違えば検出する", raises_assertion(m.check_english_names))
finally:
    m.GAMES_EN.clear()
    m.GAMES_EN.update(orig_en)

try:
    del m.GAMES_EN["poker"]
    check("GAMES_EN にゲームが欠ければ検出する", raises_assertion(m.check_english_names))
finally:
    m.GAMES_EN.clear()
    m.GAMES_EN.update(orig_en)

orig_games = dict(m.GAMES)
try:
    m.GAMES["zzz-new"] = ("新ゲーム", "#000000")
    check("GAMES にゲームが増えて GAMES_EN に無ければ検出する", raises_assertion(m.check_english_names))
finally:
    m.GAMES.clear()
    m.GAMES.update(orig_games)

orig_ex = set(m.EN_NOT_IN_CATALOG)
try:
    m.EN_NOT_IN_CATALOG.discard("2048")
    m.GAMES_EN["2048"] = "Totally Different"
    check("EN_NOT_IN_CATALOG 外の 2048 は Catalog を引き、無ければ検出する", raises_assertion(m.check_english_names))
finally:
    m.EN_NOT_IN_CATALOG.update(orig_ex)
    m.GAMES_EN.clear()
    m.GAMES_EN.update(orig_en)

check("EN_NOT_IN_CATALOG のゲームは Catalog を引かず通る", not raises_assertion(m.check_english_names))

print(f"\n{passed} 件成功 / {failed} 件失敗")
sys.exit(1 if failed else 0)
PY
