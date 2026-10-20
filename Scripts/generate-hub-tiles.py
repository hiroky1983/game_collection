#!/usr/bin/env python3
"""ハブの絵タイル（#1831・#2175）を、モック（docs/design/hub-redesign-1831）の見た目そのままで書き出す。AI 不使用。

会長指示（#2175「画像で良いからちゃんとしてくれ」）により、タイルはモックのタイル絵に、モックの CSS
（01-picture-tiles.html の `.tile .name` / `.tile .ul` / `.badge.trial`）でゲーム名・下線を重ねた**1 枚の画像**にする。
Chrome のヘッドレスでモックと同じ HTML を 179×215pt @3x で描くので、文字の書体・太さ・影もモックと同じになる。

- モックにタイル絵があるゲームは、その PNG をそのまま使う（`--mock` で場所を渡す。既定は origin/main の
  `docs/design/hub-redesign-1831/hub-redesign/assets/tiles`）。
- 荷物運びパズルはモックの絵が旧仕様の荷物なので、現行のゲーム内の荷物（`OjisanLuggage_*`）とおじさんの顔
  （`OjisanFace_cheer`）でモックと同じ作り（tiles/tile_art.py の方式）で描き直す。ぱっと暗算はモックに絵が無いので同じ方式で描く。
- 花札こいこいはモックの絵が旧仕様の札なので、ゲーム内の札の画像（#2188 の `Hanafuda_NN.png`）で描き直す（#2273）。
  左下・右下は「続きから」「NEW」が重なるので、文字や吹き出しは入れない。

使い方:
  git archive origin/main docs/design/hub-redesign-1831 | tar -x -C /tmp/mock
  python3 Scripts/generate-hub-tiles.py --mock /tmp/mock/docs/design/hub-redesign-1831/hub-redesign/assets/tiles
出力: App/Assets.xcassets/HubTiles/
  hubtile-<id>.imageset  … 名前・下線入りのタイル（537×645）
  hubthumb-<id>.imageset … 「つづき・最近」の小さいアイコン用（名前なしの絵を正方形に切り抜き・120×120）
  hubtile-homerun-wide(-pad).imageset … 柵越えおじさんだけの横長タイル（#2184。iPhone 2 列ぶん／iPad 4 列ぶん）
  hubtile-<id>-en / hubtile-homerun-wide(-pad)-en.imageset … 英語のゲーム名入り（#2181。アプリ内の言語設定で切り替える）
一部だけ書き直すとき（ほかのアセットは消さない・モック不要）:
  python3 Scripts/generate-hub-tiles.py --only homerun-wide
柵越えおじさんの横長タイルの元絵は main の docs にある（release ブランチには docs が無いので取り出して --hero で渡す）:
  git archive origin/main docs/design/homerun/hub-tile | tar -x -C /tmp/mock
  python3 Scripts/generate-hub-tiles.py --only homerun-wide --hero /tmp/mock/docs/design/homerun/hub-tile/source.png
英語版だけ書き直すとき（日本語版は消さない）:
  python3 Scripts/generate-hub-tiles.py --lang en --mock <上と同じ場所>
"""
import argparse
import json
import os
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
REDRAWN = {"ojisanpuzzle", "anzan", "hanafuda", "colorrelay", "fruits", "dicecombo"}
FRUITS_RES = os.path.join(ROOT, "Packages/GameKit/Sources/GameFruits/Resources")

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
# 荷物運びパズルの名前はモックに無い長さなので、省略せずに入るよう縮める（`fit`）。
FIT = {"ojisanpuzzle"}


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


# 柵越えおじさんだけの横長タイル（#2184）。iPhone はグリッドの 2 列ぶん、iPad は 4 列ぶんの幅で、高さはふつうの
# タイルと同じ 215pt。絵は会長が用意したロゴ（文字）無しの正方形の絵（1254×1254・ChatGPT で作成。原画と出所は main の
# docs/design/homerun/hub-tile/）を切り抜いて使う（#2273。以前はロゴ入りの HomerunHubHeroArtLogo.jpg を切っていた）。
# 切り抜きは元画像の座標で、比率はタイルと同じ。「体験版」のバッジは出さない（会長指示・#2184）。
# 左上のゲーム名と右下の残り回数のボールに、おじさんの顔・ボールが重ならない位置で切る。
# iPhone 用は幅いっぱい・上端から（ヘルメットの頭頂が名前の下線の高さ。顔・バット・ボールがまるごと入り、右下は観客席）。
# iPad 用は横長すぎて正方形の絵の幅では背が足りず、名前がヘルメットに重なるので、絵の左端（ヘルメットより左の
# 150px・青空と照明塔）を鏡写しで 2 回継ぎ足して左へ 300px 広げ、名前をその上に置く。切り抜きは継ぎ足した後の座標（ボールは上が少し切れる）。
HERO_ART = os.path.join(ROOT, "docs/design/homerun/hub-tile/source.png")
WIDE_TILES = [
    # (アセット名, タイルの寸法 pt, 左に継ぎ足す幅 px, 切り抜き (left, top, right, bottom))
    ("hubtile-homerun-wide", (179 * 2 + 12, 215), 0, (0, 0, 1254, 729)),
    ("hubtile-homerun-wide-pad", (179 * 4 + 12 * 3, 215), 300, (0, 85, 1554, 529)),
]


def extend_left(src, pad):
    """絵の左端 150px（おじさんより左）を鏡写し・そのまま…と交互に `pad` px ぶん左へ継ぎ足す（継ぎ目が連続する）。"""
    strip = 150
    assert pad % strip == 0, pad
    out = Image.new("RGB", (src.width + pad, src.height))
    out.paste(src, (pad, 0))
    edge = src.crop((0, 0, strip, src.height))
    for i in range(pad // strip):
        piece = edge.transpose(Image.FLIP_LEFT_RIGHT) if i % 2 == 0 else edge
        out.paste(piece, (pad - strip * (i + 1), 0))
    return out


def wide_tile_html(art_path, size, lang="ja"):
    w, h = size
    name, color = GAMES["homerun"]
    if lang == "en":
        name = GAMES_EN["homerun"]
    css = TILE_CSS.replace("width:179px;height:215px", f"width:{w}px;height:{h}px")
    haze = ('<div style="position:absolute;inset:0;background:linear-gradient(rgba(255,255,255,.88),'
            'rgba(255,255,255,.55) 22%,rgba(255,255,255,0) 36%)"></div>')
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>{css}</style></head><body>'
            f'<div class="tile"><img src="file://{art_path}">{haze}'
            f'<div class="name">{name}</div><div class="ul" style="background:{color}"></div></div></body></html>')


def write_wide_tiles(tmp, langs, hero=HERO_ART):
    assert os.path.exists(hero), f"柵越えおじさんの元絵が無い: {hero}（--hero で渡す。使い方は先頭の説明）"
    src = Image.open(hero).convert("RGB")
    for (base, size, pad, box), lang in ((t, l) for t in WIDE_TILES for l in langs):
        asset = asset_name(base, lang)
        art = os.path.join(tmp, f"art-{asset}.png")
        crop = extend_left(src, pad).crop(box)
        # 切り抜きの比率がタイルとずれていると object-fit:cover で意図しない所が切れるので確かめる。
        assert abs(crop.width / crop.height - size[0] / size[1]) < 0.03, (asset, crop.size, size)
        crop.save(art)
        tile = os.path.join(tmp, f"tile-{asset}.png")
        render(wide_tile_html(art, size, lang), tile, tmp, size)
        write_imageset(asset, Image.open(tile))
        print("wide", asset)


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
    ap = argparse.ArgumentParser()
    ap.add_argument("--mock", help="モックのタイル絵の場所（hub-redesign/assets/tiles）。描き直すゲーム・横長タイルだけなら不要")
    ap.add_argument("--hero", default=HERO_ART, help="柵越えおじさんの横長タイルの元絵（既定は docs/design/homerun/hub-tile/source.png）")
    ap.add_argument("--keep", help="途中の PNG（名前なしの絵）を残す場所")
    ap.add_argument("--only", nargs="+", help="このゲームだけ書き直す（ほかのアセットは消さない）。"
                    "homerun-wide で柵越えおじさんの横長タイルだけ")
    ap.add_argument("--lang", nargs="+", choices=["ja", "en"], default=["ja", "en"],
                    help="書き出す言語（既定は両方）。1 つだけ指定したときはほかの言語のアセットを消さない")
    args = ap.parse_args()
    check_english_names()

    if not args.only and len(args.lang) == 2:
        if os.path.isdir(OUT):
            shutil.rmtree(OUT)
        os.makedirs(OUT)
        with open(os.path.join(OUT, "Contents.json"), "w") as f:
            json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}}, f, indent=2)
            f.write("\n")

    with tempfile.TemporaryDirectory() as tmp:
        if not args.only or "homerun-wide" in args.only:
            write_wide_tiles(tmp, args.lang, args.hero)
        for gid in GAMES:
            if args.only and gid not in args.only:
                continue
            art = os.path.join(tmp, f"art-{gid}.png")
            if gid in REDRAWN:
                render(art_html(gid), art, tmp)
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
            # 「つづき・最近」のアイコン（名前なしなので言語で分けない）: モックの `object-fit:cover` と同じく中央を正方形に切る。
            a = Image.open(art).convert("RGB")
            side = min(a.size)
            left, top = (a.width - side) // 2, (a.height - side) // 2
            write_imageset(f"hubthumb-{gid}", a.crop((left, top, left + side, top + side)).resize((120, 120), Image.LANCZOS))
            print("tile", gid)


if __name__ == "__main__":
    main()
