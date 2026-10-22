#!/usr/bin/env python3
"""ハブの絵タイル（#1831・#2175）を、モック（docs/design/hub-redesign-1831）の見た目そのままで書き出す。AI 不使用。

会長指示（#2175「画像で良いからちゃんとしてくれ」）により、タイルはモックのタイル絵に、モックの CSS
（01-picture-tiles.html の `.tile .name` / `.tile .ul` / `.badge.trial`）でゲーム名・下線を重ねた**1 枚の画像**にする。
Chrome のヘッドレスでモックと同じ HTML を 179×215pt @3x で描くので、文字の書体・太さ・影もモックと同じになる。

- モックにタイル絵があるゲームは、その PNG をそのまま使う（`--mock` で場所を渡す。既定は origin/main の
  `docs/design/hub-redesign-1831/hub-redesign/assets/tiles`）。
- 荷物運びパズルはモックの絵が旧仕様の荷物なので、現行のゲーム内の荷物（`OjisanLuggage_*`）とおじさんの顔
  （`OjisanFace_cheer`）でモックと同じ作り（tiles/tile_art.py の方式）で描き直す。ぱっと暗算はモックに絵が無いので同じ方式で描く。
- ブラックジャック・ポーカーは、モックの HTML（タイル絵と同じ場所の `<id>.html`）から**カジノチップ（`.chip`）を外して**
  描き直す（#2552。審査で疑似ギャンブルと見られないよう、賭けを思わせる絵を出さない）。札・下地・配置はモックのまま。
- 花札こいこいはモックの絵が旧仕様の札なので、ゲーム内の札の画像（#2188 の `Hanafuda_NN.png`）で描き直す（#2273）。
  左下・右下は「続きから」「NEW」が重なるので、文字や吹き出しは入れない。
- おじさんちのねこさがし（#2250）はモックに絵が無いので `art_html` で描く（案 a6b・会長決裁 2026-10-22）。猫の顔は
  main の `docs/design/cat-puzzle-2250/assets/cats`（ゲーム内の `Resources/Cats` より高解像度）、前足・尻尾は同じ場所の
  `hub-tile/parts`。release ブランチには docs が無いので、main から取り出して `--cat-art` で渡す。
- 柵越えおじさんはモックの絵（おじさんの顔が上に切れる）ではなく、横長タイル（#2273・廃止 #2566）と同じ会長提供の
  正方形の絵（main の `docs/design/homerun/hub-tile/source.png`・ロゴ無し）から、**顔がはっきり見える構図**で
  切り抜く（#2572）。release ブランチには docs が無いので、main から取り出して `--hero` で渡す。

使い方:
  git archive origin/main docs/design/hub-redesign-1831 | tar -x -C /tmp/mock
  python3 Scripts/generate-hub-tiles.py --mock /tmp/mock/docs/design/hub-redesign-1831/hub-redesign/assets/tiles
出力: App/Assets.xcassets/HubTiles/
  hubtile-<id>.imageset  … 名前・下線入りのタイル（537×645）
  hubthumb-<id>.imageset … 「つづき・最近」の小さいアイコン用（名前なしの絵を正方形に切り抜き・120×120）
  hubtile-<id>-en.imageset … 英語のゲーム名入り（#2181。アプリ内の言語設定で切り替える）
一部だけ書き直すとき（ほかのアセットは消さない・モック不要）:
  python3 Scripts/generate-hub-tiles.py --only anzan
柵越えおじさんだけ書き直すとき（元絵は main の docs から取り出して渡す。取り出し方は hub-tile/README.md）:
  python3 Scripts/generate-hub-tiles.py --only homerun --hero /tmp/mock/docs/design/homerun/hub-tile/source.png
おじさんちのねこさがしだけ書き直すとき（猫の高解像度の絵と前足・尻尾の部品は main の docs にあるので取り出して渡す）:
  git archive origin/main docs/design/cat-puzzle-2250 | tar -x -C /tmp/mock
  python3 Scripts/generate-hub-tiles.py --only catpuzzle --cat-art /tmp/mock/docs/design/cat-puzzle-2250
英語版だけ書き直すとき（日本語版は消さない）:
  python3 Scripts/generate-hub-tiles.py --lang en --mock <上と同じ場所>
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "App/Assets.xcassets/HubTiles")
CORE_RES = os.path.join(ROOT, "Packages/GameKit/Sources/Core/Resources")
PUZZLE_RES = os.path.join(ROOT, "Packages/GameKit/Sources/GameOjisanPuzzle/Resources")
HANAFUDA_CARDS = os.path.join(ROOT, "Packages/GameKit/Sources/GameHanafuda/Resources/Cards")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 179, 215

# ゲーム名と下線の色。名前と色はモック（01-picture-tiles.html）どおり。HubView の `HubTileStyle.accentHex` と同じ表。
CORAL, TEAL, PURPLE, YELLOW, PINK = "#FF6F61", "#22C3BE", "#8C7BE0", "#FFC24B", "#FF8FB1"
GAMES = {
    "homerun": ("柵越えおじさん", PURPLE),
    "poker": ("ポーカー", CORAL),
    "solitaire": ("ソリティア", TEAL),
    "runner": ("チャリンコおじさん", PURPLE),
    "mahjong4": ("麻雀", YELLOW),
    "sudoku": ("ナンプレ", PINK),
    "othello": ("オセロ", CORAL),
    "2048": ("2048", TEAL),
    "shogi": ("将棋", PURPLE),
    "shiritori": ("カードしりとり", YELLOW),
    "daifugo": ("大富豪", PINK),
    "gomoku": ("五目並べ", CORAL),
    "minesweeper": ("マインスイーパー", TEAL),
    "spider": ("スパイダーソリティア", PURPLE),
    "blackjack": ("ブラックジャック", YELLOW),
    "mahjong": ("麻雀ソリティア", PINK),
    "hanafuda": ("花札こいこい", CORAL),
    "go": ("囲碁", TEAL),
    "blocks": ("ブロック崩し", PURPLE),
    "concentration": ("神経衰弱", YELLOW),
    "chess": ("チェス", PINK),
    "freecell": ("フリーセル", CORAL),
    "fifteen": ("15パズル", TEAL),
    "ojisanpuzzle": ("おじさんの荷物運びパズル", YELLOW),
    "anzan": ("ぱっと暗算", CORAL),
    # 企画倉庫から v1.1.13 でハブに出した 3 本（#2384）。モックに絵が無いので `art_html` で描く。
    "colorrelay": ("いろリレー", PURPLE),
    "fruits": ("おじさんの盆栽", TEAL),
    "dicecombo": ("サイコロ役づくり", PINK),
    # 企画倉庫から v1.1.14 でハブに出した 1 本（#2250・会長決裁 2026-10-22）。橙の下地に映える青緑の下線（隣に並ぶ柵越えおじさんの紫と分ける）。
    "catpuzzle": ("おじさんちのねこさがし", TEAL),
}
# 英語のゲーム名（#2181）。各ゲームの String Catalog（`Resources/Localization/Localizable.xcstrings`）の訳と同じ
# （#2166〜#2169）。食い違いは `check_english_names` が書き出しの前に止める。2048 は訳さない（タイトルを直書き）、
# 大富豪は表のキーが身分の「大富豪」と重なるため `daifugoGameName()` に直書き（GameDaifugo/Localization.swift）。
GAMES_EN = {
    "homerun": "Sakugoe Ojisan",
    "poker": "Poker",
    "solitaire": "Solitaire",
    "runner": "Charinko Ojisan",
    "mahjong4": "Mahjong",
    "sudoku": "Number Place",
    "othello": "Osero",
    "2048": "2048",
    "shogi": "Shogi",
    "shiritori": "Card Shiritori",
    "daifugo": "Daifugo",
    "gomoku": "Gomoku",
    "minesweeper": "Minesweeper",
    "spider": "Spider Solitaire",
    "blackjack": "Blackjack",
    "mahjong": "Mahjong Solitaire",
    "hanafuda": "Hanafuda Koi-Koi",
    "go": "Go",
    "blocks": "Block Breaker",
    "concentration": "Memory Match",
    "chess": "Chess",
    "freecell": "FreeCell",
    "fifteen": "15 Puzzle",
    "ojisanpuzzle": "Ojisan's Box Puzzle",
    "anzan": "Quick Mental Math",
    "colorrelay": "Color Relay",
    "fruits": "Ojisan no Bonsai",
    "dicecombo": "Dice Combos",
    "catpuzzle": "Ojisan's Hidden Cats",
}
# String Catalog を引かずに上の表で持つゲーム（理由は上）。
EN_NOT_IN_CATALOG = {"2048", "daifugo"}
SOURCES = os.path.join(ROOT, "Packages/GameKit/Sources")


def check_english_names():
    """GAMES_EN が各ゲームの String Catalog の訳（日本語の名前 → en）と一致することを確かめる。"""
    import glob
    import re
    catalogs = {}
    for module in glob.glob(os.path.join(SOURCES, "Game*")):
        path = os.path.join(module, "Resources/Localization/Localizable.xcstrings")
        if not os.path.exists(path):
            continue
        with open(path) as f:
            for key, entry in json.load(f)["strings"].items():
                en = entry.get("localizations", {}).get("en", {}).get("stringUnit", {}).get("value")
                if en:
                    catalogs.setdefault(key, set()).add(en)
    for gid, (name, _) in GAMES.items():
        if gid in EN_NOT_IN_CATALOG:
            continue
        found = catalogs.get(name, set())
        assert GAMES_EN[gid] in found, f"{gid}: 英語名 {GAMES_EN[gid]!r} が String Catalog の訳 {sorted(found)} と違う"
    assert set(GAMES_EN) == set(GAMES), "GAMES と GAMES_EN のゲームが揃っていない"


def asset_name(base, lang):
    """日本語は従来どおりの名前、英語は末尾に `-en`（アプリの `HubTileStyle` と同じ規則）。"""
    return base if lang == "ja" else f"{base}-en"


# モックの絵を使わず描き直すゲーム（上の docstring 参照）。倉庫から出した 3 本（#2384）はモックに絵が無いので、
# ゲーム内の部品（いろリレーの札・盆栽の絵と縁側のおじさん・サイコロ）を同じ方式で組む。
REDRAWN = {"ojisanpuzzle", "anzan", "hanafuda", "colorrelay", "fruits", "dicecombo", "catpuzzle"}
FRUITS_RES = os.path.join(ROOT, "Packages/GameKit/Sources/GameFruits/Resources")

# モックの HTML からカジノチップを外して描くゲーム（#2552）。モックの PNG ではなく、隣の `<id>.html` を描く。
CHIPLESS = {"blackjack", "poker"}
CHIP_DIV = re.compile(r'<div class="chip"[^>]*></div>')


def chipless_html(mock_dir, gid):
    """モックのタイル絵の HTML から `.chip` の要素を取り除いたもの。チップが 1 枚も無ければ止める（モックが変わった合図）。"""
    with open(os.path.join(mock_dir, f"{gid}.html"), encoding="utf-8") as f:
        html = f.read()
    stripped, count = CHIP_DIV.subn("", html)
    assert count > 0, f"{gid}.html にチップの要素が見つからない"
    return stripped

# モックの tiles/tile_art.py と同じ下地の CSS（必要な部品だけ）。
ART_CSS = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:179px;height:215px;overflow:hidden}
body{font-family:"SF Pro Rounded",".SF NS Rounded","Hiragino Sans",sans-serif;-webkit-font-smoothing:antialiased}
.bg{position:absolute;inset:0}
.o{position:absolute;filter:drop-shadow(0 6px 6px rgba(0,0,0,.28))}
.px{image-rendering:pixelated}
.cell{position:absolute;width:52px;height:52px;border-radius:8px;display:flex;align-items:center;justify-content:center;font-weight:900;font-size:30px;box-shadow:0 6px 8px rgba(0,0,0,.28)}
.num{position:absolute;font-weight:900;color:#fff;text-shadow:0 4px 6px rgba(0,0,0,.25)}
.fuda{position:absolute;width:58px;height:87px;border-radius:7px;border:2.5px solid #FAF6EC;overflow:hidden;box-shadow:0 6px 8px rgba(0,0,0,.32)}
.fuda img{display:block;width:100%;height:100%;object-fit:cover}
.rc{position:absolute;width:58px;height:82px;border-radius:10px;border:3px solid #fff;box-shadow:0 6px 8px rgba(0,0,0,.28)}
.rc .win{position:absolute;left:9px;right:9px;top:17px;bottom:17px;border-radius:8px;background:#fff;display:flex;align-items:center;justify-content:center;font-weight:900;font-size:32px;line-height:1}
.rc .mk{position:absolute;left:5px;top:3px;font-weight:900;font-size:11px;line-height:1;color:#fff}
.chip{position:absolute;width:46px;height:46px;border-radius:50%;border:5px dashed #fff;box-shadow:0 5px 6px rgba(0,0,0,.3)}
.die{position:absolute;width:54px;height:54px;border-radius:12px;background:#fff;box-shadow:0 6px 8px rgba(0,0,0,.28)}
.die i{position:absolute;border-radius:50%;background:#2B2624;transform:translate(-50%,-50%)}
.pill{position:absolute;padding:3px 10px;border-radius:999px;background:#fff;font-weight:900;font-size:13px;box-shadow:0 4px 6px rgba(0,0,0,.25)}
"""


def img(path, x, y, w, rot=0):
    return f'<img class="o px" src="file://{path}" style="left:{x}px;top:{y}px;width:{w}px;transform:rotate({rot}deg);">'


# ---- おじさんちのねこさがし（#2250）の絵（案 a6b）: 家の間取り（3×3）の上辺の真ん中の裏から猫が顔を出す ----
# 間取りの床の色は `CatPuzzleHouse.rooms` のライトの床色（居間・押し入れ・寝室・書斎・お風呂・台所・玄関・縁側）。
CAT_ART = os.path.join(ROOT, "docs/design/cat-puzzle-2250")
CAT_ROOM_TINT = ["#DDE49C", "#F1D9AE", "#FFC4CE", "#C9BFF4", "#A9E2EE", "#FFCF8A", "#D5CBBB", "#E6B274"]
CAT_ROOM_FLOOR = ["tatami", "planks", "carpet", "planks", "tile", "tile", "stone", "planks"]
CAT_INK = "#4A3B33"
CAT_ROOMS = [[0, 0, 2], [1, 1, 2], [1, 5, 5]]


def cat_png(name):
    return os.path.join(CAT_ART, "assets/cats", f"{name}.png")


def cat_part(name):
    return os.path.join(CAT_ART, "hub-tile/parts", f"{name}.png")


def cat_floor_pattern(kind, s):
    a = "rgba(74,59,51,.09)"
    if kind == "tatami":
        return f"repeating-linear-gradient(180deg,transparent 0 {s/5-0.8:.1f}px,{a} {s/5-0.8:.1f}px {s/5:.1f}px)"
    if kind == "planks":
        return f"repeating-linear-gradient(90deg,transparent 0 {s/3-0.8:.1f}px,{a} {s/3-0.8:.1f}px {s/3:.1f}px)"
    if kind == "carpet":
        return f"radial-gradient({a} 0.8px,transparent 1px) 0 0/{s/4:.1f}px {s/4:.1f}px"
    if kind == "stone":
        return f"radial-gradient(circle at 50% 50%,rgba(255,255,255,.35) {s*0.3:.1f}px,transparent {s*0.33:.1f}px)"
    return "none"


def cat_board(rooms, s, x, y, rot, marks=(), extra="", z=1):
    """間取りの盤。部屋の境は太い墨の壁、マスの区切りは細い線、外側は墨と白の二重の縁。extra は盤の座標の家具。"""
    rows, cols = len(rooms), len(rooms[0])
    cells = ""
    for r in range(rows):
        for c in range(cols):
            k = rooms[r][c]
            tint, fl = CAT_ROOM_TINT[k % 8], CAT_ROOM_FLOOR[k % 8]
            face = ""
            if fl == "tile":
                i = s * 0.07
                face = (f'<div style="position:absolute;left:{i:.1f}px;top:{i:.1f}px;right:{i:.1f}px;bottom:{i:.1f}px;'
                        f'border-radius:{s*0.04:.1f}px;background:rgba(255,255,255,.3)"></div>')
            cells += (f'<div style="position:absolute;left:{c*s}px;top:{r*s}px;width:{s}px;height:{s}px;background:{tint};'
                      f'background-image:{cat_floor_pattern(fl, s)};box-shadow:inset 0 0 0 0.6px rgba(74,59,51,.3)">{face}</div>')
    walls = ""
    wt = max(2.2, s * 0.09)
    for r in range(rows):
        for c in range(cols):
            if c + 1 < cols and rooms[r][c] != rooms[r][c + 1]:
                walls += f'<div style="position:absolute;left:{(c+1)*s - wt/2:.1f}px;top:{r*s}px;width:{wt:.1f}px;height:{s}px;background:{CAT_INK}"></div>'
            if r + 1 < rows and rooms[r][c] != rooms[r + 1][c]:
                walls += f'<div style="position:absolute;left:{c*s}px;top:{(r+1)*s - wt/2:.1f}px;width:{s}px;height:{wt:.1f}px;background:{CAT_INK}"></div>'
    xs = "".join(f'<div style="position:absolute;left:{c*s}px;top:{r*s}px;width:{s}px;height:{s}px;display:flex;align-items:center;'
                 f'justify-content:center;font-weight:900;font-size:{s*0.78:.0f}px;line-height:1;color:{CAT_INK};'
                 f'text-shadow:0 0 3px #fff,0 0 2px #fff;font-family:\'SF Pro Rounded\',\'Hiragino Sans\',sans-serif">×</div>'
                 for (r, c) in marks)
    ow = wt * 1.5
    return (f'<div style="position:absolute;left:{x}px;top:{y}px;width:{cols*s}px;height:{rows*s}px;transform:rotate({rot}deg) scale(1.0);'
            f'transform-origin:center;z-index:{z};border-radius:6px;background:#fff;'
            f'box-shadow:0 0 0 {ow:.1f}px {CAT_INK},0 0 0 {ow+5:.1f}px #fff,0 8px 10px {ow+5:.1f}px rgba(0,0,0,.28)">'
            f'<div style="position:absolute;inset:0;overflow:hidden;border-radius:4px">{cells}{walls}{xs}{extra}</div></div>')


def cat_kotatsu(r, c, s):
    """こたつ。布団の下から尻尾が下に出ている（付け根は布団の下に隠す）。"""
    x, y = c * s, r * s
    tw = s * 0.42
    th = tw * 141 / 99
    return (f'<img src="file://{cat_part("tail-v")}" style="position:absolute;left:{x + s*0.5:.1f}px;top:{y + s*1.28 - th:.1f}px;'
            f'width:{tw:.1f}px;z-index:2;filter:drop-shadow(0 1px 1px rgba(0,0,0,.25))">'
            f'<div style="position:absolute;left:{x + s*0.08:.1f}px;top:{y + s*0.12:.1f}px;width:{s*0.84:.1f}px;height:{s*0.8:.1f}px;'
            f'border-radius:{s*0.16:.1f}px;background:#E8684F;z-index:3;'
            f'background-image:radial-gradient(rgba(255,255,255,.55) {s*0.045:.1f}px,transparent {s*0.055:.1f}px);background-size:{s*0.2:.1f}px {s*0.2:.1f}px;'
            f'box-shadow:0 2px 2px rgba(0,0,0,.25)"></div>'
            f'<div style="position:absolute;left:{x + s*0.24:.1f}px;top:{y + s*0.28:.1f}px;width:{s*0.52:.1f}px;height:{s*0.46:.1f}px;'
            f'border-radius:{s*0.08:.1f}px;background:#8F5F3C;z-index:4;box-shadow:inset 0 0 0 1.2px #6B4428"></div>')


def cat_box(r, c, s, peek=0.5):
    """段ボール箱。箱のふちの上に耳と目だけ出す（peek は顔の出具合）。"""
    x, y = c * s, r * s
    fw = s * 0.9
    im = Image.open(cat_png("face_normal"))
    fh = fw * im.height / im.width
    rim = y + s * 0.5
    return (f'<div style="position:absolute;left:{x + s*0.1:.1f}px;top:{y + s*0.2:.1f}px;width:{s*0.8:.1f}px;height:{s*0.34:.1f}px;'
            f'background:#B8925F;z-index:2;border-radius:2px"></div>'
            f'<img src="file://{cat_png("face_normal")}" style="position:absolute;left:{x + s*0.05:.1f}px;top:{rim - fh*peek:.1f}px;'
            f'width:{fw:.1f}px;z-index:3;filter:drop-shadow(0 1px 1px rgba(0,0,0,.25))">'
            f'<div style="position:absolute;left:{x + s*0.06:.1f}px;top:{rim:.1f}px;width:{s*0.88:.1f}px;height:{s*0.46:.1f}px;'
            f'background:#D3AC77;z-index:4;border-radius:2px;box-shadow:inset 0 0 0 1.2px #9D7444,0 2px 2px rgba(0,0,0,.25)">'
            f'<div style="position:absolute;left:38%;top:0;width:24%;height:100%;background:rgba(255,255,255,.35)"></div></div>'
            f'<div style="position:absolute;left:{x + s*0.02:.1f}px;top:{rim - s*0.06:.1f}px;width:{s*0.96:.1f}px;height:{s*0.1:.1f}px;'
            f'background:#C49A62;z-index:5;border-radius:1.5px;box-shadow:inset 0 0 0 1px #9D7444"></div>')


def cat_fusuma(r, c, s, gap=0.34):
    """押し入れのふすま。少し開いた隙間から顔がのぞく（gap は隙間の幅の割合）。"""
    x, y = c * s, r * s
    gx = x + s * 0.5 - s * gap / 2
    fw = s * 0.9
    im = Image.open(cat_png("face_normal"))
    fh = fw * im.height / im.width
    door = lambda l, w: (f'<div style="position:absolute;left:{l:.1f}px;top:{y + s*0.1:.1f}px;width:{w:.1f}px;height:{s*0.8:.1f}px;'
                         f'background:#F4ECD9;z-index:4;box-shadow:inset 0 0 0 1.2px #8B6A45;'
                         f'background-image:linear-gradient(90deg,transparent 0 30%,rgba(139,106,69,.25) 30% 31%,transparent 31%)"></div>')
    return (f'<div style="position:absolute;left:{x + s*0.04:.1f}px;top:{y + s*0.06:.1f}px;width:{s*0.92:.1f}px;height:{s*0.88:.1f}px;'
            f'background:#8B6A45;z-index:2;border-radius:2px;box-shadow:0 2px 2px rgba(0,0,0,.25)"></div>'
            f'<div style="position:absolute;left:{x + s*0.08:.1f}px;top:{y + s*0.1:.1f}px;width:{s*0.84:.1f}px;height:{s*0.8:.1f}px;'
            f'background:#2E2521;z-index:3;overflow:hidden">'
            f'<img src="file://{cat_png("face_normal")}" style="position:absolute;left:{s*0.5 - s*0.08 - fw*0.52:.1f}px;top:{s*0.42 - fh*0.45:.1f}px;width:{fw:.1f}px"></div>'
            + door(x + s * 0.08, gx - (x + s * 0.08)) + door(gx + s * gap, x + s * 0.92 - (gx + s * gap)))


def cat_board_top(y, s, x, rot=-8):
    """3×3 の盤（左上 x, y・一辺 3s・回転 rot）の上辺の y を、x から求める関数（translateY 前の座標）。"""
    import math
    n = 3 * s
    cx, cy = x + n / 2, y + n / 2
    t = math.radians(rot)
    pt = lambda dx, dy: (cx + dx * math.cos(t) - dy * math.sin(t), cy + dx * math.sin(t) + dy * math.cos(t))
    tl, tr = pt(-n / 2, -n / 2), pt(n / 2, -n / 2)
    return lambda px: tl[1] + (tr[1] - tl[1]) * (px - tl[0]) / (tr[0] - tl[0])


def cat_art_body():
    """案 a6b「上辺の真ん中から顔をしっかり」: 盤（右寄せ）の上辺の真ん中の裏から、鼻・口元まで顔を出し、
    前足をほほの下で左右に掛ける。盤の中は こたつ（尻尾）・段ボール（耳と目）・ふすま（隙間から両目）と × 。"""
    s, bx, by = 34, 40, 74
    extra = cat_kotatsu(0, 1, s) + cat_box(1, 2, s) + cat_fusuma(1, 0, s)
    board = cat_board(CAT_ROOMS, s, bx, by, -8, marks=[(0, 0), (0, 2), (2, 1)], extra=extra)
    fw, cx, face_top = 76, 98, 6
    rim = cat_board_top(by, s, bx)(cx) - 10  # 墨の外枠 5px + 白い縁 5px
    face = (f'<img class="o" src="file://{cat_png("face_normal")}" '
            f'style="left:{cx - fw / 2}px;top:{face_top}px;width:{fw}px;transform:rotate(-8deg);z-index:0;">')
    pw, gap = 20, 9
    ptop = rim + 6 - pw * 41 / 52  # 指先が白い縁に 6px かかる高さ
    paw = lambda part, x: (f'<img src="file://{cat_part(part)}" style="position:absolute;left:{x}px;top:{ptop}px;width:{pw}px;'
                           f'transform:rotate(-8deg);z-index:5;filter:drop-shadow(0 1px 1px rgba(0,0,0,.3))">')
    return board + face + paw("paw", cx - gap / 2 - pw) + paw("paw-r", cx + gap / 2)


def art_html(gid):
    if gid == "ojisanpuzzle":
        # モックの ojisanpuzzle と同じ配置で、荷物を現行の 5 種・おじさんを現行の顔に差し替える。
        lug = lambda n: os.path.join(PUZZLE_RES, n)
        bg = "linear-gradient(180deg,#CDE7F7 0%,#E8F2F8 55%,#D9D2C6 55%,#C4B9A8 100%)"
        body = (img(lug("OjisanLuggage_5_beercase.png"), 14, 122, 56, 0)
                + img(lug("OjisanLuggage_3_coolerbox.png"), 68, 124, 56, 0)
                + img(lug("OjisanLuggage_4_polytank.png"), 120, 126, 52, 0)
                + img(lug("OjisanLuggage_2_suika.png"), 42, 74, 56, -6)
                + img(lug("OjisanLuggage_1_zabuton.png"), 98, 78, 54, 6)
                + img(os.path.join(CORE_RES, "OjisanFace_cheer.png"), 110, 8, 60, 8))
    elif gid == "anzan":
        bg = "linear-gradient(160deg,#FFB59A 0%,#FF7F66 55%,#E85C45 100%)"
        cells = [(12, 70, "7", -10, "#fff", "#E85C45"), (64, 60, "+", 4, "#FFC24B", "#4A3B33"),
                 (114, 72, "5", 10, "#fff", "#E85C45"), (34, 132, "=", -6, "#FFC24B", "#4A3B33")]
        body = "".join(f'<div class="cell" style="left:{x}px;top:{y}px;transform:rotate({r}deg);background:{b};color:{c}">{t}</div>'
                       for x, y, t, r, b, c in cells)
        body += ('<div class="cell" style="left:90px;top:124px;width:68px;height:62px;font-size:34px;transform:rotate(8deg);'
                 'background:#fff;color:#4A3B33;border:3px solid #4A3B33">12</div>'
                 '<div style="position:absolute;left:96px;top:14px;padding:3px 10px;border-radius:999px;background:#fff;color:#E85C45;'
                 'font-weight:900;font-size:13px;box-shadow:0 4px 6px rgba(0,0,0,.25);transform:rotate(8deg)">ぱっと！</div>')
    elif gid == "hanafuda":
        # モックと同じ赤い下地に、ゲーム内の光札 3 枚（松に鶴・桜に幕・芒に月）を扇に並べる。モックの「こいこい！」の
        # 吹き出しは「続きから」に隠れるので入れない（#2273）。札はラベルの高さ（下 35pt）より上に収める。
        card = lambda i, x, y, r: (f'<div class="fuda" style="left:{x}px;top:{y}px;transform:rotate({r}deg)">'
                                   f'<img src="file://{os.path.join(HANAFUDA_CARDS, f"Hanafuda_{i:02d}.png")}"></div>')
        bg = "linear-gradient(160deg,#E57F72 0%,#B3382E 50%,#8E261E 100%)"
        body = card(0, 16, 46, -14) + card(28, 104, 46, 14) + card(8, 60, 36, 0)
    elif gid == "colorrelay":
        # ゲーム内の札（`ColorRelayCardView`: 白い角丸の枠 + 色の地 + 白い角丸の窓に大きな数字・記号）を 4 色ぶん
        # 扇に並べる（ポーカーのモックと同じ配置）。地の色は `Theme.Hex.Fill`、窓の文字色は `RelayColor.glyphHex`。
        rc = lambda x, y, r, fill, ink, text, mark: (
            f'<div class="rc" style="left:{x}px;top:{y}px;background:{fill};transform:rotate({r}deg)">'
            f'<div class="mk">{mark}</div><div class="win" style="color:{ink}">{text}</div></div>')
        bg = "linear-gradient(160deg,#5C6B8A 0%,#3A4766 50%,#2B354F 100%)"
        body = (rc(10, 92, -22, "#FF8A7E", "#C93D2E", "7", "7")
                + rc(44, 78, -8, "#22C3BE", "#167B78", "3", "3")
                + rc(80, 76, 8, "#B3A6F0", "#8C7BE0", "+2", "+2")
                + rc(116, 86, 22, "#FFC24B", "#976400", "9", "9")
                # 万能札の印（`FourColorMark`: 4 色の角丸を 2 × 2）を右上に 1 つ。
                + '<div class="o" style="left:120px;top:14px;width:44px;height:44px;transform:rotate(12deg);display:grid;'
                  'grid-template-columns:1fr 1fr;gap:3px;padding:4px;border-radius:10px;background:#fff">'
                + "".join(f'<div style="border-radius:4px;background:{c}"></div>' for c in ("#FF8A7E", "#22C3BE", "#FFC24B", "#B3A6F0"))
                + '</div>')
    elif gid == "fruits":
        # 縁側（`FruitsPalette.wood`）に立つおじさん（`BonsaiOjisan_hold`）と、庭（`FruitsPalette.box`）に落ちた盆栽
        # 3 鉢（ゲーム内の `Bonsai_*.png`）。ゲーム内と同じく上に危険線（白の点線）を引く。
        bz = lambda n, x, y, w: f'<img class="o" src="file://{os.path.join(FRUITS_RES, "Bonsai", n)}" style="left:{x}px;top:{y}px;width:{w}px">'
        bg = "linear-gradient(180deg,#CDE7F7 0%,#E3F0F8 30%,#EFE7D3 30%,#DCD0B6 100%)"
        # 縁側は名前の下（タイルの 56〜92pt）。おじさんは名前と重ならないよう右端に置く。
        body = ('<div style="position:absolute;left:0;right:0;top:32px;height:36px;background:#C89E6B;'
                'box-shadow:0 4px 6px rgba(0,0,0,.18)"></div>'
                '<div style="position:absolute;left:0;right:0;top:32px;height:36px;background:repeating-linear-gradient('
                '90deg,transparent 0 26px,#A87D4E 26px 28px)"></div>'
                '<div style="position:absolute;left:0;right:0;top:36px;height:2px;background:#D9B484"></div>'
                '<div style="position:absolute;left:0;right:0;top:70px;border-top:2.5px dashed rgba(255,255,255,.9)"></div>'
                # おじさんは鏡写しで左向きにし、差し出した手の先に持っている桜を置く。
                + f'<img class="o px" src="file://{os.path.join(FRUITS_RES, "BonsaiOjisan_hold.png")}" '
                  'style="left:134px;top:13px;width:42px;transform:scaleX(-1)">'
                + bz("Bonsai_01_sakura.png", 106, 30, 30)
                + bz("Bonsai_10_kuromatsu.png", -2, 78, 92)
                + bz("Bonsai_05_mikan.png", 100, 100, 66))
    elif gid == "dicecombo":
        # ゲーム内のサイコロ（`DiceComboDieFace`: 白い角丸・墨の目・1 だけ coral）を 4 つ散らし、役の名前のピル。
        pips = {1: [(.5, .5)], 3: [(.27, .27), (.5, .5), (.73, .73)],
                5: [(.27, .27), (.73, .27), (.5, .5), (.27, .73), (.73, .73)],
                6: [(.27, .27), (.73, .27), (.27, .5), (.73, .5), (.27, .73), (.73, .73)]}
        s = 50
        die = lambda v, x, y, r: (f'<div class="die" style="left:{x}px;top:{y}px;width:{s}px;height:{s}px;transform:rotate({r}deg)">'
                                  + "".join(f'<i style="left:{px * s:.1f}px;top:{py * s:.1f}px;width:{(13 if v == 1 else 9)}px;'
                                            f'height:{(13 if v == 1 else 9)}px;{"background:#FF6F61" if v == 1 else ""}"></i>'
                                            for px, py in pips[v]) + '</div>')
        bg = "linear-gradient(160deg,#6C7CC9 0%,#3F4F9E 50%,#2C3875 100%)"
        # フルハウス（5・5・5・1・1）。上の段に 3 つ、下の段に 2 つ。絵は日本語・英語で共通なので役の名前の文字は入れない。
        body = die(5, 8, 58, -10) + die(5, 64, 52, 4) + die(5, 120, 60, 12) + die(1, 34, 118, -6) + die(1, 96, 122, 8)
    elif gid == "catpuzzle":
        bg = "linear-gradient(160deg,#FFD98A 0%,#F7A94B 55%,#E88A2E 100%)"
        body = cat_art_body()
    else:
        raise KeyError(gid)
    # モックと同じく、名前を上に重ねるぶん物を 24pt 下げる。
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{ART_CSS}</style></head><body>'
            f'<div class="bg" style="background:{bg}"></div>'
            f'<div style="position:absolute;inset:0;transform:translateY(24px)">{body}</div></body></html>')


# モックの 01-picture-tiles.html の CSS（タイルの部分）。角丸と影はアプリ側で付けるので 0 にする。
TILE_CSS = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:179px;height:215px;overflow:hidden;background:#fff}
body{color:#4A3B33;font-family:"SF Pro Rounded",".SF NS Rounded","Hiragino Sans","Hiragino Kaku Gothic ProN",sans-serif;-webkit-font-smoothing:antialiased}
.tile{position:relative;width:179px;height:215px;overflow:hidden;background:#ddd}
.tile img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.tile .name{position:absolute;left:12px;right:12px;top:11px;font-size:19px;font-weight:900;line-height:1.15;color:#4A3B33;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;text-shadow:0 0 6px rgba(255,255,255,.9),0 0 2px rgba(255,255,255,.9)}
.tile .name.small{font-size:16px}
.tile .ul{position:absolute;left:12px;top:38px;width:44px;height:4px;border-radius:2px;box-shadow:0 0 4px rgba(255,255,255,.8)}
.badge{position:absolute;left:10px;bottom:10px;font-size:11px;font-weight:800;padding:4px 9px;border-radius:999px;background:rgba(255,255,255,.92)}
.badge.trial{background:#5B3FC4;color:#fff;border:2px solid #fff;box-shadow:0 2px 3px rgba(0,0,0,.35);font-size:12px}
"""

# モックで 16pt（`.name.small`）になっている名前は 8 文字以上。
# 荷物運びパズル・ねこさがし（11 文字）の名前はモックに無い長さなので、省略せずに入るよう縮める（`fit`）。
FIT = {"ojisanpuzzle", "catpuzzle"}


# 英語の名前は日本語より横に長い（#2181）。まず 1 行のまま 14px まで縮めて収め（日本語の長い名前と同じく 1 行・
# 絵とぶつからない）、それでも入らない名前だけ 19px で 2 行に折り返す（2 行に収まらなければさらに縮める）。
# 下線は名前の下に置き、1 行のときは日本語と同じ位置（top:38px）。
EN_FIT = ('<script>const n=document.querySelector(".name"),u=document.querySelector(".ul");'
          'const lh=()=>parseFloat(getComputedStyle(n).lineHeight);let s=19;n.style.whiteSpace="nowrap";'
          'while(n.scrollWidth>n.clientWidth&&s>14){s-=0.25;n.style.fontSize=s+"px";}'
          'if(n.scrollWidth>n.clientWidth){s=19;n.style.fontSize=s+"px";n.style.whiteSpace="normal";'
          'while((n.scrollHeight>lh()*2+1||n.scrollWidth>n.clientWidth)&&s>10){s-=0.25;n.style.fontSize=s+"px";}}'
          'u.style.top=Math.max(38,n.offsetTop+n.offsetHeight+5)+"px";</script>')
EN_CSS = ".tile .name.en{white-space:normal;overflow:visible;text-overflow:clip;overflow-wrap:normal}"


def tile_html(gid, art_path, lang="ja"):
    name, color = GAMES[gid]
    if lang == "en":
        name = GAMES_EN[gid]
    cls = "name small" if (lang == "ja" and len(name) >= 8) else "name"
    if lang == "en":
        cls += " en"
    extra = ""
    if gid == "homerun":
        # モックの柵越えおじさんだけ、名前の下に白い霞を敷く。モックの左下の「体験版」は会長指示で出さない（#2184）。
        extra_before = ('<div style="position:absolute;inset:0;background:linear-gradient(rgba(255,255,255,.88),'
                        'rgba(255,255,255,.55) 22%,rgba(255,255,255,0) 36%)"></div>')
    else:
        extra_before = ""
    fit = ""
    if lang == "en":
        fit = EN_FIT
    elif gid in FIT:
        fit = ('<script>const n=document.querySelector(".name");let s=16;'
               'while(n.scrollWidth>n.clientWidth&&s>10){s-=0.25;n.style.fontSize=s+"px";}</script>')
    css = TILE_CSS + (EN_CSS if lang == "en" else "")
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head><body>'
            f'<div class="tile"><img src="file://{art_path}">{extra_before}'
            f'<div class="{cls}">{name}</div><div class="ul" style="background:{color}"></div>{extra}</div>{fit}</body></html>')


# 柵越えおじさんの通常タイルの絵（#2572）。元絵は会長提供の正方形（1254×1254・ChatGPT で作成。原画と出所は main の
# docs/design/homerun/hub-tile/）。顔が主役になるよう、ヘルメットから胸までを幅いっぱいに切り抜く。
# - 左上のゲーム名（上 16% まで・白い霞は 36% まで）の下にヘルメットの頭頂（元絵の y≈130）が来るよう、頭頂をタイルの
#   高さの 20% に置く。元絵の上に空が足りない分（42px）は、上端の 60px を鏡写しで継ぎ足して補う（青空と雲なので継ぎ目は出ない）。
# - 左下の「イベント開催中」と残り回数のボール（2 段で下 32%）に顔が重ならないよう、あご（y≈470）はタイルの 60% より上。
# - 幅は顔の中心（x≈350）が真ん中に来る 716px（比率はタイルと同じ 179:215）。右にバットの握りと打球の光が少し入る。
HERO_ART = os.path.join(ROOT, "docs/design/homerun/hub-tile/source.png")
HOMERUN_TOP_PAD = 60
HOMERUN_CROP = (0, 18, 716, 878)  # 継ぎ足した後の座標（元絵では y = -42 〜 818）
# 「つづき・最近」のアイコン用。顔を中心にした正方形（元絵の座標）。
HOMERUN_THUMB_CROP = (120, 60, 595, 535)


def homerun_art(hero=HERO_ART):
    assert os.path.exists(hero), f"柵越えおじさんの元絵が無い: {hero}（--hero で渡す。使い方は先頭の説明）"
    src = Image.open(hero).convert("RGB")
    assert src.size == (1254, 1254), src.size
    padded = Image.new("RGB", (src.width, src.height + HOMERUN_TOP_PAD))
    padded.paste(src.crop((0, 0, src.width, HOMERUN_TOP_PAD)).transpose(Image.FLIP_TOP_BOTTOM), (0, 0))
    padded.paste(src, (0, HOMERUN_TOP_PAD))
    crop = padded.crop(HOMERUN_CROP)
    # 切り抜きの比率がタイルとずれていると object-fit:cover で意図しない所が切れるので確かめる。
    assert abs(crop.width / crop.height - W / H) < 0.01, crop.size
    return crop, src.crop(HOMERUN_THUMB_CROP)


def render(html, png, tmp, size=(W, H)):
    p = os.path.join(tmp, os.path.basename(png) + ".html")
    with open(p, "w") as f:
        f.write(html)
    # 書き出しの後、Chrome が終了処理の見張り（Teardown watchdog）で終了コード 2 を返すことがあるので、
    # 終了コードではなく PNG ができたかで判断する（できていなければ数回やり直す）。
    for _ in range(3):
        if os.path.exists(png):
            os.remove(png)
        r = subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files",
                            f"--window-size={size[0]},{size[1]}", "--force-device-scale-factor=3", f"--screenshot={png}", f"file://{p}"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=120)
        if os.path.exists(png):
            break
    else:
        raise RuntimeError(r.stderr.decode()[-2000:])
    im = Image.open(png)
    assert im.size == (size[0] * 3, size[1] * 3), (png, im.size)


def write_imageset(name, image):
    folder = os.path.join(OUT, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    image.convert("RGB").save(os.path.join(folder, f"{name}.png"), optimize=True)
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")


def main():
    global CAT_ART
    ap = argparse.ArgumentParser()
    ap.add_argument("--mock", help="モックのタイル絵の場所（hub-redesign/assets/tiles）。描き直すゲームだけなら不要")
    ap.add_argument("--keep", help="途中の PNG（名前なしの絵）を残す場所")
    ap.add_argument("--only", nargs="+", help="このゲームだけ書き直す（ほかのアセットは消さない）")
    ap.add_argument("--hero", default=HERO_ART, help="柵越えおじさんの元絵（既定は docs/design/homerun/hub-tile/source.png）")
    ap.add_argument("--cat-art", default=CAT_ART,
                    help="おじさんちのねこさがしの素材（main の docs/design/cat-puzzle-2250。既定はこのツリーの同じ場所）")
    ap.add_argument("--lang", nargs="+", choices=["ja", "en"], default=["ja", "en"],
                    help="書き出す言語（既定は両方）。1 つだけ指定したときはほかの言語のアセットを消さない")
    args = ap.parse_args()
    check_english_names()
    CAT_ART = args.cat_art
    if not args.only or "catpuzzle" in args.only:
        for path in (cat_png("face_normal"), cat_part("tail-v"), cat_part("paw"), cat_part("paw-r")):
            assert os.path.exists(path), f"ねこさがしの素材が無い: {path}（--cat-art で渡す。使い方は先頭の説明）"

    # 元絵の検証は出力先を消す前に済ませる（無い・サイズ違いのまま HubTiles を消して止まらないように。#2577）。検証済みの crop / thumb は後続で使い回す。
    homerun = homerun_art(args.hero) if not args.only or "homerun" in args.only else None

    if not args.only and len(args.lang) == 2:
        if os.path.isdir(OUT):
            shutil.rmtree(OUT)
        os.makedirs(OUT)
        with open(os.path.join(OUT, "Contents.json"), "w") as f:
            json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, f, indent=2)
            f.write("\n")

    with tempfile.TemporaryDirectory() as tmp:
        for gid in GAMES:
            if args.only and gid not in args.only:
                continue
            art = os.path.join(tmp, f"art-{gid}.png")
            thumb_art = None
            if gid == "homerun":
                crop, thumb_art = homerun
                crop.save(art)
            elif gid in REDRAWN:
                render(art_html(gid), art, tmp)
            elif gid in CHIPLESS:
                render(chipless_html(args.mock, gid), art, tmp)
            else:
                shutil.copy(os.path.join(args.mock, f"{gid}.png"), art)
            if args.keep:
                os.makedirs(args.keep, exist_ok=True)
                shutil.copy(art, os.path.join(args.keep, f"{gid}.png"))
            for lang in args.lang:
                tile = os.path.join(tmp, f"tile-{gid}-{lang}.png")
                render(tile_html(gid, art, lang), tile, tmp)
                write_imageset(asset_name(f"hubtile-{gid}", lang), Image.open(tile))
            if "ja" not in args.lang:
                print("tile", gid)
                continue
            # 「つづき・最近」のアイコン（名前なしなので言語で分けない）: モックの `object-fit:cover` と同じく中央を正方形に切る
            # （柵越えおじさんは顔を中心にした正方形・#2572）。
            a = thumb_art or Image.open(art).convert("RGB")
            side = min(a.size)
            left, top = (a.width - side) // 2, (a.height - side) // 2
            write_imageset(f"hubthumb-{gid}", a.crop((left, top, left + side, top + side)).resize((120, 120), Image.LANCZOS))
            print("tile", gid)


if __name__ == "__main__":
    main()
