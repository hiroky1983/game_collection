#!/usr/bin/env python3
"""ハブのタイル用イラスト（179×215pt @3x）。アプリ内の部品（トランプ・駒・牌・ドット絵）を
HTML/SVG で組み直し、色の強い背景の上に大きく・傾けて・影付きで置く。AI 生成は使わない。"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
S = os.path.dirname(HERE)  # docs/design/hub-redesign-1831（このスクリプト自身の位置基準）
OUT = f"{S}/hub-redesign/assets/tiles"
SP = "../sprites"   # tiles/ から見たスプライトの場所
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
W, H = 179, 215

BASE_CSS = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:%dpx;height:%dpx;overflow:hidden}
body{font-family:"SF Pro Rounded",".SF NS Rounded","Hiragino Sans",sans-serif;-webkit-font-smoothing:antialiased}
.bg{position:absolute;inset:0}
.o{position:absolute;filter:drop-shadow(0 6px 6px rgba(0,0,0,.28))}
.px{image-rendering:pixelated}
.card{position:absolute;width:62px;height:88px;border-radius:7px;background:#fff;border:1.5px solid #E6E0D6;box-shadow:0 6px 8px rgba(0,0,0,.28);font-weight:800;font-family:"SF Pro Rounded",".SF NS Rounded",sans-serif}
.card .r{position:absolute;left:6px;top:4px;font-size:17px;line-height:1}
.card .s{position:absolute;left:6px;top:22px;font-size:14px;line-height:1}
.card .c{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;font-size:34px;padding-top:10px}
.card.red{color:#C0392B}.card.blk{color:#1A1A1A}
.back{position:absolute;width:62px;height:88px;border-radius:7px;background:#2F5F9E;border:4px solid #fff;box-shadow:0 6px 8px rgba(0,0,0,.28)}
.back::after{content:"";position:absolute;inset:4px;border-radius:4px;border:2px solid rgba(255,255,255,.55);background:repeating-linear-gradient(45deg,rgba(255,255,255,.18) 0 4px,transparent 4px 8px)}
.stone{position:absolute;width:44px;height:44px;border-radius:50%%;box-shadow:0 5px 6px rgba(0,0,0,.3)}
.stone.b{background:radial-gradient(circle at 35%% 30%%,#5a5a5a,#111 70%%)}
.stone.w{background:radial-gradient(circle at 35%% 30%%,#fff,#d9d9d9 75%%)}
.grid{position:absolute;background-size:26px 26px;background-image:linear-gradient(rgba(0,0,0,.35) 1.5px,transparent 1.5px),linear-gradient(90deg,rgba(0,0,0,.35) 1.5px,transparent 1.5px)}
.chip{position:absolute;width:46px;height:46px;border-radius:50%%;border:5px dashed #fff;box-shadow:0 5px 6px rgba(0,0,0,.3)}
.koma{position:absolute;width:62px;height:70px;filter:drop-shadow(0 6px 5px rgba(0,0,0,.3))}
.tile2048{position:absolute;width:64px;height:64px;border-radius:9px;display:flex;align-items:center;justify-content:center;font-weight:900;color:#fff;box-shadow:0 6px 8px rgba(0,0,0,.25)}
.num{position:absolute;font-weight:900;color:#fff;text-shadow:0 4px 6px rgba(0,0,0,.25)}
.cell{position:absolute;width:52px;height:52px;border-radius:8px;display:flex;align-items:center;justify-content:center;font-weight:900;font-size:30px;box-shadow:0 6px 8px rgba(0,0,0,.28)}
""" % (W, H)

def koma(text, x, y, rot):
    return f'''<svg class="koma" style="left:{x}px;top:{y}px;transform:rotate({rot}deg)" viewBox="0 0 62 70">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#EFC98A"/><stop offset="1" stop-color="#D9A85C"/></linearGradient></defs>
<polygon points="31,2 56,16 60,68 2,68 6,16" fill="url(#g)" stroke="#8A5A22" stroke-width="2.5" stroke-linejoin="round"/>
<text x="31" y="50" text-anchor="middle" font-family="Hiragino Mincho ProN,serif" font-weight="700" font-size="26" fill="#2B1B0E">{text}</text></svg>'''

def card(rank, suit, x, y, rot, red=False, scale=1):
    cls = "red" if red else "blk"
    return f'<div class="card {cls}" style="left:{x}px;top:{y}px;transform:rotate({rot}deg) scale({scale});transform-origin:bottom center"><div class="r">{rank}</div><div class="s">{suit}</div><div class="c">{suit}</div></div>'

def back(x, y, rot):
    return f'<div class="back" style="left:{x}px;top:{y}px;transform:rotate({rot}deg)"></div>'

def stone(kind, x, y, size=44):
    return f'<div class="stone {kind}" style="left:{x}px;top:{y}px;width:{size}px;height:{size}px"></div>'

def img(src, x, y, w, rot=0, px=True, extra=""):
    return f'<img class="o{" px" if px else ""}" src="{src}" style="left:{x}px;top:{y}px;width:{w}px;transform:rotate({rot}deg);{extra}">'

def hanafuda(x, y, rot, kind):
    if kind == "sakura":
        art = ('<rect x="0" y="0" width="60" height="86" rx="6" fill="#2B2234"/>'
               '<rect x="0" y="0" width="60" height="13" rx="6" fill="#C83A3A"/>'
               '<rect x="0" y="6" width="60" height="7" fill="#C83A3A"/>'
               + "".join(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="#F4A6B7"/>' for cx, cy, r in [(18, 40, 9), (36, 32, 7), (44, 52, 9), (24, 62, 8), (12, 74, 6), (48, 74, 6)])
               + '<circle cx="18" cy="40" r="3" fill="#E06C8B"/><circle cx="44" cy="52" r="3" fill="#E06C8B"/><circle cx="24" cy="62" r="2.5" fill="#E06C8B"/>')
    else:  # 芒に月
        art = ('<rect x="0" y="0" width="60" height="86" rx="6" fill="#2B2234"/>'
               '<circle cx="30" cy="30" r="17" fill="#FAF6EC"/>'
               '<path d="M0 60 Q30 40 60 60 L60 86 L0 86 Z" fill="#C83A3A"/>')
    return f'<svg class="o" style="left:{x}px;top:{y}px;width:60px;height:86px;transform:rotate({rot}deg)" viewBox="0 0 60 86">{art}</svg>'

def crown(x, y, rot, size=46):
    return f'<svg class="o" style="left:{x}px;top:{y}px;width:{size}px;transform:rotate({rot}deg)" viewBox="0 0 48 40"><path d="M4 34 L2 10 L15 20 L24 4 L33 20 L46 10 L44 34 Z" fill="#FFC24B" stroke="#B5801A" stroke-width="2.5" stroke-linejoin="round"/><rect x="4" y="30" width="40" height="7" fill="#F2A33A" stroke="#B5801A" stroke-width="2"/></svg>'

def flag_cell(x, y, rot):
    return f'<div class="cell" style="left:{x}px;top:{y}px;transform:rotate({rot}deg);background:#C9D3DE"><svg width="30" height="30" viewBox="0 0 30 30"><path d="M12 4 L12 27" stroke="#2B2634" stroke-width="3"/><path d="M12 4 L26 10 L12 16 Z" fill="#E24A3C"/><rect x="6" y="25" width="14" height="3" fill="#2B2634"/></svg></div>'

def bomb_cell(x, y, rot):
    return f'<div class="cell" style="left:{x}px;top:{y}px;transform:rotate({rot}deg);background:#E8EDF2"><svg width="32" height="32" viewBox="0 0 32 32"><circle cx="16" cy="18" r="10" fill="#2B2634"/><path d="M16 4 L16 32 M2 18 L30 18 M6 8 L26 28 M26 8 L6 28" stroke="#2B2634" stroke-width="3"/><circle cx="13" cy="15" r="2.5" fill="#fff"/></svg></div>'

TILES = {}

TILES["poker"] = ('linear-gradient(160deg,#5FC9AE 0%,#1E8C72 55%,#136B56 100%)',
    card("A", "♠", 10, 92, -22) + card("K", "♥", 44, 78, -8, True) + card("Q", "♦", 80, 76, 8, True) + card("J", "♣", 116, 86, 22)
    + '<div class="chip" style="left:112px;top:28px;background:#FFC24B"></div><div class="chip" style="left:128px;top:14px;background:#E24A3C"></div>')

TILES["solitaire"] = ('linear-gradient(160deg,#8FE0D2 0%,#2F9E8F 50%,#1F7A6E 100%)',
    back(14, 20, -10) + back(26, 22, -4) + card("K", "♠", 86, 18, 8) + card("Q", "♥", 84, 46, 8, True) + card("J", "♣", 82, 74, 8)
    + card("10", "♦", 80, 102, 8, True) + '<div class="o" style="left:18px;top:122px;width:56px;height:80px;border:3px dashed rgba(255,255,255,.85);border-radius:7px"></div>'
    + '<div style="position:absolute;left:28px;top:138px;font-size:30px;color:rgba(255,255,255,.85)">♛</div>')

TILES["runner"] = ('linear-gradient(180deg,#8ED0F0 0%,#C9E8F7 60%,#B5D98F 60%,#9CC96E 100%)',
    '<div class="bg" style="background:radial-gradient(ellipse 110px 70px at 30% 72%,#A9D483 0 60%,transparent 61%),radial-gradient(ellipse 120px 60px at 90% 70%,#95C66B 0 60%,transparent 61%)"></div>'
    '<div style="position:absolute;left:0;right:0;top:188px;height:14px;background:#8E8A86"></div><div style="position:absolute;left:0;right:0;top:194px;height:2px;background:repeating-linear-gradient(90deg,#fff 0 12px,transparent 12px 22px)"></div>'
    '<div style="position:absolute;left:18px;top:34px;width:44px;height:16px;border-radius:10px;background:#fff;opacity:.9"></div><div style="position:absolute;left:120px;top:54px;width:36px;height:13px;border-radius:10px;background:#fff;opacity:.9"></div>'
    + img(f"{SP}/ojisan_jump.png", 26, 60, 138, -8))

TILES["mahjong4"] = ('linear-gradient(160deg,#4FB58A 0%,#1F6B4A 50%,#15503A 100%)',
    img(f"{SP}/mj_man7.png", 14, 78, 54, -12, False) + img(f"{SP}/mj_pin3.png", 62, 66, 54, -4, False) + img(f"{SP}/mj_sou5.png", 112, 72, 54, 8, False)
    + '<div style="position:absolute;left:56px;top:26px;padding:3px 10px;border-radius:999px;background:#E24A3C;color:#fff;font-weight:900;font-size:13px;box-shadow:0 4px 6px rgba(0,0,0,.25);transform:rotate(-6deg)">リーチ</div>')

TILES["sudoku"] = ('linear-gradient(160deg,#8FA9F2 0%,#4C6FD6 55%,#3A55B5 100%)',
    '<div class="num" style="left:12px;top:30px;font-size:64px;transform:rotate(-12deg)">7</div>'
    '<div class="num" style="left:92px;top:20px;font-size:48px;transform:rotate(10deg);opacity:.9">3</div>'
    '<div class="num" style="left:118px;top:150px;font-size:40px;transform:rotate(14deg);opacity:.85">9</div>'
    '<div class="o" style="left:58px;top:86px;width:96px;height:96px;background:#fff;border-radius:10px;transform:rotate(-7deg);display:grid;grid-template-columns:repeat(3,1fr);border:3px solid #4A3B33;font-weight:900;font-size:19px;color:#4A3B33">'
    + "".join(f'<div style="display:flex;align-items:center;justify-content:center;border:1px solid #BBB">{c}</div>' for c in ["5","","1","","8","","2","","6"]) + '</div>'
    '<div class="num" style="left:14px;top:150px;font-size:44px;transform:rotate(-8deg);opacity:.85">1</div>')

TILES["othello"] = ('linear-gradient(160deg,#5BC47F 0%,#2E8B57 50%,#1E6B40 100%)',
    '<div class="grid" style="left:-30px;top:30px;width:260px;height:260px;transform:rotate(-12deg);opacity:.5"></div>'
    + stone("b", 22, 60) + stone("w", 70, 52) + stone("b", 118, 60) + stone("w", 34, 112) + stone("b", 82, 108, 56) + stone("w", 134, 116) + stone("b", 58, 164) + stone("w", 108, 168))

TILES["2048"] = ('linear-gradient(160deg,#F3DDC3 0%,#E7C9A8 50%,#D4A77F 100%)',
    '<div class="tile2048" style="left:16px;top:120px;background:#EDCF72;font-size:22px;transform:rotate(-8deg)">512</div>'
    '<div class="tile2048" style="left:96px;top:128px;background:#F2B179;font-size:22px;transform:rotate(6deg)">256</div>'
    '<div class="tile2048" style="left:56px;top:62px;background:#EDC22E;font-size:18px;width:76px;height:76px;transform:rotate(-4deg);box-shadow:0 10px 14px rgba(0,0,0,.3)">2048</div>'
    '<div class="tile2048" style="left:124px;top:34px;background:#F67C5F;font-size:16px;width:46px;height:46px;transform:rotate(12deg)">8</div>')

TILES["shogi"] = ('linear-gradient(160deg,#F3D79A 0%,#EDC178 50%,#D3A04D 100%)',
    '<div class="grid" style="left:-20px;top:-10px;width:260px;height:260px;transform:rotate(-10deg);opacity:.35;background-size:34px 34px"></div>'
    + koma("王", 16, 110, -16) + koma("飛", 60, 60, -2) + koma("角", 108, 112, 14))

TILES["shiritori"] = ('linear-gradient(160deg,#FFC5D6 0%,#FF8FB1 55%,#E96E95 100%)',
    ''.join(f'<div class="o" style="left:{x}px;top:{y}px;width:72px;height:96px;background:#fff;border-radius:9px;transform:rotate({r}deg);filter:drop-shadow(0 6px 6px rgba(0,0,0,.25))">'
            f'<img class="px" src="{SP}/{s}.png" style="position:absolute;left:8px;top:6px;width:56px"><div style="position:absolute;left:0;right:0;top:70px;text-align:center;font-weight:900;font-size:13px;color:#4A3B33">{t}</div></div>'
            for x, y, r, s, t in [(8, 90, -16, "card_apple", "りんご"), (54, 62, -3, "card_gorilla", "ごりら"), (102, 86, 14, "card_rabbit", "うさぎ")]))

TILES["daifugo"] = ('linear-gradient(160deg,#C4B8F8 0%,#8C7BE0 50%,#6A4BC8 100%)',
    card("8", "♠", 6, 96, -24) + card("J", "♥", 40, 82, -10, True) + card("2", "♣", 76, 80, 6) + card("A", "♦", 112, 90, 20, True) + crown(66, 18, -8, 54))

TILES["gomoku"] = ('linear-gradient(160deg,#F2D59A 0%,#E4B96A 50%,#C99A4A 100%)',
    '<div class="grid" style="left:-20px;top:-20px;width:260px;height:260px;transform:rotate(-8deg);opacity:.5;background-size:30px 30px"></div>'
    + "".join(stone("b", 22 + i * 30, 150 - i * 28, 36) for i in range(5)) + stone("w", 18, 54, 36) + stone("w", 126, 150, 36) + stone("w", 60, 160, 36))

TILES["minesweeper"] = ('linear-gradient(160deg,#C5D3E6 0%,#9CB0C8 50%,#7F93AC 100%)',
    '<div class="cell" style="left:14px;top:40px;background:#E8EDF2;color:#2A5BD7;transform:rotate(-12deg)">1</div>'
    '<div class="cell" style="left:72px;top:28px;background:#E8EDF2;color:#2E8B3A;transform:rotate(4deg)">2</div>'
    + flag_cell(118, 50, 12) + bomb_cell(40, 112, -6)
    + '<div class="cell" style="left:104px;top:124px;background:#E8EDF2;color:#C0392B;transform:rotate(10deg)">3</div>')

TILES["spider"] = ('linear-gradient(160deg,#6ED1B0 0%,#1D6B4F 50%,#134A37 100%)',
    back(8, 14, -6) + back(118, 14, 6)
    + card("K", "♠", 58, 24, 0) + card("Q", "♠", 58, 50, 0) + card("J", "♠", 58, 76, 0) + card("10", "♠", 58, 102, 0) + card("9", "♠", 58, 128, 0)
    + '<svg class="o" style="left:116px;top:120px;width:54px;transform:rotate(16deg)" viewBox="0 0 48 44"><circle cx="24" cy="26" r="11" fill="#2B2634"/><circle cx="24" cy="12" r="7" fill="#2B2634"/>'
    + "".join(f'<path d="M24 24 Q{x} {y} {x2} {y2}" stroke="#2B2634" stroke-width="3" fill="none" stroke-linecap="round"/>' for x, y, x2, y2 in [(4, 10, 2, 22), (6, 22, 2, 34), (10, 34, 8, 44), (44, 10, 46, 22), (42, 22, 46, 34), (38, 34, 40, 44)])
    + '<circle cx="21" cy="10" r="1.6" fill="#fff"/><circle cx="27" cy="10" r="1.6" fill="#fff"/></svg>')

TILES["blackjack"] = ('linear-gradient(160deg,#F0A092 0%,#C04A3A 50%,#9E2F26 100%)',
    card("A", "♠", 30, 74, -14, False, 1.15) + card("K", "♥", 84, 72, 12, True, 1.15)
    + "".join(f'<div class="chip" style="left:{x}px;top:{y}px;background:{c}"></div>' for x, y, c in [(10, 150, "#FFC24B"), (18, 138, "#22C3BE"), (26, 126, "#FF6F61")])
    + '<div style="position:absolute;left:112px;top:22px;padding:3px 10px;border-radius:999px;background:#fff;color:#C04A3A;font-weight:900;font-size:16px;box-shadow:0 4px 6px rgba(0,0,0,.25);transform:rotate(8deg)">21</div>')

TILES["mahjong"] = ('linear-gradient(160deg,#8FE0D6 0%,#2A9D8F 50%,#1F7A70 100%)',
    "".join(img(f"{SP}/{s}.png", x, y, 50, 0, False) for x, y, s in [(14, 118, "mj_pin6"), (60, 118, "mj_sou2"), (106, 118, "mj_man8"), (36, 76, "mj_pin3"), (84, 76, "mj_sou5"), (60, 34, "mj_man7")]))

TILES["hanafuda"] = ('linear-gradient(160deg,#E57F72 0%,#B3382E 50%,#8E261E 100%)',
    hanafuda(22, 60, -14, "sakura") + hanafuda(92, 54, 12, "moon")
    + '<div style="position:absolute;left:14px;top:168px;padding:3px 10px;border-radius:999px;background:#fff;color:#B3382E;font-weight:900;font-size:13px;box-shadow:0 4px 6px rgba(0,0,0,.25);transform:rotate(-4deg)">こいこい！</div>')

TILES["go"] = ('linear-gradient(160deg,#F2DCA8 0%,#E8C98A 50%,#CFA660 100%)',
    '<div class="grid" style="left:-20px;top:-20px;width:260px;height:260px;transform:rotate(8deg);opacity:.5;background-size:28px 28px"></div>'
    + stone("b", 30, 50, 38) + stone("w", 70, 44, 38) + stone("b", 110, 56, 38) + stone("w", 44, 96, 38) + stone("b", 88, 92, 38) + stone("w", 126, 100, 38) + stone("b", 64, 140, 38) + stone("w", 104, 146, 38) + stone("b", 22, 150, 38))

TILES["blocks"] = ('linear-gradient(160deg,#4A5290 0%,#1F2440 50%,#151A30 100%)',
    "".join(f'<div class="o" style="left:{x}px;top:{y}px;width:44px;height:18px;border-radius:4px;background:{c};transform:rotate(-8deg)"></div>' for i, (x, y, c) in enumerate([(14, 40, "#FF6F61"), (62, 33, "#FF6F61"), (110, 26, "#FF6F61"), (14, 64, "#FFC24B"), (62, 57, "#FFC24B"), (110, 50, "#FFC24B"), (14, 88, "#22C3BE"), (62, 81, "#22C3BE"), (110, 74, "#22C3BE")]))
    + '<div class="o" style="left:98px;top:124px;width:22px;height:22px;border-radius:50%;background:#fff"></div>'
    + '<div class="o" style="left:52px;top:172px;width:76px;height:16px;border-radius:999px;background:#FF8A7E;transform:rotate(-6deg)"></div>')

TILES["concentration"] = ('linear-gradient(160deg,#D6CCFA 0%,#B3A6F0 50%,#8C7BE0 100%)',
    "".join(f'<div class="o" style="left:{x}px;top:{y}px;width:64px;height:88px;border-radius:9px;background:#8C7BE0;border:3px solid #fff;transform:rotate({r}deg);display:flex;align-items:center;justify-content:center;color:#fff;font-weight:900;font-size:34px">?</div>' for x, y, r in [(10, 24, -12), (112, 26, 12)])
    + f'<div class="o" style="left:56px;top:96px;width:68px;height:92px;border-radius:9px;background:#fff;transform:rotate(-4deg)"><img class="px" src="{SP}/card_apple.png" style="position:absolute;left:6px;top:14px;width:56px"></div>')

TILES["chess"] = ('linear-gradient(160deg,#A77F55 0%,#6B4A2A 50%,#4A321C 100%)',
    '<div style="position:absolute;left:-30px;top:40px;width:260px;height:260px;transform:rotate(-10deg);opacity:.45;background-size:52px 52px;background-image:linear-gradient(45deg,#F3DFAE 25%,transparent 25%,transparent 75%,#F3DFAE 75%),linear-gradient(45deg,#F3DFAE 25%,transparent 25%,transparent 75%,#F3DFAE 75%);background-position:0 0,26px 26px"></div>'
    '<div class="o" style="left:18px;top:52px;font-size:96px;line-height:1;color:#FAF6EC;font-family:\'Apple Symbols\',\'Segoe UI Symbol\',serif;transform:rotate(-8deg)">♞</div>'
    '<div class="o" style="left:98px;top:76px;font-size:84px;line-height:1;color:#2B2634;font-family:\'Apple Symbols\',\'Segoe UI Symbol\',serif;transform:rotate(10deg)">♛</div>')

TILES["freecell"] = ('linear-gradient(160deg,#8DE4E1 0%,#22C3BE 50%,#1A9A96 100%)',
    "".join(f'<div class="o" style="left:{x}px;top:18px;width:34px;height:46px;border:2.5px dashed rgba(255,255,255,.9);border-radius:6px"></div>' for x in [12, 52, 92, 132])
    + card("A", "♥", 18, 92, -12, True) + card("2", "♣", 64, 84, 0) + card("3", "♦", 110, 92, 12, True))

TILES["fifteen"] = ('linear-gradient(160deg,#FFD98A 0%,#FFC24B 50%,#F2A33A 100%)',
    "".join(f'<div class="cell" style="left:{x}px;top:{y}px;width:62px;height:62px;background:{c};color:#4A3B33;font-size:28px;border-radius:12px;transform:rotate(-8deg)">{t}</div>' for x, y, t, c in [(24, 44, "1", "#FFC24B"), (92, 36, "2", "#22C3BE"), (16, 112, "3", "#FFC24B"), (84, 104, "15", "#FFC24B")])
    + '<div style="position:absolute;left:84px;top:104px;width:62px;height:62px;border-radius:12px;background:rgba(0,0,0,.15);transform:rotate(-8deg)"></div>'
    '<div class="cell" style="left:92px;top:160px;width:62px;height:62px;background:#FFC24B;color:#4A3B33;font-size:28px;border-radius:12px;transform:rotate(-8deg)">14</div>')

TILES["homerun"] = ('#1F6EDB',
    '<img src="../HomerunHubHeroArtLogo.jpg" style="position:absolute;left:-150px;top:-80px;height:300px">')

TILES["ojisanpuzzle"] = ('linear-gradient(180deg,#CDE7F7 0%,#E8F2F8 55%,#D9D2C6 55%,#C4B9A8 100%)',
    img(f"{SP}/luggage_beer.png", 14, 122, 60, 0) + img(f"{SP}/luggage_cooler.png", 70, 124, 60, 0) + img(f"{SP}/luggage_tank.png", 120, 128, 52, 0)
    + img(f"{SP}/luggage_watermelon.png", 44, 76, 58, -6) + img(f"{SP}/luggage_cushion.png", 100, 80, 56, 6)
    + img(f"{SP}/ojisan_cheer.png", 112, 10, 62, 8))

def html(gid):
    bg, body = TILES[gid]
    shift = 0 if gid in ("homerun",) else 24   # 名前を上に載せる案のため、物を少し下に置く
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{BASE_CSS}</style></head><body><div class="bg" style="background:{bg}"></div><div style="position:absolute;inset:0;transform:translateY({shift}px)">{body}</div></body></html>'

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:] or list(TILES)
    for gid in only:
        p = f"{OUT}/{gid}.html"
        open(p, "w").write(html(gid))
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--window-size={W},{H}",
                        "--force-device-scale-factor=3", f"--screenshot={OUT}/{gid}.png", f"file://{p}"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        print("tile", gid)
